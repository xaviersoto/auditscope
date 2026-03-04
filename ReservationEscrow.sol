// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IAHT.sol";

/// @title ReservationEscrow — reserves homes using AHT; burns on fulfill, refunds on cancel.
/// @notice Prices are denominated in AHT units. No USD/oracle logic.
contract ReservationEscrow is ReentrancyGuard, AccessControl {
    bytes32 public constant BUILDER_ROLE = keccak256("BUILDER_ROLE");

    IAHT public immutable AHT_TOKEN;
    IERC20Permit public immutable AHT_PERMIT;

    enum Status { LISTED, RESERVED, FULFILLED, CANCELED }

    struct Listing {
        uint256 id;
        address builder;     // controls fulfill/cancel for this listing
        uint256 priceAHT;    // amount of AHT required to reserve
        Status  status;
        address reserver;    // who reserved
        uint40  reserveUntil;// optional expiration (0 = no expiry)
    }

    // listingId => listing
    mapping(uint256 => Listing) public listings;
    // listingId => escrowed balance
    mapping(uint256 => uint256) public escrowed;

    event Listed(uint256 indexed id, address indexed builder, uint256 priceAHT, uint40 reserveUntil);
    event Updated(uint256 indexed id, uint256 priceAHT, uint40 reserveUntil);
    event Reserved(uint256 indexed id, address indexed reserver, uint256 amount);
    event Fulfilled(uint256 indexed id, uint256 burned);
    event Canceled(uint256 indexed id, uint256 refunded);

    constructor(address aht) {
        require(aht != address(0), "aht=0");
        AHT_TOKEN = IAHT(aht);
        AHT_PERMIT = IERC20Permit(aht);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // --- Admin / Builder functions ---

    function list(
        uint256 id,
        address builder,
        uint256 priceAHT,
        uint40 reserveUntil
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(listings[id].id == 0, "exists");
        require(builder != address(0), "builder=0");
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

    function updateListing(
        uint256 id,
        uint256 priceAHT,
        uint40 reserveUntil
    ) external {
        Listing storage L = listings[id];
        require(L.id != 0, "no listing");
        require(msg.sender == L.builder || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "not builder/admin");
        require(L.status == Status.LISTED, "not LISTED");
        L.priceAHT = priceAHT;
        L.reserveUntil = reserveUntil;
        emit Updated(id, priceAHT, reserveUntil);
    }

    // --- User flow ---

    /// @notice Reserve by transferring required AHT into escrow (optionally using EIP-2612 permit).
    function reserve(
        uint256 id,
        uint256 amount,
        uint256 deadline,
        uint8 v, bytes32 r, bytes32 s
    ) external nonReentrant {
        Listing storage L = listings[id];
        require(L.id != 0, "no listing");
        require(L.status == Status.LISTED, "not LISTED");
        if (L.reserveUntil != 0) require(block.timestamp <= L.reserveUntil, "expired");
        require(amount == L.priceAHT && amount > 0, "price mismatch");
        require(L.reserver == address(0), "already reserved");

        // Optional gasless approval via permit; if signature is zeroed out, skip
        if (deadline != 0 || v != 0 || r != bytes32(0) || s != bytes32(0)) {
            AHT_PERMIT.permit(msg.sender, address(this), amount, deadline, v, r, s);
        }

        // Pull AHT into escrow
        require(IERC20(address(AHT_TOKEN)).transferFrom(msg.sender, address(this), amount), "pull failed");

        escrowed[id] = amount;
        L.status = Status.RESERVED;
        L.reserver = msg.sender;

        emit Reserved(id, msg.sender, amount);
    }

    /// @notice Fulfill: burns escrowed AHT using the token's burn function (requires IAHT interface)
    function fulfill(uint256 id) external nonReentrant {
        Listing storage L = listings[id];
        require(L.id != 0, "no listing");
        require(L.status == Status.RESERVED, "not RESERVED");
        require(msg.sender == L.builder || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "not builder/admin");

        uint256 amt = escrowed[id];
        require(amt > 0, "no escrow");

        escrowed[id] = 0;
        L.status = Status.FULFILLED;

        // Burn via the token's burn function (true burn, not transfer to 0xdead)
        // The escrow contract holds the tokens, so we call burn(amount) on the token
        AHT_TOKEN.burn(amt);

        emit Fulfilled(id, amt);
    }

    /// @notice Cancel: refunds escrowed AHT to the reserver.
    function cancel(uint256 id) external nonReentrant {
        Listing storage L = listings[id];
        require(L.id != 0, "no listing");
        require(L.status == Status.RESERVED, "not RESERVED");
        require(msg.sender == L.builder || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "not builder/admin");

        uint256 amt = escrowed[id];
        address to = L.reserver;
        require(amt > 0 && to != address(0), "nothing to refund");

        escrowed[id] = 0;
        L.status = Status.CANCELED;

        require(IERC20(address(AHT_TOKEN)).transfer(to, amt), "refund failed");

        emit Canceled(id, amt);
    }
}
