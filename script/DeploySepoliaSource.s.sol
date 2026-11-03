// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console2} from "forge-std/Script.sol";
import {MyNFT} from "../src/mocks/MyNFT.sol";
import {NFTPoolLockAndRelease} from "../src/core/NFTPoolLockAndRelease.sol";

/// @notice Deploys the source-chain NFT and lock-and-release pool on Sepolia.
/// @dev Run:
///   `forge script script/DeploySepoliaSource.s.sol --rpc-url sepolia --broadcast --verify`
///   Requires SEPOLIA_PRIVATE_KEY, SEPOLIA_ROUTER, SEPOLIA_LINK in env.
contract DeploySepoliaSource is Script {
    function run() external {
        uint256 key = vm.envUint("SEPOLIA_PRIVATE_KEY");
        address deployer = vm.addr(key);
        address router = vm.envAddress("SEPOLIA_ROUTER");
        address link = vm.envAddress("SEPOLIA_LINK");

        vm.startBroadcast(key);

        MyNFT original = new MyNFT("Original NFT", "ONFT");
        NFTPoolLockAndRelease pool = new NFTPoolLockAndRelease(router, link, address(original), deployer);

        vm.stopBroadcast();

        console2.log("========== Sepolia source deployment ==========");
        console2.log("MyNFT (original) :", address(original));
        console2.log("SourcePool       :", address(pool));
        console2.log("Next: deploy destination on Arbitrum Sepolia, then");
        console2.log("      call pool.allowlistDestinationChain(<arbSelector>, true)");
        console2.log("      call pool.allowlistSourceChain(<arbSelector>, true)");
        console2.log("      call pool.allowlistSender(<destPool>, true)");
    }
}
