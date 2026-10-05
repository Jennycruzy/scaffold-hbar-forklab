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
    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    bool private immutable _logUrls;
    uint256 private constant TRANSACTION_PAGE_SIZE = 100;
    string private _forkTimestamp;

    /// @dev Resolves the fork block's consensus timestamp once. HTS reads reach this
    ///      contract through STATICCALL, so the timestamp is stored here, where writes
    ///      are allowed, instead of being re-fetched for every query. Offline chains
    ///      have no Mirror Node and leave it empty.
    constructor() {
        _logUrls = VM.envOr("FORKLAB_MIRROR_LOG_URLS", false);
        if (block.chainid >= 295 && block.chainid <= 298) {
            _forkTimestamp =
                VM.parseJsonString(_get(string.concat("blocks/", VM.toString(block.number))), ".timestamp.to");
        }
    }

    /// @notice Fetches token metadata at the fork timestamp.
    /// @param token The long-zero token address.
    /// @return json The Mirror Node response body.
    function fetchTokenData(address token) external override isValid(token) returns (string memory json) {
        return _get(_withTimestamp(string.concat("tokens/0.0.", VM.toString(uint160(token)))));
    }

    /// @notice Fetches a token balance at the fork timestamp.
    /// @dev `balances?timestamp=lte:` returns the server's last balance snapshot at or before the fork, not the
    ///      balance at the fork. The public mainnet hostname is served by several Mirror Nodes that snapshot at
    ///      different times (on 5 October 2026 one returned a snapshot five minutes older than another for the same
    ///      query), so the raw answer depended on which server a run reached. The token transfers between that
    ///      snapshot and the fork are added here, which gives the exact fork balance on every server.
    /// @param token The long-zero token address.
    /// @param accountNum The numeric Hedera account identifier.
    /// @return json A balances response whose `.balances[0].balance` is the balance at the fork timestamp.
    function fetchBalance(address token, uint32 accountNum)
        external
        override
        isValid(token)
        returns (string memory json)
    {
        VM.pauseGasMetering();
        string memory tokenId = string.concat("0.0.", VM.toString(uint160(token)));
        string memory accountId = string.concat("0.0.", VM.toString(accountNum));
        json = _fetch(_withTimestamp(string.concat("tokens/", tokenId, "/balances?account.id=", accountId)));
        string memory snapshot;
        try VM.parseJsonString(json, ".timestamp") returns (string memory value) {
            snapshot = value;
        } catch { }
        // A response with no balance rows carries `"timestamp": null`, which parses as the string "null".
        if (bytes(snapshot).length != 0 && !_eq(snapshot, "null") && _isAfter(_forkTimestamp, snapshot)) {
            int256 balance = VM.keyExistsJson(json, ".balances[0].balance")
                ? int256(VM.parseJsonUint(json, ".balances[0].balance"))
                : int256(0);
            int256 delta = _transfersAfter(tokenId, accountId, snapshot);
            if (delta != 0) {
                json = string.concat(
                    "{\"timestamp\":\"",
                    _forkTimestamp,
                    "\",\"balances\":[{\"account\":\"",
                    accountId,
                    "\",\"balance\":",
                    VM.toString(balance + delta),
                    "}]}"
                );
            }
        }
        VM.resumeGasMetering();
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

    /// @notice Fetches an account-token relationship as of the fork timestamp.
    /// @dev `/accounts/{id}/tokens` rejects a `timestamp` parameter (HTTP 400, "Unknown query
    ///      parameter: timestamp"), so the current relationship is fetched and dropped when it was
    ///      created after the fork. A relationship removed after the fork cannot be seen here.
    /// @param idOrAliasOrEvmAddress An account id, alias, or EVM address.
    /// @param token The long-zero token address.
    /// @return json The Mirror Node response body, with `tokens` empty if associated after the fork.
    function fetchTokenRelationshipOfAccount(string memory idOrAliasOrEvmAddress, address token)
        external
        override
        returns (string memory json)
    {
        json = _get(
            string.concat("accounts/", idOrAliasOrEvmAddress, "/tokens?token.id=0.0.", VM.toString(uint160(token)))
        );
        if (
            bytes(_forkTimestamp).length != 0 && VM.keyExistsJson(json, ".tokens[0].created_timestamp")
                && _isAfter(VM.parseJsonString(json, ".tokens[0].created_timestamp"), _forkTimestamp)
        ) {
            return '{"tokens":[]}';
        }
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

    /// @dev Compares Mirror Node `seconds.nanoseconds` timestamps; nanoseconds are always nine digits.
    function _isAfter(string memory a, string memory b) private pure returns (bool) {
        (uint256 aSeconds, uint256 aNanos) = _splitTimestamp(a);
        (uint256 bSeconds, uint256 bNanos) = _splitTimestamp(b);
        return aSeconds > bSeconds || (aSeconds == bSeconds && aNanos > bNanos);
    }

    function _splitTimestamp(string memory timestamp) private pure returns (uint256 secondsPart, uint256 nanosPart) {
        bytes memory raw = bytes(timestamp);
        bool fraction;
        for (uint256 i; i < raw.length; i++) {
            if (raw[i] == ".") {
                fraction = true;
                continue;
            }
            uint256 digit = uint8(raw[i]) - 48;
            if (fraction) nanosPart = nanosPart * 10 + digit;
            else secondsPart = secondsPart * 10 + digit;
        }
    }

    function _withTimestamp(string memory endpoint) private view returns (string memory) {
        string memory timestamp = _forkTimestamp;
        require(bytes(timestamp).length != 0, "ForklabMirrorNode: no fork timestamp on this chain");
        bytes memory endpointBytes = bytes(endpoint);
        for (uint256 i; i < endpointBytes.length; i++) {
            if (endpointBytes[i] == 0x3f) return string.concat(endpoint, "&timestamp=lte:", timestamp);
        }
        return string.concat(endpoint, "?timestamp=lte:", timestamp);
    }

    /// @dev Gas metering is paused for the fetch: the FFI request and response
    ///      handling are emulator plumbing that a real HTS read never pays for, and
    ///      counting them would make realistic gas limits fail inside emulated HTS.
    function _get(string memory endpoint) private returns (string memory json) {
        VM.pauseGasMetering();
        json = _fetch(endpoint);
        VM.resumeGasMetering();
    }

    /// @dev `_get` without the gas-metering pause, for callers that already paused it.
    function _fetch(string memory endpoint) private returns (string memory json) {
        string memory url = string.concat(_mirrorNodeUrl(), endpoint);
        if (_logUrls) console2.log(url);
        (uint256 status, bytes memory result) = Surl.get(url);
        json = string(result);
        require(status == 200 || status == 404, json);
    }

    /// @dev Sums the account's successful transfers of `tokenId` after `snapshot`, up to the fork timestamp.
    ///      Pages are walked by consensus timestamp, so the result does not depend on `links.next`.
    function _transfersAfter(string memory tokenId, string memory accountId, string memory snapshot)
        private
        returns (int256 delta)
    {
        string memory after_ = snapshot;
        uint256 count = TRANSACTION_PAGE_SIZE;
        while (count == TRANSACTION_PAGE_SIZE) {
            string memory page = _fetch(
                string.concat(
                    "transactions?account.id=",
                    accountId,
                    "&timestamp=gt:",
                    after_,
                    "&timestamp=lte:",
                    _forkTimestamp,
                    "&order=asc&limit=",
                    VM.toString(TRANSACTION_PAGE_SIZE)
                )
            );
            count = 0;
            while (VM.keyExistsJson(page, string.concat(".transactions[", VM.toString(count), "]"))) {
                string memory path = string.concat(".transactions[", VM.toString(count), "]");
                after_ = VM.parseJsonString(page, string.concat(path, ".consensus_timestamp"));
                if (_eq(VM.parseJsonString(page, string.concat(path, ".result")), "SUCCESS")) {
                    delta += _tokenTransfer(page, path, tokenId, accountId);
                }
                count++;
            }
        }
    }

    function _tokenTransfer(string memory page, string memory path, string memory tokenId, string memory accountId)
        private
        view
        returns (int256 amount)
    {
        for (uint256 j;; j++) {
            string memory transfer = string.concat(path, ".token_transfers[", VM.toString(j), "]");
            if (!VM.keyExistsJson(page, transfer)) return amount;
            if (
                _eq(VM.parseJsonString(page, string.concat(transfer, ".token_id")), tokenId)
                    && _eq(VM.parseJsonString(page, string.concat(transfer, ".account")), accountId)
            ) amount += VM.parseJsonInt(page, string.concat(transfer, ".amount"));
        }
    }

    function _eq(string memory a, string memory b) private pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
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
