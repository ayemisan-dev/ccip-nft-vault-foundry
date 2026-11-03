// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console2} from "forge-std/Test.sol";
import {PlainERC721} from "../../src/mocks/PlainERC721.sol";
import {PlainERC721Enumerable} from "../../src/mocks/PlainERC721Enumerable.sol";
import {PlainERC721A} from "../../src/mocks/PlainERC721A.sol";

/// @title MintGasComparison
/// @notice Educational gas benchmark: OZ ERC721 vs OZ ERC721Enumerable vs ERC721A.
/// @dev This file is NOT part of the cross-chain protocol. It exists to document
///      the engineering trade-off that justified dropping ERC721Enumerable.
contract MintGasComparisonTest is Test {
    PlainERC721 plain;
    PlainERC721Enumerable enumerableNft;
    PlainERC721A erc721a;

    address alice = makeAddr("alice");

    function setUp() public {
        plain = new PlainERC721();
        enumerableNft = new PlainERC721Enumerable();
        erc721a = new PlainERC721A();
    }

    /// @notice Mint `quantity` tokens in a single transaction per contract.
    function _gasPlain(uint256 quantity) internal returns (uint256) {
        uint256 gasBefore = gasleft();
        for (uint256 i = 0; i < quantity; i++) {
            plain.mint(alice);
        }
        return gasBefore - gasleft();
    }

    function _gasEnumerable(uint256 quantity) internal returns (uint256) {
        uint256 gasBefore = gasleft();
        for (uint256 i = 0; i < quantity; i++) {
            enumerableNft.mint(alice);
        }
        return gasBefore - gasleft();
    }

    function _gasERC721A(uint256 quantity) internal returns (uint256) {
        uint256 gasBefore = gasleft();
        erc721a.mint(alice, quantity);
        return gasBefore - gasleft();
    }

    /// @notice Fuzz test: compare gas across all three for arbitrary quantities.
    /// @dev Run with: forge test --match-test testFuzz_MintGas -vv
    function testFuzz_MintGas(uint256 quantity) public {
        quantity = bound(quantity, 1, 10);

        uint256 gPlain = _gasPlain(quantity);
        uint256 gEnum = _gasEnumerable(quantity);
        uint256 gA = _gasERC721A(quantity);

        console2.log("quantity          :", quantity);
        console2.log("plain ERC721      :", gPlain);
        console2.log("ERC721Enumerable  :", gEnum);
        console2.log("ERC721A           :", gA);

        if (quantity >= 2) {
            assertLt(gA, gPlain, "ERC721A should beat plain ERC721 for batch >= 2");
            assertLt(gA, gEnum, "ERC721A should beat Enumerable for batch >= 2");
        }
    }

    function test_GasSnapshot() public {
        uint256[4] memory quantities = [uint256(1), 2, 5, 10];
        for (uint256 i = 0; i < quantities.length; i++) {
            uint256 q = quantities[i];

            // Reset contracts so each row starts from a clean state.
            plain = new PlainERC721();
            enumerableNft = new PlainERC721Enumerable();
            erc721a = new PlainERC721A();

            uint256 gPlain = _gasPlain(q);
            uint256 gEnum = _gasEnumerable(q);
            uint256 gA = _gasERC721A(q);

            console2.log("-------- quantity:", q);
            console2.log("plain ERC721     :", gPlain);
            console2.log("ERC721Enumerable :", gEnum);
            console2.log("ERC721A          :", gA);
        }
    }
}
