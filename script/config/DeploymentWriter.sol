// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {Vm} from "forge-std/Vm.sol";

/**
 * @title DeploymentWriter
 * @notice Helper library for writing deployment output files with block numbers
 * @dev Uses Foundry's vm.writeJson to create deployment records for indexers.
 *      vm.writeJson with a path selector can only overwrite existing keys, not insert new ones.
 *      So we read the whole file, rebuild the category object with the new entry, and write it back.
 */
library DeploymentWriter {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    string constant DEPLOYMENTS_DIR = "deployments/";

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
        _writeEntry(chainName, "verifiers", name, addr, blockNumber);
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
        _writeEntry(chainName, "contracts", name, addr, blockNumber);
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
        _writeEntry(chainName, "paymasters", name, addr, blockNumber);
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

    /**
     * @dev Write a deployment entry by reading the file, rebuilding the category with the
     *      new entry appended, and writing the updated category back. This works because
     *      vm.writeJson with a path selector can overwrite existing keys (the category exists).
     */
    function _writeEntry(
        string memory chainName,
        string memory category,
        string memory name,
        address addr,
        uint256 blockNumber
    ) private {
        string memory path = getDeploymentPath(chainName);
        string memory fileJson = vm.readFile(path);

        // Build the new entry
        string memory entryKey = "entry";
        vm.serializeAddress(entryKey, "address", addr);
        string memory entryJson = vm.serializeUint(entryKey, "blockNumber", blockNumber);

        // Rebuild the category object: start with existing entries, then add the new one.
        // We use the category name as the serialization namespace.
        string memory catKey = category;
        string memory categoryPath = string.concat(".", category);

        // Parse all existing keys in this category and re-serialize them
        string[] memory keys = vm.parseJsonKeys(fileJson, categoryPath);
        for (uint256 i = 0; i < keys.length; i++) {
            string memory existingPath = string.concat(categoryPath, ".", keys[i]);
            // Skip _initialized marker and skip the key we're about to overwrite
            if (keccak256(bytes(keys[i])) == keccak256("_initialized")) {
                vm.serializeString(catKey, "_initialized", "true");
            } else if (keccak256(bytes(keys[i])) != keccak256(bytes(name))) {
                // Re-serialize existing entry as raw JSON
                address existingAddr = vm.parseJsonAddress(fileJson, string.concat(existingPath, ".address"));
                uint256 existingBlock = vm.parseJsonUint(fileJson, string.concat(existingPath, ".blockNumber"));

                string memory reKey = string.concat("re_", keys[i]);
                vm.serializeAddress(reKey, "address", existingAddr);
                string memory reEntry = vm.serializeUint(reKey, "blockNumber", existingBlock);
                vm.serializeString(catKey, keys[i], reEntry);
            }
        }

        // Add the new entry
        string memory updatedCategory = vm.serializeString(catKey, name, entryJson);

        // Write the updated category back to the file
        vm.writeJson(updatedCategory, path, categoryPath);
    }
}
