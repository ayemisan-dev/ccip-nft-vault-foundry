// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console2} from "forge-std/Script.sol";
import {CCIPLocalSimulator} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {LinkToken} from "@chainlink/local/src/shared/LinkToken.sol";

import {MyNFT} from "../src/mocks/MyNFT.sol";
import {WrappedNFT} from "../src/core/WrappedNFT.sol";
import {NFTPoolLockAndRelease} from "../src/core/NFTPoolLockAndRelease.sol";
import {NFTPoolBurnAndMint} from "../src/core/NFTPoolBurnAndMint.sol";

/// @title DeployLocal
/// @notice One-shot deployment on Anvil: simulator, both NFTs, both pools,
///         ownership wiring, bilateral allowlist, and a demo mint to the deployer.
/// @dev Run: `anvil` in one terminal, then
/// `forge script script/DeployLocal.s.sol --rpc-url localhost --broadcast`.
contract DeployLocal is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("ANVIL_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        // 1. Deploy the local CCIP simulator.
        CCIPLocalSimulator simulator = new CCIPLocalSimulator();
        (uint64 chainSelector, IRouterClient sourceRouter, IRouterClient destRouter,, LinkToken linkToken,,) =
            simulator.configuration();

        // 2. Deploy both NFTs.
        MyNFT original = new MyNFT("Local Original NFT", "LONFT");
        WrappedNFT wrapped = new WrappedNFT("Local Wrapped NFT", "LWNFT");

        // 3. Deploy both pools.
        NFTPoolLockAndRelease sourcePool =
            new NFTPoolLockAndRelease(address(sourceRouter), address(linkToken), address(original), deployer);
        NFTPoolBurnAndMint destPool =
            new NFTPoolBurnAndMint(address(destRouter), address(linkToken), address(wrapped), deployer);

        // 4. Pool must own the wrapped NFT to mint/burn.
        wrapped.transferOwnership(address(destPool));

        // 5. Bilateral allowlist. Simulator shares one chain selector.
        sourcePool.allowlistDestinationChain(chainSelector, true);
        sourcePool.allowlistSourceChain(chainSelector, true);
        sourcePool.allowlistSender(address(destPool), true);

        destPool.allowlistDestinationChain(chainSelector, true);
        destPool.allowlistSourceChain(chainSelector, true);
        destPool.allowlistSender(address(sourcePool), true);

        // 6. Demo: mint one NFT to the deployer on the "source chain".
        original.safeMint(deployer);

        vm.stopBroadcast();

        console2.log("========== Local deployment ==========");
        console2.log("chainSelector      :", chainSelector);
        console2.log("simulator          :", address(simulator));
        console2.log("sourceRouter       :", address(sourceRouter));
        console2.log("destRouter         :", address(destRouter));
        console2.log("linkToken          :", address(linkToken));
        console2.log("MyNFT (original)   :", address(original));
        console2.log("WrappedNFT         :", address(wrapped));
        console2.log("SourcePool         :", address(sourcePool));
        console2.log("DestPool           :", address(destPool));
        console2.log("deployer owns NFT 0:", original.ownerOf(0));
    }
}
