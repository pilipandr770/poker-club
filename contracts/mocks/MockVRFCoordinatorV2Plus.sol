// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title MockVRFCoordinatorV2Plus
 * @notice Mock VRF Coordinator for local testing
 * @dev Allows manual fulfillment of randomness requests for testing
 */
contract MockVRFCoordinatorV2Plus {
    
    uint256 private nonce;
    uint256 public lastRequestId;
    
    struct Request {
        address consumer;
        uint256 subId;
        uint32 callbackGasLimit;
        uint32 numWords;
        bool fulfilled;
    }
    
    mapping(uint256 => Request) public requests;
    
    event RandomWordsRequested(
        bytes32 indexed keyHash,
        uint256 requestId,
        uint256 preSeed,
        uint256 subId,
        uint16 minimumRequestConfirmations,
        uint32 callbackGasLimit,
        uint32 numWords,
        address indexed sender
    );
    
    event RandomWordsFulfilled(
        uint256 indexed requestId,
        uint256[] randomWords,
        address indexed consumer
    );
    
    /**
     * @notice Request random words
     * @dev Stores the request and returns a unique request ID
     */
    function requestRandomWords(
        bytes32 keyHash,
        uint256 subId,
        uint16 requestConfirmations,
        uint32 callbackGasLimit,
        uint32 numWords
    ) external returns (uint256 requestId) {
        nonce++;
        requestId = uint256(keccak256(abi.encodePacked(
            block.timestamp,
            msg.sender,
            nonce
        )));
        
        requests[requestId] = Request({
            consumer: msg.sender,
            subId: subId,
            callbackGasLimit: callbackGasLimit,
            numWords: numWords,
            fulfilled: false
        });
        
        lastRequestId = requestId;
        
        emit RandomWordsRequested(
            keyHash,
            requestId,
            nonce,
            subId,
            requestConfirmations,
            callbackGasLimit,
            numWords,
            msg.sender
        );
        
        return requestId;
    }
    
    /**
     * @notice Fulfill random words manually (for testing)
     * @param requestId The request ID to fulfill
     * @param randomWords Array of random words to return
     */
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) external {
        Request storage request = requests[requestId];
        require(request.consumer != address(0), "Request not found");
        require(!request.fulfilled, "Already fulfilled");
        require(randomWords.length == request.numWords, "Wrong number of words");
        
        request.fulfilled = true;
        
        // Call the consumer's rawFulfillRandomWords
        // Note: In testing, we don't limit gas to allow for debugging
        bytes memory data = abi.encodeWithSignature(
            "rawFulfillRandomWords(uint256,uint256[])",
            requestId,
            randomWords
        );
        
        (bool success, bytes memory returnData) = request.consumer.call(data);
        
        if (!success) {
            // Try to extract revert reason
            if (returnData.length > 0) {
                assembly {
                    let returndata_size := mload(returnData)
                    revert(add(32, returnData), returndata_size)
                }
            } else {
                revert("Callback failed");
            }
        }
        
        emit RandomWordsFulfilled(requestId, randomWords, request.consumer);
    }
    
    /**
     * @notice Fulfill with a random seed (generates random words automatically)
     * @param requestId The request ID to fulfill
     * @param seed A seed to generate random words
     */
    function fulfillRandomWordsWithSeed(
        uint256 requestId,
        uint256 seed
    ) external {
        Request storage request = requests[requestId];
        require(request.consumer != address(0), "Request not found");
        require(!request.fulfilled, "Already fulfilled");
        
        uint256[] memory randomWords = new uint256[](request.numWords);
        for (uint32 i = 0; i < request.numWords; i++) {
            randomWords[i] = uint256(keccak256(abi.encodePacked(seed, i)));
        }
        
        request.fulfilled = true;
        
        // Call the consumer's rawFulfillRandomWords
        // Note: In testing, we don't limit gas to allow for debugging
        bytes memory data = abi.encodeWithSignature(
            "rawFulfillRandomWords(uint256,uint256[])",
            requestId,
            randomWords
        );
        
        (bool success, bytes memory returnData) = request.consumer.call(data);
        
        if (!success) {
            if (returnData.length > 0) {
                assembly {
                    let returndata_size := mload(returnData)
                    revert(add(32, returnData), returndata_size)
                }
            } else {
                revert("Callback failed");
            }
        }
        
        emit RandomWordsFulfilled(requestId, randomWords, request.consumer);
    }
    
    /**
     * @notice Get request details
     */
    function getRequest(uint256 requestId) external view returns (
        address consumer,
        uint256 subId,
        uint32 callbackGasLimit,
        uint32 numWords,
        bool fulfilled
    ) {
        Request storage request = requests[requestId];
        return (
            request.consumer,
            request.subId,
            request.callbackGasLimit,
            request.numWords,
            request.fulfilled
        );
    }
    
    /**
     * @notice Check if a request exists
     */
    function requestExists(uint256 requestId) external view returns (bool) {
        return requests[requestId].consumer != address(0);
    }
    
    /**
     * @notice Check if a request is fulfilled
     */
    function isRequestFulfilled(uint256 requestId) external view returns (bool) {
        return requests[requestId].fulfilled;
    }
}
