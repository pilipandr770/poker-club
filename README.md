# 🎰 Decentralized Poker VRF

A decentralized Texas Hold'em poker game built on Ethereum using Chainlink VRF for provably fair card shuffling.

## Features

- 🃏 **Provably Fair** - Uses Chainlink VRF for verifiable random card generation
- 💰 **Non-custodial** - Players control their own funds
- 🔒 **Secure** - Card commitments prevent cheating
- ⚡ **Gas Efficient** - Optimized for on-chain execution
- 🎮 **Full Game Logic** - Complete Texas Hold'em implementation

## Quick Start

```bash
# Install dependencies
npm install

# Run tests
npm test

# Start local node
npm run node

# Deploy locally (in another terminal)
npm run deploy:local
```

## Game Rules

- 2-6 players per table
- Texas Hold'em rules
- 10% rake on pots
- 5-minute action timeout
- Heads-up and multiplayer support

## Documentation

See [PROJECT_SETUP.md](./PROJECT_SETUP.md) for detailed documentation.

## License

MIT
