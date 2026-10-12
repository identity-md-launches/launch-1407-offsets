// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {OffsetsToken} from "src/OffsetsToken.sol";

/// @dev An actual contract deployer, so constructor ownership is tested without impersonating one.
contract OffsetsDeploymentProbe {
    function deploy(bytes32 salt) external returns (OffsetsToken) {
        return new OffsetsToken{salt: salt}();
    }

    function forward(OffsetsToken token, address recipient, uint256 amount) external returns (bool) {
        return token.transfer(recipient, amount);
    }
}

/// @notice Complements the original suite with boundaries, aliasing, rollback and algebraic properties.
/// forge-config: default.fuzz.runs = 1000
contract OffsetsTokenEdgeCasesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    address private deployer = makeAddr("edge-deployer");
    address private alice = makeAddr("edge-alice");
    address private bob = makeAddr("edge-bob");
    address private carol = makeAddr("edge-carol");
    OffsetsToken private token;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        vm.prank(deployer);
        token = new OffsetsToken();
    }

    function test_zeroTransfersFromEmptyHoldersEmitAndPreserveState() public {
        bytes32 beforeState = _stateHash();
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(_stateHash(), beforeState);

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(carol);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(_stateHash(), beforeState, "zero delegated transfer consumed permission or moved funds");
    }

    function test_zeroAmountsStillRejectZeroRecipientAndSpender() public {
        bytes32 beforeState = _stateHash();
        vm.expectRevert(OffsetsToken.TransferToZeroAddress.selector);
        vm.prank(alice);
        token.transfer(address(0), 0);
        vm.expectRevert(OffsetsToken.TransferToZeroAddress.selector);
        vm.prank(bob);
        token.transferFrom(alice, address(0), 0);
        vm.expectRevert(OffsetsToken.ApproveToZeroAddress.selector);
        vm.prank(alice);
        token.approve(address(0), 0);
        assertEq(_stateHash(), beforeState);
    }

    function test_oneMinorUnitCanMoveAndReturn() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 1);
        vm.prank(alice);
        assertTrue(token.approve(bob, 1));
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, deployer, 1));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(alice, bob), 0);
    }

    function test_entireSupplyCanBeDelegatedButSpentAllowanceCannotBeReused() public {
        vm.prank(deployer);
        token.approve(bob, SUPPLY);
        vm.prank(bob);
        assertTrue(token.transferFrom(deployer, alice, SUPPLY));
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.allowance(deployer, bob), 0);

        // Replenish the holder: only exhausted authorization prevents this second spend.
        vm.prank(alice);
        token.transfer(deployer, 1);
        bytes32 beforeState = _stateHash();
        vm.expectRevert(abi.encodeWithSelector(OffsetsToken.InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(deployer, alice, 1);
        assertEq(_stateHash(), beforeState);
    }

    function test_maximumFiniteAllowanceIsNotTreatedAsUnlimited() public {
        vm.prank(deployer);
        token.approve(bob, type(uint256).max - 1);
        vm.prank(bob);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertEq(token.allowance(deployer, bob), type(uint256).max - 2);

        vm.prank(deployer);
        token.approve(bob, type(uint256).max);
        vm.prank(bob);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertEq(token.allowance(deployer, bob), type(uint256).max);
        assertEq(token.balanceOf(alice), 2);
        assertEq(token.balanceOf(deployer), SUPPLY - 2);
    }

    function test_unlimitedAllowanceCanBeReducedRevokedAndRegranted() public {
        vm.prank(deployer);
        token.approve(bob, type(uint256).max);
        vm.prank(bob);
        token.transferFrom(deployer, alice, 1);
        vm.prank(bob);
        token.transferFrom(deployer, alice, 1);
        assertEq(token.allowance(deployer, bob), type(uint256).max);

        vm.prank(deployer);
        token.approve(bob, 2);
        assertEq(token.allowance(deployer, bob), 2);
        vm.expectRevert(abi.encodeWithSelector(OffsetsToken.InsufficientAllowance.selector, bob, 2, 3));
        vm.prank(bob);
        token.transferFrom(deployer, alice, 3);
        assertEq(token.allowance(deployer, bob), 2);

        vm.prank(deployer);
        token.approve(bob, 0);
        bytes32 revokedState = _stateHash();
        vm.expectRevert(abi.encodeWithSelector(OffsetsToken.InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(deployer, alice, 1);
        assertEq(_stateHash(), revokedState);

        vm.prank(deployer);
        token.approve(bob, 1);
        vm.prank(bob);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertEq(token.allowance(deployer, bob), 0);
        assertEq(token.balanceOf(alice), 3);
        assertEq(token.balanceOf(deployer), SUPPLY - 3);
    }

    function test_selfTransferBoundariesDoNotCreateTokensOrBypassBalanceChecks() public {
        uint256[3] memory amounts = [uint256(0), uint256(1), SUPPLY];
        bytes32 beforeState = _stateHash();
        for (uint256 i; i < amounts.length; ++i) {
            vm.prank(deployer);
            assertTrue(token.transfer(deployer, amounts[i]));
            assertEq(_stateHash(), beforeState);
        }
        vm.expectRevert(
            abi.encodeWithSelector(OffsetsToken.InsufficientBalance.selector, deployer, SUPPLY, type(uint256).max)
        );
        vm.prank(deployer);
        token.transfer(deployer, type(uint256).max);
        assertEq(_stateHash(), beforeState);
    }

    function test_delegatedSelfTransferConsumesOnlyItsFiniteAllowance() public {
        vm.prank(deployer);
        token.approve(bob, SUPPLY);
        vm.prank(bob);
        assertTrue(token.transferFrom(deployer, deployer, SUPPLY));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(deployer, bob), 0);

        vm.prank(deployer);
        token.approve(bob, type(uint256).max);
        vm.prank(bob);
        assertTrue(token.transferFrom(deployer, deployer, SUPPLY));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.allowance(deployer, bob), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ownerCanExplicitlyApproveItselfAndBeAllThreeTransferFromRoles() public {
        vm.prank(deployer);
        token.approve(deployer, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transferFrom(deployer, deployer, SUPPLY));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.allowance(deployer, deployer), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_permissionsAreIsolatedByBothOwnerAndSpender() public {
        vm.startPrank(deployer);
        token.approve(alice, 5);
        token.approve(bob, 9);
        vm.stopPrank();
        vm.prank(carol);
        token.approve(alice, 11);
        vm.prank(bob);
        token.approve(carol, type(uint256).max);

        // Approval is not transitive: Bob cannot delegate the deployer's funds to Carol.
        bytes32 beforeState = _stateHash();
        vm.expectRevert(abi.encodeWithSelector(OffsetsToken.InsufficientAllowance.selector, carol, 0, 1));
        vm.prank(carol);
        token.transferFrom(deployer, carol, 1);
        assertEq(_stateHash(), beforeState);

        vm.prank(bob);
        assertTrue(token.transferFrom(deployer, alice, 9));
        assertEq(token.allowance(deployer, bob), 0);
        assertEq(token.allowance(deployer, alice), 5);
        assertEq(token.allowance(carol, alice), 11);
        assertEq(token.allowance(bob, carol), type(uint256).max);
        assertEq(token.balanceOf(alice), 9);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(carol), 0);
    }

    function test_failedSpendCanBeRetriedAfterHolderIsFunded() public {
        vm.prank(alice);
        token.approve(bob, 1);
        bytes32 beforeState = _stateHash();
        vm.expectRevert(abi.encodeWithSelector(OffsetsToken.InsufficientBalance.selector, alice, 0, 1));
        vm.prank(bob);
        token.transferFrom(alice, carol, 1);
        assertEq(_stateHash(), beforeState, "failed transfer consumed allowance");

        vm.prank(deployer);
        token.transfer(alice, 1);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, carol, 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(carol), 1);
        assertEq(token.allowance(alice, bob), 0);
    }

    function test_maximumTransferAmountsRejectWithoutArithmeticPanic() public {
        vm.prank(deployer);
        token.approve(bob, type(uint256).max);
        bytes32 beforeState = _stateHash();
        bytes memory errorData =
            abi.encodeWithSelector(OffsetsToken.InsufficientBalance.selector, deployer, SUPPLY, type(uint256).max);
        vm.expectRevert(errorData);
        vm.prank(deployer);
        token.transfer(alice, type(uint256).max);
        assertEq(_stateHash(), beforeState);
        vm.expectRevert(errorData);
        vm.prank(bob);
        token.transferFrom(deployer, alice, type(uint256).max);
        assertEq(_stateHash(), beforeState);
    }

    function testFuzz_contractCREATE2DeployerReceivesAndCanForwardWholeSupply(bytes32 salt) public {
        OffsetsDeploymentProbe factory = new OffsetsDeploymentProbe();
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff), address(factory), salt, keccak256(type(OffsetsToken).creationCode)
                        )
                    )
                )
            )
        );
        vm.prank(alice);
        OffsetsToken deployed = factory.deploy(salt);
        assertEq(address(deployed), predicted);
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(alice), 0, "mint went to the external caller instead of the factory");
        assertEq(deployed.totalSupply(), SUPPLY);
        assertTrue(factory.forward(deployed, alice, SUPPLY));
        assertEq(deployed.balanceOf(address(factory)), 0);
        assertEq(deployed.balanceOf(alice), SUPPLY);
    }

    function testFuzz_transferRoundTripRestoresBalancesAndLeavesApprovals(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        token.approve(bob, 17);
        vm.prank(alice);
        token.approve(carol, type(uint256).max);
        bytes32 beforeState = _stateHash();
        vm.prank(deployer);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), amount, "forward transfer arrived short");
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        vm.prank(alice);
        assertTrue(token.transfer(deployer, amount));
        assertEq(_stateHash(), beforeState, "round trip changed balances or permission");
    }

    function testFuzz_splitDirectTransfersEqualOneDelegatedTransfer(uint256 first, uint256 second) public {
        first = bound(first, 0, SUPPLY);
        second = bound(second, 0, SUPPLY - first);
        vm.prank(deployer);
        OffsetsToken other = new OffsetsToken();
        vm.startPrank(deployer);
        token.transfer(alice, first);
        token.transfer(alice, second);
        other.approve(bob, first + second);
        vm.stopPrank();
        vm.prank(bob);
        assertTrue(other.transferFrom(deployer, alice, first + second));
        assertEq(token.balanceOf(alice), first + second);
        assertEq(other.balanceOf(alice), token.balanceOf(alice));
        assertEq(other.balanceOf(deployer), token.balanceOf(deployer));
        assertEq(other.balanceOf(deployer), SUPPLY - first - second);
        assertEq(other.allowance(deployer, bob), 0);
        assertEq(other.totalSupply(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferOverdraftIsAtomic(uint256 held, uint256 requested) public {
        held = bound(held, 0, SUPPLY);
        requested = bound(requested, held + 1, type(uint256).max);
        vm.prank(deployer);
        token.transfer(alice, held);
        vm.prank(alice);
        token.approve(bob, type(uint256).max);
        bytes32 beforeState = _stateHash();
        vm.expectRevert(abi.encodeWithSelector(OffsetsToken.InsufficientBalance.selector, alice, held, requested));
        vm.prank(alice);
        token.transfer(carol, requested);
        assertEq(_stateHash(), beforeState);
    }

    function testFuzz_delegatedOverdraftRollsBackFiniteOrUnlimitedApproval(
        uint256 held,
        uint256 requested,
        bool unlimited
    ) public {
        held = bound(held, 0, SUPPLY);
        requested = bound(requested, held + 1, type(uint256).max - 1);
        vm.prank(deployer);
        token.transfer(alice, held);
        vm.prank(alice);
        token.approve(bob, unlimited ? type(uint256).max : requested);
        bytes32 beforeState = _stateHash();
        vm.expectRevert(abi.encodeWithSelector(OffsetsToken.InsufficientBalance.selector, alice, held, requested));
        vm.prank(bob);
        token.transferFrom(alice, carol, requested);
        assertEq(_stateHash(), beforeState);
    }

    function testFuzz_insufficientAllowanceCannotBeSpent(uint256 approval, uint256 requested) public {
        requested = bound(requested, 1, SUPPLY);
        approval = bound(approval, 0, requested - 1);
        vm.prank(deployer);
        token.approve(bob, approval);
        bytes32 beforeState = _stateHash();
        vm.expectRevert(abi.encodeWithSelector(OffsetsToken.InsufficientAllowance.selector, bob, approval, requested));
        vm.prank(bob);
        token.transferFrom(deployer, carol, requested);
        assertEq(_stateHash(), beforeState);
    }

    function testFuzz_zeroRecipientRollsBackFiniteOrUnlimitedApproval(uint256 amount, bool unlimited) public {
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        token.approve(bob, unlimited ? type(uint256).max : amount);
        bytes32 beforeState = _stateHash();
        vm.expectRevert(OffsetsToken.TransferToZeroAddress.selector);
        vm.prank(bob);
        token.transferFrom(deployer, address(0), amount);
        assertEq(_stateHash(), beforeState);
    }

    function testFuzz_approvalReplacementAndRepetitionDoNotAccumulate(uint256 first, uint256 replacement) public {
        vm.startPrank(alice);
        assertTrue(token.approve(bob, first));
        assertEq(token.allowance(alice, bob), first);
        assertTrue(token.approve(bob, replacement));
        assertEq(token.allowance(alice, bob), replacement);
        vm.stopPrank();
        bytes32 replacedState = _stateHash();
        vm.prank(alice);
        assertTrue(token.approve(bob, replacement));
        assertEq(_stateHash(), replacedState, "repeating approval accumulated allowance");
        assertEq(token.balanceOf(alice), 0, "approving minted a balance");
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function testFuzz_transferToAnyNonzeroAddressConservesSupply(address recipient, uint256 amount) public {
        recipient = address(uint160(bound(uint160(recipient), 1, type(uint160).max)));
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(recipient, amount));
        if (recipient == deployer) {
            assertEq(token.balanceOf(deployer), SUPPLY);
        } else {
            assertEq(token.balanceOf(recipient), amount);
            assertEq(token.balanceOf(deployer), SUPPLY - amount);
        }
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// @dev Snapshot every tracked balance and permission, including zero-address and token custody.
    function _stateHash() private view returns (bytes32) {
        address[6] memory accounts = [deployer, alice, bob, carol, address(0), address(token)];
        uint256[6] memory balances;
        uint256[36] memory allowances;
        for (uint256 i; i < accounts.length; ++i) {
            balances[i] = token.balanceOf(accounts[i]);
            for (uint256 j; j < accounts.length; ++j) {
                allowances[i * accounts.length + j] = token.allowance(accounts[i], accounts[j]);
            }
        }
        return keccak256(abi.encode(token.totalSupply(), balances, allowances));
    }
}
