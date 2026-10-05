// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title ForklabTokenProxy
/// @notice HIP-719 token proxy that `Forklab.useTokens` etches at each declared HTS token address.
/// @dev It forwards every call to `0x167` exactly like the upstream proxy: a delegatecall with
///      `redirectForToken(address,bytes)` (0x618dc65e), the unpadded token address, then the original calldata.
///      Before an ERC-20 or ERC-721 `approve(address,uint256)` it first asks the token, in the same delegatecall
///      form, whether the caller is associated (`isAssociated()`, read from the pinned Mirror Node or a local
///      association). Hedera testnet reverts an approve from an unassociated account with empty data and leaves the
///      allowance at 0 (probe of 4 October 2026, docs/TESTNET_PROOF.md); the pinned hedera-forking release has no
///      overridable hook on that path, so the check lives here. Like the upstream proxy, it rejects call value.
contract ForklabTokenProxy {
    fallback() external {
        assembly {
            // approve(address,uint256)
            if eq(shr(224, calldataload(0)), 0x095ea7b3) {
                // [0:4] redirectForToken selector, [4:24] token address, [24:28] isAssociated() selector.
                mstore(0, shl(224, 0x618dc65e))
                mstore(4, shl(96, address()))
                mstore(24, shl(224, 0x4d8fdd6d))
                let checked := delegatecall(gas(), 0x167, 0, 28, 0, 32)
                // An account unknown at the pinned block makes the lookup revert; that is also "not associated".
                if or(or(iszero(checked), lt(returndatasize(), 32)), iszero(mload(0))) { revert(0, 0) }
            }

            mstore(0, shl(224, 0x618dc65e))
            mstore(4, shl(96, address()))
            calldatacopy(24, 0, calldatasize())
            let success := delegatecall(gas(), 0x167, 0, add(24, calldatasize()), 0, 0)
            returndatacopy(0, 0, returndatasize())
            if iszero(success) { revert(0, returndatasize()) }
            return(0, returndatasize())
        }
    }
}
