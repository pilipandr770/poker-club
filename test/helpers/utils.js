/**
 * Test utility functions for DecentralizedPokerVRF
 */

const { ethers } = require("hardhat");

// Card encoding/decoding utilities
const SUITS = ["Hearts", "Diamonds", "Clubs", "Spades"];
const SUIT_SYMBOLS = ["♥", "♦", "♣", "♠"];
const RANKS = ["2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K", "A"];

/**
 * Decode a card number (0-51) to rank and suit
 */
function decodeCard(cardNumber) {
  const rank = cardNumber % 13;
  const suit = Math.floor(cardNumber / 13);
  return { rank, suit };
}

/**
 * Get card name from card number
 */
function getCardName(cardNumber) {
  const { rank, suit } = decodeCard(cardNumber);
  return `${RANKS[rank]}${SUIT_SYMBOLS[suit]}`;
}

/**
 * Get full card description
 */
function getCardDescription(cardNumber) {
  const { rank, suit } = decodeCard(cardNumber);
  return `${RANKS[rank]} of ${SUITS[suit]}`;
}

/**
 * Encode rank and suit to card number
 */
function encodeCard(rank, suit) {
  return rank + suit * 13;
}

/**
 * Get card numbers for a specific hand (for testing)
 */
function getHandCards(hand) {
  const hands = {
    // Royal Flush (A♠ K♠ Q♠ J♠ T♠)
    royalFlush: [51, 50, 49, 48, 47],
    
    // Straight Flush (9♠ 8♠ 7♠ 6♠ 5♠)
    straightFlush: [46, 45, 44, 43, 42],
    
    // Four of a Kind (A♥ A♦ A♣ A♠ K♥)
    fourOfAKind: [12, 25, 38, 51, 11],
    
    // Full House (K♥ K♦ K♣ Q♥ Q♦)
    fullHouse: [11, 24, 37, 10, 23],
    
    // Flush (A♠ Q♠ T♠ 7♠ 5♠)
    flush: [51, 49, 47, 44, 42],
    
    // Straight (T♥ 9♦ 8♣ 7♠ 6♥)
    straight: [8, 20, 32, 44, 4],
    
    // Three of a Kind (J♥ J♦ J♣ A♠ K♥)
    threeOfAKind: [9, 22, 35, 51, 11],
    
    // Two Pair (A♥ A♦ K♣ K♠ Q♥)
    twoPair: [12, 25, 37, 50, 10],
    
    // One Pair (A♥ A♦ K♣ Q♠ J♥)
    onePair: [12, 25, 37, 49, 9],
    
    // High Card (A♥ K♦ Q♣ J♠ 9♥)
    highCard: [12, 24, 36, 48, 7]
  };
  
  return hands[hand] || [];
}

/**
 * Hand rank names
 */
const HAND_RANKS = [
  "High Card",
  "One Pair",
  "Two Pair",
  "Three of a Kind",
  "Straight",
  "Flush",
  "Full House",
  "Four of a Kind",
  "Straight Flush",
  "Royal Flush"
];

/**
 * Get hand rank name from enum value
 */
function getHandRankName(rankValue) {
  return HAND_RANKS[rankValue] || "Unknown";
}

/**
 * Player action names
 */
const PLAYER_ACTIONS = [
  "None",
  "Fold",
  "Check",
  "Call",
  "Raise",
  "AllIn"
];

/**
 * Get action name from enum value
 */
function getActionName(actionValue) {
  return PLAYER_ACTIONS[actionValue] || "Unknown";
}

/**
 * Game phase names
 */
const GAME_PHASES = [
  "WaitingForPlayers",
  "RequestingVRF",
  "PreFlop",
  "Flop",
  "Turn",
  "River",
  "Showdown",
  "Finished"
];

/**
 * Get phase name from enum value
 */
function getPhaseName(phaseValue) {
  return GAME_PHASES[phaseValue] || "Unknown";
}

/**
 * Wait for a specific game phase
 */
async function waitForPhase(poker, gameId, targetPhase, maxWait = 10000) {
  const startTime = Date.now();
  while (Date.now() - startTime < maxWait) {
    const gameInfo = await poker.getGameInfo(gameId);
    if (gameInfo.phase >= targetPhase) {
      return gameInfo;
    }
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  throw new Error(`Timeout waiting for phase ${getPhaseName(targetPhase)}`);
}

/**
 * Format ETH value for display
 */
function formatEth(wei) {
  return ethers.formatEther(wei) + " ETH";
}

/**
 * Parse ETH string to wei
 */
function parseEth(eth) {
  return ethers.parseEther(eth.toString());
}

/**
 * Log game state (for debugging)
 */
async function logGameState(poker, gameId) {
  const gameInfo = await poker.getGameInfo(gameId);
  
  console.log("\n=== Game State ===");
  console.log(`Game ID: ${gameId}`);
  console.log(`Phase: ${getPhaseName(gameInfo.phase)}`);
  console.log(`Buy-in: ${formatEth(gameInfo.buyIn)}`);
  console.log(`Pot: ${formatEth(gameInfo.pot)}`);
  console.log(`Current Bet: ${formatEth(gameInfo.currentBet)}`);
  console.log(`Players: ${gameInfo.playerCount} (${gameInfo.activePlayers} active)`);
  console.log(`Current Player: ${gameInfo.currentPlayer}`);
  console.log(`Deck Generated: ${gameInfo.deckGenerated}`);
  
  // Log players
  console.log("\n--- Players ---");
  for (let i = 0; i < gameInfo.playerCount; i++) {
    const playerInfo = await poker.getPlayerInfo(gameId, i);
    console.log(`Player ${i}: ${playerInfo.addr.slice(0, 10)}...`);
    console.log(`  Chips: ${formatEth(playerInfo.chips)}`);
    console.log(`  Current Bet: ${formatEth(playerInfo.currentBet)}`);
    console.log(`  Folded: ${playerInfo.folded}`);
  }
  
  // Log community cards if revealed
  if (gameInfo.phase >= 3) {
    const [communityCards, revealed] = await poker.getCommunityCards(gameId);
    console.log("\n--- Community Cards ---");
    for (let i = 0; i < revealed; i++) {
      console.log(`  ${getCardName(communityCards[i])}`);
    }
  }
  
  console.log("==================\n");
}

module.exports = {
  SUITS,
  SUIT_SYMBOLS,
  RANKS,
  HAND_RANKS,
  PLAYER_ACTIONS,
  GAME_PHASES,
  decodeCard,
  getCardName,
  getCardDescription,
  encodeCard,
  getHandCards,
  getHandRankName,
  getActionName,
  getPhaseName,
  waitForPhase,
  formatEth,
  parseEth,
  logGameState
};
