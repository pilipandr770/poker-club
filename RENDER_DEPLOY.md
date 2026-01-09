# Decentralized Poker - Render Deployment

## Static Site Configuration

This project is configured as a static site for Render.

### Build Settings
- **Build Command:** `npm run build:static`
- **Publish Directory:** `dist`

### Environment Variables
No environment variables required for the static site.
The frontend connects to the blockchain via user's MetaMask wallet.

## Supported Networks

1. **Polygon Amoy Testnet** (Default for testing)
   - Chain ID: 80002
   - RPC: https://rpc-amoy.polygon.technology
   - Explorer: https://amoy.polygonscan.com

2. **Polygon Mainnet** (Production)
   - Chain ID: 137
   - RPC: https://polygon-rpc.com
   - Explorer: https://polygonscan.com

3. **Hardhat Localhost** (Development)
   - Chain ID: 31337
   - RPC: http://127.0.0.1:8545

## Deployment Steps

1. Push code to GitHub
2. Create new Static Site on Render
3. Connect your GitHub repo
4. Render will auto-deploy on push

## Contract Deployment

Before using the DApp on a real network, you need to deploy the smart contract:

```bash
# For Polygon Amoy testnet
npx hardhat run scripts/deploy.js --network polygonAmoy

# For Polygon mainnet
npx hardhat run scripts/deploy.js --network polygon
```

Then update the contract address in `deployments/<network>.json`
