// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console2} from "forge-std/Script.sol";
import {WrappedNFT} from "../src/core/WrappedNFT.sol";
import {NFTPoolBurnAndMint} from "../src/core/NFTPoolBurnAndMint.sol";

/// @notice Deploys the destination-chain wrapped NFT and burn-and-mint pool
///         on Arbitrum Sepolia.
/// @dev Run:
///   `forge script script/DeployArbitrumSepoliaDest.s.sol --rpc-url arbitrum_sepolia --broadcast --verify`
///   Requires ARBITRUM_PRIVATE_KEY, ARBITRUM_ROUTER, ARBITRUM_LINK in env.
contract DeployArbitrumSepoliaDest is Script {
    function run() external {
        uint256 key = vm.envUint("ARBITRUM_PRIVATE_KEY");
        address deployer = vm.addr(key);
        address router = vm.envAddress("ARBITRUM_ROUTER");
        address link = vm.envAddress("ARBITRUM_LINK");

        vm.startBroadcast(key);

        WrappedNFT wrapped = new WrappedNFT("Wrapped NFT", "WNFT");
        NFTPoolBurnAndMint pool = new NFTPoolBurnAndMint(router, link, address(wrapped), deployer);

        // Critical: the pool must own the WrappedNFT to mint/burn.
        wrapped.transferOwnership(address(pool));

        vm.stopBroadcast();

        console2.log("========== Arbitrum Sepolia destination deployment ==========");
        console2.log("WrappedNFT  :", address(wrapped));
        console2.log("DestPool    :", address(pool));
        console2.log("Next: call pool.allowlistDestinationChain(<sepoliaSelector>, true)");
        console2.log("      call pool.allowlistSourceChain(<sepoliaSelector>, true)");
        console2.log("      call pool.allowlistSender(<sourcePool>, true)");
    }
}
