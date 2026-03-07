// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {RoutingStorageData, RoutingStorageLib} from "../storage/RoutingStorage.sol";
import {IFacet} from "../interfaces/IFacet.sol";

library RoutingOps {
    event FacetAdded(address indexed facet);
    event FacetReplaced(address indexed oldFacet, address indexed newFacet);
    event FacetRemoved(address indexed facet);

    error FacetAlreadyRegistered(address facet);
    error FacetNotRegistered(address facet);
    error SelectorAlreadyRegistered(bytes4 selector, address existingFacet);
    error SelectorNotRegistered(bytes4 selector);
    error InvalidFacetAddress();
    error NoSelectorsExported(address facet);
    error SelectorConflict(bytes4 selector, address existingFacet, address newFacet);

    function addFacet(address facet) internal {
        if (facet == address(0) || facet.code.length == 0) revert InvalidFacetAddress();

        RoutingStorageData storage ds = RoutingStorageLib.layout();

        // Call exportSelectors() directly on the facet contract
        bytes memory selectors = IFacet(facet).exportSelectors();
        uint256 selectorCount = selectors.length / 4;
        if (selectorCount == 0) revert NoSelectorsExported(facet);

        // Register each selector
        for (uint256 i; i < selectorCount; ++i) {
            bytes4 selector;
            assembly {
                selector := mload(add(selectors, add(32, mul(i, 4))))
            }

            if (ds.selectorToFacet[selector] != address(0)) {
                revert SelectorAlreadyRegistered(selector, ds.selectorToFacet[selector]);
            }

            ds.selectorToFacet[selector] = facet;
            ds.facetSelectors[facet].push(selector);
        }

        ds.facets.push(facet);
        emit FacetAdded(facet);
    }

    function replaceFacet(address oldFacet, address newFacet) internal {
        if (oldFacet == address(0) || newFacet == address(0) || newFacet.code.length == 0) {
            revert InvalidFacetAddress();
        }

        RoutingStorageData storage ds = RoutingStorageLib.layout();

        // Remove old selectors
        bytes4[] storage oldSelectors = ds.facetSelectors[oldFacet];
        uint256 oldCount = oldSelectors.length;
        if (oldCount == 0) revert FacetNotRegistered(oldFacet);

        for (uint256 i; i < oldCount; ++i) {
            delete ds.selectorToFacet[oldSelectors[i]];
        }
        delete ds.facetSelectors[oldFacet];

        // Register new selectors from the new facet
        bytes memory newSelectors = IFacet(newFacet).exportSelectors();
        uint256 newCount = newSelectors.length / 4;
        if (newCount == 0) revert NoSelectorsExported(newFacet);

        for (uint256 i; i < newCount; ++i) {
            bytes4 selector;
            assembly {
                selector := mload(add(newSelectors, add(32, mul(i, 4))))
            }

            if (ds.selectorToFacet[selector] != address(0)) {
                revert SelectorConflict(selector, ds.selectorToFacet[selector], newFacet);
            }

            ds.selectorToFacet[selector] = newFacet;
            ds.facetSelectors[newFacet].push(selector);
        }

        // Swap old facet for new in the facets array
        address[] storage facets = ds.facets;
        for (uint256 i; i < facets.length; ++i) {
            if (facets[i] == oldFacet) {
                facets[i] = newFacet;
                break;
            }
        }

        emit FacetReplaced(oldFacet, newFacet);
    }

    function removeFacet(address facet) internal {
        if (facet == address(0)) revert InvalidFacetAddress();

        RoutingStorageData storage ds = RoutingStorageLib.layout();

        bytes4[] storage selectors = ds.facetSelectors[facet];
        uint256 count = selectors.length;
        if (count == 0) revert FacetNotRegistered(facet);

        // Unregister all selectors
        for (uint256 i; i < count; ++i) {
            delete ds.selectorToFacet[selectors[i]];
        }
        delete ds.facetSelectors[facet];

        // Remove from facets array (swap-and-pop)
        address[] storage facets = ds.facets;
        for (uint256 i; i < facets.length; ++i) {
            if (facets[i] == facet) {
                facets[i] = facets[facets.length - 1];
                facets.pop();
                break;
            }
        }

        emit FacetRemoved(facet);
    }
}
