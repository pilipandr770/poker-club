# 🎰 Decentralized Poker VRF - Project Setup

A decentralized Texas Hold'em poker game built on Ethereum with Chainlink VRF for provably fair card shuffling.

## 📁 Project Structure

```
decentralized-poker/
├── contracts/
│   ├── DecentralizedPokerVRF.sol      # Main poker contract
│   ├── interfaces/
│   │   ├── IOraoVRF.sol               # Orao VRF interface
│   │   └── IVRFCoordinatorV2Plus.sol  # Chainlink VRF interface
│   └── mocks/
│       └── MockVRFCoordinatorV2Plus.sol # Mock for local testing
├── scripts/
│   └── deploy.js                       # Deployment script
├── test/
│   └── DecentralizedPokerVRF.test.js   # Comprehensive tests
├── deployments/                        # Deployment artifacts (auto-generated)
├── hardhat.config.js                   # Hardhat configuration
├── package.json                        # Dependencies
├── .env.example                        # Environment variables template
└── PROJECT_SETUP.md                    # This file
```

## 🚀 Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Set Up Environment Variables

```bash
cp .env.example .env
# Edit .env with your values
```

### 3. Compile Contracts

```bash
npm run compile
```

### 4. Run Tests

```bash
npm test
```

### 5. Run Local Node

```bash
npm run node
```

### 6. Deploy Locally

```bash
npm run deploy:local
```

## 🔧 Configuration

### Environment Variables

| Variable | Description |
|----------|-------------|
| `PRIVATE_KEY` | Your wallet private key (without 0x) |
| `SEPOLIA_RPC_URL` | Alchemy/Infura RPC URL for Sepolia |
| `POLYGON_RPC_URL` | Alchemy/Infura RPC URL for Polygon |
| `MUMBAI_RPC_URL` | Alchemy/Infura RPC URL for Mumbai |
| `ETHERSCAN_API_KEY` | Etherscan API key for verification |
| `POLYGONSCAN_API_KEY` | Polygonscan API key for verification |
| `VRF_SUBSCRIPTION_ID` | Chainlink VRF subscription ID |

### Supported Networks

| Network | Chain ID | VRF Coordinator |
|---------|----------|-----------------|
| Sepolia | 11155111 | `0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625` |
| Polygon | 137 | `0xAE975071Be8F8eE67addBC1A82488F1C24858067` |
| Mumbai | 80001 | `0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed` |

## 📋 NPM Scripts

| Script | Description |
|--------|-------------|
| `npm run compile` | Compile smart contracts |
| `npm test` | Run all tests |
| `npm run test:gas` | Run tests with gas report |
| `npm run node` | Start local Hardhat node |
| `npm run deploy:local` | Deploy to localhost |
| `npm run deploy:sepolia` | Deploy to Sepolia testnet |
| `npm run deploy:polygon` | Deploy to Polygon mainnet |
| `npm run deploy:mumbai` | Deploy to Mumbai testnet |
| `npm run clean` | Clean build artifacts |
| `npm run coverage` | Run test coverage |

## 🎮 Game Flow

```
1. createGame()     → Creator sets buy-in, blinds
2. joinGame()       → Other players join
3. startGame()      → Requests VRF randomness
4. VRF Callback     → Deck generated, cards dealt
5. playerAction()   → Betting rounds (PreFlop → Flop → Turn → River)
6. Showdown         → Winner determined, pot distributed
```

### Player Actions

| Action | Enum Value | Description |
|--------|------------|-------------|
| `Fold` | 1 | Give up hand |
| `Check` | 2 | Pass (if no bet) |
| `Call` | 3 | Match current bet |
| `Raise` | 4 | Increase bet |
| `AllIn` | 5 | Bet all chips |

### Game Phases

| Phase | Enum Value | Description |
|-------|------------|-------------|
| `WaitingForPlayers` | 0 | Lobby |
| `RequestingVRF` | 1 | Waiting for randomness |
| `PreFlop` | 2 | First betting round |
| `Flop` | 3 | 3 community cards |
| `Turn` | 4 | 4th community card |
| `River` | 5 | 5th community card |
| `Showdown` | 6 | Reveal cards |
| `Finished` | 7 | Game ended |

## 🔐 Chainlink VRF Setup

### 1. Create Subscription

1. Go to [vrf.chain.link](https://vrf.chain.link/)
2. Connect wallet
3. Create new subscription
4. Fund with LINK tokens
5. Copy subscription ID to `.env`

### 2. Deploy Contract

```bash
npm run deploy:sepolia
```

### 3. Add Consumer

1. Go to your subscription on vrf.chain.link
2. Add the deployed contract address as consumer

## 📊 Gas Estimates

| Action | Estimated Gas |
|--------|---------------|
| `createGame` | ~150,000 |
| `joinGame` | ~100,000 |
| `startGame` | ~200,000 |
| VRF callback | ~400,000 |
| `fold/check` | ~50,000 |
| `call` | ~60,000 |
| `raise` | ~70,000 |
| showdown | ~200,000 |

## 🃏 Card Encoding

Cards are encoded as numbers 0-51:

```
Card Number = Rank + (Suit * 13)

Ranks: 0=2, 1=3, 2=4, ... 8=T, 9=J, 10=Q, 11=K, 12=A
Suits: 0=Hearts, 1=Diamonds, 2=Clubs, 3=Spades

Examples:
  0 = 2♥  (2 of Hearts)
 12 = A♥  (Ace of Hearts)
 13 = 2♦  (2 of Diamonds)
 51 = A♠  (Ace of Spades)
```

Use `decodeCard(uint8)` to get rank and suit:

```javascript
const [rank, suit] = await poker.decodeCard(51);
// rank = 12 (Ace), suit = 3 (Spades)
```

## 🏆 Hand Rankings

| Rank | Name | Value |
|------|------|-------|
| 0 | High Card | Lowest |
| 1 | One Pair | |
| 2 | Two Pair | |
| 3 | Three of a Kind | |
| 4 | Straight | |
| 5 | Flush | |
| 6 | Full House | |
| 7 | Four of a Kind | |
| 8 | Straight Flush | |
| 9 | Royal Flush | Highest |

## ⚠️ Known Limitations

1. **Side Pots** - Not yet implemented for all-in scenarios with different stack sizes
2. **Rake Cap** - No maximum commission per hand
3. **Tournament Mode** - Only cash games supported
4. **Card Privacy** - Cards are stored on-chain (visible in storage)
5. **Rebuy** - Cannot add chips during a session

## 🧪 Testing

Run the full test suite:

```bash
npm test
```

Run with gas reporting:

```bash
npm run test:gas
```

Run specific test:

```bash
npx hardhat test test/DecentralizedPokerVRF.test.js --grep "should create a game"
```

## 📝 Contract Verification

After deploying to a public network:

```bash
npx hardhat verify --network sepolia <CONTRACT_ADDRESS> <VRF_COORDINATOR> <KEY_HASH> <SUBSCRIPTION_ID>
```

## 🔗 Useful Links

- [Chainlink VRF Documentation](https://docs.chain.link/vrf)
- [Hardhat Documentation](https://hardhat.org/docs)
- [Poker Hand Rankings](https://en.wikipedia.org/wiki/List_of_poker_hands)

## 📄 License

MIT
