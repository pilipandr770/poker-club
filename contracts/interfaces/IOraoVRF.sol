// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IOraoVRF
 * @dev Interface for Orao VRF (adapted for EVM)
 * @notice Orao VRF provides verifiable random numbers
 * Documentation: https://docs.orao.network/
 */
interface IOraoVRF {
    /**
     * @notice Request a random number
     * @param seed A seed value for the random number generation
     * @return requestId The ID of the randomness request
     */
    function request(bytes32 seed) external returns (bytes32 requestId);
    
    /**
     * @notice Get the randomness for a fulfilled request
     * @param requestId The ID of the request
     * @return randomness The random value (bytes32(0) if not yet fulfilled)
     */
    function getRandomness(bytes32 requestId) external view returns (bytes32 randomness);
}
