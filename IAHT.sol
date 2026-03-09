// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

/// @title IAHT — Interface for the Affordable Home Token
/// @author Affordable Home U.S.
/// @notice Extends IERC20 and IERC20Permit with mint, burn, and pause capabilities.
interface IAHT is IERC20, IERC20Permit {
    /// @notice Mint new tokens to `to` within the supply cap.
    /// @param to Recipient address.
    /// @param amount Number of tokens to mint.
    function mint(address to, uint256 amount) external;

    /// @notice Burn `amount` tokens from the caller's balance.
    /// @param amount Number of tokens to burn.
    function burn(uint256 amount) external;

    /// @notice Pause all token transfers (admin emergency).
    function pause() external;

    /// @notice Unpause token transfers.
    function unpause() external;
}
