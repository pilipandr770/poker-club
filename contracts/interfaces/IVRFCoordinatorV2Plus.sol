// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IVRFCoordinatorV2Plus
 * @dev Interface for Chainlink VRF Coordinator V2.5
 * @notice Chainlink VRF provides verifiable random numbers on-chain
 * Documentation: https://docs.chain.link/vrf
 */
interface IVRFCoordinatorV2Plus {
    /**
     * @notice Request random words
     * @param keyHash The gas lane key hash value
     * @param subId The subscription ID
     * @param requestConfirmations Number of confirmations to wait
     * @param callbackGasLimit Gas limit for the callback
     * @param numWords Number of random words to request
     * @return requestId The ID of the VRF request
     */
    function requestRandomWords(
        bytes32 keyHash,
        uint256 subId,
        uint16 requestConfirmations,
        uint32 callbackGasLimit,
        uint32 numWords
    ) external returns (uint256 requestId);
}
