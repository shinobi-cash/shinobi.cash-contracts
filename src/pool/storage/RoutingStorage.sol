// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

/// @title RoutingStorage - ERC-8153 routing state
struct RoutingStorageData {
    /// @notice Maps function selector to its implementing facet address
    mapping(bytes4 => address) selectorToFacet;
    /// @notice List of all registered facet addresses
    address[] facets;
    /// @notice Maps facet address to its selectors for loupe queries
    mapping(address => bytes4[]) facetSelectors;
}

library RoutingStorageLib {
    /// @dev keccak256("shinobi.diamond.storage")
    bytes32 internal constant SLOT = 0xd5624ee4df56b6db2abe51f96a25d28e8c5128406129775e93b33fb3ae622627;

    function layout() internal pure returns (RoutingStorageData storage s) {
        bytes32 slot = SLOT;
        assembly {
            s.slot := slot
        }
    }
}
