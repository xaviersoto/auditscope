// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IReservationEscrow {
    enum Status { LISTED, RESERVED, FULFILLED, CANCELED }

    event Listed(uint256 indexed id, address indexed builder, uint256 priceAHT, uint40 reserveUntil);
    event Updated(uint256 indexed id, uint256 priceAHT, uint40 reserveUntil);
    event Reserved(uint256 indexed id, address indexed reserver, uint256 amount);
    event Fulfilled(uint256 indexed id, uint256 burned);
    event Canceled(uint256 indexed id, uint256 refunded);

    function list(uint256 id, address builder, uint256 priceAHT, uint40 reserveUntil) external;
    function updateListing(uint256 id, uint256 priceAHT, uint40 reserveUntil) external;

    function reserve(
        uint256 id,
        uint256 amount,
        uint256 deadline,
        uint8 v, bytes32 r, bytes32 s
    ) external;

    function fulfill(uint256 id) external;
    function cancel(uint256 id) external;

    function listings(uint256 id) external view returns (
        uint256 _id,
        address builder,
        uint256 priceAHT,
        Status status,
        address reserver,
        uint40 reserveUntil
    );

    function escrowed(uint256 id) external view returns (uint256);
}
