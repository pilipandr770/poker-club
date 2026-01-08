const hre = require("hardhat");
const ethers = hre.ethers;

async function main() {
    // Load deployment
    const fs = require('fs');
    const deploymentPath = './deployments/localhost.json';
    const deployment = JSON.parse(fs.readFileSync(deploymentPath, 'utf8'));
    
    const contractAddress = deployment.contracts.DecentralizedPokerVRF.address;
    console.log('Contract address:', contractAddress);
    
    // Get contract
    const DecentralizedPokerVRF = await ethers.getContractFactory("DecentralizedPokerVRF");
    const contract = DecentralizedPokerVRF.attach(contractAddress);
    
    // Get signer
    const [signer] = await ethers.getSigners();
    console.log('Signer address:', signer.address);
    
    // Create game
    const buyInWei = ethers.parseEther("0.12");
    const smallBlindWei = ethers.parseEther("0.003");
    const bigBlindWei = ethers.parseEther("0.006");
    
    console.log('Creating game with:');
    console.log('  Buy-in:', ethers.formatEther(buyInWei), 'ETH');
    console.log('  Small blind:', ethers.formatEther(smallBlindWei), 'ETH');
    console.log('  Big blind:', ethers.formatEther(bigBlindWei), 'ETH');
    
    try {
        const tx = await contract.createGame(
            buyInWei,
            smallBlindWei,
            bigBlindWei,
            { value: buyInWei }
        );
        
        console.log('Transaction sent:', tx.hash);
        const receipt = await tx.wait();
        console.log('Transaction confirmed in block:', receipt.blockNumber);
        console.log('Gas used:', receipt.gasUsed.toString());
        
        // Find GameCreated event
        const gameCreatedEvent = receipt.logs.find(
            log => log.topics[0] === ethers.id('GameCreated(uint256,address,uint256,uint256,uint256)')
        );
        
        if (gameCreatedEvent) {
            const decoded = contract.interface.parseLog(gameCreatedEvent);
            console.log('Game created with ID:', decoded.args.gameId.toString());
        }
        
    } catch (error) {
        console.error('Error creating game:');
        console.error('Message:', error.message);
        if (error.data) {
            console.error('Data:', error.data);
        }
        if (error.reason) {
            console.error('Reason:', error.reason);
        }
        throw error;
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
