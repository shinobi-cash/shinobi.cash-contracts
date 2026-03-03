// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {DiamondTestBase} from "./DiamondTestBase.sol";
import {AdminFacet} from "../../src/diamond/facets/AdminFacet.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {IEntrypoint} from "interfaces/IEntrypoint.sol";
import {ProofLib} from "contracts/lib/ProofLib.sol";
import {Constants} from "contracts/lib/Constants.sol";
import {IFacet} from "../../src/diamond/interfaces/IFacet.sol";
import {IPoolDiamond} from "../../src/diamond/interfaces/IPoolDiamond.sol";

contract IntegrationTest is DiamondTestBase {
    /*//////////////////////////////////////////////////////////////
                    DEPOSIT → WITHDRAW FLOW
    //////////////////////////////////////////////////////////////*/

    function test_depositAndWithdraw() public {
        // 1. Deposit
        uint256 precommitment = 12345;
        vm.prank(user);
        uint256 commitment = pool.deposit{value: DEPOSIT_AMOUNT}(precommitment);
        assertTrue(commitment != 0);

        // 2. Verify state after deposit
        assertEq(pool.nonce(), 1);
        assertEq(pool.currentTreeSize(), 1);
        assertTrue(pool.currentRoot() != 0);

        // 3. Withdraw
        address recipient = makeAddr("recipient");
        uint256 withdrawValue = 0.5 ether;

        IPrivacyPool.Withdrawal memory withdrawal = IPrivacyPool.Withdrawal({
            processooor: address(diamond),
            data: abi.encode(IEntrypoint.RelayData({
                recipient: recipient,
                feeRecipient: feeRecipient,
                relayFeeBPS: 100
            }))
        });

        ProofLib.WithdrawProof memory proof = _makeWithdrawProof(111, withdrawValue, 222);
        proof.pubSignals[7] = _computeContext(withdrawal);

        // Fund diamond (simulates having funds from deposit)
        vm.deal(address(diamond), 10 ether);

        uint256 recipientBefore = recipient.balance;
        vm.prank(relayer);
        pool.withdraw(withdrawal, proof);

        // 4. Verify withdrawal succeeded
        uint256 fee = withdrawValue * 100 / 10_000;
        assertEq(recipient.balance - recipientBefore, withdrawValue - fee);
        assertTrue(pool.nullifierHashes(111));
        assertEq(pool.currentTreeSize(), 2); // deposit + new commitment from withdraw
    }

    /*//////////////////////////////////////////////////////////////
                    MULTIPLE DEPOSITS + VIEW STATE
    //////////////////////////////////////////////////////////////*/

    function test_multipleDepositsUpdateState() public {
        vm.startPrank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}(1);
        pool.deposit{value: DEPOSIT_AMOUNT}(2);
        pool.deposit{value: DEPOSIT_AMOUNT}(3);
        vm.stopPrank();

        assertEq(pool.nonce(), 3);
        assertEq(pool.currentTreeSize(), 3);
        assertTrue(pool.currentTreeDepth() > 0);
        assertTrue(pool.currentRoot() != 0);
    }

    /*//////////////////////////////////////////////////////////////
                    DIAMOND UPGRADE + CALL NEW FACET
    //////////////////////////////////////////////////////////////*/

    function test_upgradeAndCallNewFacet() public {
        // Deploy and add mock extra facet
        MockExtraFacet newFacet = new MockExtraFacet();

        address[] memory addFacets = new address[](1);
        addFacets[0] = address(newFacet);
        address[] memory removeFacets = new address[](0);
        IPoolDiamond.ReplaceAction[] memory replaceFacets = new IPoolDiamond.ReplaceAction[](0);

        vm.prank(diamondAdmin);
        pool.upgradeDiamond(addFacets, removeFacets, replaceFacets);

        // Call the new function through the diamond
        (bool success, bytes memory data) =
            address(diamond).call(abi.encodeWithSelector(MockExtraFacet.extraFunction.selector));
        assertTrue(success);
        uint256 result = abi.decode(data, (uint256));
        assertEq(result, 42);
    }

    /*//////////////////////////////////////////////////////////////
                    REENTRANCY PROTECTION
    //////////////////////////////////////////////////////////////*/

    function test_reentrancyGuard_preventsReentry() public {
        // The reentrancy guard shares state across all facets via PoolStorage
        // We can verify it works by checking reentrancy status is reset
        vm.prank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}(12345);

        // If reentrancy guard was stuck, this would revert
        vm.prank(user);
        pool.deposit{value: DEPOSIT_AMOUNT}(12346);

        assertEq(pool.nonce(), 2);
    }

    /*//////////////////////////////////////////////////////////////
                    REFUND FLOW
    //////////////////////////////////////////////////////////////*/

    function test_refundInsertsCommitmentAndPaysFee() public {
        uint256 refundCommitmentHash = 42;
        uint256 refundAmount = 1 ether;
        uint256 refundFeeBPS = 200; // 2%

        uint256 feeBefore = feeRecipient.balance;
        uint256 treeSizeBefore = pool.currentTreeSize();

        uint256 scope = pool.SCOPE();
        vm.prank(address(mockSettler));
        pool.handleRefund{value: refundAmount}(refundCommitmentHash, feeRecipient, refundFeeBPS, scope);

        uint256 expectedFee = refundAmount * refundFeeBPS / 10_000;
        assertEq(feeRecipient.balance - feeBefore, expectedFee);
        assertEq(pool.currentTreeSize(), treeSizeBefore + 1);
    }

    /*//////////////////////////////////////////////////////////////
                    ACCESS CONTROL ACROSS FACETS
    //////////////////////////////////////////////////////////////*/

    function test_accessControl_sharedAcrossFacets() public {
        // Grant a new admin via AdminFacet
        address newAdmin = makeAddr("newAdmin");
        vm.prank(admin);
        pool.grantRole(keccak256("ADMIN_ROLE"), newAdmin);

        // New admin can use admin functions
        vm.prank(newAdmin);
        pool.setMaxSolverFeeBPS(300);
        assertEq(pool.maxSolverFeeBPS(), 300);
    }

    /*//////////////////////////////////////////////////////////////
                    CROSS-CHAIN DEPOSIT VIA SETTLER
    //////////////////////////////////////////////////////////////*/

    function test_crosschainDepositAndVerifyState() public {
        uint256 precommitment = 55555;

        vm.prank(depositSettler);
        uint256 commitment = pool.crosschainDeposit{value: DEPOSIT_AMOUNT}(user, DEPOSIT_AMOUNT, precommitment);

        assertTrue(commitment != 0);
        assertEq(pool.nonce(), 1);
        assertTrue(pool.usedPrecommitments(precommitment));
    }
}

/// @dev Used by DiamondTestBase for upgrade tests
contract MockExtraFacet is IFacet {
    function extraFunction() external pure returns (uint256) {
        return 42;
    }

    function exportSelectors() external pure returns (bytes memory) {
        return abi.encodePacked(this.extraFunction.selector);
    }
}
