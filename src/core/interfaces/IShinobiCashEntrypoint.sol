// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

import {IShinobiCashCrossChainHandler} from "./IShinobiCashCrossChainHandler.sol";
import {IEntrypoint} from "interfaces/IEntrypoint.sol";


/**
 * @title IShinobiCashEntrypoint
 * @notice Interface for the ShinobiCashEntrypoint contract
 */
interface IShinobiCashEntrypoint is IEntrypoint, IShinobiCashCrossChainHandler {

}