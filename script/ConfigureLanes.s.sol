// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console2} from "forge-std/Script.sol";
import {NFTPoolLockAndRelease} from "../src/core/NFTPoolLockAndRelease.sol";
import {NFTPoolBurnAndMint} from "../src/core/NFTPoolBurnAndMint.sol";

/// @notice Post-deployment lane configuration. Run once per chain after both
///         pools are deployed. Environment variables required:
///         SOURCE_POOL, DEST_POOL, SEPOLIA_SELECTOR, ARB_SELECTOR.
contract ConfigureLanes is Script {
    function runSource() external {
        uint256 key = vm.envUint("SEPOLIA_PRIVATE_KEY");
        // Pool has a payable receive() -> cast requires payable(address).
        NFTPoolLockAndRelease pool = NFTPoolLockAndRelease(payable(vm.envAddress("SOURCE_POOL")));
        address destPool = vm.envAddress("DEST_POOL");
        uint64 arbSelector = uint64(vm.envUint("ARBITRUM_SELECTOR"));

        vm.startBroadcast(key);
        pool.allowlistDestinationChain(arbSelector, true);
        pool.allowlistSourceChain(arbSelector, true);
        pool.allowlistSender(destPool, true);
        vm.stopBroadcast();

        console2.log("Source pool lane configured for Arb selector:", arbSelector);
    }

    function runDest() external {
        uint256 key = vm.envUint("ARBITRUM_PRIVATE_KEY");
        NFTPoolBurnAndMint pool = NFTPoolBurnAndMint(payable(vm.envAddress("DEST_POOL")));
        address sourcePool = vm.envAddress("SOURCE_POOL");
        uint64 sepoliaSelector = uint64(vm.envUint("SEPOLIA_SELECTOR"));

        vm.startBroadcast(key);
        pool.allowlistDestinationChain(sepoliaSelector, true);
        pool.allowlistSourceChain(sepoliaSelector, true);
        pool.allowlistSender(sourcePool, true);
        vm.stopBroadcast();

        console2.log("Dest pool lane configured for Sepolia selector:", sepoliaSelector);
    }
}
