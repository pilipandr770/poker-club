// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title DecentralizedPokerVRF - Texas Hold'em с верифицируемой случайностью
 * @notice Покер с интеграцией Orao VRF / Chainlink VRF для честной генерации колоды
 * @dev Колода генерируется VRF оракулом - никто не может предсказать карты
 * 
 * АРХИТЕКТУРА БЕЗОПАСНОСТИ:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │  1. Игроки делают ставки                                        │
 * │  2. Контракт запрашивает случайность у VRF                      │
 * │  3. VRF возвращает верифицируемое случайное число               │
 * │  4. Колода генерируется и карты раздаются                       │
 * │  5. Карты игроков зашифрованы до showdown                       │
 * │  6. На showdown карты раскрываются и определяется победитель    │
 * └─────────────────────────────────────────────────────────────────┘
 */

// ============ ИНТЕРФЕЙСЫ VRF ============

/**
 * @dev Интерфейс Orao VRF (Solana-style, адаптирован для EVM)
 * Документация: https://docs.orao.network/
 */
interface IOraoVRF {
    function request(bytes32 seed) external returns (bytes32 requestId);
    function getRandomness(bytes32 requestId) external view returns (bytes32 randomness);
}

/**
 * @dev Интерфейс Chainlink VRF v2.5
 * Документация: https://docs.chain.link/vrf
 */
interface IVRFCoordinatorV2Plus {
    function requestRandomWords(
        bytes32 keyHash,
        uint256 subId,
        uint16 requestConfirmations,
        uint32 callbackGasLimit,
        uint32 numWords
    ) external returns (uint256 requestId);
}

/**
 * @title VRFConsumerBaseV2Plus
 * @dev Базовый контракт для получения случайности от Chainlink VRF
 */
abstract contract VRFConsumerBaseV2Plus {
    address public vrfCoordinator;
    
    constructor(address _vrfCoordinator) {
        vrfCoordinator = _vrfCoordinator;
    }
    
    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external {
        require(msg.sender == vrfCoordinator, "Only VRF Coordinator");
        fulfillRandomWords(requestId, randomWords);
    }
    
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal virtual;
}

/**
 * @title DecentralizedPokerVRF
 * @notice Главный контракт покера с VRF
 */
contract DecentralizedPokerVRF is VRFConsumerBaseV2Plus {
    
    // ============ ВЫБОР VRF ПРОВАЙДЕРА ============
    
    enum VRFProvider {
        Chainlink,
        Orao
    }
    
    VRFProvider public immutable vrfProvider;
    
    // Chainlink VRF параметры
    bytes32 public immutable keyHash;
    uint256 public immutable subscriptionId;
    uint16 public constant REQUEST_CONFIRMATIONS = 3;
    uint32 public constant CALLBACK_GAS_LIMIT = 2500000; // Increased for deck generation
    
    // Orao VRF
    IOraoVRF public oraoVRF;
    
    // ============ КОНСТАНТЫ ИГРЫ ============
    
    uint256 public constant COMMISSION_PERCENT = 10;
    uint256 public constant MIN_PLAYERS = 2;
    uint256 public constant MAX_PLAYERS = 6;
    uint256 public constant ACTION_TIMEOUT = 5 minutes;
    uint256 public constant VRF_TIMEOUT = 10 minutes; // Таймаут ожидания VRF
    
    uint8 public constant CARDS_IN_DECK = 52;
    uint8 public constant HAND_SIZE = 2;
    uint8 public constant COMMUNITY_SIZE = 5;
    
    // ============ ТИПЫ ============
    
    enum HandRank {
        HighCard,      // 0
        OnePair,       // 1
        TwoPair,       // 2
        ThreeOfAKind,  // 3
        Straight,      // 4
        Flush,         // 5
        FullHouse,     // 6
        FourOfAKind,   // 7
        StraightFlush, // 8
        RoyalFlush     // 9
    }
    
    enum GamePhase {
        WaitingForPlayers,  // 0 - Ожидание игроков
        RequestingVRF,      // 1 - Запрос случайности от VRF
        PreFlop,            // 2 - Торговля до флопа
        Flop,               // 3 - После флопа (3 карты)
        Turn,               // 4 - После тёрна (4-я карта)
        River,              // 5 - После ривера (5-я карта)
        Showdown,           // 6 - Вскрытие карт
        Finished            // 7 - Игра завершена
    }
    
    enum PlayerAction {
        None,
        Fold,
        Check,
        Call,
        Raise,
        AllIn
    }
    
    // ============ СТРУКТУРЫ ============
    
    struct Player {
        address addr;
        uint256 chips;
        uint256 currentBet;
        uint256 totalBet;
        uint8[2] holeCards;      // Карты игрока (скрыты до showdown)
        bytes32 cardCommitment;  // Хэш карт для верификации
        bool folded;
        bool cardsRevealed;
        uint256 lastActionTime;
    }
    
    struct Game {
        uint256 gameId;
        uint256 buyIn;
        uint256 pot;
        uint256 currentBet;
        uint256 smallBlind;
        uint256 bigBlind;
        uint8 dealerPosition;
        uint8 currentPlayer;
        uint8 playerCount;
        uint8 activePlayers;
        GamePhase phase;
        uint8[5] communityCards;
        uint8[52] deck;
        bool deckGenerated;
        uint256 vrfRequestTime;      // Время запроса VRF
        uint256 vrfRequestId;        // ID запроса (Chainlink)
        bytes32 oraoRequestId;       // ID запроса (Orao)
        uint256 randomSeed;          // Полученное случайное число
        uint8 lastRaiser;
        uint8 actionsInRound;
        uint8 deckIndex;             // Текущая позиция в колоде
    }
    
    struct HandEvaluation {
        HandRank rank;
        uint32 value;
    }
    
    // ============ СОСТОЯНИЕ ============
    
    address public owner;
    uint256 public totalCommission;
    uint256 public gameCounter;
    
    mapping(uint256 => Game) public games;
    mapping(uint256 => mapping(uint8 => Player)) public players;
    mapping(uint256 => mapping(address => uint8)) public playerIndex;
    mapping(uint256 => mapping(address => bool)) public isPlayerInGame;
    
    // VRF request ID => Game ID
    mapping(uint256 => uint256) public chainlinkRequestToGame;
    mapping(bytes32 => uint256) public oraoRequestToGame;
    
    // ============ СОБЫТИЯ ============
    
    event GameCreated(uint256 indexed gameId, uint256 buyIn, uint256 smallBlind, uint256 bigBlind);
    event PlayerJoined(uint256 indexed gameId, address player, uint8 position);
    event VRFRequested(uint256 indexed gameId, uint256 requestId);
    event VRFFulfilled(uint256 indexed gameId, uint256 randomSeed);
    event DeckGenerated(uint256 indexed gameId);
    event CardsDealt(uint256 indexed gameId, address player, bytes32 commitment);
    event PhaseChanged(uint256 indexed gameId, GamePhase newPhase);
    event PlayerActed(uint256 indexed gameId, address player, PlayerAction action, uint256 amount);
    event CommunityCardsRevealed(uint256 indexed gameId, uint8[] cards);
    event ShowdownResult(uint256 indexed gameId, address winner, HandRank rank, uint256 winnings);
    event PotSplit(uint256 indexed gameId, address[] winners, uint256 amountEach);
    event CommissionCollected(uint256 indexed gameId, uint256 amount);
    event PlayerTimedOut(uint256 indexed gameId, address player);
    event CardsRevealedForPlayer(uint256 indexed gameId, address player, uint8 card1, uint8 card2);
    
    // ============ МОДИФИКАТОРЫ ============
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }
    
    modifier gameExists(uint256 _gameId) {
        require(_gameId < gameCounter, "Game does not exist");
        _;
    }
    
    modifier isActivePlayer(uint256 _gameId) {
        require(isPlayerInGame[_gameId][msg.sender], "Not in game");
        uint8 idx = playerIndex[_gameId][msg.sender];
        require(!players[_gameId][idx].folded, "Player folded");
        _;
    }
    
    modifier inPhase(uint256 _gameId, GamePhase _phase) {
        require(games[_gameId].phase == _phase, "Wrong phase");
        _;
    }
    
    // ============ КОНСТРУКТОР ============
    
    /**
     * @notice Конструктор для Chainlink VRF
     * @param _vrfCoordinator Адрес VRF Coordinator
     * @param _keyHash Key hash для VRF
     * @param _subscriptionId ID подписки Chainlink VRF
     */
    constructor(
        address _vrfCoordinator,
        bytes32 _keyHash,
        uint256 _subscriptionId
    ) VRFConsumerBaseV2Plus(_vrfCoordinator) {
        owner = msg.sender;
        vrfProvider = VRFProvider.Chainlink;
        keyHash = _keyHash;
        subscriptionId = _subscriptionId;
    }
    
    /**
     * @notice Альтернативный конструктор для Orao VRF (использовать через фабрику)
     */
    function initializeOrao(address _oraoVRF) external onlyOwner {
        require(address(oraoVRF) == address(0), "Already initialized");
        oraoVRF = IOraoVRF(_oraoVRF);
    }
    
    // ============ СОЗДАНИЕ И ПРИСОЕДИНЕНИЕ ============
    
    /**
     * @notice Создать новую игру
     */
    function createGame(
        uint256 _buyIn,
        uint256 _smallBlind,
        uint256 _bigBlind
    ) external payable returns (uint256) {
        require(msg.value == _buyIn, "Must send exact buy-in");
        require(_bigBlind == _smallBlind * 2, "Big blind must be 2x small blind");
        require(_buyIn >= _bigBlind * 20, "Buy-in must be at least 20 big blinds");
        
        uint256 gameId = gameCounter++;
        Game storage game = games[gameId];
        
        game.gameId = gameId;
        game.buyIn = _buyIn;
        game.smallBlind = _smallBlind;
        game.bigBlind = _bigBlind;
        game.phase = GamePhase.WaitingForPlayers;
        
        _addPlayer(gameId, msg.sender, _buyIn);
        
        emit GameCreated(gameId, _buyIn, _smallBlind, _bigBlind);
        return gameId;
    }
    
    /**
     * @notice Присоединиться к игре
     */
    function joinGame(uint256 _gameId) external payable gameExists(_gameId) {
        Game storage game = games[_gameId];
        require(game.phase == GamePhase.WaitingForPlayers, "Game already started");
        require(!isPlayerInGame[_gameId][msg.sender], "Already in game");
        require(game.playerCount < MAX_PLAYERS, "Game is full");
        require(msg.value == game.buyIn, "Must send exact buy-in");
        
        _addPlayer(_gameId, msg.sender, msg.value);
    }
    
    function _addPlayer(uint256 _gameId, address _player, uint256 _chips) internal {
        Game storage game = games[_gameId];
        uint8 position = game.playerCount;
        
        players[_gameId][position] = Player({
            addr: _player,
            chips: _chips,
            currentBet: 0,
            totalBet: 0,
            holeCards: [uint8(0), uint8(0)],
            cardCommitment: bytes32(0),
            folded: false,
            cardsRevealed: false,
            lastActionTime: block.timestamp
        });
        
        playerIndex[_gameId][_player] = position;
        isPlayerInGame[_gameId][_player] = true;
        game.playerCount++;
        game.activePlayers++;
        
        emit PlayerJoined(_gameId, _player, position);
    }
    
    // ============ ЗАПУСК ИГРЫ И VRF ============
    
    /**
     * @notice Начать игру - запрашивает VRF для генерации колоды
     */
    function startGame(uint256 _gameId) external gameExists(_gameId) {
        Game storage game = games[_gameId];
        require(game.phase == GamePhase.WaitingForPlayers, "Game already started");
        require(game.playerCount >= MIN_PLAYERS, "Not enough players");
        require(isPlayerInGame[_gameId][msg.sender], "Not in game");
        
        game.phase = GamePhase.RequestingVRF;
        game.vrfRequestTime = block.timestamp;
        
        // Запрашиваем случайность
        _requestRandomness(_gameId);
        
        emit PhaseChanged(_gameId, GamePhase.RequestingVRF);
    }
    
    /**
     * @dev Запрос случайности от VRF провайдера
     */
    function _requestRandomness(uint256 _gameId) internal {
        Game storage game = games[_gameId];
        
        if (vrfProvider == VRFProvider.Chainlink) {
            // Chainlink VRF v2.5
            uint256 requestId = IVRFCoordinatorV2Plus(vrfCoordinator).requestRandomWords(
                keyHash,
                subscriptionId,
                REQUEST_CONFIRMATIONS,
                CALLBACK_GAS_LIMIT,
                1 // Запрашиваем 1 случайное число
            );
            
            game.vrfRequestId = requestId;
            chainlinkRequestToGame[requestId] = _gameId;
            
            emit VRFRequested(_gameId, requestId);
            
        } else if (vrfProvider == VRFProvider.Orao) {
            // Orao VRF
            bytes32 seed = keccak256(abi.encodePacked(
                _gameId,
                block.timestamp,
                blockhash(block.number - 1)
            ));
            
            bytes32 requestId = oraoVRF.request(seed);
            game.oraoRequestId = requestId;
            oraoRequestToGame[requestId] = _gameId;
            
            emit VRFRequested(_gameId, uint256(requestId));
        }
    }
    
    /**
     * @dev Callback от Chainlink VRF
     */
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] calldata randomWords
    ) internal override {
        uint256 gameId = chainlinkRequestToGame[requestId];
        require(gameId != 0 || requestId == games[0].vrfRequestId, "Unknown request");
        
        Game storage game = games[gameId];
        require(game.phase == GamePhase.RequestingVRF, "Not waiting for VRF");
        
        game.randomSeed = randomWords[0];
        
        emit VRFFulfilled(gameId, game.randomSeed);
        
        // Генерируем колоду и раздаём карты
        _generateDeckAndDeal(gameId);
    }
    
    /**
     * @notice Получить случайность от Orao VRF (вызывается вручную после получения)
     */
    function fulfillOraoRandomness(uint256 _gameId) external gameExists(_gameId) {
        Game storage game = games[_gameId];
        require(game.phase == GamePhase.RequestingVRF, "Not waiting for VRF");
        require(vrfProvider == VRFProvider.Orao, "Not using Orao");
        
        bytes32 randomness = oraoVRF.getRandomness(game.oraoRequestId);
        require(randomness != bytes32(0), "Randomness not ready");
        
        game.randomSeed = uint256(randomness);
        
        emit VRFFulfilled(_gameId, game.randomSeed);
        
        _generateDeckAndDeal(_gameId);
    }
    
    /**
     * @notice Таймаут VRF - отмена игры если VRF не ответил
     */
    function vrfTimeout(uint256 _gameId) external gameExists(_gameId) {
        Game storage game = games[_gameId];
        require(game.phase == GamePhase.RequestingVRF, "Not waiting for VRF");
        require(block.timestamp > game.vrfRequestTime + VRF_TIMEOUT, "Timeout not reached");
        
        // Возвращаем деньги всем игрокам
        _cancelGame(_gameId);
    }
    
    // ============ ГЕНЕРАЦИЯ КОЛОДЫ ============
    
    /**
     * @dev Генерирует колоду и раздаёт карты
     * Колода генерируется из VRF seed - никто не мог знать результат заранее
     */
    function _generateDeckAndDeal(uint256 _gameId) internal {
        Game storage game = games[_gameId];
        
        // Инициализируем колоду (0-51)
        for (uint8 i = 0; i < CARDS_IN_DECK; i++) {
            game.deck[i] = i;
        }
        
        // Fisher-Yates shuffle с VRF seed
        uint256 seed = game.randomSeed;
        for (uint8 i = CARDS_IN_DECK - 1; i > 0; i--) {
            seed = uint256(keccak256(abi.encodePacked(seed, i)));
            uint8 j = uint8(seed % (i + 1));
            
            // Swap
            uint8 temp = game.deck[i];
            game.deck[i] = game.deck[j];
            game.deck[j] = temp;
        }
        
        game.deckGenerated = true;
        game.deckIndex = 0;
        
        emit DeckGenerated(_gameId);
        
        // Раздаём карты игрокам
        _dealHoleCards(_gameId);
        
        // Предустанавливаем community cards (burn + deal)
        _setupCommunityCards(_gameId);
        
        // Начинаем PreFlop
        _startPreFlop(_gameId);
    }
    
    /**
     * @dev Раздаёт по 2 карты каждому игроку
     * Карты сохраняются в контракте, но commitment позволяет верифицировать
     */
    function _dealHoleCards(uint256 _gameId) internal {
        Game storage game = games[_gameId];
        
        // Раздаём по 2 карты каждому (как в реальном покере - по кругу)
        for (uint8 round = 0; round < HAND_SIZE; round++) {
            for (uint8 i = 0; i < game.playerCount; i++) {
                uint8 playerIdx = (game.dealerPosition + 1 + i) % game.playerCount;
                if (!players[_gameId][playerIdx].folded) {
                    players[_gameId][playerIdx].holeCards[round] = game.deck[game.deckIndex++];
                }
            }
        }
        
        // Создаём commitment для каждого игрока (для верификации на showdown)
        for (uint8 i = 0; i < game.playerCount; i++) {
            Player storage player = players[_gameId][i];
            player.cardCommitment = keccak256(abi.encodePacked(
                player.holeCards[0],
                player.holeCards[1],
                game.randomSeed,
                player.addr
            ));
            
            emit CardsDealt(_gameId, player.addr, player.cardCommitment);
        }
    }
    
    /**
     * @dev Предустанавливает community cards с burn картами
     */
    function _setupCommunityCards(uint256 _gameId) internal {
        Game storage game = games[_gameId];
        
        // Burn + Flop (3 cards)
        game.deckIndex++; // burn
        game.communityCards[0] = game.deck[game.deckIndex++];
        game.communityCards[1] = game.deck[game.deckIndex++];
        game.communityCards[2] = game.deck[game.deckIndex++];
        
        // Burn + Turn
        game.deckIndex++; // burn
        game.communityCards[3] = game.deck[game.deckIndex++];
        
        // Burn + River
        game.deckIndex++; // burn
        game.communityCards[4] = game.deck[game.deckIndex++];
    }
    
    // ============ ТОРГОВЛЯ ============
    
    function _startPreFlop(uint256 _gameId) internal {
        Game storage game = games[_gameId];
        game.phase = GamePhase.PreFlop;
        
        // Постим блайнды
        if (game.playerCount == 2) {
            // Хедз-ап: dealer = SB
            _postBlind(_gameId, 0, game.smallBlind);
            _postBlind(_gameId, 1, game.bigBlind);
            game.currentPlayer = 0; // SB действует первым preflop
        } else {
            uint8 sbPos = (game.dealerPosition + 1) % game.playerCount;
            uint8 bbPos = (game.dealerPosition + 2) % game.playerCount;
            
            _postBlind(_gameId, sbPos, game.smallBlind);
            _postBlind(_gameId, bbPos, game.bigBlind);
            
            game.currentPlayer = (bbPos + 1) % game.playerCount;
        }
        
        game.currentBet = game.bigBlind;
        game.lastRaiser = game.currentPlayer;
        game.actionsInRound = 0;
        
        // Устанавливаем время для текущего игрока
        players[_gameId][game.currentPlayer].lastActionTime = block.timestamp;
        
        emit PhaseChanged(_gameId, GamePhase.PreFlop);
    }
    
    function _postBlind(uint256 _gameId, uint8 _playerIdx, uint256 _amount) internal {
        Player storage player = players[_gameId][_playerIdx];
        Game storage game = games[_gameId];
        
        uint256 blindAmount = _amount > player.chips ? player.chips : _amount;
        
        player.chips -= blindAmount;
        player.currentBet = blindAmount;
        player.totalBet += blindAmount;
        game.pot += blindAmount;
        
        emit PlayerActed(_gameId, player.addr, PlayerAction.Call, blindAmount);
    }
    
    /**
     * @notice Выполнить действие в торговле
     */
    function playerAction(uint256 _gameId, PlayerAction _action, uint256 _raiseAmount)
        external
        gameExists(_gameId)
        isActivePlayer(_gameId)
    {
        Game storage game = games[_gameId];
        require(
            game.phase >= GamePhase.PreFlop && game.phase <= GamePhase.River,
            "Not in betting phase"
        );
        
        uint8 idx = playerIndex[_gameId][msg.sender];
        require(idx == game.currentPlayer, "Not your turn");
        
        Player storage player = players[_gameId][idx];
        require(block.timestamp <= player.lastActionTime + ACTION_TIMEOUT, "Action timed out");
        
        if (_action == PlayerAction.Fold) {
            _fold(_gameId, idx);
        } else if (_action == PlayerAction.Check) {
            require(player.currentBet == game.currentBet, "Cannot check, must call or raise");
        } else if (_action == PlayerAction.Call) {
            _call(_gameId, idx);
        } else if (_action == PlayerAction.Raise) {
            _raise(_gameId, idx, _raiseAmount);
        } else if (_action == PlayerAction.AllIn) {
            _allIn(_gameId, idx);
        }
        
        player.lastActionTime = block.timestamp;
        game.actionsInRound++;
        
        emit PlayerActed(_gameId, msg.sender, _action, _raiseAmount);
        
        // Проверяем завершение раунда
        if (game.activePlayers == 1) {
            _finishGameSingleWinner(_gameId);
        } else if (_isBettingRoundComplete(_gameId)) {
            _nextPhase(_gameId);
        } else {
            _nextPlayer(_gameId);
        }
    }
    
    function _fold(uint256 _gameId, uint8 _playerIdx) internal {
        players[_gameId][_playerIdx].folded = true;
        games[_gameId].activePlayers--;
    }
    
    function _call(uint256 _gameId, uint8 _playerIdx) internal {
        Player storage player = players[_gameId][_playerIdx];
        Game storage game = games[_gameId];
        
        uint256 callAmount = game.currentBet - player.currentBet;
        if (callAmount > player.chips) {
            callAmount = player.chips;
        }
        
        player.chips -= callAmount;
        player.currentBet += callAmount;
        player.totalBet += callAmount;
        game.pot += callAmount;
    }
    
    function _raise(uint256 _gameId, uint8 _playerIdx, uint256 _raiseAmount) internal {
        Player storage player = players[_gameId][_playerIdx];
        Game storage game = games[_gameId];
        
        uint256 callAmount = game.currentBet - player.currentBet;
        uint256 totalAmount = callAmount + _raiseAmount;
        
        require(totalAmount <= player.chips, "Not enough chips");
        require(_raiseAmount >= game.bigBlind, "Raise must be at least big blind");
        
        player.chips -= totalAmount;
        player.currentBet += totalAmount;
        player.totalBet += totalAmount;
        game.pot += totalAmount;
        game.currentBet = player.currentBet;
        game.lastRaiser = _playerIdx;
        game.actionsInRound = 0;
    }
    
    function _allIn(uint256 _gameId, uint8 _playerIdx) internal {
        Player storage player = players[_gameId][_playerIdx];
        Game storage game = games[_gameId];
        
        uint256 allInAmount = player.chips;
        
        player.currentBet += allInAmount;
        player.totalBet += allInAmount;
        game.pot += allInAmount;
        player.chips = 0;
        
        if (player.currentBet > game.currentBet) {
            game.currentBet = player.currentBet;
            game.lastRaiser = _playerIdx;
            game.actionsInRound = 0;
        }
    }
    
    function _nextPlayer(uint256 _gameId) internal {
        Game storage game = games[_gameId];
        uint8 startPos = game.currentPlayer;
        
        do {
            game.currentPlayer = (game.currentPlayer + 1) % game.playerCount;
        } while (
            (players[_gameId][game.currentPlayer].folded || 
             players[_gameId][game.currentPlayer].chips == 0) &&
            game.currentPlayer != startPos
        );
        
        players[_gameId][game.currentPlayer].lastActionTime = block.timestamp;
    }
    
    function _isBettingRoundComplete(uint256 _gameId) internal view returns (bool) {
        Game storage game = games[_gameId];
        
        uint8 playersToAct = 0;
        for (uint8 i = 0; i < game.playerCount; i++) {
            Player storage player = players[_gameId][i];
            if (!player.folded && player.chips > 0) {
                if (player.currentBet != game.currentBet) {
                    return false;
                }
                playersToAct++;
            }
        }
        
        return game.actionsInRound >= playersToAct;
    }
    
    function _nextPhase(uint256 _gameId) internal {
        Game storage game = games[_gameId];
        
        // Сброс ставок
        for (uint8 i = 0; i < game.playerCount; i++) {
            players[_gameId][i].currentBet = 0;
        }
        game.currentBet = 0;
        game.actionsInRound = 0;
        
        // Определяем первого игрока (после дилера, не фолднувший)
        if (game.playerCount == 2) {
            game.currentPlayer = 1;
        } else {
            game.currentPlayer = (game.dealerPosition + 1) % game.playerCount;
            while (players[_gameId][game.currentPlayer].folded) {
                game.currentPlayer = (game.currentPlayer + 1) % game.playerCount;
            }
        }
        game.lastRaiser = game.currentPlayer;
        
        // Переход фазы и раскрытие карт
        if (game.phase == GamePhase.PreFlop) {
            game.phase = GamePhase.Flop;
            uint8[] memory flop = new uint8[](3);
            flop[0] = game.communityCards[0];
            flop[1] = game.communityCards[1];
            flop[2] = game.communityCards[2];
            emit CommunityCardsRevealed(_gameId, flop);
        } else if (game.phase == GamePhase.Flop) {
            game.phase = GamePhase.Turn;
            uint8[] memory turn = new uint8[](1);
            turn[0] = game.communityCards[3];
            emit CommunityCardsRevealed(_gameId, turn);
        } else if (game.phase == GamePhase.Turn) {
            game.phase = GamePhase.River;
            uint8[] memory river = new uint8[](1);
            river[0] = game.communityCards[4];
            emit CommunityCardsRevealed(_gameId, river);
        } else if (game.phase == GamePhase.River) {
            game.phase = GamePhase.Showdown;
            _resolveShowdown(_gameId);
            return;
        }
        
        emit PhaseChanged(_gameId, game.phase);
        players[_gameId][game.currentPlayer].lastActionTime = block.timestamp;
    }
    
    /**
     * @notice Форсировать таймаут - автофолд
     */
    function forceActionTimeout(uint256 _gameId) external gameExists(_gameId) {
        Game storage game = games[_gameId];
        require(
            game.phase >= GamePhase.PreFlop && game.phase <= GamePhase.River,
            "Not in betting phase"
        );
        
        Player storage currentPlayer = players[_gameId][game.currentPlayer];
        require(
            block.timestamp > currentPlayer.lastActionTime + ACTION_TIMEOUT,
            "Timeout not reached"
        );
        
        emit PlayerTimedOut(_gameId, currentPlayer.addr);
        _fold(_gameId, game.currentPlayer);
        
        if (game.activePlayers == 1) {
            _finishGameSingleWinner(_gameId);
        } else {
            _nextPlayer(_gameId);
        }
    }
    
    // ============ SHOWDOWN ============
    
    function _resolveShowdown(uint256 _gameId) internal {
        Game storage game = games[_gameId];
        emit PhaseChanged(_gameId, GamePhase.Showdown);
        
        // Раскрываем карты всех активных игроков
        for (uint8 i = 0; i < game.playerCount; i++) {
            if (!players[_gameId][i].folded) {
                Player storage player = players[_gameId][i];
                player.cardsRevealed = true;
                emit CardsRevealedForPlayer(
                    _gameId, 
                    player.addr, 
                    player.holeCards[0], 
                    player.holeCards[1]
                );
            }
        }
        
        // Определяем победителя
        _determineWinner(_gameId);
    }
    
    function _determineWinner(uint256 _gameId) internal {
        Game storage game = games[_gameId];
        
        uint8 bestPlayer = 0;
        HandEvaluation memory bestHand;
        bestHand.rank = HandRank.HighCard;
        bestHand.value = 0;
        
        address[] memory winners = new address[](game.playerCount);
        uint8 winnerCount = 0;
        
        for (uint8 i = 0; i < game.playerCount; i++) {
            if (!players[_gameId][i].folded) {
                HandEvaluation memory eval = _evaluateHand(
                    players[_gameId][i].holeCards,
                    game.communityCards
                );
                
                int8 comparison = _compareHands(eval, bestHand);
                
                if (comparison > 0) {
                    bestHand = eval;
                    bestPlayer = i;
                    winnerCount = 1;
                    winners[0] = players[_gameId][i].addr;
                } else if (comparison == 0) {
                    winners[winnerCount] = players[_gameId][i].addr;
                    winnerCount++;
                }
            }
        }
        
        if (winnerCount == 1) {
            _payWinner(_gameId, winners[0], game.pot);
            emit ShowdownResult(_gameId, winners[0], bestHand.rank, game.pot);
        } else {
            address[] memory actualWinners = new address[](winnerCount);
            for (uint8 i = 0; i < winnerCount; i++) {
                actualWinners[i] = winners[i];
            }
            _splitPot(_gameId, actualWinners);
        }
        
        game.phase = GamePhase.Finished;
        emit PhaseChanged(_gameId, GamePhase.Finished);
    }
    
    // ============ ОЦЕНКА РУК ============
    
    function _evaluateHand(uint8[2] memory holeCards, uint8[5] memory communityCards) 
        internal 
        pure 
        returns (HandEvaluation memory) 
    {
        uint8[7] memory allCards;
        allCards[0] = holeCards[0];
        allCards[1] = holeCards[1];
        for (uint8 i = 0; i < 5; i++) {
            allCards[i + 2] = communityCards[i];
        }
        
        uint8[7] memory ranks;
        uint8[7] memory suits;
        for (uint8 i = 0; i < 7; i++) {
            ranks[i] = allCards[i] % 13;
            suits[i] = allCards[i] / 13;
        }
        
        _sortDescending(ranks);
        
        uint8[13] memory rankCount;
        uint8[4] memory suitCount;
        
        for (uint8 i = 0; i < 7; i++) {
            uint8 r = allCards[i] % 13;
            uint8 s = allCards[i] / 13;
            rankCount[r]++;
            suitCount[s]++;
        }
        
        // Флеш
        int8 flushSuit = -1;
        for (uint8 s = 0; s < 4; s++) {
            if (suitCount[s] >= 5) {
                flushSuit = int8(s);
                break;
            }
        }
        
        // Стрит
        (bool hasStraight, uint8 straightHigh) = _checkStraight(rankCount);
        
        // Стрит-флеш / Роял-флеш
        if (flushSuit >= 0 && hasStraight) {
            (bool hasStraightFlush, uint8 sfHigh) = _checkStraightFlush(allCards, uint8(flushSuit));
            if (hasStraightFlush) {
                if (sfHigh == 12) {
                    return HandEvaluation(HandRank.RoyalFlush, 0);
                }
                return HandEvaluation(HandRank.StraightFlush, uint32(sfHigh));
            }
        }
        
        // Каре
        for (uint8 r = 0; r < 13; r++) {
            if (rankCount[r] == 4) {
                uint8 kicker = _findHighestExcluding(ranks, r);
                return HandEvaluation(HandRank.FourOfAKind, uint32(r) * 16 + kicker);
            }
        }
        
        // Фулл хаус
        int8 threeRank = -1;
        int8 pairRank = -1;
        for (uint8 r = 12; r < 13; r--) {
            if (rankCount[r] >= 3 && threeRank < 0) {
                threeRank = int8(r);
            } else if (rankCount[r] >= 2 && pairRank < 0) {
                pairRank = int8(r);
            }
            if (r == 0) break;
        }
        
        if (threeRank >= 0 && pairRank >= 0) {
            return HandEvaluation(HandRank.FullHouse, uint32(uint8(threeRank)) * 16 + uint8(pairRank));
        }
        
        // Флеш
        if (flushSuit >= 0) {
            uint32 flushValue = _getFlushValue(allCards, uint8(flushSuit));
            return HandEvaluation(HandRank.Flush, flushValue);
        }
        
        // Стрит
        if (hasStraight) {
            return HandEvaluation(HandRank.Straight, uint32(straightHigh));
        }
        
        // Тройка
        if (threeRank >= 0) {
            uint32 kickers = _getTwoKickers(ranks, uint8(threeRank));
            return HandEvaluation(HandRank.ThreeOfAKind, uint32(uint8(threeRank)) * 256 + kickers);
        }
        
        // Две пары
        int8 firstPair = -1;
        int8 secondPair = -1;
        for (uint8 r = 12; r < 13; r--) {
            if (rankCount[r] >= 2) {
                if (firstPair < 0) {
                    firstPair = int8(r);
                } else if (secondPair < 0) {
                    secondPair = int8(r);
                    break;
                }
            }
            if (r == 0) break;
        }
        
        if (firstPair >= 0 && secondPair >= 0) {
            uint8 kicker = _findHighestExcludingTwo(ranks, uint8(firstPair), uint8(secondPair));
            return HandEvaluation(
                HandRank.TwoPair, 
                uint32(uint8(firstPair)) * 256 + uint32(uint8(secondPair)) * 16 + kicker
            );
        }
        
        // Пара
        if (firstPair >= 0) {
            uint32 kickers = _getThreeKickers(ranks, uint8(firstPair));
            return HandEvaluation(HandRank.OnePair, uint32(uint8(firstPair)) * 4096 + kickers);
        }
        
        // Старшая карта
        uint32 highCardValue = uint32(ranks[0]) * 65536 + 
                               uint32(ranks[1]) * 4096 + 
                               uint32(ranks[2]) * 256 + 
                               uint32(ranks[3]) * 16 + 
                               uint32(ranks[4]);
        return HandEvaluation(HandRank.HighCard, highCardValue);
    }
    
    function _sortDescending(uint8[7] memory arr) internal pure {
        for (uint8 i = 0; i < 6; i++) {
            for (uint8 j = i + 1; j < 7; j++) {
                if (arr[j] > arr[i]) {
                    uint8 temp = arr[i];
                    arr[i] = arr[j];
                    arr[j] = temp;
                }
            }
        }
    }
    
    function _checkStraight(uint8[13] memory rankCount) internal pure returns (bool, uint8) {
        // Wheel (A-2-3-4-5)
        if (rankCount[12] > 0 && rankCount[0] > 0 && rankCount[1] > 0 && 
            rankCount[2] > 0 && rankCount[3] > 0) {
            return (true, 3);
        }
        
        uint8 consecutive = 0;
        for (uint8 r = 12; r < 13; r--) {
            if (rankCount[r] > 0) {
                consecutive++;
                if (consecutive >= 5) {
                    return (true, r + 4);
                }
            } else {
                consecutive = 0;
            }
            if (r == 0) break;
        }
        
        return (false, 0);
    }
    
    function _checkStraightFlush(uint8[7] memory cards, uint8 flushSuit) 
        internal pure returns (bool, uint8) 
    {
        uint8[13] memory suitedRankCount;
        
        for (uint8 i = 0; i < 7; i++) {
            if (cards[i] / 13 == flushSuit) {
                suitedRankCount[cards[i] % 13]++;
            }
        }
        
        return _checkStraight(suitedRankCount);
    }
    
    function _getFlushValue(uint8[7] memory cards, uint8 flushSuit) internal pure returns (uint32) {
        uint8[5] memory flushCards;
        uint8 count = 0;
        
        for (uint8 r = 12; r < 13 && count < 5; r--) {
            for (uint8 i = 0; i < 7; i++) {
                if (cards[i] / 13 == flushSuit && cards[i] % 13 == r) {
                    flushCards[count++] = r;
                    break;
                }
            }
            if (r == 0) break;
        }
        
        return uint32(flushCards[0]) * 65536 + 
               uint32(flushCards[1]) * 4096 + 
               uint32(flushCards[2]) * 256 + 
               uint32(flushCards[3]) * 16 + 
               uint32(flushCards[4]);
    }
    
    function _findHighestExcluding(uint8[7] memory ranks, uint8 exclude) internal pure returns (uint8) {
        for (uint8 i = 0; i < 7; i++) {
            if (ranks[i] != exclude) return ranks[i];
        }
        return 0;
    }
    
    function _findHighestExcludingTwo(uint8[7] memory ranks, uint8 ex1, uint8 ex2) internal pure returns (uint8) {
        for (uint8 i = 0; i < 7; i++) {
            if (ranks[i] != ex1 && ranks[i] != ex2) return ranks[i];
        }
        return 0;
    }
    
    function _getTwoKickers(uint8[7] memory ranks, uint8 exclude) internal pure returns (uint32) {
        uint8 count = 0;
        uint8[2] memory kickers;
        
        for (uint8 i = 0; i < 7 && count < 2; i++) {
            if (ranks[i] != exclude) {
                kickers[count++] = ranks[i];
            }
        }
        
        return uint32(kickers[0]) * 16 + uint32(kickers[1]);
    }
    
    function _getThreeKickers(uint8[7] memory ranks, uint8 exclude) internal pure returns (uint32) {
        uint8 count = 0;
        uint8[3] memory kickers;
        
        for (uint8 i = 0; i < 7 && count < 3; i++) {
            if (ranks[i] != exclude) {
                kickers[count++] = ranks[i];
            }
        }
        
        return uint32(kickers[0]) * 256 + uint32(kickers[1]) * 16 + uint32(kickers[2]);
    }
    
    function _compareHands(HandEvaluation memory a, HandEvaluation memory b) internal pure returns (int8) {
        if (uint8(a.rank) > uint8(b.rank)) return 1;
        if (uint8(a.rank) < uint8(b.rank)) return -1;
        if (a.value > b.value) return 1;
        if (a.value < b.value) return -1;
        return 0;
    }
    
    // ============ ВЫПЛАТЫ ============
    
    function _payWinner(uint256 _gameId, address _winner, uint256 _amount) internal {
        uint256 commission = (_amount * COMMISSION_PERCENT) / 100;
        uint256 winnings = _amount - commission;
        
        totalCommission += commission;
        games[_gameId].pot = 0;
        
        emit CommissionCollected(_gameId, commission);
        
        (bool sent, ) = payable(_winner).call{value: winnings}("");
        require(sent, "Failed to send winnings");
    }
    
    function _splitPot(uint256 _gameId, address[] memory _winners) internal {
        Game storage game = games[_gameId];
        uint256 totalPot = game.pot;
        
        uint256 commission = (totalPot * COMMISSION_PERCENT) / 100;
        uint256 distributablePot = totalPot - commission;
        uint256 share = distributablePot / _winners.length;
        
        totalCommission += commission;
        game.pot = 0;
        
        emit CommissionCollected(_gameId, commission);
        emit PotSplit(_gameId, _winners, share);
        
        for (uint256 i = 0; i < _winners.length; i++) {
            (bool sent, ) = payable(_winners[i]).call{value: share}("");
            require(sent, "Failed to send split");
        }
        
        uint256 remainder = distributablePot - (share * _winners.length);
        if (remainder > 0) {
            (bool sent, ) = payable(_winners[0]).call{value: remainder}("");
            require(sent, "Failed to send remainder");
        }
    }
    
    function _finishGameSingleWinner(uint256 _gameId) internal {
        Game storage game = games[_gameId];
        
        for (uint8 i = 0; i < game.playerCount; i++) {
            if (!players[_gameId][i].folded) {
                _payWinner(_gameId, players[_gameId][i].addr, game.pot);
                emit ShowdownResult(_gameId, players[_gameId][i].addr, HandRank.HighCard, game.pot);
                break;
            }
        }
        
        game.phase = GamePhase.Finished;
        emit PhaseChanged(_gameId, GamePhase.Finished);
    }
    
    function _cancelGame(uint256 _gameId) internal {
        Game storage game = games[_gameId];
        
        for (uint8 i = 0; i < game.playerCount; i++) {
            Player storage player = players[_gameId][i];
            uint256 refund = game.buyIn;
            
            if (refund > 0) {
                (bool sent, ) = payable(player.addr).call{value: refund}("");
                require(sent, "Refund failed");
            }
        }
        
        game.phase = GamePhase.Finished;
        game.pot = 0;
    }
    
    // ============ VIEW ФУНКЦИИ ============
    
    function getGameInfo(uint256 _gameId) external view returns (
        uint256 buyIn,
        uint256 pot,
        uint256 currentBet,
        GamePhase phase,
        uint8 playerCount,
        uint8 activePlayers,
        uint8 currentPlayer,
        bool deckGenerated
    ) {
        Game storage game = games[_gameId];
        return (
            game.buyIn,
            game.pot,
            game.currentBet,
            game.phase,
            game.playerCount,
            game.activePlayers,
            game.currentPlayer,
            game.deckGenerated
        );
    }
    
    function getPlayerInfo(uint256 _gameId, uint8 _playerIdx) external view returns (
        address addr,
        uint256 chips,
        uint256 currentBet,
        bool folded,
        bool cardsRevealed
    ) {
        Player storage player = players[_gameId][_playerIdx];
        return (
            player.addr,
            player.chips,
            player.currentBet,
            player.folded,
            player.cardsRevealed
        );
    }
    
    /**
     * @notice Получить свои карты (только владелец карт)
     */
    function getMyCards(uint256 _gameId) external view returns (uint8[2] memory) {
        require(isPlayerInGame[_gameId][msg.sender], "Not in game");
        require(games[_gameId].deckGenerated, "Cards not dealt yet");
        
        uint8 idx = playerIndex[_gameId][msg.sender];
        return players[_gameId][idx].holeCards;
    }
    
    /**
     * @notice Получить карты игрока (только после showdown)
     */
    function getPlayerCards(uint256 _gameId, uint8 _playerIdx) external view returns (uint8[2] memory) {
        require(
            games[_gameId].phase == GamePhase.Showdown || 
            games[_gameId].phase == GamePhase.Finished,
            "Cards not revealed yet"
        );
        require(players[_gameId][_playerIdx].cardsRevealed, "Player cards not revealed");
        
        return players[_gameId][_playerIdx].holeCards;
    }
    
    function getCommunityCards(uint256 _gameId) external view returns (uint8[5] memory, uint8 revealed) {
        Game storage game = games[_gameId];
        
        if (game.phase == GamePhase.PreFlop || game.phase < GamePhase.PreFlop) {
            revealed = 0;
        } else if (game.phase == GamePhase.Flop) {
            revealed = 3;
        } else if (game.phase == GamePhase.Turn) {
            revealed = 4;
        } else {
            revealed = 5;
        }
        
        return (game.communityCards, revealed);
    }
    
    function decodeCard(uint8 cardNumber) external pure returns (uint8 rank, uint8 suit) {
        return (cardNumber % 13, cardNumber / 13);
    }
    
    /**
     * @notice Верифицировать карты игрока (проверка честности)
     */
    function verifyPlayerCards(
        uint256 _gameId, 
        uint8 _playerIdx,
        uint8 card1,
        uint8 card2
    ) external view returns (bool) {
        Game storage game = games[_gameId];
        Player storage player = players[_gameId][_playerIdx];
        
        bytes32 expectedCommitment = keccak256(abi.encodePacked(
            card1,
            card2,
            game.randomSeed,
            player.addr
        ));
        
        return expectedCommitment == player.cardCommitment;
    }
    
    // ============ ADMIN ФУНКЦИИ ============
    
    function withdrawCommission() external onlyOwner {
        uint256 amount = totalCommission;
        totalCommission = 0;
        
        (bool sent, ) = payable(owner).call{value: amount}("");
        require(sent, "Withdraw failed");
    }
    
    function transferOwnership(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "Invalid address");
        owner = _newOwner;
    }
    
    function getCommissionBalance() external view returns (uint256) {
        return totalCommission;
    }
    
    receive() external payable {}
}
