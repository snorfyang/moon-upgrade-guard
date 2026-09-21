// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

contract Counter {
    uint128 public value;

    function set(uint256 next) public {
        value = uint128(next);
    }
}
