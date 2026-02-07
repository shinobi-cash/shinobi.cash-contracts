// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Vm} from "forge-std/Vm.sol";

/**
 * @title DeploymentWriter
 * @notice Helper library for writing deployment output files with block numbers
 * @dev Uses Foundry's vm.writeJson to create deployment records for indexers
 */
library DeploymentWriter {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    string constant DEPLOYMENTS_DIR = "deployments/";

    struct DeployedContract {
        address addr;
        uint256 blockNumber;
    }

    /**
     * @notice Get the deployment file path for a chain
     * @param chainName The chain name (e.g., "arbitrum-sepolia")
     */
    function getDeploymentPath(string memory chainName) internal pure returns (string memory) {
        return string.concat(DEPLOYMENTS_DIR, chainName, ".json");
    }

    /**
     * @notice Initialize a new deployment file
     * @param chainName The chain name
     * @param chainId The chain ID
     * @param deployer The deployer address
     */
    function initDeployment(
        string memory chainName,
        uint256 chainId,
        address deployer
    ) internal {
        string memory path = getDeploymentPath(chainName);

        // Create base JSON structure
        string memory json = "deployment";
        vm.serializeString(json, "chainName", chainName);
        vm.serializeUint(json, "chainId", chainId);
        vm.serializeAddress(json, "deployer", deployer);
        vm.serializeUint(json, "deployedAt", block.timestamp);

        // Initialize empty objects for each category
        string memory verifiers = "verifiers";
        string memory verifiersJson = vm.serializeString(verifiers, "_initialized", "true");

        string memory contracts = "contracts";
        string memory contractsJson = vm.serializeString(contracts, "_initialized", "true");

        string memory paymasters = "paymasters";
        string memory paymastersJson = vm.serializeString(paymasters, "_initialized", "true");

        vm.serializeString(json, "verifiers", verifiersJson);
        vm.serializeString(json, "contracts", contractsJson);
        string memory finalJson = vm.serializeString(json, "paymasters", paymastersJson);

        vm.writeJson(finalJson, path);
    }

    /**
     * @notice Write a verifier deployment
     */
    function writeVerifier(
        string memory chainName,
        string memory name,
        address addr,
        uint256 blockNumber
    ) internal {
        string memory path = getDeploymentPath(chainName);

        string memory contractJson = "contract";
        vm.serializeAddress(contractJson, "address", addr);
        string memory finalContract = vm.serializeUint(contractJson, "blockNumber", blockNumber);

        vm.writeJson(finalContract, path, string.concat(".verifiers.", name));
    }

    /**
     * @notice Write a contract deployment
     */
    function writeContract(
        string memory chainName,
        string memory name,
        address addr,
        uint256 blockNumber
    ) internal {
        string memory path = getDeploymentPath(chainName);

        string memory contractJson = "contract";
        vm.serializeAddress(contractJson, "address", addr);
        string memory finalContract = vm.serializeUint(contractJson, "blockNumber", blockNumber);

        vm.writeJson(finalContract, path, string.concat(".contracts.", name));
    }

    /**
     * @notice Write a paymaster deployment
     */
    function writePaymaster(
        string memory chainName,
        string memory name,
        address addr,
        uint256 blockNumber
    ) internal {
        string memory path = getDeploymentPath(chainName);

        string memory contractJson = "contract";
        vm.serializeAddress(contractJson, "address", addr);
        string memory finalContract = vm.serializeUint(contractJson, "blockNumber", blockNumber);

        vm.writeJson(finalContract, path, string.concat(".paymasters.", name));
    }

    /**
     * @notice Read a deployed contract address from deployment file
     * @dev Returns address(0) if file doesn't exist, key doesn't exist, or address is empty
     */
    function readContractAddress(
        string memory chainName,
        string memory category,
        string memory name
    ) internal view returns (address) {
        string memory path = getDeploymentPath(chainName);

        try vm.readFile(path) returns (string memory json) {
            string memory key = string.concat(".", category, ".", name, ".address");
            try vm.parseJsonAddress(json, key) returns (address addr) {
                return addr;
            } catch {
                return address(0);
            }
        } catch {
            return address(0);
        }
    }

    /**
     * @notice Check if deployment file exists
     */
    function deploymentExists(string memory chainName) internal view returns (bool) {
        string memory path = getDeploymentPath(chainName);
        try vm.readFile(path) returns (string memory) {
            return true;
        } catch {
            return false;
        }
    }
}
