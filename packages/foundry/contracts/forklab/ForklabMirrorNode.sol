// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Vm } from "forge-std/Vm.sol";
import { console2 } from "forge-std/console2.sol";
import { MirrorNode } from "hedera-forking/MirrorNode.sol";
import { Surl } from "hedera-forking/Surl.sol";

/// @notice Mirror Node client that pins state reads to the selected fork block.
/// @dev The upstream client only timestamped balance reads. Forklab applies the
///      same block-derived upper bound to every endpoint used by HTS state reads.
contract ForklabMirrorNode is MirrorNode {
    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    mapping(string endpoint => string response) private _responses;
    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    uint256 private immutable _forkBlockNumber;
    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    bool private immutable _logUrls;

    constructor() {
        _forkBlockNumber = block.number;
        _logUrls = VM.envOr("FORKLAB_MIRROR_LOG_URLS", false);
    }

    /// @notice Fetches token metadata at the fork timestamp.
    /// @param token The long-zero token address.
    /// @return json The Mirror Node response body.
    function fetchTokenData(address token) external override isValid(token) returns (string memory json) {
        return _get(_withTimestamp(string.concat("tokens/0.0.", VM.toString(uint160(token)))));
    }

    /// @notice Fetches a token balance at the fork timestamp.
    /// @param token The long-zero token address.
    /// @param accountNum The numeric Hedera account identifier.
    /// @return json The Mirror Node response body.
    function fetchBalance(address token, uint32 accountNum)
        external
        override
        isValid(token)
        returns (string memory json)
    {
        return _get(
            _withTimestamp(
                string.concat(
                    "tokens/0.0.", VM.toString(uint160(token)), "/balances?account.id=0.0.", VM.toString(accountNum)
                )
            )
        );
    }

    /// @notice Fetches a token allowance at the fork timestamp.
    /// @param token The long-zero token address.
    /// @param ownerNum The owner account number.
    /// @param spenderNum The spender account number.
    /// @return json The Mirror Node response body.
    function fetchAllowance(address token, uint32 ownerNum, uint32 spenderNum)
        external
        override
        isValid(token)
        returns (string memory json)
    {
        return _get(
            _withTimestamp(
                string.concat(
                    "accounts/0.0.",
                    VM.toString(ownerNum),
                    "/allowances/tokens?token.id=0.0.",
                    VM.toString(uint160(token)),
                    "&spender.id=0.0.",
                    VM.toString(spenderNum)
                )
            )
        );
    }

    /// @notice Fetches an NFT allowance at the fork timestamp.
    /// @param token The long-zero token address.
    /// @param ownerNum The owner account number.
    /// @param operatorNum The operator account number.
    /// @return json The Mirror Node response body.
    function fetchNftAllowance(address token, uint32 ownerNum, uint32 operatorNum)
        external
        override
        isValid(token)
        returns (string memory json)
    {
        return _get(
            _withTimestamp(
                string.concat(
                    "accounts/0.0.",
                    VM.toString(ownerNum),
                    "/allowances/nfts?token.id=0.0.",
                    VM.toString(uint160(token)),
                    "&account.id=0.0.",
                    VM.toString(operatorNum)
                )
            )
        );
    }

    /// @notice Fetches an account record at the fork timestamp.
    /// @param idOrAliasOrEvmAddress An account id, alias, or EVM address.
    /// @return json The Mirror Node response body.
    function fetchAccount(string memory idOrAliasOrEvmAddress) external override returns (string memory json) {
        return _get(_withTimestamp(string.concat("accounts/", idOrAliasOrEvmAddress, "?transactions=false")));
    }

    /// @notice Fetches an account-token relationship at the fork timestamp.
    /// @param idOrAliasOrEvmAddress An account id, alias, or EVM address.
    /// @param token The long-zero token address.
    /// @return json The Mirror Node response body.
    function fetchTokenRelationshipOfAccount(string memory idOrAliasOrEvmAddress, address token)
        external
        override
        returns (string memory json)
    {
        return _get(
            _withTimestamp(
                string.concat("accounts/", idOrAliasOrEvmAddress, "/tokens?token.id=0.0.", VM.toString(uint160(token)))
            )
        );
    }

    /// @notice Fetches a non-fungible token record at the fork timestamp.
    /// @param token The long-zero token address.
    /// @param serial The NFT serial number.
    /// @return json The Mirror Node response body.
    function fetchNonFungibleToken(address token, uint32 serial)
        external
        override
        isValid(token)
        returns (string memory json)
    {
        return _get(
            _withTimestamp(string.concat("tokens/0.0.", VM.toString(uint160(token)), "/nfts/", VM.toString(serial)))
        );
    }

    /// @notice Fetches a block record without adding a recursive timestamp filter.
    /// @param blockNumber The fork block number.
    /// @return json The Mirror Node response body.
    function fetchBlock(uint256 blockNumber) external returns (string memory json) {
        return _get(string.concat("blocks/", VM.toString(blockNumber)));
    }

    function _withTimestamp(string memory endpoint) private returns (string memory) {
        string memory json = this.fetchBlock(_forkBlockNumber);
        string memory timestamp = VM.parseJsonString(json, ".timestamp.to");
        bytes memory endpointBytes = bytes(endpoint);
        for (uint256 i; i < endpointBytes.length; i++) {
            if (endpointBytes[i] == 0x3f) return string.concat(endpoint, "&timestamp=lte:", timestamp);
        }
        return string.concat(endpoint, "?timestamp=lte:", timestamp);
    }

    function _get(string memory endpoint) private returns (string memory json) {
        json = _responses[endpoint];
        if (bytes(json).length != 0) return json;
        string memory url = string.concat(_mirrorNodeUrl(), endpoint);
        if (_logUrls) console2.log(url);
        (uint256 status, bytes memory result) = Surl.get(url);
        json = string(result);
        require(status == 200 || status == 404, json);
    }

    function _mirrorNodeUrl() private view returns (string memory url) {
        if (block.chainid == 295) {
            return string.concat(
                VM.envOr("HEDERA_MIRROR_MAINNET_URL", string("https://mainnet-public.mirrornode.hedera.com")),
                "/api/v1/"
            );
        }
        if (block.chainid == 296) {
            return string.concat(
                VM.envOr("HEDERA_MIRROR_TESTNET_URL", string("https://testnet.mirrornode.hedera.com")), "/api/v1/"
            );
        }
        if (block.chainid == 297) return "https://previewnet.mirrornode.hedera.com/api/v1/";
        if (block.chainid == 298) return "http://localhost:5551/api/v1/";
        revert("Unsupported Hedera Mirror Node chain id");
    }
}
