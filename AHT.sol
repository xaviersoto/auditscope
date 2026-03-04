// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/// @title Affordable Home Token (AHT) — Ethereum canonical
/// @notice Capped, burnable, permit-enabled ERC20. No sale logic. Minting restricted by role and cap.
///         Burns on fulfillment reduce float, reopening headroom under the cap (recyclable supply).
contract AHT is ERC20Capped, ERC20Burnable, ERC20Permit, AccessControl, Pausable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(
        uint256 cap_,          // e.g., 1_000_000e18
        address admin_         // deployer / multisig with DEFAULT_ADMIN_ROLE
    )
        ERC20("Affordable Home Token", "AHT")
        ERC20Capped(cap_)
        ERC20Permit("Affordable Home Token")
    {
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(MINTER_ROLE, admin_); // optional; can remove and grant to a sale contract later
    }

    /// @notice Mint within cap; callable only by MINTER_ROLE
    function mint(address to, uint256 amount) external whenNotPaused onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /// @notice Admin pause/unpause for emergencies
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) { _pause(); }
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) { _unpause(); }

    /// @dev Hook to enforce pause on transfers (OpenZeppelin v5.x uses _update instead of _beforeTokenTransfer)
    function _update(address from, address to, uint256 amount)
        internal
        whenNotPaused
        override(ERC20, ERC20Capped)
    {
        super._update(from, to, amount);
    }
}
