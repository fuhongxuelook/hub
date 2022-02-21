// SPDX-License-Identifier: MIT

pragma solidity ^0.8.1;

/**
 * @dev Token airdrop interface
 */

interface IAirdrop {
    function airdrop(address recipient, uint256 amount) external;
}