// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {OffsetsToken} from "../src/OffsetsToken.sol";
import {DeployOffsets} from "../script/DeployOffsets.s.sol";

/// @notice Behavioural tests for the Offsets token: metadata, the one-time mint, every ERC-20
/// success and failure path, supply conservation, and the absence of any privileged function.
contract OffsetsTokenTest is Test {
    uint256 constant SUPPLY = 1_000_000_000 * 10 ** 18;

    address deployer = makeAddr("deployer");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");

    OffsetsToken token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        vm.prank(deployer);
        token = new OffsetsToken();
    }

    // ---------------------------------------------------------------------------------------------
    // Metadata and construction
    // ---------------------------------------------------------------------------------------------

    function test_metadata() public view {
        assertEq(token.name(), "Offsets");
        assertEq(token.symbol(), "OFFSETS");
        assertEq(token.decimals(), 18);
    }

    function test_supplyIsOneBillionWithEighteenDecimals() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), 1_000_000_000_000_000_000_000_000_000);
    }

    function test_constructorMintsWholeSupplyToDeployer() public view {
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function test_constructorEmitsMintTransfer() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), alice, SUPPLY);
        vm.prank(alice);
        new OffsetsToken();
    }

    /// @dev Whoever deploys receives the supply: no address is hard-wired, so a factory deploying
    /// through CREATE2 holds everything just as an EOA deploying directly would.
    function test_mintGoesToWhoeverDeploys(address anyone) public {
        vm.assume(anyone != address(0));
        vm.prank(anyone);
        OffsetsToken fresh = new OffsetsToken();
        assertEq(fresh.balanceOf(anyone), SUPPLY);
        assertEq(fresh.totalSupply(), SUPPLY);
    }

    function test_deployScriptMintsToItsCaller() public {
        DeployOffsets script = new DeployOffsets();
        OffsetsToken deployed = script.deploy();
        assertEq(deployed.totalSupply(), SUPPLY);
        assertEq(deployed.balanceOf(address(script)), SUPPLY);
        assertEq(deployed.name(), "Offsets");
        assertEq(deployed.symbol(), "OFFSETS");
    }

    // ---------------------------------------------------------------------------------------------
    // transfer
    // ---------------------------------------------------------------------------------------------

    function test_transferMovesBalanceAndEmits() public {
        uint256 amount = 1_234 ether;
        vm.expectEmit(true, true, true, true);
        emit Transfer(deployer, alice, amount);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferWholeBalance() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
    }

    function test_transferZeroAmountSucceeds() public {
        vm.prank(bob);
        assertTrue(token.transfer(alice, 0));
        assertEq(token.balanceOf(alice), 0);
    }

    function test_transferToSelfKeepsBalance() public {
        vm.prank(deployer);
        assertTrue(token.transfer(deployer, 5 ether));
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_transferRevertsOnInsufficientBalance() public {
        vm.prank(deployer);
        token.transfer(alice, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(OffsetsToken.InsufficientBalance.selector, alice, 10 ether, 11 ether));
        vm.prank(alice);
        token.transfer(bob, 11 ether);
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferRevertsFromEmptyAccount() public {
        vm.expectRevert(abi.encodeWithSelector(OffsetsToken.InsufficientBalance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transfer(alice, 1);
    }

    function test_transferRevertsToZeroAddress() public {
        vm.expectRevert(OffsetsToken.TransferToZeroAddress.selector);
        vm.prank(deployer);
        token.transfer(address(0), 1 ether);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    // ---------------------------------------------------------------------------------------------
    // approve / allowance / transferFrom
    // ---------------------------------------------------------------------------------------------

    function test_approveSetsAllowanceAndEmits() public {
        vm.expectEmit(true, true, true, true);
        emit Approval(deployer, alice, 7 ether);
        vm.prank(deployer);
        assertTrue(token.approve(alice, 7 ether));
        assertEq(token.allowance(deployer, alice), 7 ether);
    }

    function test_approveOverwritesPreviousAllowance() public {
        vm.startPrank(deployer);
        token.approve(alice, 7 ether);
        token.approve(alice, 3 ether);
        vm.stopPrank();
        assertEq(token.allowance(deployer, alice), 3 ether);
    }

    function test_approveRevertsForZeroSpender() public {
        vm.expectRevert(OffsetsToken.ApproveToZeroAddress.selector);
        vm.prank(deployer);
        token.approve(address(0), 1);
    }

    function test_transferFromSpendsAllowance() public {
        vm.prank(deployer);
        token.approve(alice, 10 ether);

        vm.expectEmit(true, true, true, true);
        emit Approval(deployer, alice, 4 ether);
        vm.expectEmit(true, true, true, true);
        emit Transfer(deployer, bob, 6 ether);
        vm.prank(alice);
        assertTrue(token.transferFrom(deployer, bob, 6 ether));

        assertEq(token.balanceOf(bob), 6 ether);
        assertEq(token.balanceOf(deployer), SUPPLY - 6 ether);
        assertEq(token.allowance(deployer, alice), 4 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromWithUnlimitedAllowanceKeepsIt() public {
        vm.prank(deployer);
        token.approve(alice, type(uint256).max);
        vm.prank(alice);
        assertTrue(token.transferFrom(deployer, bob, 6 ether));
        assertEq(token.allowance(deployer, alice), type(uint256).max);
        assertEq(token.balanceOf(bob), 6 ether);
    }

    function test_transferFromRevertsWithoutAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(OffsetsToken.InsufficientAllowance.selector, alice, 0, 1 ether));
        vm.prank(alice);
        token.transferFrom(deployer, bob, 1 ether);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_transferFromRevertsBeyondAllowance() public {
        vm.prank(deployer);
        token.approve(alice, 5 ether);
        vm.expectRevert(abi.encodeWithSelector(OffsetsToken.InsufficientAllowance.selector, alice, 5 ether, 6 ether));
        vm.prank(alice);
        token.transferFrom(deployer, bob, 6 ether);
        assertEq(token.allowance(deployer, alice), 5 ether);
    }

    function test_transferFromRevertsOnInsufficientBalanceEvenWithAllowance() public {
        vm.prank(bob);
        token.approve(alice, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(OffsetsToken.InsufficientBalance.selector, bob, 0, 1 ether));
        vm.prank(alice);
        token.transferFrom(bob, carol, 1 ether);
    }

    function test_transferFromRevertsToZeroAddress() public {
        vm.prank(deployer);
        token.approve(alice, 1 ether);
        vm.expectRevert(OffsetsToken.TransferToZeroAddress.selector);
        vm.prank(alice);
        token.transferFrom(deployer, address(0), 1 ether);
    }

    /// @dev The holder's own transferFrom needs an allowance too: self-approval is not implicit.
    function test_transferFromBySelfStillNeedsAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(OffsetsToken.InsufficientAllowance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transferFrom(deployer, alice, 1);
    }

    // ---------------------------------------------------------------------------------------------
    // Supply conservation and the absence of privileged paths
    // ---------------------------------------------------------------------------------------------

    function testFuzz_transfersConserveSupply(uint256 a, uint256 b, uint256 c) public {
        a = bound(a, 0, SUPPLY);
        b = bound(b, 0, a);
        c = bound(c, 0, b);
        vm.prank(deployer);
        token.transfer(alice, a);
        vm.prank(alice);
        token.transfer(bob, b);
        vm.prank(bob);
        token.transfer(carol, c);
        uint256 sum = token.balanceOf(deployer) + token.balanceOf(alice) + token.balanceOf(bob) + token.balanceOf(carol);
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromConservesSupply(uint256 approved, uint256 moved) public {
        approved = bound(approved, 0, SUPPLY);
        moved = bound(moved, 0, approved);
        vm.prank(deployer);
        token.approve(alice, approved);
        vm.prank(alice);
        token.transferFrom(deployer, bob, moved);
        assertEq(token.balanceOf(deployer) + token.balanceOf(bob), SUPPLY);
        assertEq(token.allowance(deployer, alice), approved - moved);
    }

    /// @dev The common minting and ownership entry points do not exist: every one reverts, from a
    /// stranger and from the deployer alike, and the supply and balances are untouched.
    function test_noMintOrAdminFunctionExists() public {
        address attacker = makeAddr("attacker");
        string[10] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], attacker, type(uint128).max);
            vm.prank(attacker);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
            vm.prank(deployer);
            (ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(attacker), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    /// @dev Nothing can pause, freeze, blacklist or seize: every such call reverts and the holder
    /// can still move the full balance afterwards.
    function test_noPrivilegedFunctionFreezesOrMovesAHolder() public {
        vm.prank(deployer);
        token.transfer(alice, 1_000 ether);
        string[12] memory signatures = [
            "pause()",
            "blacklist(address)",
            "blocklist(address)",
            "freeze(address)",
            "freezeAccount(address)",
            "setBlacklist(address,bool)",
            "setBlocked(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "burnFrom(address,uint256)",
            "seize(address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], alice, true);
            vm.prank(deployer);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
        }
        vm.prank(deployer);
        (bool moved,) = address(token).call(abi.encodeWithSelector(token.transferFrom.selector, alice, deployer, 1));
        assertFalse(moved, "deployer moved a holder's balance without allowance");
        assertEq(token.balanceOf(alice), 1_000 ether);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 1_000 ether));
        assertEq(token.balanceOf(bob), 1_000 ether);
    }

    function test_unknownSelectorReverts() public {
        (bool ok,) = address(token).call(abi.encodeWithSignature("doesNotExist()"));
        assertFalse(ok);
    }

    function test_plainEtherIsRefused() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok);
        assertEq(address(token).balance, 0);
    }

    /// @dev Mirrors the launch floor's opcode scan: no DELEGATECALL, CALLCODE or SELFDESTRUCT in the
    /// runtime, so the deployed code can neither be redirected nor removed.
    function test_runtimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576, "runtime exceeds EIP-170");
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            assertTrue(op != 0xF4, "DELEGATECALL");
            assertTrue(op != 0xF2, "CALLCODE");
            assertTrue(op != 0xFF, "SELFDESTRUCT");
        }
    }
}
