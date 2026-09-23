// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

contract ComplexLayout {
    uint16 public first;
    uint8 public second;
    mapping(address => uint128) internal balances;

    struct Config {
        uint128 low;
        uint64 high;
    }

    Config internal config;
    uint256[2] private __gap;
    uint256 public tail;

    uint256 transient private nonce;
    uint256 transient private lock;
}
