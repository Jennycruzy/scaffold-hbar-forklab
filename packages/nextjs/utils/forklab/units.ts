import { formatUnits, parseUnits } from "viem";

export const TINYBARS_PER_HBAR = 100_000_000n;
export const WEIBARS_PER_TINYBAR = 10_000_000_000n;
export const WEIBARS_PER_HBAR = TINYBARS_PER_HBAR * WEIBARS_PER_TINYBAR;

/** One HBAR is 100,000,000 tinybars in contract arguments. */
export function hbarToTinybar(value: string): bigint {
  return parseUnits(value || "0", 8);
}

/** JSON-RPC native values use 18-decimal weibar units. */
export function hbarToWeibar(value: string): bigint {
  return parseUnits(value || "0", 18);
}

export function tinybarToWeibar(value: bigint | number | string): bigint {
  return BigInt(value) * WEIBARS_PER_TINYBAR;
}

export function tinybarToHbar(value: bigint | number | string): string {
  return formatUnits(BigInt(value), 8);
}

export function weibarToHbar(value: bigint | number | string): string {
  return formatUnits(BigInt(value), 18);
}
