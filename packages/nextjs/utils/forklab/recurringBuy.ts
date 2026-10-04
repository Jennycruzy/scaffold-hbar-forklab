import type { Abi } from "viem";

export const recurringBuyAbi = [
  {
    type: "constructor",
    stateMutability: "nonpayable",
    inputs: [
      { name: "supraAddress", type: "address" },
      { name: "routerAddress", type: "address" },
    ],
  },
  { type: "function", name: "amountPerBuy", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  {
    type: "function",
    name: "configure",
    stateMutability: "nonpayable",
    inputs: [
      { name: "tokenOutAddress", type: "address" },
      { name: "amountTinybars", type: "uint256" },
      { name: "intervalSeconds", type: "uint256" },
      { name: "deviationBps", type: "uint256" },
      { name: "priceAgeSeconds", type: "uint256" },
    ],
    outputs: [],
  },
  {
    type: "function",
    name: "configureBonzo",
    stateMutability: "nonpayable",
    inputs: [
      { name: "pool", type: "address" },
      { name: "enabled", type: "bool" },
    ],
    outputs: [],
  },
  { type: "function", name: "bonzoPool", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "deposit", stateMutability: "payable", inputs: [], outputs: [] },
  { type: "function", name: "execute", stateMutability: "nonpayable", inputs: [], outputs: [] },
  { type: "function", name: "purchase", stateMutability: "nonpayable", inputs: [], outputs: [] },
  { type: "function", name: "executionGas", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  {
    type: "function",
    name: "DEFAULT_EXECUTION_GAS",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
  {
    type: "function",
    name: "setExecutionGas",
    stateMutability: "nonpayable",
    inputs: [{ name: "gasLimit", type: "uint256" }],
    outputs: [],
  },
  { type: "function", name: "hbarBalance", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "lastRunAt", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "lastScheduleStatus", stateMutability: "view", inputs: [], outputs: [{ type: "int64" }] },
  { type: "function", name: "maxDeviationBps", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "maxPriceAge", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "nextRunAt", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "nextSchedule", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "owner", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "running", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  {
    type: "function",
    name: "start",
    stateMutability: "nonpayable",
    inputs: [],
    outputs: [{ type: "int64" }, { type: "address" }],
  },
  { type: "function", name: "stop", stateMutability: "nonpayable", inputs: [], outputs: [{ type: "int64" }] },
  { type: "function", name: "sweepToBonzo", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  {
    type: "function",
    name: "transferOwnership",
    stateMutability: "nonpayable",
    inputs: [{ name: "newOwner", type: "address" }],
    outputs: [],
  },
  { type: "function", name: "tokenOut", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  {
    type: "function",
    name: "withdraw",
    stateMutability: "nonpayable",
    inputs: [{ name: "amountTinybars", type: "uint256" }],
    outputs: [],
  },
  {
    type: "event",
    name: "Bought",
    anonymous: false,
    inputs: [
      { indexed: false, name: "hbarAmount", type: "uint256" },
      { indexed: false, name: "tokenAmount", type: "uint256" },
      { indexed: false, name: "oracleAmountOut", type: "uint256" },
      { indexed: false, name: "poolAmountOut", type: "uint256" },
    ],
  },
  {
    type: "event",
    name: "ScheduleCreated",
    anonymous: false,
    inputs: [
      { indexed: true, name: "schedule", type: "address" },
      { indexed: false, name: "runAt", type: "uint256" },
    ],
  },
  {
    type: "event",
    name: "PurchaseFailed",
    anonymous: false,
    inputs: [{ indexed: false, name: "reason", type: "bytes" }],
  },
  {
    type: "event",
    name: "ScheduleFailed",
    anonymous: false,
    inputs: [{ indexed: true, name: "responseCode", type: "int64" }],
  },
] as const satisfies Abi;

export const recurringBuyFactoryAbi = [
  {
    type: "function",
    name: "createVault",
    stateMutability: "nonpayable",
    inputs: [
      { name: "supra", type: "address" },
      { name: "router", type: "address" },
    ],
    outputs: [{ name: "vault", type: "address" }],
  },
  {
    type: "event",
    name: "VaultCreated",
    anonymous: false,
    inputs: [
      { indexed: true, name: "owner", type: "address" },
      { indexed: true, name: "vault", type: "address" },
      { indexed: false, name: "supra", type: "address" },
      { indexed: false, name: "router", type: "address" },
    ],
  },
] as const satisfies Abi;

/** HRC-719 association and the ERC-20 calls the owner makes on tokenOut before start(). */
export const ownerTokenAbi = [
  { type: "function", name: "associate", stateMutability: "nonpayable", inputs: [], outputs: [{ type: "uint256" }] },
  {
    type: "function",
    name: "approve",
    stateMutability: "nonpayable",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ type: "bool" }],
  },
  {
    type: "function",
    name: "allowance",
    stateMutability: "view",
    inputs: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
    ],
    outputs: [{ type: "uint256" }],
  },
] as const satisfies Abi;

/** Hedera ContractCall gas price observed on testnet on 4 October 2026, in tinybars per gas. */
export const OBSERVED_GAS_PRICE_TINYBARS = 83n;

/** Hedera reserves gas at the full limit before a call and refunds what the call does not use. */
export function gasReservationTinybars(gasLimit: bigint) {
  return gasLimit * OBSERVED_GAS_PRICE_TINYBARS;
}
