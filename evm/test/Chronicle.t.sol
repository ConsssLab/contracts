// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Chronicle} from "../src/Chronicle.sol";
import {WitnessSeal} from "../src/WitnessSeal.sol";

contract ChronicleTest is Test {
    Chronicle internal chronicle;
    WitnessSeal internal seal;
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        chronicle = new Chronicle("https://chainoa.consss.io/chronicle/");
        seal = new WitnessSeal("https://chainoa.consss.io/witness/");
    }

    function test_MintChronicleFromAlice() public {
        vm.prank(alice);
        uint256 tokenId = chronicle.mintChronicle(
            1,
            1,
            "The Battle of Lumen Harbor",
            "Speak with your blade, not your numbers.",
            0
        );
        assertEq(chronicle.ownerOf(tokenId), alice);

        Chronicle.ChronicleData memory data = chronicle.chronicleOf(tokenId);
        assertEq(data.battleId, 1);
        assertEq(data.heroId, 1);
        assertEq(data.mintOrder, 1);
        assertTrue(data.isFirstChronicler);
        assertEq(data.player, alice);
    }

    function test_RevertWhen_TransferringWitnessSeal() public {
        vm.prank(alice);
        uint256 tokenId = seal.mintWitness(
            3,
            3,
            "When the Validators Spoke as One",
            "Decentralization is loud, messy, and beautiful.",
            0
        );
        assertEq(seal.ownerOf(tokenId), alice);
        assertTrue(seal.locked(tokenId));

        vm.prank(alice);
        vm.expectRevert(WitnessSeal.Soulbound.selector);
        seal.transferFrom(alice, bob, tokenId);
    }
}
