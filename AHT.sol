// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Capped} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title Affordable Home Token (AHT) — Ethereum canonical
/// @author Affordable Home U.S.
/// @notice Capped, burnable, permit-enabled ERC20. No sale logic. Minting restricted by role and cap.
///         Burns on fulfillment reduce float, reopening headroom under the cap (recyclable supply).
contract AHT is ERC20Capped, ERC20Burnable, ERC20Permit, AccessControl, Pausable {
    /// @notice Role identifier for addresses permitted to mint new tokens.
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Deploy AHT with a hard supply cap and an initial admin.
    /// @param cap_ Maximum token supply (e.g., 1_000_000e18).
    /// @param admin_ Address receiving DEFAULT_ADMIN_ROLE and MINTER_ROLE.
    constructor(
        uint256 cap_,
        address admin_
    )
        ERC20("Affordable Home Token", "AHOME")
        ERC20Capped(cap_)
        ERC20Permit("Affordable Home Token")
    {
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(MINTER_ROLE, admin_);
    }

    /// @notice Mint new tokens within the cap. Callable only by MINTER_ROLE.
    /// @param to Recipient address.
    /// @param amount Number of tokens to mint (in wei units).
    function mint(address to, uint256 amount) external whenNotPaused onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /// @notice Pause all token transfers. Admin only — for emergencies.
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) { _pause(); }

    /// @notice Unpause token transfers. Admin only.
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) { _unpause(); }

    /// @notice Hook that enforces pause on all transfers and respects the supply cap.
    /// @param from Sender (address(0) for mints).
    /// @param to Recipient (address(0) for burns).
    /// @param amount Transfer amount.
    function _update(address from, address to, uint256 amount)
        internal
        whenNotPaused
        override(ERC20, ERC20Capped)
    {
        super._update(from, to, amount);
    }
}
