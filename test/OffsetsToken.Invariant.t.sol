// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {OffsetsToken} from "src/OffsetsToken.sol";

/// @dev Only this handler is targeted. All successful transfers stay within four actors, so the
/// balance sum is exhaustive. Ghosts record transaction inputs, never copy the token's balances.
contract OffsetsTokenHandler is Test {
    uint256 public constant SUPPLY = 1_000_000_000 ether;
    uint256 public constant ACTOR_COUNT = 4;
    OffsetsToken public immutable token;
    address[4] public actors;

    mapping(address => uint256) public received;
    mapping(address => uint256) public sent;
    mapping(address => mapping(address => uint256)) public granted;
    mapping(address => mapping(address => uint256)) public spentSinceApproval;

    constructor(OffsetsToken token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
    }

    function expectedBalance(address owner) public view returns (uint256) {
        uint256 opening = owner == actors[0] ? SUPPLY : 0;
        return opening + received[owner] - sent[owner];
    }

    function expectedAllowance(address owner, address spender) public view returns (uint256) {
        uint256 approval = granted[owner][spender];
        return approval == type(uint256).max ? approval : approval - spentSinceApproval[owner][spender];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) public {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 amount = _bound(amountSeed, 0, expectedBalance(from));
        vm.prank(from);
        assertTrue(token.transfer(to, amount), "transfer returned false");
        _recordTransfer(from, to, amount);
    }

    /// @dev Includes revocation, unlimited approval, affordable amounts, and the full uint256 range.
    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, uint8 mode) public {
        if (mode % 4 == 0) amount = 0;
        else if (mode % 4 == 1) amount = type(uint256).max;
        else if (mode % 4 == 2) amount = _bound(amount, 0, SUPPLY);
        _approve(_actor(ownerSeed), _actor(spenderSeed), amount);
    }

    /// @dev Spends existing approvals, allowing repeated spends and interleaved revocations.
    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) public {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 limit = expectedBalance(owner);
        uint256 allowance = expectedAllowance(owner, spender);
        if (allowance < limit) limit = allowance;
        _transferFrom(owner, spender, _actor(toSeed), _bound(amountSeed, 0, limit));
    }

    /// @dev Always exercises a positive delegated transfer, even after many approvals were revoked.
    function approveAndTransferFrom(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amountSeed,
        bool unlimited
    ) public {
        address owner = _fundedActor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 amount = _bound(amountSeed, 1, expectedBalance(owner));
        _approve(owner, spender, unlimited ? type(uint256).max : amount);
        _transferFrom(owner, spender, _actor(toSeed), amount);
    }

    function rejectOverdraw(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) public {
        address from = _actor(fromSeed);
        uint256 balance = expectedBalance(from);
        uint256 amount = _bound(amountSeed, balance + 1, type(uint256).max);
        _mustRevert(
            from,
            abi.encodeCall(token.transfer, (_actor(toSeed), amount)),
            abi.encodeWithSelector(OffsetsToken.InsufficientBalance.selector, from, balance, amount)
        );
    }

    /// @dev There is enough balance, but the spender is exactly one minor unit short of permission.
    function rejectAllowanceOverrun(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) public {
        address owner = _fundedActor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 amount = _bound(amountSeed, 1, expectedBalance(owner));
        _approve(owner, spender, amount - 1);
        _mustRevert(
            spender,
            abi.encodeCall(token.transferFrom, (owner, _actor(toSeed), amount)),
            abi.encodeWithSelector(OffsetsToken.InsufficientAllowance.selector, spender, amount - 1, amount)
        );
    }

    /// @dev Enough permission, insufficient funds: spending the allowance must roll back as well.
    function rejectDelegatedOverdraw(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amountSeed,
        bool unlimited
    ) public {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 balance = expectedBalance(owner);
        uint256 amount = _bound(amountSeed, balance + 1, type(uint256).max - 1);
        _approve(owner, spender, unlimited ? type(uint256).max : amount);
        _mustRevert(
            spender,
            abi.encodeCall(token.transferFrom, (owner, _actor(toSeed), amount)),
            abi.encodeWithSelector(OffsetsToken.InsufficientBalance.selector, owner, balance, amount)
        );
    }

    function rejectZeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool delegated) public {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 amount = _bound(amountSeed, 0, expectedBalance(owner));
        if (delegated) {
            _approve(owner, spender, amount);
            _mustRevert(
                spender,
                abi.encodeCall(token.transferFrom, (owner, address(0), amount)),
                abi.encodeWithSelector(OffsetsToken.TransferToZeroAddress.selector)
            );
        } else {
            _mustRevert(
                owner,
                abi.encodeCall(token.transfer, (address(0), amount)),
                abi.encodeWithSelector(OffsetsToken.TransferToZeroAddress.selector)
            );
        }
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) public {
        _mustRevert(
            _actor(ownerSeed),
            abi.encodeCall(token.approve, (address(0), amount)),
            abi.encodeWithSelector(OffsetsToken.ApproveToZeroAddress.selector)
        );
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount), "approve returned false");
        granted[owner][spender] = amount;
        spentSinceApproval[owner][spender] = 0;
    }

    function _transferFrom(address owner, address spender, address to, uint256 amount) private {
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount), "transferFrom returned false");
        if (granted[owner][spender] != type(uint256).max) spentSinceApproval[owner][spender] += amount;
        _recordTransfer(owner, to, amount);
    }

    function _recordTransfer(address from, address to, uint256 amount) private {
        // Separate cumulative receipts and payments also handle self-transfers without special cases.
        sent[from] += amount;
        received[to] += amount;
    }

    function _mustRevert(address caller, bytes memory data, bytes memory expectedError) private {
        vm.prank(caller);
        (bool success, bytes memory result) = address(token).call(data);
        assertFalse(success, "invalid operation succeeded");
        assertEq(result, expectedError, "unexpected failure reason");
        // No ghosts change: invariants check all balances and all allowance pairs after this call.
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[seed % ACTOR_COUNT];
    }

    function _fundedActor(uint256 seed) private view returns (address) {
        uint256 start = seed % ACTOR_COUNT;
        for (uint256 i; i < ACTOR_COUNT; ++i) {
            address actor = actors[(start + i) % ACTOR_COUNT];
            if (expectedBalance(actor) > 0) return actor;
        }
        revert("harness lost the fixed supply");
    }
}

/// @dev Unexpected handler reverts fail the campaign; rejected token calls are checked explicitly.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 96
/// forge-config: default.invariant.fail-on-revert = true
contract OffsetsTokenInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    OffsetsToken private token;
    OffsetsTokenHandler private handler;
    address[4] private actors;

    function setUp() public {
        actors = [makeAddr("deployer"), makeAddr("alice"), makeAddr("bob"), makeAddr("carol")];
        vm.prank(actors[0]);
        token = new OffsetsToken();
        handler = new OffsetsTokenHandler(token, actors);

        for (uint256 i = 1; i < actors.length; ++i) {
            handler.transfer(0, i, SUPPLY / 4);
        }
        // Start with useful finite and unlimited approvals; randomized calls may replace or revoke them.
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                handler.approve(i, j, SUPPLY / 4, (i + j) % 2 == 0 ? 1 : 2);
            }
        }

        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.approveAndTransferFrom.selector;
        selectors[4] = handler.rejectOverdraw.selector;
        selectors[5] = handler.rejectAllowanceOverrun.selector;
        selectors[6] = handler.rejectDelegatedOverdraw.selector;
        selectors[7] = handler.rejectZeroRecipient.selector;
        selectors[8] = handler.rejectZeroSpender.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_fixedSupplyEqualsAllBalances() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(token.totalSupply(), SUPPLY, "supply changed");
        assertEq(token.TOTAL_SUPPLY(), SUPPLY, "wrong declared supply");
        assertEq(sum, SUPPLY, "tokens created, lost, or charged as a fee");
        assertEq(token.balanceOf(address(0)), 0, "zero address received tokens");
        assertEq(token.balanceOf(address(token)), 0, "unexpected token custody");
    }

    function invariant_eachHolderHasExactlyItsEntitlement() public view {
        for (uint256 i; i < actors.length; ++i) {
            uint256 opening = i == 0 ? SUPPLY : 0;
            assertEq(
                token.balanceOf(actors[i]) + handler.sent(actors[i]),
                opening + handler.received(actors[i]),
                "holder balance disagrees with transfer history"
            );
        }
    }

    function invariant_allowancesMatchOwnerAuthorization() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(
                    token.allowance(actors[i], actors[j]),
                    handler.expectedAllowance(actors[i], actors[j]),
                    "allowance changed without approval or a successful finite spend"
                );
            }
            assertEq(token.allowance(actors[i], address(0)), 0, "zero spender was approved");
        }
    }

    /// @dev No sequence may freeze funds: every holder can still move its entire balance.
    function afterInvariant() public {
        for (uint256 i = 1; i < actors.length; ++i) {
            handler.transfer(i, 0, token.balanceOf(actors[i]));
            assertEq(token.balanceOf(actors[i]), 0, "holder could not empty its balance");
        }
        assertEq(token.balanceOf(actors[0]), SUPPLY, "full supply could not be recovered by its holders");
        invariant_fixedSupplyEqualsAllBalances();
        invariant_eachHolderHasExactlyItsEntitlement();
        invariant_allowancesMatchOwnerAuthorization();
    }
}
