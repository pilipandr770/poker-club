/**
 * Build script for static deployment (Render, Vercel, Netlify, etc.)
 * Creates a dist folder with all necessary files, using CDN for ethers.js
 */

const fs = require('fs');
const path = require('path');

const DIST_DIR = path.join(__dirname, '..', 'dist');
const SRC_DIR = path.join(__dirname, '..');

// Create dist directory
if (!fs.existsSync(DIST_DIR)) {
    fs.mkdirSync(DIST_DIR, { recursive: true });
}

// Create deployments directory in dist
const deploymentsDir = path.join(DIST_DIR, 'deployments');
if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir, { recursive: true });
}

console.log('🔨 Building static site for deployment...\n');

// Read index.html and replace local ethers with CDN
let indexHtml = fs.readFileSync(path.join(SRC_DIR, 'index.html'), 'utf8');

// Replace local ethers.js with CDN version
indexHtml = indexHtml.replace(
    './node_modules/ethers/dist/ethers.umd.min.js',
    'https://cdnjs.cloudflare.com/ajax/libs/ethers/6.9.0/ethers.umd.min.js'
);

// Write modified index.html to dist
fs.writeFileSync(path.join(DIST_DIR, 'index.html'), indexHtml);
console.log('✅ index.html (with CDN ethers.js)');

// Copy rules.html
if (fs.existsSync(path.join(SRC_DIR, 'rules.html'))) {
    fs.copyFileSync(
        path.join(SRC_DIR, 'rules.html'),
        path.join(DIST_DIR, 'rules.html')
    );
    console.log('✅ rules.html');
}

// Create network configurations
const networkConfigs = {
    'polygonAmoy': {
        name: 'Polygon Amoy Testnet',
        chainId: 80002,
        rpcUrl: 'https://rpc-amoy.polygon.technology',
        blockExplorer: 'https://amoy.polygonscan.com',
        nativeCurrency: { name: 'MATIC', symbol: 'MATIC', decimals: 18 },
        contractAddress: null, // Will be set after deployment
        vrfCoordinator: '0x343300b5d84D444B2ADc9116FEF1bED02BE49Cf2' // Chainlink VRF on Amoy
    },
    'polygon': {
        name: 'Polygon Mainnet',
        chainId: 137,
        rpcUrl: 'https://polygon-rpc.com',
        blockExplorer: 'https://polygonscan.com',
        nativeCurrency: { name: 'MATIC', symbol: 'MATIC', decimals: 18 },
        contractAddress: null, // Will be set after deployment
        vrfCoordinator: '0xAE975071Be8F8eE67addBC1A82488F1C24858067' // Chainlink VRF on Polygon
    },
    'localhost': {
        name: 'Hardhat Localhost',
        chainId: 31337,
        rpcUrl: 'http://127.0.0.1:8545',
        blockExplorer: null,
        nativeCurrency: { name: 'ETH', symbol: 'ETH', decimals: 18 },
        contractAddress: null,
        vrfCoordinator: null
    }
};

// Try to read existing deployment files and merge contract addresses
const srcDeployments = path.join(SRC_DIR, 'deployments');
if (fs.existsSync(srcDeployments)) {
    const files = fs.readdirSync(srcDeployments);
    files.forEach(file => {
        if (file.endsWith('.json')) {
            const networkName = file.replace('.json', '');
            try {
                const deployment = JSON.parse(fs.readFileSync(path.join(srcDeployments, file), 'utf8'));
                if (networkConfigs[networkName]) {
                    networkConfigs[networkName].contractAddress = deployment.poker || deployment.contractAddress;
                    networkConfigs[networkName].mockVRF = deployment.mockVRF;
                }
                // Copy deployment file to dist
                fs.copyFileSync(
                    path.join(srcDeployments, file),
                    path.join(deploymentsDir, file)
                );
                console.log(`✅ deployments/${file}`);
            } catch (e) {
                console.log(`⚠️ Could not parse ${file}`);
            }
        }
    });
}

// Write network config
fs.writeFileSync(
    path.join(DIST_DIR, 'networks.json'),
    JSON.stringify(networkConfigs, null, 2)
);
console.log('✅ networks.json');

// Create a simple 404.html for SPA routing
const html404 = `<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta http-equiv="refresh" content="0;url=/">
    <title>Redirecting...</title>
</head>
<body>
    <p>Redirecting to <a href="/">home page</a>...</p>
</body>
</html>`;

fs.writeFileSync(path.join(DIST_DIR, '404.html'), html404);
console.log('✅ 404.html');

// Create _redirects for Netlify/Render
fs.writeFileSync(path.join(DIST_DIR, '_redirects'), '/* /index.html 200');
console.log('✅ _redirects');

console.log('\n🎉 Build complete! Files are in ./dist/');
console.log('\nTo deploy on Render:');
console.log('1. Push to GitHub');
console.log('2. Create new Static Site on Render');
console.log('3. Set Build Command: npm run build:static');
console.log('4. Set Publish Directory: dist');
