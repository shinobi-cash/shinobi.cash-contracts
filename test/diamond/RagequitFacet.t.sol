// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {DiamondTestBase} from "./DiamondTestBase.sol";
import {RagequitFacet} from "../../src/diamond/facets/RagequitFacet.sol";
import {PoolOps} from "../../src/diamond/libraries/PoolOps.sol";
import {ProofLib} from "contracts/lib/ProofLib.sol";
import {Constants} from "contracts/lib/Constants.sol";

contract RagequitFacetTest is DiamondTestBase {
    uint256 public depositCommitment;
    uint256 public depositLabel;
    uint256 public netAmount;

    function setUp() public override {
        super.setUp();
        // Deposit as user
        vm.prank(user);
        depositCommitment = pool.deposit{value: DEPOSIT_AMOUNT}(12345);

        // Compute the label for nonce=1
        depositLabel = _computeLabel(1);

        // Compute net amount after vetting fee
        netAmount = DEPOSIT_AMOUNT - (DEPOSIT_AMOUNT * VETTING_FEE_BPS / 10_000);
    }

    function test_ragequit_success() public {
        ProofLib.RagequitProof memory proof =
            _makeRagequitProof(depositCommitment, 111, netAmount, depositLabel);

        uint256 balanceBefore = user.balance;

        vm.prank(user);
        pool.ragequit(proof);

        // User receives net amount
        assertEq(user.balance - balanceBefore, netAmount);
        // Nullifier is spent
        assertTrue(pool.nullifierHashes(111));
    }

    function test_ragequit_revertsForNonDepositor() public {
        ProofLib.RagequitProof memory proof =
            _makeRagequitProof(depositCommitment, 111, netAmount, depositLabel);

        vm.expectRevert(RagequitFacet.OnlyOriginalDepositor.selector);
        vm.prank(relayer); // not the original depositor
        pool.ragequit(proof);
    }

    function test_ragequit_revertsForInvalidProof() public {
        ragequitVerifier.setShouldPass(false);

        ProofLib.RagequitProof memory proof =
            _makeRagequitProof(depositCommitment, 111, netAmount, depositLabel);

        vm.expectRevert(RagequitFacet.InvalidProof.selector);
        vm.prank(user);
        pool.ragequit(proof);
    }

    function test_ragequit_revertsForInvalidCommitment() public {
        // Use a commitment hash that doesn't exist in the tree
        ProofLib.RagequitProof memory proof =
            _makeRagequitProof(999999, 111, netAmount, depositLabel);

        vm.expectRevert(RagequitFacet.InvalidCommitment.selector);
        vm.prank(user);
        pool.ragequit(proof);
    }

    function test_ragequit_revertsForSpentNullifier() public {
        ProofLib.RagequitProof memory proof =
            _makeRagequitProof(depositCommitment, 111, netAmount, depositLabel);

        vm.prank(user);
        pool.ragequit(proof);

        // Try to ragequit again with same nullifier
        ProofLib.RagequitProof memory proof2 =
            _makeRagequitProof(depositCommitment, 111, netAmount, depositLabel);

        vm.expectRevert(PoolOps.NullifierAlreadySpent.selector);
        vm.prank(user);
        pool.ragequit(proof2);
    }

    function test_ragequit_worksWhenPoolIsDead() public {
        // Wind down the pool
        vm.prank(admin);
        pool.windDown();
        assertTrue(pool.dead());

        // Ragequit should still work (no whenAlive check)
        ProofLib.RagequitProof memory proof =
            _makeRagequitProof(depositCommitment, 111, netAmount, depositLabel);

        uint256 balanceBefore = user.balance;

        vm.prank(user);
        pool.ragequit(proof);

        assertEq(user.balance - balanceBefore, netAmount);
    }

    function test_ragequit_emitsEvent() public {
        ProofLib.RagequitProof memory proof =
            _makeRagequitProof(depositCommitment, 111, netAmount, depositLabel);

        vm.expectEmit(true, false, false, true, address(diamond));
        emit RagequitFacet.Ragequit(user, depositCommitment, depositLabel, netAmount);

        vm.prank(user);
        pool.ragequit(proof);
    }
}
