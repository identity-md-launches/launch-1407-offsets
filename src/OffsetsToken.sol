// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title Offsets (OFFSETS)
/// @notice A plain, fixed-supply ERC-20. The whole supply of 1,000,000,000 OFFSETS (18 decimals) is
/// minted once, in the constructor, to the deployer (`msg.sender`). There is no owner, no minter,
/// no pause, no blacklist and no fee: after construction the contract has no privileged path at all,
/// and the supply can never grow.
/// @dev Written without an external library so the bytecode has no link placeholders and no
/// behaviour beyond the ERC-20 standard. Transfers to the zero address are refused, as is approving
/// the zero address, matching the conventions of the widely used library implementations. An
/// allowance of `type(uint256).max` is treated as unlimited and is not decremented.
contract OffsetsToken {
    // ---------------------------------------------------------------------------------------------
    // Metadata
    // ---------------------------------------------------------------------------------------------

    string public constant name = "Offsets";
    string public constant symbol = "OFFSETS";
    uint8 public constant decimals = 18;

    /// @notice The fixed total supply, in minor units: 1,000,000,000 tokens with 18 decimals.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    // ---------------------------------------------------------------------------------------------
    // Events (ERC-20)
    // ---------------------------------------------------------------------------------------------

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // ---------------------------------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------------------------------

    /// @notice A transfer to the zero address was attempted.
    error TransferToZeroAddress();
    /// @notice An approval of the zero address as spender was attempted.
    error ApproveToZeroAddress();
    /// @notice `sender` tried to move `needed` but holds only `balance`.
    error InsufficientBalance(address sender, uint256 balance, uint256 needed);
    /// @notice `spender` tried to move `needed` on behalf of a holder but was allowed only `allowance`.
    error InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    // ---------------------------------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------------------------------

    mapping(address account => uint256) private _balances;
    mapping(address owner => mapping(address spender => uint256)) private _allowances;

    // ---------------------------------------------------------------------------------------------
    // Construction
    // ---------------------------------------------------------------------------------------------

    /// @notice Mints the entire fixed supply to the deployer. Takes no arguments and calls no other
    /// contract, so it deploys on an empty chain and through a factory alike; whoever deploys it
    /// (the launch factory, in the IdentityMD launch) receives everything.
    constructor() {
        _balances[msg.sender] = TOTAL_SUPPLY;
        emit Transfer(address(0), msg.sender, TOTAL_SUPPLY);
    }

    // ---------------------------------------------------------------------------------------------
    // ERC-20 views
    // ---------------------------------------------------------------------------------------------

    /// @notice The total supply. Constant for the life of the contract: nothing mints or burns.
    function totalSupply() external pure returns (uint256) {
        return TOTAL_SUPPLY;
    }

    /// @notice The balance held by `account`.
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    /// @notice How much `spender` may still move on behalf of `owner`.
    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    // ---------------------------------------------------------------------------------------------
    // ERC-20 actions
    // ---------------------------------------------------------------------------------------------

    /// @notice Moves `amount` from the caller to `to`.
    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    /// @notice Lets `spender` move up to `amount` of the caller's balance.
    /// @dev Sets the allowance outright. Callers changing a non-zero allowance should be aware of
    /// the standard approve race and may set it to zero first.
    function approve(address spender, uint256 amount) external returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    /// @notice Moves `amount` from `from` to `to` using the caller's allowance.
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }

    // ---------------------------------------------------------------------------------------------
    // Internals
    // ---------------------------------------------------------------------------------------------

    function _transfer(address from, address to, uint256 amount) private {
        if (to == address(0)) revert TransferToZeroAddress();
        uint256 fromBalance = _balances[from];
        if (fromBalance < amount) revert InsufficientBalance(from, fromBalance, amount);
        unchecked {
            // fromBalance >= amount was just checked.
            _balances[from] = fromBalance - amount;
            // The sum of all balances is TOTAL_SUPPLY, which fits in uint256, so this cannot overflow.
            _balances[to] += amount;
        }
        emit Transfer(from, to, amount);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        if (spender == address(0)) revert ApproveToZeroAddress();
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(address owner, address spender, uint256 amount) private {
        uint256 current = _allowances[owner][spender];
        if (current == type(uint256).max) return;
        if (current < amount) revert InsufficientAllowance(spender, current, amount);
        unchecked {
            // current >= amount was just checked.
            _allowances[owner][spender] = current - amount;
        }
        emit Approval(owner, spender, current - amount);
    }
}
