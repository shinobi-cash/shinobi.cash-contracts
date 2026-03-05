// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IFacet - ERC-8153 facet interface
/// @notice All diamond facets must implement this interface for on-chain selector discovery
interface IFacet {
    /// @notice Returns the function selectors exported by this facet
    /// @return selectors Packed bytes4 selectors (length = N * 4)
    function exportSelectors() external pure returns (bytes memory selectors);
}
