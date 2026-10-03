// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Vm } from "forge-std/Vm.sol";
import { HTS_ADDRESS } from "hedera-forking/HtsSystemContract.sol";
import { HtsSystemContractJson } from "hedera-forking/HtsSystemContractJson.sol";
import { HederaResponseCodes } from "hedera-forking/HederaResponseCodes.sol";
import { IHederaTokenService } from "hedera-forking/IHederaTokenService.sol";
import { IHRC719 } from "hedera-forking/IHRC719.sol";
import { MirrorNode } from "hedera-forking/MirrorNode.sol";

/// @notice Forklab's HTS adapter for the pinned hedera-forking release.
/// @dev It keeps the upstream implementation intact and adds the legacy ABI
///      overloads still emitted by deployed Hedera helper contracts.
contract ForklabHts is HtsSystemContractJson {
    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice Raised when the legacy unsigned amount cannot be represented by the pinned signed ABI.
    error LegacyAmountTooLarge();

    /// @notice Raised when a token repair is attempted before setup installs a Mirror Node provider.
    error MirrorNodeNotConfigured();

    MirrorNode private _forklabMirrorNode;

    /// @notice Stores the timestamp-bounded Mirror Node used to repair protobuf contract keys.
    /// @param mirrorNode The provider installed by `Forklab.setUp`.
    function setForklabMirrorNode(MirrorNode mirrorNode) external htsCall {
        _forklabMirrorNode = mirrorNode;
    }

    /// @notice Repairs a protobuf-encoded contract supply key using verified Mirror Node data.
    /// @dev hedera-forking v0.1.2 decodes ED25519 and ECDSA keys but leaves protobuf contract
    ///      keys empty. This method decodes the real key and repairs the token's local
    ///      metadata, preserving the inherited supply-key check.
    /// @param token The long-zero HTS token address.
    function repairProtobufSupplyKey(address token) external htsCall {
        MirrorNode mirrorNode = _forklabMirrorNode;
        if (address(mirrorNode) == address(0)) revert MirrorNodeNotConfigured();

        string memory json = mirrorNode.fetchTokenData(token);
        if (!VM.keyExistsJson(json, ".supply_key.key")) return;
        if (keccak256(bytes(VM.parseJsonString(json, ".supply_key._type"))) != keccak256(bytes("ProtobufEncoded"))) {
            return;
        }

        bytes memory encodedKey = VM.parseBytes(VM.parseJsonString(json, ".supply_key.key"));
        address contractId = _decodeContractId(encodedKey);
        // Non-contract protobuf keys remain untouched; the inherited decoder handles
        // the ED25519 and ECDSA forms used by those tokens.
        if (contractId == address(0)) return;

        (int64 responseCode, IHederaTokenService.TokenInfo memory tokenInfo) =
            IHederaTokenService(token).getTokenInfo(token);
        if (responseCode != HederaResponseCodes.SUCCESS || tokenInfo.token.tokenKeys.length <= 4) return;
        if (tokenInfo.token.tokenKeys[4].key.contractId == contractId) return;

        // v0.1.2 stores the seven token keys at keccak256(slot 7). Each key
        // occupies five slots, with the contract ID in the second slot.
        uint256 keySlot = uint256(keccak256(abi.encodePacked(uint256(7)))) + 4 * 5 + 1;
        // forge-lint: disable-next-line(unsafe-typecast)
        VM.store(token, bytes32(keySlot), bytes32(uint256(uint160(contractId))));
    }

    /// @notice Re-etches a HIP-719 proxy only when a token has an EIP-7702 code marker.
    /// @param token The long-zero HTS token address.
    function ensureHip719Proxy(address token) external {
        if (address(this) != HTS_ADDRESS) return;
        bytes memory code = token.code;
        if (code.length < 3 || code[0] != 0xef || code[1] != 0x01 || code[2] != 0x00) return;
        deployHIP719Proxy(token);
    }

    /// @notice Supports the legacy uint64 mintToken ABI used by WHBAR helpers.
    /// @param token The fungible token address.
    /// @param amount The amount to mint in the token's smallest unit.
    /// @param metadata NFT metadata, retained for ABI compatibility.
    /// @return responseCode The HTS response code.
    /// @return newTotalSupply The resulting total supply.
    /// @return serialNumbers Empty for fungible tokens.
    function mintToken(address token, uint64 amount, bytes[] memory metadata)
        external
        htsCall
        returns (int64 responseCode, int64 newTotalSupply, int64[] memory serialNumbers)
    {
        if (amount > uint64(type(int64).max)) revert LegacyAmountTooLarge();
        // forge-lint: disable-next-line(unsafe-typecast)
        return this.mintToken(token, int64(amount), metadata);
    }

    /// @notice Supports the legacy uint64 burnToken ABI used by deployed helpers.
    /// @param token The fungible token address.
    /// @param amount The amount to burn in the token's smallest unit.
    /// @param serialNumbers NFT serial numbers, retained for ABI compatibility.
    /// @return responseCode The HTS response code.
    /// @return newTotalSupply The resulting total supply.
    function burnToken(address token, uint64 amount, int64[] memory serialNumbers)
        external
        htsCall
        returns (int64 responseCode, int64 newTotalSupply)
    {
        if (amount > uint64(type(int64).max)) revert LegacyAmountTooLarge();
        // forge-lint: disable-next-line(unsafe-typecast)
        return this.burnToken(token, int64(amount), serialNumbers);
    }

    /// @notice Associates a fork-local account that has no historical Mirror Node record.
    /// @dev The upstream v0.1.2 slot adapter requires an existing Mirror account.
    ///      A newly deployed local contract has no such record, so this method
    ///      initializes the same HIP-719 slot the pinned adapter would use.
    /// @param token The token storage address.
    /// @param account The newly deployed local account or contract.
    /// @return handled True when the account was absent from the Mirror Node.
    function associateLocalAccount(address token, address account) external htsCall returns (bool handled) {
        (uint32 accountId, bool exists) = this.getAccountId(account);
        if (exists) return false;
        bytes32 accountSlot = bytes32(abi.encodePacked(this.getAccountId.selector, uint64(0), account));
        VM.store(HTS_ADDRESS, accountSlot, bytes32((uint256(1) << 248) | uint256(accountId)));
        bytes32 slot = bytes32(abi.encodePacked(IHRC719.isAssociated.selector, uint192(0), accountId));
        VM.store(token, slot, bytes32(uint256(1)));
        return true;
    }

    function _decodeContractId(bytes memory encodedKey) private pure returns (address contractId) {
        if (encodedKey.length < 4 || encodedKey[0] != 0x0a || encodedKey[2] != 0x18) return address(0);
        uint256 number;
        uint256 shift;
        for (uint256 i = 3; i < encodedKey.length && i < 13; i++) {
            uint256 byteValue = uint8(encodedKey[i]);
            number |= (byteValue & 0x7f) << shift;
            if (byteValue & 0x80 == 0) {
                if (number > type(uint160).max) return address(0);
                // forge-lint: disable-next-line(unsafe-typecast)
                return address(uint160(number));
            }
            shift += 7;
        }
        return address(0);
    }
}
