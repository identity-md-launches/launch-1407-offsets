// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {OffsetsToken} from "../src/OffsetsToken.sol";

/// @title Deploy script for Offsets (OFFSETS)
/// @notice The token takes no constructor arguments, so there is nothing to configure: whoever
/// sends the deployment transaction receives the whole supply. In the IdentityMD launch the factory
/// deploys the token from its creation code and this script is not used; it is kept for a manual
/// deployment and so tests can exercise the exact deployment path.
/// @dev `run()` only wraps `deploy()` in a broadcast. It reads nothing from the environment; the
/// sender is whatever the `forge script` invocation supplies (`--private-key`, `--ledger`, ...).
contract DeployOffsets is Script {
    /// @notice Deploys the token. The caller of this function (the broadcast sender under `run()`,
    /// or this script contract when called directly from a test) receives the full supply.
    function deploy() public returns (OffsetsToken token) {
        token = new OffsetsToken();
    }

    function run() external returns (OffsetsToken token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
