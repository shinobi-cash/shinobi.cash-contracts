// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {PoolDiamond} from "../../../src/pool/PoolDiamond.sol";
import {DepositFacet} from "../../../src/pool/facets/DepositFacet.sol";
import {CrosschainDepositFacet} from "../../../src/pool/facets/CrosschainDepositFacet.sol";
import {WithdrawFacet} from "../../../src/pool/facets/WithdrawFacet.sol";
import {RagequitFacet} from "../../../src/pool/facets/RagequitFacet.sol";
import {CrosschainWithdrawFacet} from "../../../src/pool/facets/CrosschainWithdrawFacet.sol";
import {Withdraw2Facet} from "../../../src/pool/facets/Withdraw2Facet.sol";
import {CrosschainWithdraw2Facet} from "../../../src/pool/facets/CrosschainWithdraw2Facet.sol";
import {IPoolDiamond} from "../../../src/pool/interfaces/IPoolDiamond.sol";
import {IFacet} from "../../../src/pool/interfaces/IFacet.sol";
import {AccessControlStorageLib} from "../../../src/pool/storage/AccessControlStorage.sol";
import {PoolOps} from "../../../src/pool/libraries/PoolOps.sol";
import {Constants} from "../../../src/pool/libraries/Constants.sol";
import {IWithdrawalVerifier} from "../../../src/verifiers/interfaces/IWithdrawalVerifier.sol";
import {IRagequitVerifier} from "../../../src/verifiers/interfaces/IRagequitVerifier.sol";
import {ICrosschainWithdrawalProofVerifier} from "../../../src/verifiers/interfaces/ICrosschainWithdrawalProofVerifier.sol";
import {IWithdraw2Verifier} from "../../../src/verifiers/interfaces/IWithdraw2Verifier.sol";
import {ICrosschainWithdraw2Verifier} from "../../../src/verifiers/interfaces/ICrosschainWithdraw2Verifier.sol";
import {WithdrawData, CrosschainWithdrawData} from "../../../src/pool/libraries/Types.sol";
import {WithdrawProofLib} from "../../../src/proofLibs/WithdrawProofLib.sol";
import {RagequitProofLib} from "../../../src/proofLibs/RagequitProofLib.sol";
import {CrosschainProofLib} from "../../../src/proofLibs/CrosschainProofLib.sol";
import {Withdraw2ProofLib} from "../../../src/proofLibs/Withdraw2ProofLib.sol";
import {CrosschainWithdraw2ProofLib} from "../../../src/proofLibs/CrosschainWithdraw2ProofLib.sol";
import {ShinobiIntent} from "../../../src/oif/libraries/ShinobiIntentType.sol";

/*//////////////////////////////////////////////////////////////
                          MOCK CONTRACTS
//////////////////////////////////////////////////////////////*/

contract MockVerifier is IWithdrawalVerifier, IRagequitVerifier {
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
    }

    address public entrypoint;
    OpenCall[] public openCalls;

    function setEntrypoint(address _entrypoint) external {
        entrypoint = _entrypoint;
    }

    function open(ShinobiIntent calldata) external payable {
        openCalls.push(OpenCall({value: msg.value}));
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

    DepositFacet public depositFacet;
    CrosschainDepositFacet public crosschainDepositFacet;
    WithdrawFacet public withdrawFacet;
    RagequitFacet public ragequitFacet;
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
        depositFacet = new DepositFacet();
        crosschainDepositFacet = new CrosschainDepositFacet();
        withdrawFacet = new WithdrawFacet(IWithdrawalVerifier(address(withdrawalVerifier)));
        ragequitFacet = new RagequitFacet(IRagequitVerifier(address(ragequitVerifier)));
        crosschainWithdrawFacet = new CrosschainWithdrawFacet(crosschainVerifier);
        withdraw2Facet = new Withdraw2Facet(withdraw2Verifier);
        crosschainWithdraw2Facet = new CrosschainWithdraw2Facet(crosschainWithdraw2Verifier);

        // Build facets array (operational facets only — governance/config/views are on the diamond)
        address[] memory facets = new address[](7);
        facets[0] = address(depositFacet);
        facets[1] = address(crosschainDepositFacet);
        facets[2] = address(withdrawFacet);
        facets[3] = address(ragequitFacet);
        facets[4] = address(crosschainWithdrawFacet);
        facets[5] = address(withdraw2Facet);
        facets[6] = address(crosschainWithdraw2Facet);

        // Deploy diamond
        diamond = new PoolDiamond(
            PoolDiamond.InitParams({
                asset: NATIVE_ASSET,
                admin: admin,
                aspPostman: aspPostman,
                facets: facets
            })
        );

        pool = IPoolDiamond(address(diamond));

        // Configure asset config
        vm.prank(admin);
        pool.setAssetConfig(MIN_DEPOSIT, VETTING_FEE_BPS, MAX_RELAY_FEE_BPS);

        // Configure settlers and fee recipient
        mockSettler.setEntrypoint(address(diamond));
        vm.etch(depositSettler, hex"00"); // needs code for contract check
        vm.startPrank(admin);
        pool.setWithdrawalInputSettler(address(mockSettler));
        pool.setDepositOutputSettler(depositSettler);
        pool.setVettingFeeRecipient(makeAddr("vettingFeeVault"));
        vm.stopPrank();

        // Set initial ASP root
        vm.prank(aspPostman);
        pool.updateRoot(42, "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG");

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
        returns (WithdrawProofLib.WithdrawProof memory proof)
    {
        proof.pubSignals[0] = newCommitment; // newCommitment
        proof.pubSignals[1] = nullifier; // existingNullifierHash
        proof.pubSignals[2] = value; // withdrawnValue
        proof.pubSignals[3] = pool.currentRoot(); // stateRoot
        proof.pubSignals[4] = pool.currentTreeDepth(); // stateTreeDepth
        proof.pubSignals[5] = pool.latestRoot(); // ASPRoot
        proof.pubSignals[6] = 1; // ASPTreeDepth
        // context will be set by caller
    }

    function _computeContext(bytes memory withdrawalData) internal view returns (uint256) {
        return uint256(keccak256(abi.encode(withdrawalData, pool.SCOPE()))) % Constants.SNARK_SCALAR_FIELD;
    }

    function _makeWithdrawData(address recipient, uint256 relayFeeBPS) internal view returns (WithdrawData memory) {
        return WithdrawData({
            recipient: recipient,
            feeRecipient: feeRecipient,
            relayFeeBPS: relayFeeBPS
        });
    }

    /*//////////////////////////////////////////////////////////////
                         WITHDRAW2 PROOF HELPER
    //////////////////////////////////////////////////////////////*/

    function _makeWithdraw2Proof(uint256 nullifier0, uint256 nullifier1, uint256 value, uint256 newCommitment)
        internal
        view
        returns (Withdraw2ProofLib.Withdraw2Proof memory proof)
    {
        proof.pubSignals[0] = newCommitment;
        proof.pubSignals[1] = nullifier0;
        proof.pubSignals[2] = nullifier1;
        proof.pubSignals[3] = value;
        proof.pubSignals[4] = pool.currentRoot();
        proof.pubSignals[5] = pool.currentTreeDepth();
        proof.pubSignals[6] = pool.latestRoot();
        proof.pubSignals[7] = 1; // ASPTreeDepth
        // [8] context - set by caller
    }

    /*//////////////////////////////////////////////////////////////
                    CROSSCHAIN WITHDRAW PROOF HELPER
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant DEST_CHAIN_ID = 84532;

    function _setupCrosschainConfig() internal {
        vm.startPrank(admin);
        pool.setMaxSolverFeeBPS(500);
        pool.setMaxRefundFeeBPS(500);
        pool.setWithdrawalChainConfig(
            DEST_CHAIN_ID,
            makeAddr("outputSettler"),
            makeAddr("outputOracle"),
            makeAddr("fillOracle"),
            3600,
            7200
        );
        vm.stopPrank();
    }

    function _encodeCrosschainDestination(uint256 chainId, address recipient) internal pure returns (bytes32) {
        return bytes32(chainId << 224 | uint256(uint160(recipient)));
    }

    function _makeCrosschainWithdrawData(uint256 solverFeeBPS, uint256 destChainId, address recipient)
        internal
        view
        returns (CrosschainWithdrawData memory)
    {
        return CrosschainWithdrawData({
            feeRecipient: feeRecipient,
            solverFeeBPS: solverFeeBPS,
            encodedDestination: _encodeCrosschainDestination(destChainId, recipient)
        });
    }

    function _makeCrosschainWithdrawProof(
        uint256 nullifier,
        uint256 value,
        uint256 newCommitment,
        uint256 refundCommitment,
        uint256 relayFeeBPS,
        uint256 refundFeeBPS
    ) internal view returns (CrosschainProofLib.CrosschainWithdrawProof memory proof) {
        proof.pubSignals[0] = newCommitment;
        proof.pubSignals[1] = nullifier;
        proof.pubSignals[2] = refundCommitment;
        proof.pubSignals[3] = relayFeeBPS;
        proof.pubSignals[4] = refundFeeBPS;
        proof.pubSignals[5] = value;
        proof.pubSignals[6] = pool.currentRoot();
        proof.pubSignals[7] = pool.currentTreeDepth();
        proof.pubSignals[8] = pool.latestRoot();
        proof.pubSignals[9] = 1; // ASPTreeDepth
        // [10] context - set by caller
    }

    /*//////////////////////////////////////////////////////////////
                 CROSSCHAIN WITHDRAW2 PROOF HELPER
    //////////////////////////////////////////////////////////////*/

    function _makeCrosschainWithdraw2Proof(
        uint256 nullifier0,
        uint256 nullifier1,
        uint256 value,
        uint256 newCommitment,
        uint256 refundCommitment,
        uint256 relayFeeBPS,
        uint256 refundFeeBPS
    ) internal view returns (CrosschainWithdraw2ProofLib.CrosschainWithdraw2Proof memory proof) {
        proof.pubSignals[0] = newCommitment;
        proof.pubSignals[1] = nullifier0;
        proof.pubSignals[2] = nullifier1;
        proof.pubSignals[3] = refundCommitment;
        proof.pubSignals[4] = relayFeeBPS;
        proof.pubSignals[5] = refundFeeBPS;
        proof.pubSignals[6] = value;
        proof.pubSignals[7] = pool.currentRoot();
        proof.pubSignals[8] = pool.currentTreeDepth();
        proof.pubSignals[9] = pool.latestRoot();
        proof.pubSignals[10] = 1; // ASPTreeDepth
        // [11] context - set by caller
    }

    /*//////////////////////////////////////////////////////////////
                         RAGEQUIT PROOF HELPER
    //////////////////////////////////////////////////////////////*/

    function _makeRagequitProof(uint256 commitmentHash, uint256 nullifierHash, uint256 value, uint256 label)
        internal
        pure
        returns (RagequitProofLib.RagequitProof memory proof)
    {
        proof.pubSignals[0] = commitmentHash;
        proof.pubSignals[1] = nullifierHash;
        proof.pubSignals[2] = value;
        proof.pubSignals[3] = label;
    }

    function _computeLabel(uint256 nonceValue) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(pool.SCOPE(), nonceValue))) % Constants.SNARK_SCALAR_FIELD;
    }

    function _buildFacets() internal view returns (address[] memory facets) {
        facets = new address[](7);
        facets[0] = address(depositFacet);
        facets[1] = address(crosschainDepositFacet);
        facets[2] = address(withdrawFacet);
        facets[3] = address(ragequitFacet);
        facets[4] = address(crosschainWithdrawFacet);
        facets[5] = address(withdraw2Facet);
        facets[6] = address(crosschainWithdraw2Facet);
    }
}
