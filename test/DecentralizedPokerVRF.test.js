const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture, time } = require("@nomicfoundation/hardhat-network-helpers");

describe("DecentralizedPokerVRF", function () {
  // Game constants
  const BUY_IN = ethers.parseEther("1");
  const SMALL_BLIND = ethers.parseEther("0.01");
  const BIG_BLIND = ethers.parseEther("0.02");
  const KEY_HASH = "0x0000000000000000000000000000000000000000000000000000000000000001";
  const SUBSCRIPTION_ID = 1;

  // Player Action enum
  const PlayerAction = {
    None: 0,
    Fold: 1,
    Check: 2,
    Call: 3,
    Raise: 4,
    AllIn: 5
  };

  // Game Phase enum
  const GamePhase = {
    WaitingForPlayers: 0,
    RequestingVRF: 1,
    PreFlop: 2,
    Flop: 3,
    Turn: 4,
    River: 5,
    Showdown: 6,
    Finished: 7
  };

  async function deployFixture() {
    const [owner, player1, player2, player3, player4] = await ethers.getSigners();

    // Deploy Mock VRF Coordinator
    const MockVRF = await ethers.getContractFactory("MockVRFCoordinatorV2Plus");
    const mockVRF = await MockVRF.deploy();
    await mockVRF.waitForDeployment();

    // Deploy Poker Contract
    const Poker = await ethers.getContractFactory("DecentralizedPokerVRF");
    const poker = await Poker.deploy(
      await mockVRF.getAddress(),
      KEY_HASH,
      SUBSCRIPTION_ID
    );
    await poker.waitForDeployment();

    return { poker, mockVRF, owner, player1, player2, player3, player4 };
  }

  async function createGameFixture() {
    const { poker, mockVRF, owner, player1, player2, player3, player4 } = await loadFixture(deployFixture);

    // Player1 creates game
    await poker.connect(player1).createGame(BUY_IN, SMALL_BLIND, BIG_BLIND, { value: BUY_IN });

    return { poker, mockVRF, owner, player1, player2, player3, player4 };
  }

  async function twoPlayerGameFixture() {
    const { poker, mockVRF, owner, player1, player2, player3, player4 } = await loadFixture(createGameFixture);

    // Player2 joins
    await poker.connect(player2).joinGame(0, { value: BUY_IN });

    return { poker, mockVRF, owner, player1, player2, player3, player4 };
  }

  async function startedGameFixture() {
    const { poker, mockVRF, owner, player1, player2, player3, player4 } = await loadFixture(twoPlayerGameFixture);

    // Start game
    await poker.connect(player1).startGame(0);

    // Get request ID and fulfill VRF
    const requestId = await mockVRF.lastRequestId();
    const randomSeed = 12345678901234567890n;
    await mockVRF.fulfillRandomWordsWithSeed(requestId, randomSeed);

    return { poker, mockVRF, owner, player1, player2, player3, player4, randomSeed };
  }

  describe("Deployment", function () {
    it("Should deploy with correct VRF coordinator", async function () {
      const { poker, mockVRF } = await loadFixture(deployFixture);
      expect(await poker.vrfCoordinator()).to.equal(await mockVRF.getAddress());
    });

    it("Should set correct owner", async function () {
      const { poker, owner } = await loadFixture(deployFixture);
      expect(await poker.owner()).to.equal(owner.address);
    });

    it("Should have correct constants", async function () {
      const { poker } = await loadFixture(deployFixture);
      expect(await poker.COMMISSION_PERCENT()).to.equal(10);
      expect(await poker.MIN_PLAYERS()).to.equal(2);
      expect(await poker.MAX_PLAYERS()).to.equal(6);
    });
  });

  describe("Game Creation", function () {
    it("Should create a game with correct parameters", async function () {
      const { poker, player1 } = await loadFixture(deployFixture);

      await expect(
        poker.connect(player1).createGame(BUY_IN, SMALL_BLIND, BIG_BLIND, { value: BUY_IN })
      ).to.emit(poker, "GameCreated")
        .withArgs(0, BUY_IN, SMALL_BLIND, BIG_BLIND);

      const gameInfo = await poker.getGameInfo(0);
      expect(gameInfo.buyIn).to.equal(BUY_IN);
      expect(gameInfo.phase).to.equal(GamePhase.WaitingForPlayers);
      expect(gameInfo.playerCount).to.equal(1);
    });

    it("Should fail if buy-in doesn't match sent value", async function () {
      const { poker, player1 } = await loadFixture(deployFixture);

      await expect(
        poker.connect(player1).createGame(BUY_IN, SMALL_BLIND, BIG_BLIND, { value: ethers.parseEther("0.5") })
      ).to.be.revertedWith("Must send exact buy-in");
    });

    it("Should fail if big blind != 2x small blind", async function () {
      const { poker, player1 } = await loadFixture(deployFixture);

      await expect(
        poker.connect(player1).createGame(BUY_IN, SMALL_BLIND, SMALL_BLIND, { value: BUY_IN })
      ).to.be.revertedWith("Big blind must be 2x small blind");
    });

    it("Should fail if buy-in is less than 20 big blinds", async function () {
      const { poker, player1 } = await loadFixture(deployFixture);
      const lowBuyIn = BIG_BLIND * 10n;

      await expect(
        poker.connect(player1).createGame(lowBuyIn, SMALL_BLIND, BIG_BLIND, { value: lowBuyIn })
      ).to.be.revertedWith("Buy-in must be at least 20 big blinds");
    });
  });

  describe("Joining Games", function () {
    it("Should allow player to join game", async function () {
      const { poker, player1, player2 } = await loadFixture(createGameFixture);

      await expect(
        poker.connect(player2).joinGame(0, { value: BUY_IN })
      ).to.emit(poker, "PlayerJoined")
        .withArgs(0, player2.address, 1);

      const gameInfo = await poker.getGameInfo(0);
      expect(gameInfo.playerCount).to.equal(2);
    });

    it("Should fail if game is full", async function () {
      const { poker, player1, player2, player3, player4, owner } = await loadFixture(createGameFixture);

      // Add 5 more players (total 6)
      await poker.connect(player2).joinGame(0, { value: BUY_IN });
      await poker.connect(player3).joinGame(0, { value: BUY_IN });
      await poker.connect(player4).joinGame(0, { value: BUY_IN });
      
      const [, , , , , player5, player6, player7] = await ethers.getSigners();
      await poker.connect(player5).joinGame(0, { value: BUY_IN });
      await poker.connect(player6).joinGame(0, { value: BUY_IN });

      // 7th player should fail
      await expect(
        poker.connect(player7).joinGame(0, { value: BUY_IN })
      ).to.be.revertedWith("Game is full");
    });

    it("Should fail if already in game", async function () {
      const { poker, player1 } = await loadFixture(createGameFixture);

      await expect(
        poker.connect(player1).joinGame(0, { value: BUY_IN })
      ).to.be.revertedWith("Already in game");
    });

    it("Should fail if wrong buy-in amount", async function () {
      const { poker, player2 } = await loadFixture(createGameFixture);

      await expect(
        poker.connect(player2).joinGame(0, { value: ethers.parseEther("0.5") })
      ).to.be.revertedWith("Must send exact buy-in");
    });
  });

  describe("Starting Games", function () {
    it("Should start game and request VRF", async function () {
      const { poker, mockVRF, player1 } = await loadFixture(twoPlayerGameFixture);

      await expect(poker.connect(player1).startGame(0))
        .to.emit(poker, "PhaseChanged")
        .withArgs(0, GamePhase.RequestingVRF);

      const gameInfo = await poker.getGameInfo(0);
      expect(gameInfo.phase).to.equal(GamePhase.RequestingVRF);
    });

    it("Should fail if not enough players", async function () {
      const { poker, player1 } = await loadFixture(createGameFixture);

      await expect(
        poker.connect(player1).startGame(0)
      ).to.be.revertedWith("Not enough players");
    });

    it("Should fail if not a player", async function () {
      const { poker, owner } = await loadFixture(twoPlayerGameFixture);

      await expect(
        poker.connect(owner).startGame(0)
      ).to.be.revertedWith("Not in game");
    });
  });

  describe("VRF Fulfillment", function () {
    it("Should deal cards after VRF fulfillment", async function () {
      const { poker, mockVRF, player1, player2 } = await loadFixture(twoPlayerGameFixture);

      await poker.connect(player1).startGame(0);
      const requestId = await mockVRF.lastRequestId();

      await expect(mockVRF.fulfillRandomWordsWithSeed(requestId, 12345))
        .to.emit(poker, "DeckGenerated")
        .withArgs(0);

      const gameInfo = await poker.getGameInfo(0);
      expect(gameInfo.phase).to.equal(GamePhase.PreFlop);
      expect(gameInfo.deckGenerated).to.be.true;
    });

    it("Should allow players to see their cards after dealing", async function () {
      const { poker, player1, player2 } = await loadFixture(startedGameFixture);

      const cards1 = await poker.connect(player1).getMyCards(0);
      const cards2 = await poker.connect(player2).getMyCards(0);

      // Cards should be valid (0-51)
      expect(cards1[0]).to.be.lt(52);
      expect(cards1[1]).to.be.lt(52);
      expect(cards2[0]).to.be.lt(52);
      expect(cards2[1]).to.be.lt(52);

      // All cards should be different
      expect(cards1[0]).to.not.equal(cards1[1]);
      expect(cards1[0]).to.not.equal(cards2[0]);
      expect(cards1[0]).to.not.equal(cards2[1]);
    });
  });

  describe("Betting Actions", function () {
    it("Should post blinds correctly", async function () {
      const { poker, player1, player2 } = await loadFixture(startedGameFixture);

      const gameInfo = await poker.getGameInfo(0);
      expect(gameInfo.pot).to.equal(SMALL_BLIND + BIG_BLIND);
      expect(gameInfo.currentBet).to.equal(BIG_BLIND);
    });

    it("Should allow fold", async function () {
      const { poker, player1, player2 } = await loadFixture(startedGameFixture);

      // In heads-up, player at position 0 (SB) acts first preflop
      const gameInfo = await poker.getGameInfo(0);
      const currentPlayerInfo = await poker.getPlayerInfo(0, gameInfo.currentPlayer);

      let foldingPlayer;
      if (currentPlayerInfo.addr === player1.address) {
        foldingPlayer = player1;
      } else {
        foldingPlayer = player2;
      }

      await expect(poker.connect(foldingPlayer).playerAction(0, PlayerAction.Fold, 0))
        .to.emit(poker, "PlayerActed");

      // Game should finish with single winner
      const finalGameInfo = await poker.getGameInfo(0);
      expect(finalGameInfo.phase).to.equal(GamePhase.Finished);
    });

    it("Should allow call", async function () {
      const { poker, player1, player2 } = await loadFixture(startedGameFixture);

      const gameInfo = await poker.getGameInfo(0);
      const currentPlayerInfo = await poker.getPlayerInfo(0, gameInfo.currentPlayer);

      let callingPlayer;
      if (currentPlayerInfo.addr === player1.address) {
        callingPlayer = player1;
      } else {
        callingPlayer = player2;
      }

      await expect(poker.connect(callingPlayer).playerAction(0, PlayerAction.Call, 0))
        .to.emit(poker, "PlayerActed");
    });

    it("Should allow raise", async function () {
      const { poker, player1, player2 } = await loadFixture(startedGameFixture);

      const gameInfo = await poker.getGameInfo(0);
      const currentPlayerInfo = await poker.getPlayerInfo(0, gameInfo.currentPlayer);

      let raisingPlayer;
      if (currentPlayerInfo.addr === player1.address) {
        raisingPlayer = player1;
      } else {
        raisingPlayer = player2;
      }

      const raiseAmount = BIG_BLIND;
      await expect(poker.connect(raisingPlayer).playerAction(0, PlayerAction.Raise, raiseAmount))
        .to.emit(poker, "PlayerActed");

      const newGameInfo = await poker.getGameInfo(0);
      expect(newGameInfo.currentBet).to.be.gt(BIG_BLIND);
    });

    it("Should allow all-in", async function () {
      const { poker, player1, player2 } = await loadFixture(startedGameFixture);

      const gameInfo = await poker.getGameInfo(0);
      const currentPlayerInfo = await poker.getPlayerInfo(0, gameInfo.currentPlayer);

      let allInPlayer;
      if (currentPlayerInfo.addr === player1.address) {
        allInPlayer = player1;
      } else {
        allInPlayer = player2;
      }

      await expect(poker.connect(allInPlayer).playerAction(0, PlayerAction.AllIn, 0))
        .to.emit(poker, "PlayerActed");
    });

    it("Should fail if not your turn", async function () {
      const { poker, player1, player2 } = await loadFixture(startedGameFixture);

      const gameInfo = await poker.getGameInfo(0);
      const currentPlayerInfo = await poker.getPlayerInfo(0, gameInfo.currentPlayer);

      let notCurrentPlayer;
      if (currentPlayerInfo.addr === player1.address) {
        notCurrentPlayer = player2;
      } else {
        notCurrentPlayer = player1;
      }

      await expect(
        poker.connect(notCurrentPlayer).playerAction(0, PlayerAction.Call, 0)
      ).to.be.revertedWith("Not your turn");
    });

    it("Should fail check when there's a bet to call", async function () {
      const { poker, player1, player2 } = await loadFixture(startedGameFixture);

      const gameInfo = await poker.getGameInfo(0);
      const currentPlayerInfo = await poker.getPlayerInfo(0, gameInfo.currentPlayer);

      let checkingPlayer;
      if (currentPlayerInfo.addr === player1.address) {
        checkingPlayer = player1;
      } else {
        checkingPlayer = player2;
      }

      // In preflop, SB needs to at least call the BB
      if (currentPlayerInfo.currentBet < gameInfo.currentBet) {
        await expect(
          poker.connect(checkingPlayer).playerAction(0, PlayerAction.Check, 0)
        ).to.be.revertedWith("Cannot check, must call or raise");
      }
    });
  });

  describe("Phase Transitions", function () {
    it("Should transition from PreFlop to Flop", async function () {
      const { poker, player1, player2 } = await loadFixture(startedGameFixture);

      // Get current player
      let gameInfo = await poker.getGameInfo(0);
      let currentPlayerInfo = await poker.getPlayerInfo(0, gameInfo.currentPlayer);
      let currentPlayer = currentPlayerInfo.addr === player1.address ? player1 : player2;
      let otherPlayer = currentPlayerInfo.addr === player1.address ? player2 : player1;

      // Current player calls
      await poker.connect(currentPlayer).playerAction(0, PlayerAction.Call, 0);

      // Other player checks (BB can check after call)
      await poker.connect(otherPlayer).playerAction(0, PlayerAction.Check, 0);

      // Should be in Flop now
      gameInfo = await poker.getGameInfo(0);
      expect(gameInfo.phase).to.equal(GamePhase.Flop);
    });

    it("Should reveal community cards progressively", async function () {
      const { poker, player1, player2 } = await loadFixture(startedGameFixture);

      // Play to flop
      let gameInfo = await poker.getGameInfo(0);
      let currentPlayerInfo = await poker.getPlayerInfo(0, gameInfo.currentPlayer);
      let currentPlayer = currentPlayerInfo.addr === player1.address ? player1 : player2;
      let otherPlayer = currentPlayerInfo.addr === player1.address ? player2 : player1;

      await poker.connect(currentPlayer).playerAction(0, PlayerAction.Call, 0);
      await poker.connect(otherPlayer).playerAction(0, PlayerAction.Check, 0);

      // Check community cards at flop
      let [communityCards, revealed] = await poker.getCommunityCards(0);
      expect(revealed).to.equal(3);

      // Play to turn
      gameInfo = await poker.getGameInfo(0);
      currentPlayerInfo = await poker.getPlayerInfo(0, gameInfo.currentPlayer);
      currentPlayer = currentPlayerInfo.addr === player1.address ? player1 : player2;
      otherPlayer = currentPlayerInfo.addr === player1.address ? player2 : player1;

      await poker.connect(currentPlayer).playerAction(0, PlayerAction.Check, 0);
      await poker.connect(otherPlayer).playerAction(0, PlayerAction.Check, 0);

      [communityCards, revealed] = await poker.getCommunityCards(0);
      expect(revealed).to.equal(4);
    });
  });

  describe("Showdown", function () {
    it("Should determine winner at showdown", async function () {
      const { poker, player1, player2 } = await loadFixture(startedGameFixture);

      // Play through all phases with checks/calls
      for (let phase = 0; phase < 4; phase++) {
        let gameInfo = await poker.getGameInfo(0);
        if (gameInfo.phase >= GamePhase.Showdown) break;

        let currentPlayerInfo = await poker.getPlayerInfo(0, gameInfo.currentPlayer);
        let currentPlayer = currentPlayerInfo.addr === player1.address ? player1 : player2;
        let otherPlayer = currentPlayerInfo.addr === player1.address ? player2 : player1;

        // First action in round
        if (phase === 0) {
          // Preflop: SB calls
          await poker.connect(currentPlayer).playerAction(0, PlayerAction.Call, 0);
        } else {
          await poker.connect(currentPlayer).playerAction(0, PlayerAction.Check, 0);
        }

        gameInfo = await poker.getGameInfo(0);
        if (gameInfo.phase >= GamePhase.Showdown) break;

        // Second action in round
        await poker.connect(otherPlayer).playerAction(0, PlayerAction.Check, 0);
      }

      const finalGameInfo = await poker.getGameInfo(0);
      expect(finalGameInfo.phase).to.equal(GamePhase.Finished);
    });
  });

  describe("Timeout", function () {
    it("Should allow force timeout after ACTION_TIMEOUT", async function () {
      const { poker, player1, player2 } = await loadFixture(startedGameFixture);

      // Advance time past ACTION_TIMEOUT (5 minutes)
      await time.increase(301);

      await expect(poker.forceActionTimeout(0))
        .to.emit(poker, "PlayerTimedOut");
    });

    it("Should fail force timeout before ACTION_TIMEOUT", async function () {
      const { poker, player1, player2 } = await loadFixture(startedGameFixture);

      await expect(
        poker.forceActionTimeout(0)
      ).to.be.revertedWith("Timeout not reached");
    });
  });

  describe("VRF Timeout", function () {
    it("Should allow VRF timeout and refund", async function () {
      const { poker, mockVRF, player1, player2 } = await loadFixture(twoPlayerGameFixture);

      await poker.connect(player1).startGame(0);

      // Advance time past VRF_TIMEOUT (10 minutes)
      await time.increase(601);

      const player1BalanceBefore = await ethers.provider.getBalance(player1.address);

      await poker.vrfTimeout(0);

      const gameInfo = await poker.getGameInfo(0);
      expect(gameInfo.phase).to.equal(GamePhase.Finished);
    });

    it("Should fail VRF timeout before VRF_TIMEOUT", async function () {
      const { poker, mockVRF, player1, player2 } = await loadFixture(twoPlayerGameFixture);

      await poker.connect(player1).startGame(0);

      await expect(
        poker.vrfTimeout(0)
      ).to.be.revertedWith("Timeout not reached");
    });
  });

  describe("Commission", function () {
    it("Should collect commission on winner payout", async function () {
      const { poker, player1, player2 } = await loadFixture(startedGameFixture);

      // Player folds, other player wins
      const gameInfo = await poker.getGameInfo(0);
      const currentPlayerInfo = await poker.getPlayerInfo(0, gameInfo.currentPlayer);
      let foldingPlayer = currentPlayerInfo.addr === player1.address ? player1 : player2;

      await poker.connect(foldingPlayer).playerAction(0, PlayerAction.Fold, 0);

      const commission = await poker.getCommissionBalance();
      expect(commission).to.be.gt(0);
    });

    it("Should allow owner to withdraw commission", async function () {
      const { poker, owner, player1, player2 } = await loadFixture(startedGameFixture);

      // End game
      const gameInfo = await poker.getGameInfo(0);
      const currentPlayerInfo = await poker.getPlayerInfo(0, gameInfo.currentPlayer);
      let foldingPlayer = currentPlayerInfo.addr === player1.address ? player1 : player2;
      await poker.connect(foldingPlayer).playerAction(0, PlayerAction.Fold, 0);

      const commissionBefore = await poker.getCommissionBalance();
      const ownerBalanceBefore = await ethers.provider.getBalance(owner.address);

      const tx = await poker.connect(owner).withdrawCommission();
      const receipt = await tx.wait();
      const gasUsed = receipt.gasUsed * receipt.gasPrice;

      const ownerBalanceAfter = await ethers.provider.getBalance(owner.address);
      const commissionAfter = await poker.getCommissionBalance();

      expect(commissionAfter).to.equal(0);
      expect(ownerBalanceAfter).to.be.closeTo(
        ownerBalanceBefore + commissionBefore - gasUsed,
        ethers.parseEther("0.001")
      );
    });
  });

  describe("Card Verification", function () {
    it("Should verify cards correctly", async function () {
      const { poker, player1, player2 } = await loadFixture(startedGameFixture);

      // Get player's cards
      const cards = await poker.connect(player1).getMyCards(0);

      // Verify the cards
      const isValid = await poker.verifyPlayerCards(0, 0, cards[0], cards[1]);
      expect(isValid).to.be.true;
    });

    it("Should fail verification with wrong cards", async function () {
      const { poker, player1, player2 } = await loadFixture(startedGameFixture);

      // Verify with wrong cards
      const isValid = await poker.verifyPlayerCards(0, 0, 50, 51);
      expect(isValid).to.be.false;
    });
  });

  describe("Card Decoding", function () {
    it("Should decode cards correctly", async function () {
      const { poker } = await loadFixture(deployFixture);

      // Card 0 = 2 of Hearts (rank 0, suit 0)
      let [rank, suit] = await poker.decodeCard(0);
      expect(rank).to.equal(0);
      expect(suit).to.equal(0);

      // Card 12 = Ace of Hearts (rank 12, suit 0)
      [rank, suit] = await poker.decodeCard(12);
      expect(rank).to.equal(12);
      expect(suit).to.equal(0);

      // Card 13 = 2 of Diamonds (rank 0, suit 1)
      [rank, suit] = await poker.decodeCard(13);
      expect(rank).to.equal(0);
      expect(suit).to.equal(1);

      // Card 51 = Ace of Spades (rank 12, suit 3)
      [rank, suit] = await poker.decodeCard(51);
      expect(rank).to.equal(12);
      expect(suit).to.equal(3);
    });
  });

  describe("Admin Functions", function () {
    it("Should transfer ownership", async function () {
      const { poker, owner, player1 } = await loadFixture(deployFixture);

      await poker.connect(owner).transferOwnership(player1.address);
      expect(await poker.owner()).to.equal(player1.address);
    });

    it("Should fail transfer ownership from non-owner", async function () {
      const { poker, player1, player2 } = await loadFixture(deployFixture);

      await expect(
        poker.connect(player1).transferOwnership(player2.address)
      ).to.be.revertedWith("Only owner");
    });

    it("Should fail transfer to zero address", async function () {
      const { poker, owner } = await loadFixture(deployFixture);

      await expect(
        poker.connect(owner).transferOwnership(ethers.ZeroAddress)
      ).to.be.revertedWith("Invalid address");
    });
  });

  describe("Multiple Games", function () {
    it("Should support multiple concurrent games", async function () {
      const { poker, player1, player2, player3, player4 } = await loadFixture(deployFixture);

      // Create game 0
      await poker.connect(player1).createGame(BUY_IN, SMALL_BLIND, BIG_BLIND, { value: BUY_IN });
      await poker.connect(player2).joinGame(0, { value: BUY_IN });

      // Create game 1
      await poker.connect(player3).createGame(BUY_IN, SMALL_BLIND, BIG_BLIND, { value: BUY_IN });
      await poker.connect(player4).joinGame(1, { value: BUY_IN });

      const game0Info = await poker.getGameInfo(0);
      const game1Info = await poker.getGameInfo(1);

      expect(game0Info.playerCount).to.equal(2);
      expect(game1Info.playerCount).to.equal(2);
      expect(await poker.gameCounter()).to.equal(2);
    });
  });

  describe("View Functions", function () {
    it("Should return correct game info", async function () {
      const { poker, player1, player2 } = await loadFixture(twoPlayerGameFixture);

      const gameInfo = await poker.getGameInfo(0);
      expect(gameInfo.buyIn).to.equal(BUY_IN);
      expect(gameInfo.phase).to.equal(GamePhase.WaitingForPlayers);
      expect(gameInfo.playerCount).to.equal(2);
    });

    it("Should return correct player info", async function () {
      const { poker, player1, player2 } = await loadFixture(twoPlayerGameFixture);

      const playerInfo = await poker.getPlayerInfo(0, 0);
      expect(playerInfo.addr).to.equal(player1.address);
      expect(playerInfo.chips).to.equal(BUY_IN);
      expect(playerInfo.folded).to.be.false;
    });

    it("Should fail getMyCards for non-player", async function () {
      const { poker, owner } = await loadFixture(startedGameFixture);

      await expect(
        poker.connect(owner).getMyCards(0)
      ).to.be.revertedWith("Not in game");
    });

    it("Should fail getPlayerCards before showdown", async function () {
      const { poker } = await loadFixture(startedGameFixture);

      await expect(
        poker.getPlayerCards(0, 0)
      ).to.be.revertedWith("Cards not revealed yet");
    });
  });
});
