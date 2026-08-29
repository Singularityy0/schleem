// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { CappedCallMath } from "./CappedCallMath.sol";
import { BlackScholes } from "./BlackScholes.sol";
import { IPriceOracle } from "./IPriceOracle.sol";

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @notice Five-minute fully-reserved capped-call market with verified historical settlement.
contract SchmecklesMarket {
    using CappedCallMath for uint256;

    uint64 public constant EPOCH_DURATION = 300;
    uint64 public constant TRADING_CLOSE_BUFFER = 30;
    uint64 public constant SETTLEMENT_TIMEOUT = 600;
    uint64 public constant MAX_LIVE_PRICE_AGE = 60;
    // Supra's component feeds can advance in multi-second jumps. Fifteen seconds keeps
    // settlement tightly bound to expiry without requiring an observation that may not exist.
    uint64 public constant SETTLEMENT_OBSERVATION_WINDOW = 15;
    uint256 public constant BPS = 10_000;

    enum EpochStatus {
        Uninitialized,
        Trading,
        Locked,
        AwaitingSettlement,
        Settled,
        Cancelled
    }

    enum OracleMode {
        SUPRA_VERIFIED
    }

    enum QuoteMode {
        BLACK_SCHOLES_CALL_SPREAD
    }

    struct OpenParams {
        uint16 capBps;
        uint128 maxPayout;
        uint32 pricingVolBps;
        uint16 jumpSizeBps;
        uint16 jumpWeightBps;
        uint16 feeBps;
    }

    struct Epoch {
        EpochStatus storedStatus;
        uint64 openedAt;
        uint64 tradingClose;
        uint64 expiry;
        uint64 settlementDeadline;
        uint64 reportPublishTime;
        uint256 strike;
        uint256 cap;
        uint256 maxPayout;
        uint32 pricingVolBps;
        uint16 jumpSizeBps;
        uint16 jumpWeightBps;
        uint16 feeBps;
        uint256 settlementPrice;
        uint256 payoutPerTicket;
        uint256 totalTickets;
        uint256 totalPaymentEscrow;
        uint256 totalProtocolFeeEscrow;
        uint256 totalPayoutLiability;
    }

    struct Position {
        uint256 quantity;
        uint256 payment;
        bool closed;
    }

    IERC20Minimal public immutable collateral;
    IPriceOracle public immutable oracle;
    OracleMode public constant oracleMode = OracleMode.SUPRA_VERIFIED;
    QuoteMode public constant quoteMode = QuoteMode.BLACK_SCHOLES_CALL_SPREAD;

    address public owner;
    address public keeper;
    uint256 public activeEpochId;
    uint256 public reservedLiability;
    uint256 public claimableLiability;
    uint256 public refundableEscrow;
    uint256 public accruedProtocolFees;

    mapping(uint256 => Epoch) public epochs;
    mapping(uint256 => mapping(address => Position)) public positions;

    uint256 private locked = 1;

    error Unauthorized();
    error ReentrantCall();
    error ZeroAddress();
    error ZeroAmount();
    error InvalidEpoch();
    error InvalidEpochState();
    error InvalidParameters();
    error StalePrice();
    error FuturePrice();
    error InvalidSettlementObservation();
    error PremiumSlippage();
    error InsufficientFreeCollateral();
    error TransferFailed();
    error TransferAmountMismatch();
    error PositionAlreadyClosed();
    error NoPosition();
    error InsolventAccounting();

    event CollateralDeposited(address indexed from, uint256 amount);
    event FreeCollateralWithdrawn(address indexed to, uint256 amount);
    event KeeperChanged(address indexed previousKeeper, address indexed newKeeper);
    event LivePriceUpdated(uint256 price, uint64 publishTime);
    event EpochOpened(
        uint256 indexed epochId, uint256 strike, uint256 cap, uint64 expiry, uint256 maxPayout
    );
    event TicketsPurchased(
        uint256 indexed epochId,
        address indexed buyer,
        uint256 quantity,
        uint256 payment,
        uint256 reserveAdded,
        uint256 observedPrice
    );
    event EpochSettled(
        uint256 indexed epochId,
        uint256 settlementPrice,
        uint64 reportPublishTime,
        uint256 payoutPerTicket,
        uint256 aggregatePayout
    );
    event EpochCancelled(uint256 indexed epochId, uint256 reserveReleased);
    event Claimed(uint256 indexed epochId, address indexed user, uint256 amount);
    event Refunded(uint256 indexed epochId, address indexed user, uint256 amount);
    event ProtocolFeesWithdrawn(address indexed to, uint256 amount);

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlyKeeper() {
        if (msg.sender != keeper) revert Unauthorized();
        _;
    }

    modifier onlyOwnerOrKeeper() {
        if (msg.sender != owner && msg.sender != keeper) revert Unauthorized();
        _;
    }

    modifier nonReentrant() {
        if (locked != 1) revert ReentrantCall();
        locked = 2;
        _;
        locked = 1;
    }

    constructor(address collateral_, address oracle_, address owner_, address keeper_) {
        if (
            collateral_ == address(0) || oracle_ == address(0) || owner_ == address(0)
                || keeper_ == address(0)
        ) revert ZeroAddress();
        collateral = IERC20Minimal(collateral_);
        oracle = IPriceOracle(oracle_);
        owner = owner_;
        keeper = keeper_;
    }

    function setKeeper(address newKeeper) external onlyOwner {
        if (newKeeper == address(0)) revert ZeroAddress();
        emit KeeperChanged(keeper, newKeeper);
        keeper = newKeeper;
    }

    function depositCollateral(uint256 amount) external onlyOwner nonReentrant {
        if (amount == 0) revert ZeroAmount();
        uint256 beforeBalance = collateral.balanceOf(address(this));
        _safeTransferFrom(msg.sender, address(this), amount);
        if (collateral.balanceOf(address(this)) != beforeBalance + amount) {
            revert TransferAmountMismatch();
        }
        emit CollateralDeposited(msg.sender, amount);
    }

    function withdrawFreeCollateral(address to, uint256 amount) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (amount > freeCollateral()) revert InsufficientFreeCollateral();
        _safeTransfer(to, amount);
        emit FreeCollateralWithdrawn(to, amount);
    }

    function withdrawProtocolFees(address to, uint256 amount) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0 || amount > accruedProtocolFees) revert ZeroAmount();
        accruedProtocolFees -= amount;
        _safeTransfer(to, amount);
        emit ProtocolFeesWithdrawn(to, amount);
    }

    function openEpoch(OpenParams calldata params)
        external
        onlyOwnerOrKeeper
        returns (uint256 epochId)
    {
        if (activeEpochId != 0) {
            EpochStatus previous = epochStatus(activeEpochId);
            if (previous != EpochStatus.Settled && previous != EpochStatus.Cancelled) {
                revert InvalidEpochState();
            }
        }
        if (
            params.capBps == 0 || params.maxPayout == 0 || params.pricingVolBps == 0
                || params.jumpWeightBps > BPS || params.feeBps > BPS
        ) revert InvalidParameters();

        (uint256 price, uint64 publishTime) = oracle.latest();
        _validateLiveObservation(price, publishTime);
        uint256 cap = CappedCallMath.mulDiv(price, BPS + params.capBps, BPS);
        if (cap <= price) revert InvalidParameters();
        uint256 baseReference = BlackScholes.callSpreadPrice(
            price, price, cap, params.maxPayout, params.pricingVolBps, EPOCH_DURATION
        );
        CappedCallMath.quote(
            baseReference,
            params.maxPayout,
            price,
            price,
            cap,
            params.jumpSizeBps,
            params.jumpWeightBps,
            params.feeBps
        );

        epochId = activeEpochId + 1;
        uint64 openedAt = uint64(block.timestamp);
        uint64 expiry = openedAt + EPOCH_DURATION;
        epochs[epochId] = Epoch({
            storedStatus: EpochStatus.Trading,
            openedAt: openedAt,
            tradingClose: expiry - TRADING_CLOSE_BUFFER,
            expiry: expiry,
            settlementDeadline: expiry + SETTLEMENT_TIMEOUT,
            reportPublishTime: 0,
            strike: price,
            cap: cap,
            maxPayout: params.maxPayout,
            pricingVolBps: params.pricingVolBps,
            jumpSizeBps: params.jumpSizeBps,
            jumpWeightBps: params.jumpWeightBps,
            feeBps: params.feeBps,
            settlementPrice: 0,
            payoutPerTicket: 0,
            totalTickets: 0,
            totalPaymentEscrow: 0,
            totalProtocolFeeEscrow: 0,
            totalPayoutLiability: 0
        });
        activeEpochId = epochId;
        emit EpochOpened(epochId, price, cap, expiry, params.maxPayout);
    }

    /// @notice Permissionlessly submits a current Supra proof before open/quote/buy operations.
    function updateLivePrice(bytes calldata proof)
        external
        returns (uint256 price, uint64 publishTime)
    {
        (price, publishTime) = oracle.updateLive(proof);
        _validateLiveObservation(price, publishTime);
        emit LivePriceUpdated(price, publishTime);
    }

    function buy(uint256 epochId, uint256 quantity, uint256 maxPremium)
        external
        nonReentrant
        returns (uint256 payment)
    {
        if (quantity == 0) revert ZeroAmount();
        if (epochStatus(epochId) != EpochStatus.Trading) revert InvalidEpochState();

        Epoch storage epoch = epochs[epochId];
        (uint256 observedPrice, uint64 publishTime) = oracle.latest();
        _validateLiveObservation(observedPrice, publishTime);
        CappedCallMath.Quote memory perTicket = _quote(epoch, observedPrice);
        payment = perTicket.allIn * quantity;
        if (payment > maxPremium) revert PremiumSlippage();

        uint256 reserveAdded = epoch.maxPayout * quantity;
        // Deliberately checked before accepting the buyer's payment.
        if (freeCollateral() < reserveAdded) revert InsufficientFreeCollateral();

        Position storage position = positions[epochId][msg.sender];
        if (position.closed) revert PositionAlreadyClosed();

        epoch.totalTickets += quantity;
        epoch.totalPaymentEscrow += payment;
        epoch.totalProtocolFeeEscrow += perTicket.protocolFee * quantity;
        position.quantity += quantity;
        position.payment += payment;
        reservedLiability += reserveAdded;
        refundableEscrow += payment;

        uint256 beforeBalance = collateral.balanceOf(address(this));
        _safeTransferFrom(msg.sender, address(this), payment);
        if (collateral.balanceOf(address(this)) != beforeBalance + payment) {
            revert TransferAmountMismatch();
        }

        emit TicketsPurchased(epochId, msg.sender, quantity, payment, reserveAdded, observedPrice);
    }

    function settle(uint256 epochId, bytes calldata proof) external onlyKeeper nonReentrant {
        if (epochStatus(epochId) != EpochStatus.AwaitingSettlement) {
            revert InvalidEpochState();
        }
        Epoch storage epoch = epochs[epochId];
        if (block.timestamp > epoch.settlementDeadline) revert InvalidEpochState();

        (uint256 settlementPrice, uint64 publishTime) = oracle.parseHistorical(
            proof, epoch.expiry, epoch.expiry + SETTLEMENT_OBSERVATION_WINDOW
        );
        if (
            settlementPrice == 0 || publishTime < epoch.expiry
                || publishTime > epoch.expiry + SETTLEMENT_OBSERVATION_WINDOW
                || publishTime > block.timestamp
        ) revert InvalidSettlementObservation();

        uint256 payoutPerTicket =
            CappedCallMath.payoff(settlementPrice, epoch.strike, epoch.cap, epoch.maxPayout);
        uint256 aggregatePayout = payoutPerTicket * epoch.totalTickets;
        uint256 epochReserve = epoch.maxPayout * epoch.totalTickets;

        reservedLiability -= epochReserve;
        refundableEscrow -= epoch.totalPaymentEscrow;
        claimableLiability += aggregatePayout;
        accruedProtocolFees += epoch.totalProtocolFeeEscrow;

        epoch.storedStatus = EpochStatus.Settled;
        epoch.settlementPrice = settlementPrice;
        epoch.reportPublishTime = publishTime;
        epoch.payoutPerTicket = payoutPerTicket;
        epoch.totalPayoutLiability = aggregatePayout;

        if (!isSolvent()) revert InsolventAccounting();
        emit EpochSettled(epochId, settlementPrice, publishTime, payoutPerTicket, aggregatePayout);
    }

    function cancel(uint256 epochId) external {
        Epoch storage epoch = epochs[epochId];
        if (
            epoch.storedStatus != EpochStatus.Trading || block.timestamp <= epoch.settlementDeadline
        ) revert InvalidEpochState();

        uint256 epochReserve = epoch.maxPayout * epoch.totalTickets;
        reservedLiability -= epochReserve;
        epoch.storedStatus = EpochStatus.Cancelled;
        emit EpochCancelled(epochId, epochReserve);
    }

    function claim(uint256 epochId) external nonReentrant returns (uint256 amount) {
        Epoch storage epoch = epochs[epochId];
        if (epoch.storedStatus != EpochStatus.Settled) revert InvalidEpochState();
        Position storage position = positions[epochId][msg.sender];
        if (position.quantity == 0) revert NoPosition();
        if (position.closed) revert PositionAlreadyClosed();

        position.closed = true;
        amount = position.quantity * epoch.payoutPerTicket;
        claimableLiability -= amount;
        if (amount != 0) _safeTransfer(msg.sender, amount);
        emit Claimed(epochId, msg.sender, amount);
    }

    function refund(uint256 epochId) external nonReentrant returns (uint256 amount) {
        Epoch storage epoch = epochs[epochId];
        if (epoch.storedStatus != EpochStatus.Cancelled) revert InvalidEpochState();
        Position storage position = positions[epochId][msg.sender];
        if (position.quantity == 0) revert NoPosition();
        if (position.closed) revert PositionAlreadyClosed();

        position.closed = true;
        amount = position.payment;
        refundableEscrow -= amount;
        _safeTransfer(msg.sender, amount);
        emit Refunded(epochId, msg.sender, amount);
    }

    function epochStatus(uint256 epochId) public view returns (EpochStatus) {
        Epoch storage epoch = epochs[epochId];
        if (epoch.storedStatus == EpochStatus.Uninitialized) revert InvalidEpoch();
        if (
            epoch.storedStatus == EpochStatus.Settled || epoch.storedStatus == EpochStatus.Cancelled
        ) return epoch.storedStatus;
        if (block.timestamp < epoch.tradingClose) return EpochStatus.Trading;
        if (block.timestamp < epoch.expiry) return EpochStatus.Locked;
        return EpochStatus.AwaitingSettlement;
    }

    function quote(uint256 epochId, uint256 quantity)
        external
        view
        returns (
            CappedCallMath.Quote memory perTicket,
            uint256 totalPayment,
            uint256 totalMaxPayout
        )
    {
        if (quantity == 0) revert ZeroAmount();
        Epoch storage epoch = epochs[epochId];
        if (epoch.storedStatus == EpochStatus.Uninitialized) revert InvalidEpoch();
        (uint256 observedPrice, uint64 publishTime) = oracle.latest();
        _validateLiveObservation(observedPrice, publishTime);
        perTicket = _quote(epoch, observedPrice);
        totalPayment = perTicket.allIn * quantity;
        totalMaxPayout = epoch.maxPayout * quantity;
    }

    function getEpoch(uint256 epochId) external view returns (Epoch memory) {
        if (epochs[epochId].storedStatus == EpochStatus.Uninitialized) revert InvalidEpoch();
        return epochs[epochId];
    }

    function getPosition(uint256 epochId, address account) external view returns (Position memory) {
        return positions[epochId][account];
    }

    function liabilities() public view returns (uint256) {
        return reservedLiability + claimableLiability + refundableEscrow + accruedProtocolFees;
    }

    function freeCollateral() public view returns (uint256) {
        uint256 balance = collateral.balanceOf(address(this));
        uint256 protected = liabilities();
        return balance > protected ? balance - protected : 0;
    }

    function isSolvent() public view returns (bool) {
        return collateral.balanceOf(address(this)) >= liabilities();
    }

    function accounting()
        external
        view
        returns (
            uint256 balance,
            uint256 reserved,
            uint256 claimable,
            uint256 refundable,
            uint256 fees,
            uint256 free,
            bool solvent
        )
    {
        balance = collateral.balanceOf(address(this));
        reserved = reservedLiability;
        claimable = claimableLiability;
        refundable = refundableEscrow;
        fees = accruedProtocolFees;
        free = freeCollateral();
        solvent = balance >= reserved + claimable + refundable + fees;
    }

    function _quote(Epoch storage epoch, uint256 observedPrice)
        internal
        view
        returns (CappedCallMath.Quote memory)
    {
        uint256 secondsToExpiry =
            block.timestamp < epoch.expiry ? epoch.expiry - block.timestamp : 0;
        uint256 baseReference = BlackScholes.callSpreadPrice(
            observedPrice,
            epoch.strike,
            epoch.cap,
            epoch.maxPayout,
            epoch.pricingVolBps,
            secondsToExpiry
        );
        return CappedCallMath.quote(
            baseReference,
            epoch.maxPayout,
            observedPrice,
            epoch.strike,
            epoch.cap,
            epoch.jumpSizeBps,
            epoch.jumpWeightBps,
            epoch.feeBps
        );
    }

    function _validateLiveObservation(uint256 price, uint64 publishTime) internal view {
        if (price == 0) revert InvalidParameters();
        if (publishTime > block.timestamp) revert FuturePrice();
        if (block.timestamp - publishTime > MAX_LIVE_PRICE_AGE) revert StalePrice();
    }

    function _safeTransfer(address to, uint256 amount) internal {
        (bool success, bytes memory data) =
            address(collateral).call(abi.encodeCall(IERC20Minimal.transfer, (to, amount)));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) revert TransferFailed();
    }

    function _safeTransferFrom(address from, address to, uint256 amount) internal {
        (bool success, bytes memory data) =
            address(collateral).call(abi.encodeCall(IERC20Minimal.transferFrom, (from, to, amount)));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) revert TransferFailed();
    }
}
