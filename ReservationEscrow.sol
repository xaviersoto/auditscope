// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IAHT} from "./interfaces/IAHT.sol";

/// @title ReservationEscrow — reserves homes using AHT; burns on fulfill, refunds on cancel.
/// @author Affordable Home U.S.
/// @notice Prices are denominated in AHT units. No USD/oracle logic.
contract ReservationEscrow is ReentrancyGuard, AccessControl {

    // ──────────────────── Custom Errors ────────────────────

    /// @dev Listing id must be non-zero.
    error IdZero();
    /// @dev A listing with this id already exists.
    error ListingExists();
    /// @dev Builder address must not be the zero address.
    error BuilderZero();
    /// @dev No listing found for the given id.
    error NoListing();
    /// @dev Caller is not the builder or an admin.
    error NotBuilderOrAdmin();
    /// @dev Listing is not in the required status.
    error WrongStatus();
    /// @dev Reservation window has expired.
    error Expired();
    /// @dev Supplied amount does not match the listing price.
    error PriceMismatch();
    /// @dev Listing is already reserved by another address.
    error AlreadyReserved();
    /// @dev Token transfer failed.
    error TransferFailed();
    /// @dev No tokens are held in escrow for this listing.
    error NoEscrow();
    /// @dev Nothing to refund (zero escrow or zero reserver).
    error NothingToRefund();

    // ──────────────────── State ────────────────────

    /// @notice Role identifier for builder addresses.
    bytes32 public constant BUILDER_ROLE = keccak256("BUILDER_ROLE");

    /// @notice The AHT token contract (for burn calls).
    IAHT public immutable AHT_TOKEN;

    /// @notice The AHT token's EIP-2612 permit interface.
    IERC20Permit public immutable AHT_PERMIT;

    enum Status { LISTED, RESERVED, FULFILLED, CANCELED }

    struct Listing {
        uint256 id;
        address builder;      // controls fulfill/cancel for this listing
        uint256 priceAHT;     // amount of AHT required to reserve
        Status  status;
        address reserver;     // who reserved
        uint40  reserveUntil; // optional expiration (0 = no expiry)
    }

    /// @notice Mapping from listing id to its full state.
    mapping(uint256 => Listing) public listings;

    /// @notice Mapping from listing id to the AHT amount held in escrow.
    mapping(uint256 => uint256) public escrowed;

    // ──────────────────── Events ────────────────────

    /// @notice Emitted when a new property is listed.
    /// @param id Listing identifier.
    /// @param builder Assigned builder.
    /// @param priceAHT Reservation price.
    /// @param reserveUntil Expiration timestamp (0 = none).
    event Listed(uint256 indexed id, address indexed builder, uint256 indexed priceAHT, uint40 reserveUntil);

    /// @notice Emitted when a listing is updated.
    /// @param id Listing identifier.
    /// @param priceAHT New price.
    /// @param reserveUntil New expiration.
    event Updated(uint256 indexed id, uint256 indexed priceAHT, uint40 indexed reserveUntil);

    /// @notice Emitted when a user reserves a property.
    /// @param id Listing identifier.
    /// @param reserver User who reserved.
    /// @param amount AHT escrowed.
    event Reserved(uint256 indexed id, address indexed reserver, uint256 indexed amount);

    /// @notice Emitted when a reservation is fulfilled and AHT burned.
    /// @param id Listing identifier.
    /// @param burned AHT permanently destroyed.
    event Fulfilled(uint256 indexed id, uint256 indexed burned);

    /// @notice Emitted when a reservation is canceled and AHT refunded.
    /// @param id Listing identifier.
    /// @param refunded AHT returned to reserver.
    event Canceled(uint256 indexed id, uint256 indexed refunded);

    // ──────────────────── Constructor ────────────────────

    /// @notice Deploy the escrow, binding it to an AHT token address.
    /// @param aht Address of the deployed AHT contract.
    constructor(address aht) {
        if (aht == address(0)) revert BuilderZero();
        AHT_TOKEN = IAHT(aht);
        AHT_PERMIT = IERC20Permit(aht);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(BUILDER_ROLE, msg.sender);
    }

    // ──────────────────── Admin / Builder ────────────────────

    /// @notice List a new property for reservation. Admin only.
    /// @param id Unique listing id (must be non-zero and unused).
    /// @param builder Address authorized to fulfill or cancel.
    /// @param priceAHT AHT required to reserve.
    /// @param reserveUntil Optional expiration (0 = no expiry).
    function list(
        uint256 id,
        address builder,
        uint256 priceAHT,
        uint40 reserveUntil
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (id == 0) revert IdZero();
        if (listings[id].id != 0) revert ListingExists();
        if (builder == address(0)) revert BuilderZero();
        listings[id] = Listing({
            id: id,
            builder: builder,
            priceAHT: priceAHT,
            status: Status.LISTED,
            reserver: address(0),
            reserveUntil: reserveUntil
        });
        emit Listed(id, builder, priceAHT, reserveUntil);
    }

    /// @notice Update price or expiration of an existing listing. Builder or admin only.
    /// @param id Listing identifier.
    /// @param priceAHT New reservation price.
    /// @param reserveUntil New expiration timestamp.
    function updateListing(
        uint256 id,
        uint256 priceAHT,
        uint40 reserveUntil
    ) external {
        Listing storage listing = listings[id];
        if (listing.id == 0) revert NoListing();
        if (msg.sender != listing.builder && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert NotBuilderOrAdmin();
        if (listing.status != Status.LISTED) revert WrongStatus();
        listing.priceAHT = priceAHT;
        listing.reserveUntil = reserveUntil;
        emit Updated(id, priceAHT, reserveUntil);
    }

    // ──────────────────── User Flow ────────────────────

    /// @notice Reserve a property by escrowing AHT (with optional EIP-2612 permit).
    /// @param id Listing identifier.
    /// @param amount AHT amount (must equal listing price).
    /// @param deadline Permit deadline (pass 0 with zero v/r/s to skip permit).
    /// @param v Permit signature v.
    /// @param r Permit signature r.
    /// @param s Permit signature s.
    function reserve(
        uint256 id,
        uint256 amount,
        uint256 deadline,
        uint8 v, bytes32 r, bytes32 s
    ) external nonReentrant {
        Listing storage listing = listings[id];
        if (listing.id == 0) revert NoListing();
        if (listing.status != Status.LISTED) revert WrongStatus();
        if (listing.reserveUntil != 0 && block.timestamp > listing.reserveUntil) revert Expired();
        if (amount != listing.priceAHT || amount == 0) revert PriceMismatch();
        if (listing.reserver != address(0)) revert AlreadyReserved();

        // Optional gasless approval via permit; skip if signature is zeroed out
        if (deadline != 0 || v != 0 || r != bytes32(0) || s != bytes32(0)) {
            AHT_PERMIT.permit(msg.sender, address(this), amount, deadline, v, r, s);
        }

        // Pull AHT into escrow
        if (!IERC20(address(AHT_TOKEN)).transferFrom(msg.sender, address(this), amount)) revert TransferFailed();

        escrowed[id] = amount;
        listing.status = Status.RESERVED;
        listing.reserver = msg.sender;

        emit Reserved(id, msg.sender, amount);
    }

    /// @notice Fulfill a reservation: burns escrowed AHT permanently. Builder or admin only.
    /// @param id Listing identifier.
    function fulfill(uint256 id) external nonReentrant {
        Listing storage listing = listings[id];
        if (listing.id == 0) revert NoListing();
        if (listing.status != Status.RESERVED) revert WrongStatus();
        if (msg.sender != listing.builder && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert NotBuilderOrAdmin();

        uint256 amt = escrowed[id];
        if (amt == 0) revert NoEscrow();

        escrowed[id] = 0;
        listing.status = Status.FULFILLED;

        // Burn via the token's burn function (true burn, not transfer to 0xdead).
        // The escrow contract holds the tokens, so burn(amount) burns from address(this).
        AHT_TOKEN.burn(amt);

        emit Fulfilled(id, amt);
    }

    /// @notice Cancel a reservation: refunds escrowed AHT to the reserver. Builder or admin only.
    /// @param id Listing identifier.
    function cancel(uint256 id) external nonReentrant {
        Listing storage listing = listings[id];
        if (listing.id == 0) revert NoListing();
        if (listing.status != Status.RESERVED) revert WrongStatus();
        if (msg.sender != listing.builder && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert NotBuilderOrAdmin();

        uint256 amt = escrowed[id];
        address to = listing.reserver;
        if (amt == 0 || to == address(0)) revert NothingToRefund();

        escrowed[id] = 0;
        listing.status = Status.CANCELED;

        if (!IERC20(address(AHT_TOKEN)).transfer(to, amt)) revert TransferFailed();

        emit Canceled(id, amt);
    }
}
