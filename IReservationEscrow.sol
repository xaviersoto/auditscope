// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/// @title IReservationEscrow — Interface for the property reservation escrow system
/// @author Affordable Home U.S.
/// @notice Defines the public API for listing, reserving, fulfilling, and canceling
///         property reservations backed by AHT tokens.
interface IReservationEscrow {
    enum Status { LISTED, RESERVED, FULFILLED, CANCELED }

    /// @notice Emitted when a new property is listed for reservation.
    /// @param id Unique listing identifier.
    /// @param builder Address of the assigned builder.
    /// @param priceAHT AHT amount required to reserve.
    /// @param reserveUntil Optional reservation expiration timestamp (0 = no expiry).
    event Listed(uint256 indexed id, address indexed builder, uint256 indexed priceAHT, uint40 reserveUntil);

    /// @notice Emitted when a listing's price or expiration is updated.
    /// @param id Listing identifier.
    /// @param priceAHT Updated price in AHT.
    /// @param reserveUntil Updated expiration timestamp.
    event Updated(uint256 indexed id, uint256 indexed priceAHT, uint40 indexed reserveUntil);

    /// @notice Emitted when a user reserves a listed property.
    /// @param id Listing identifier.
    /// @param reserver Address of the user who reserved.
    /// @param amount AHT amount escrowed.
    event Reserved(uint256 indexed id, address indexed reserver, uint256 indexed amount);

    /// @notice Emitted when a reservation is fulfilled and escrowed AHT is burned.
    /// @param id Listing identifier.
    /// @param burned Amount of AHT permanently burned.
    event Fulfilled(uint256 indexed id, uint256 indexed burned);

    /// @notice Emitted when a reservation is canceled and escrowed AHT is refunded.
    /// @param id Listing identifier.
    /// @param refunded Amount of AHT returned to the reserver.
    event Canceled(uint256 indexed id, uint256 indexed refunded);

    /// @notice List a new property for reservation.
    /// @param id Unique listing identifier (must be non-zero and unused).
    /// @param builder Address authorized to fulfill or cancel this listing.
    /// @param priceAHT AHT amount required to reserve.
    /// @param reserveUntil Optional expiration timestamp (0 = no expiry).
    function list(uint256 id, address builder, uint256 priceAHT, uint40 reserveUntil) external;

    /// @notice Update an existing listing's price or expiration.
    /// @param id Listing identifier.
    /// @param priceAHT New price in AHT.
    /// @param reserveUntil New expiration timestamp.
    function updateListing(uint256 id, uint256 priceAHT, uint40 reserveUntil) external;

    /// @notice Reserve a listed property by escrowing AHT (with optional EIP-2612 permit).
    /// @param id Listing identifier.
    /// @param amount AHT amount (must match listing price).
    /// @param deadline Permit deadline (0 to skip permit).
    /// @param v Permit signature v component.
    /// @param r Permit signature r component.
    /// @param s Permit signature s component.
    function reserve(
        uint256 id,
        uint256 amount,
        uint256 deadline,
        uint8 v, bytes32 r, bytes32 s
    ) external;

    /// @notice Fulfill a reservation: burns escrowed AHT permanently.
    /// @param id Listing identifier.
    function fulfill(uint256 id) external;

    /// @notice Cancel a reservation: refunds escrowed AHT to the reserver.
    /// @param id Listing identifier.
    function cancel(uint256 id) external;

    /// @notice Read a listing's current state.
    /// @param id Listing identifier.
    /// @return _id Listing id.
    /// @return builder Assigned builder address.
    /// @return priceAHT Reservation price in AHT.
    /// @return status Current listing status.
    /// @return reserver Address that reserved (address(0) if none).
    /// @return reserveUntil Expiration timestamp.
    function listings(uint256 id) external view returns (
        uint256 _id,
        address builder,
        uint256 priceAHT,
        Status status,
        address reserver,
        uint40 reserveUntil
    );

    /// @notice Read the escrowed AHT balance for a listing.
    /// @param id Listing identifier.
    /// @return Amount of AHT currently held in escrow.
    function escrowed(uint256 id) external view returns (uint256);
}
