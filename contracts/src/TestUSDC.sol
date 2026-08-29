// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Testnet-only collateral with a rate-limited CLI faucet.
/// @dev This is an onchain ERC-20-like test token. It is not canonical, redeemable, or real USDC.
contract TestUSDC {
    string public constant name = "Monad Test USDC";
    string public constant symbol = "mUSDC";
    uint8 public constant decimals = 6;
    uint256 public constant FAUCET_AMOUNT = 500e6;
    uint64 public constant FAUCET_COOLDOWN = 24 hours;

    address public owner;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint64) public lastFaucetAt;

    error Unauthorized();
    error FaucetCooldown(uint64 availableAt);
    error InsufficientBalance();
    error InsufficientAllowance();
    error ZeroAddress();

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event FaucetClaimed(address indexed account, uint256 amount, uint64 nextClaimAt);

    constructor(address initialOwner) {
        if (initialOwner == address(0)) revert ZeroAddress();
        owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (allowed < amount) revert InsufficientAllowance();
            allowance[from][msg.sender] = allowed - amount;
            emit Approval(from, msg.sender, allowed - amount);
        }
        _transfer(from, to, amount);
        return true;
    }

    /// @notice Owner minting exists only to seed fully reserved market collateral.
    function mint(address to, uint256 amount) external {
        if (msg.sender != owner) revert Unauthorized();
        _mint(to, amount);
    }

    /// @notice Mints exactly 500 mUSDC to the caller, at most once per rolling 24 hours.
    /// @dev Intentionally omitted from the web app; users invoke it with the documented CLI command.
    function faucet() external {
        uint64 previous = lastFaucetAt[msg.sender];
        if (previous != 0) {
            uint64 availableAt = previous + FAUCET_COOLDOWN;
            if (block.timestamp < availableAt) revert FaucetCooldown(availableAt);
        }

        uint64 claimedAt = uint64(block.timestamp);
        lastFaucetAt[msg.sender] = claimedAt;
        _mint(msg.sender, FAUCET_AMOUNT);
        emit FaucetClaimed(msg.sender, FAUCET_AMOUNT, claimedAt + FAUCET_COOLDOWN);
    }

    function nextFaucetAt(address account) external view returns (uint64) {
        uint64 previous = lastFaucetAt[account];
        return previous == 0 ? 0 : previous + FAUCET_COOLDOWN;
    }

    function transferOwnership(address newOwner) external {
        if (msg.sender != owner) revert Unauthorized();
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function _mint(address to, uint256 amount) internal {
        if (to == address(0)) revert ZeroAddress();
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        if (to == address(0)) revert ZeroAddress();
        uint256 balance = balanceOf[from];
        if (balance < amount) revert InsufficientBalance();
        balanceOf[from] = balance - amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}
