// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

contract ComplexLayout {
    uint8 public first;
    uint8 public second;
    mapping(address => uint256) internal balances;

    struct Config {
        uint128 low;
        uint128 high;
    }

    Config internal config;
    uint256[2] private __gap;
    uint256 public tail;

    uint256 transient private lock;
    uint256 transient private nonce;
}
