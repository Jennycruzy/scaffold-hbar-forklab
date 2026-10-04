/**
 * Browser model of one RecurringBuy vault driven by the schedule service, used by the landing-page playground.
 *
 * The Solidity emulator (`ForklabHss.sol`) and its tests are the source of truth; this file applies the same rules so
 * a visitor can explore them without Foundry. HSS constants are copied from `ForklabHss.sol`, the purchase reserve from
 * `RecurringBuy.sol`, and the execute/purchase gas is calibrated on testnet runs 1 and 2 (1,684,515 and 1,667,415 gas).
 */

export const TINYBARS_PER_HBAR = 100_000_000;

/** Values from `ForklabHss.sol`, measured on Hedera testnet. */
export const HSS_RULES = {
  scheduleCreateGas: 1_409_649,
  gasPriceTinybars: 83,
  insufficientPayerFeeTinybars: 1_735_120,
} as const;

/** Values from `RecurringBuy.sol` and the testnet runs. */
export const VAULT_RULES = {
  executeOverheadGas: 40_000,
  purchaseGas: 225_000,
  purchaseFailureReserveGas: 50_000,
  intervalSeconds: 60,
} as const;

export type VaultParams = {
  gasLimit: number;
  startingBalanceTinybars: number;
  amountPerBuyTinybars: number;
};

export type RunKind = "bought" | "purchaseFailed" | "insufficientGas" | "insufficientPayer" | "recorded";

export type Run = {
  index: number;
  at: number;
  kind: RunKind;
  gasUsed: number;
  feeTinybars: number;
  spentTinybars: number;
  balanceAfterTinybars: number;
  chainContinues: boolean;
  detail: string;
};

export type Lane = {
  balanceTinybars: number;
  runs: Run[];
  ended: boolean;
};

export const newLane = (params: VaultParams): Lane => ({
  balanceTinybars: params.startingBalanceTinybars,
  runs: [],
  ended: false,
});

/** Smallest gas limit whose run can still create the next schedule. */
export const minimumScheduleGas = VAULT_RULES.executeOverheadGas + HSS_RULES.scheduleCreateGas;

/** Gas a successful run uses: execute(), the next scheduleCall, and the purchase. */
export const successfulRunGas = minimumScheduleGas + VAULT_RULES.purchaseGas;

/**
 * A typical `0x16b` mock: it records the scheduleCall and returns SUCCESS (22). The test then calls the target by hand,
 * so nothing checks gas, fees, or the payer's balance, and the run always looks green.
 */
export function mockStep(lane: Lane, params: VaultParams): Lane {
  const index = lane.runs.length + 1;
  const run: Run = {
    index,
    at: index * VAULT_RULES.intervalSeconds,
    kind: "recorded",
    gasUsed: 0,
    feeTinybars: 0,
    spentTinybars: 0,
    balanceAfterTinybars: lane.balanceTinybars,
    chainContinues: true,
    detail: `scheduleCall recorded, returned 22; test calls execute() by hand (gas limit ${params.gasLimit.toLocaleString()} never checked)`,
  };
  return { ...lane, runs: [...lane.runs, run] };
}

/** One due schedule under Forklab's rules, in the order ForklabHss and RecurringBuy apply them. */
export function forklabStep(lane: Lane, params: VaultParams): Lane {
  if (lane.ended) return lane;
  const index = lane.runs.length + 1;
  const at = index * VAULT_RULES.intervalSeconds;
  const balance = lane.balanceTinybars;
  const finish = (run: Omit<Run, "index" | "at">): Lane => ({
    balanceTinybars: run.balanceAfterTinybars,
    runs: [...lane.runs, { index, at, ...run }],
    ended: !run.chainContinues,
  });

  // HSS reserves gas at the full limit before running the call.
  const reservation = params.gasLimit * HSS_RULES.gasPriceTinybars;
  if (balance < reservation) {
    const fee = Math.min(HSS_RULES.insufficientPayerFeeTinybars, balance);
    return finish({
      kind: "insufficientPayer",
      gasUsed: 0,
      feeTinybars: fee,
      spentTinybars: 0,
      balanceAfterTinybars: balance - fee,
      chainContinues: false,
      detail: `INSUFFICIENT_PAYER_BALANCE: needs ${formatHbar(reservation)} HBAR reserved, holds ${formatHbar(balance)}; still charged ${fee.toLocaleString()} tinybars, call never runs`,
    });
  }

  // execute() creates the next schedule first; without gas for it the whole run reverts and no schedule remains.
  if (params.gasLimit < minimumScheduleGas) {
    const fee = params.gasLimit * HSS_RULES.gasPriceTinybars;
    return finish({
      kind: "insufficientGas",
      gasUsed: params.gasLimit,
      feeTinybars: fee,
      spentTinybars: 0,
      balanceAfterTinybars: balance - fee,
      chainContinues: false,
      detail: `INSUFFICIENT_GAS in scheduleCall (needs ${HSS_RULES.scheduleCreateGas.toLocaleString()} gas); run reverts, no next schedule`,
    });
  }

  // The purchase runs in a guarded self-call that keeps a reserve back, so its failure keeps the schedule chain.
  const purchaseBudget = params.gasLimit - minimumScheduleGas - VAULT_RULES.purchaseFailureReserveGas;
  const canSwap = balance >= params.amountPerBuyTinybars;
  if (purchaseBudget < VAULT_RULES.purchaseGas || !canSwap) {
    const gasUsed = minimumScheduleGas + Math.max(purchaseBudget, 0) + 5_000;
    const fee = gasUsed * HSS_RULES.gasPriceTinybars;
    return finish({
      kind: "purchaseFailed",
      gasUsed,
      feeTinybars: fee,
      spentTinybars: 0,
      balanceAfterTinybars: balance - fee,
      chainContinues: true,
      detail: canSwap
        ? `next schedule created, then PurchaseFailed: ${Math.max(purchaseBudget, 0).toLocaleString()} gas left for a ${VAULT_RULES.purchaseGas.toLocaleString()}-gas swap`
        : `next schedule created, then PurchaseFailed: vault cannot cover a ${formatHbar(params.amountPerBuyTinybars)} HBAR swap`,
    });
  }

  const gasUsed = successfulRunGas;
  const fee = gasUsed * HSS_RULES.gasPriceTinybars;
  return finish({
    kind: "bought",
    gasUsed,
    feeTinybars: fee,
    spentTinybars: params.amountPerBuyTinybars,
    balanceAfterTinybars: balance - params.amountPerBuyTinybars - fee,
    chainContinues: true,
    detail: `next schedule created, Bought on SaucerSwap; gas ${gasUsed.toLocaleString()} / ${params.gasLimit.toLocaleString()}, fee ${formatHbar(fee)} HBAR`,
  });
}

export function formatHbar(tinybars: number, digits = 4) {
  return (tinybars / TINYBARS_PER_HBAR).toLocaleString(undefined, {
    minimumFractionDigits: 2,
    maximumFractionDigits: digits,
  });
}
