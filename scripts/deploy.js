const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

function isHexBytes32(value) {
  return typeof value === "string" && /^0x[0-9a-fA-F]{64}$/.test(value);
}

function parseSubscriptionId(value) {
  if (value === undefined || value === null) return null;
  const str = String(value).trim();
  if (str === "" || str === "0") return null;
  if (!/^\d+$/.test(str)) return null;
  return BigInt(str);
}

// VRF Configuration per network
const VRF_CONFIG = {
  // Ethereum Sepolia Testnet
  sepolia: {
    coordinator: "0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625",
    keyHash: "0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c",
    subscriptionId: process.env.VRF_SUBSCRIPTION_ID || "0"
  },
  // Polygon Mainnet
  polygon: {
    coordinator: "0xAE975071Be8F8eE67addBC1A82488F1C24858067",
    keyHash: "0x6e75b569a01ef56d18cab6a8e71e6600d6ce853834d4a5748b720d06f878b3a4",
    subscriptionId: process.env.VRF_SUBSCRIPTION_ID || "0"
  },
  // Polygon Mumbai Testnet (Amoy)
  polygonMumbai: {
    coordinator: "0x343300b5d84D444B2ADc9116FEF1bED02BE49Cf2",
    keyHash: "0x816bedba8a50b294e5cbd47842baf240c2385f2eaf719edbd4f250a137a8c899beda",
    subscriptionId: process.env.VRF_SUBSCRIPTION_ID || "0"
  },
  // Local/Hardhat - uses mock
  hardhat: {
    coordinator: "", // Will be deployed as mock
    keyHash: "0x0000000000000000000000000000000000000000000000000000000000000001",
    subscriptionId: "1"
  },
  localhost: {
    coordinator: "", // Will be deployed as mock
    keyHash: "0x0000000000000000000000000000000000000000000000000000000000000001",
    subscriptionId: "1"
  }
};

async function main() {
  const network = hre.network.name;
  console.log(`\n🎰 Deploying DecentralizedPokerVRF to ${network}...\n`);

  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  console.log("Account balance:", hre.ethers.formatEther(await hre.ethers.provider.getBalance(deployer.address)), "ETH\n");

  let vrfCoordinatorAddress;
  let keyHash;
  let subscriptionId;
  let mockVRFCoordinator;

  // Check if local network
  const isLocalNetwork = network === "hardhat" || network === "localhost";

  if (isLocalNetwork) {
    // Deploy Mock VRF Coordinator for local testing
    console.log("📦 Deploying Mock VRF Coordinator...");
    const MockVRFCoordinator = await hre.ethers.getContractFactory("MockVRFCoordinatorV2Plus");
    mockVRFCoordinator = await MockVRFCoordinator.deploy();
    await mockVRFCoordinator.waitForDeployment();
    vrfCoordinatorAddress = await mockVRFCoordinator.getAddress();
    console.log("✅ Mock VRF Coordinator deployed to:", vrfCoordinatorAddress);

    keyHash = VRF_CONFIG.hardhat.keyHash;
    subscriptionId = VRF_CONFIG.hardhat.subscriptionId;
  } else {
    // Use real VRF Coordinator
    const config = VRF_CONFIG[network];
    if (!config) {
      throw new Error(`Network ${network} not configured. Add VRF config for this network.`);
    }

    vrfCoordinatorAddress = config.coordinator;
    keyHash = config.keyHash;
    subscriptionId = parseSubscriptionId(config.subscriptionId);

    if (!isHexBytes32(keyHash)) {
      throw new Error(
        `Invalid VRF keyHash for ${network}. Expected bytes32 (0x + 64 hex chars). ` +
          `Open https://vrf.chain.link/ for the target network and copy the "Key Hash".`
      );
    }

    if (!subscriptionId) {
      throw new Error(
        `VRF_SUBSCRIPTION_ID is missing/invalid for ${network}. ` +
          `It must be a numeric subscription id (e.g. 1234), not an address.`
      );
    }

    console.log("VRF Coordinator:", vrfCoordinatorAddress);
    console.log("Key Hash:", keyHash);
    console.log("Subscription ID:", subscriptionId.toString());
  }

  // Deploy DecentralizedPokerVRF
  console.log("\n📦 Deploying DecentralizedPokerVRF...");
  const DecentralizedPokerVRF = await hre.ethers.getContractFactory("DecentralizedPokerVRF");
  const poker = await DecentralizedPokerVRF.deploy(
    vrfCoordinatorAddress,
    keyHash,
    subscriptionId
  );
  await poker.waitForDeployment();
  const pokerAddress = await poker.getAddress();
  console.log("✅ DecentralizedPokerVRF deployed to:", pokerAddress);

  // Save deployment info
  const deploymentInfo = {
    network: network,
    deployedAt: new Date().toISOString(),
    contracts: {
      DecentralizedPokerVRF: {
        address: pokerAddress,
        vrfCoordinator: vrfCoordinatorAddress,
        keyHash: keyHash,
        subscriptionId: subscriptionId
      }
    }
  };

  if (isLocalNetwork && mockVRFCoordinator) {
    deploymentInfo.contracts.MockVRFCoordinatorV2Plus = {
      address: vrfCoordinatorAddress
    };
  }

  // Save to deployments folder
  const deploymentsDir = path.join(__dirname, "..", "deployments");
  if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir, { recursive: true });
  }

  const deploymentPath = path.join(deploymentsDir, `${network}.json`);
  fs.writeFileSync(deploymentPath, JSON.stringify(deploymentInfo, null, 2));
  console.log(`\n📄 Deployment info saved to: ${deploymentPath}`);

  // Post-deployment instructions
  console.log("\n" + "=".repeat(60));
  console.log("🎉 DEPLOYMENT COMPLETE!");
  console.log("=".repeat(60));

  if (isLocalNetwork) {
    console.log("\n📋 LOCAL TESTING INSTRUCTIONS:");
    console.log("1. The Mock VRF Coordinator is deployed and ready");
    console.log("2. Run tests with: npx hardhat test");
    console.log("3. For manual testing, use the mock to fulfill VRF requests");
  } else {
    console.log("\n📋 NEXT STEPS:");
    console.log("1. Add the contract as a VRF consumer:");
    console.log(`   - Go to https://vrf.chain.link/`);
    console.log(`   - Select your subscription (ID: ${subscriptionId})`);
    console.log(`   - Add consumer: ${pokerAddress}`);
    console.log("\n2. Fund your subscription with LINK tokens if needed");
    console.log("\n3. Verify the contract on the block explorer:");
    console.log(`   npx hardhat verify --network ${network} ${pokerAddress} ${vrfCoordinatorAddress} ${keyHash} ${subscriptionId}`);
  }

  console.log("\n" + "=".repeat(60) + "\n");

  return {
    poker: pokerAddress,
    vrfCoordinator: vrfCoordinatorAddress,
    mockVRFCoordinator: mockVRFCoordinator
  };
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
