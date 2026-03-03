// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {PoolDiamond} from "../../src/diamond/PoolDiamond.sol";
import {AdminFacet} from "../../src/diamond/facets/AdminFacet.sol";
import {ViewFacet} from "../../src/diamond/facets/ViewFacet.sol";
import {DepositFacet} from "../../src/diamond/facets/DepositFacet.sol";
import {WithdrawFacet} from "../../src/diamond/facets/WithdrawFacet.sol";
import {RagequitFacet} from "../../src/diamond/facets/RagequitFacet.sol";
import {RefundFacet} from "../../src/diamond/facets/RefundFacet.sol";
import {CrosschainWithdrawFacet} from "../../src/diamond/facets/CrosschainWithdrawFacet.sol";
import {Withdraw2Facet} from "../../src/diamond/facets/Withdraw2Facet.sol";
import {CrosschainWithdraw2Facet} from "../../src/diamond/facets/CrosschainWithdraw2Facet.sol";
import {IPoolDiamond} from "../../src/diamond/interfaces/IPoolDiamond.sol";
import {IFacet} from "../../src/diamond/interfaces/IFacet.sol";
import {AccessControlStorageLib} from "../../src/diamond/storage/AccessControlStorage.sol";
import {PoolOps} from "../../src/diamond/libraries/PoolOps.sol";
import {Constants} from "contracts/lib/Constants.sol";
import {IVerifier} from "interfaces/IVerifier.sol";
import {ICrosschainWithdrawalProofVerifier} from "../../src/core/interfaces/ICrosschainWithdrawalProofVerifier.sol";
import {IWithdraw2Verifier} from "../../src/core/interfaces/IWithdraw2Verifier.sol";
import {ICrosschainWithdraw2Verifier} from "../../src/core/interfaces/ICrosschainWithdraw2Verifier.sol";
import {IPrivacyPool} from "interfaces/IPrivacyPool.sol";
import {ProofLib} from "contracts/lib/ProofLib.sol";

/*//////////////////////////////////////////////////////////////
                          MOCK CONTRACTS
//////////////////////////////////////////////////////////////*/

contract MockVerifier is IVerifier {
    bool public shouldPass = true;

    function setShouldPass(bool _pass) external {
        shouldPass = _pass;
    }

    function verifyProof(uint256[2] memory, uint256[2][2] memory, uint256[2] memory, uint256[8] memory)
        external
        view
        returns (bool)
    {
        return shouldPass;
    }

    function verifyProof(uint256[2] memory, uint256[2][2] memory, uint256[2] memory, uint256[4] memory)
        external
        view
        returns (bool)
    {
        return shouldPass;
    }
}

contract MockCrosschainVerifier is ICrosschainWithdrawalProofVerifier {
    bool public shouldPass = true;

    function setShouldPass(bool _pass) external {
        shouldPass = _pass;
    }

    function verifyProof(uint256[2] memory, uint256[2][2] memory, uint256[2] memory, uint256[11] memory)
        external
        view
        returns (bool)
    {
        return shouldPass;
    }
}

contract MockWithdraw2Verifier is IWithdraw2Verifier {
    bool public shouldPass = true;

    function setShouldPass(bool _pass) external {
        shouldPass = _pass;
    }

    function verifyProof(uint256[2] calldata, uint256[2][2] calldata, uint256[2] calldata, uint256[9] calldata)
        external
        view
        returns (bool)
    {
        return shouldPass;
    }
}

contract MockCrosschainWithdraw2Verifier is ICrosschainWithdraw2Verifier {
    bool public shouldPass = true;

    function setShouldPass(bool _pass) external {
        shouldPass = _pass;
    }

    function verifyProof(uint256[2] calldata, uint256[2][2] calldata, uint256[2] calldata, uint256[12] calldata)
        external
        view
        returns (bool)
    {
        return shouldPass;
    }
}

contract MockInputSettler {
    struct OpenCall {
        uint256 value;
        bytes intentData;
    }

    OpenCall[] public openCalls;

    function open(bytes calldata intent) external payable {
        openCalls.push(OpenCall({value: msg.value, intentData: intent}));
    }

    function openCallCount() external view returns (uint256) {
        return openCalls.length;
    }

    receive() external payable {}
}

/*//////////////////////////////////////////////////////////////
                          TEST BASE
//////////////////////////////////////////////////////////////*/

abstract contract DiamondTestBase is Test {
    // Diamond and facets
    PoolDiamond public diamond;
    IPoolDiamond public pool; // Diamond cast to interface

    AdminFacet public adminFacet;
    ViewFacet public viewFacet;
    DepositFacet public depositFacet;
    WithdrawFacet public withdrawFacet;
    RagequitFacet public ragequitFacet;
    RefundFacet public refundFacet;
    CrosschainWithdrawFacet public crosschainWithdrawFacet;
    Withdraw2Facet public withdraw2Facet;
    CrosschainWithdraw2Facet public crosschainWithdraw2Facet;

    // Mock verifiers
    MockVerifier public withdrawalVerifier;
    MockVerifier public ragequitVerifier;
    MockCrosschainVerifier public crosschainVerifier;
    MockWithdraw2Verifier public withdraw2Verifier;
    MockCrosschainWithdraw2Verifier public crosschainWithdraw2Verifier;

    // Mock settler
    MockInputSettler public mockSettler;

    // Test accounts
    address public admin = makeAddr("admin");
    address public aspPostman = makeAddr("aspPostman");
    address public diamondAdmin = makeAddr("diamondAdmin");
    address public user = makeAddr("user");
    address public relayer = makeAddr("relayer");
    address public feeRecipient = makeAddr("feeRecipient");
    address public depositSettler = makeAddr("depositSettler");

    // Constants
    address constant NATIVE_ASSET = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 constant MIN_DEPOSIT = 0.01 ether;
    uint256 constant VETTING_FEE_BPS = 100; // 1%
    uint256 constant MAX_RELAY_FEE_BPS = 500; // 5%
    uint256 constant DEPOSIT_AMOUNT = 1 ether;

    function setUp() public virtual {
        // Deploy mock verifiers
        withdrawalVerifier = new MockVerifier();
        ragequitVerifier = new MockVerifier();
        crosschainVerifier = new MockCrosschainVerifier();
        withdraw2Verifier = new MockWithdraw2Verifier();
        crosschainWithdraw2Verifier = new MockCrosschainWithdraw2Verifier();
        mockSettler = new MockInputSettler();

        // Deploy facets
        adminFacet = new AdminFacet();
        viewFacet = new ViewFacet();
        depositFacet = new DepositFacet();
        withdrawFacet = new WithdrawFacet(IVerifier(address(withdrawalVerifier)));
        ragequitFacet = new RagequitFacet(IVerifier(address(ragequitVerifier)));
        refundFacet = new RefundFacet();
        crosschainWithdrawFacet = new CrosschainWithdrawFacet(crosschainVerifier);
        withdraw2Facet = new Withdraw2Facet(withdraw2Verifier);
        crosschainWithdraw2Facet = new CrosschainWithdraw2Facet(crosschainWithdraw2Verifier);

        // Build facets array
        address[] memory facets = new address[](9);
        facets[0] = address(adminFacet);
        facets[1] = address(viewFacet);
        facets[2] = address(depositFacet);
        facets[3] = address(withdrawFacet);
        facets[4] = address(ragequitFacet);
        facets[5] = address(refundFacet);
        facets[6] = address(crosschainWithdrawFacet);
        facets[7] = address(withdraw2Facet);
        facets[8] = address(crosschainWithdraw2Facet);

        // Deploy diamond
        diamond = new PoolDiamond(
            PoolDiamond.InitParams({
                asset: NATIVE_ASSET,
                admin: admin,
                aspPostman: aspPostman,
                diamondAdmin: diamondAdmin,
                facets: facets
            })
        );

        pool = IPoolDiamond(address(diamond));

        // Configure asset config
        vm.prank(admin);
        pool.setAssetConfig(MIN_DEPOSIT, VETTING_FEE_BPS, MAX_RELAY_FEE_BPS);

        // Configure settlers
        vm.startPrank(admin);
        pool.setWithdrawalInputSettler(address(mockSettler));
        pool.setDepositOutputSettler(depositSettler);
        vm.stopPrank();

        // Set initial ASP root
        vm.prank(aspPostman);
        pool.updateRoot(42, "QmTest");

        // Fund test accounts
        vm.deal(user, 100 ether);
        vm.deal(relayer, 10 ether);
        vm.deal(depositSettler, 100 ether);
        vm.deal(address(mockSettler), 10 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _deposit(address depositor, uint256 amount, uint256 precommitment) internal returns (uint256) {
        vm.prank(depositor);
        return pool.deposit{value: amount}(precommitment);
    }

    function _makeWithdrawProof(uint256 nullifier, uint256 value, uint256 newCommitment)
        internal
        view
        returns (ProofLib.WithdrawProof memory proof)
    {
        proof.pubSignals[0] = newCommitment; // newCommitmentHash
        proof.pubSignals[1] = nullifier; // existingNullifierHash
        proof.pubSignals[2] = value; // withdrawnValue
        proof.pubSignals[3] = pool.currentRoot(); // stateRoot
        proof.pubSignals[4] = pool.currentTreeDepth(); // stateTreeDepth
        proof.pubSignals[5] = pool.latestRoot(); // ASPRoot
        proof.pubSignals[6] = 1; // ASPTreeDepth
        // context will be set by caller
    }

    function _computeContext(IPrivacyPool.Withdrawal memory withdrawal) internal view returns (uint256) {
        return uint256(keccak256(abi.encode(withdrawal, pool.SCOPE()))) % Constants.SNARK_SCALAR_FIELD;
    }

    function _makeRelayData(address recipient, uint256 relayFeeBPS) internal view returns (bytes memory) {
        return abi.encode(
            recipient,
            feeRecipient,
            relayFeeBPS
        );
    }
}
