// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.0 <0.9.0;

// Users (Maker) can open a bet and another user can take the bet (Taker); Taker can be specified by address
// 
// This build: (1) make UniV3TwapOracle address upgradeable by owner
//
// Next Steps: (1) AllowList only certain tokens as skintokens (2) Emergency stop function (3) Figure out tracking a user's bets
// (4) emergency withdraw activation (user can withdraw if funds not claimed x days after bet should be settled) 
// (5) Add upgradeable proxy (6) disallow a bet to be taken 'n' time before settlement time 
// (8) change OWNER functionality to OpenZeppelin standard

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.0.0/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.0.0/contracts/token/ERC20/ERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

interface UniV3TwapOracle {
    function convertToHumanReadable(address _factory, address _token1, address _token2, uint24 _fee, uint32 _twapInterval,
        uint8 _token0Decimals) external view returns(uint256);
    function getToken0(address _factory, address _tokenA, address _tokenB, uint24 _fee) external view returns (address);
}

contract EscrowBet {
    // Protocol constants
    uint8 public PROTOCOL_FEE;
    address OWNER;
    address UNIV3FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;      //Goerli Testnet factory address
    address ALLOWLIST;                                                      //Address of Allowlist for tokens that can be used as skinTokens

    //address UNISWAP_TWAP_LIBRARY = 0xb255C27D27185aBe44Be0Cf25997AF1221DD6521;      // Sepolia
    address UNISWAP_TWAP_LIBRARY = 0x20ad155ea921FeDb706126f7BdC18007fA55A4ff;    // Goerli 
    UniV3TwapOracle public twapGetter;

    enum Status {
        WAITING_FOR_TAKER,
        KILLED,
        IN_PROCESS,
        SETTLED,
        CANCELED
    }

    enum Comparison {
        GREATER_THAN,
        EQUALS,
        LESS_THAN
    }

    enum OracleType {
        CHAINLINK,
        UNISWAP_V3
    }

    // this function exists to circumvent Stack too deep errors
    struct BetAddresses {
        address Maker;              // stores address of bet creator via msg.sender
        address Taker;              // stores address of taker, is either defined by the bet Maker or is blank so anyone can take the bet
        address SkinToken;          // address of the token used as medium of exchange in the bet   
        address OracleAddressMain;  // address of the Main price oracle that the bet will use (if Uniswap then this is token0) 
        address OracleAddress2;     // address of a secondary oracle if two are needed (if Uniswap then this is token1)
    }

    // struct to store each address's total deposited token balance and # tokens in a bet
    struct Ledger {
        uint depositedBalance;
        uint escrowedBalance;
    }

    // Mapping of mapping to track balances for each token by owner address
    mapping(address => mapping(address => Ledger)) public balances;

    // Mapping to track all of a user's bets;
    // Risks creating an unbounded array that consumes too much gas!!!!!!!!!!!!!!!
    mapping(address => uint256[]) public UserBets;

    // Universal counter of every bet made
    uint256 public BetNumber;
    
    // this struct stores bets which will be assigned a BetNumber to be mapped to    
    struct Bets {
        BetAddresses betAddresses;  // struct to store all bet addresses
        uint BetAmount;             // ammount of SkinToken to be bet with
        uint EndTime;               // unix time that bet ends, user defines number of seconds from time the bet creation Tx is approved        
        Status BetStatus;           // Status of bet as enum: WAITING_FOR_TAKER, KILLED, IN_PROCESS, SETTLED, CANCELED        
        OracleType OracleName;      // enum defining what type of oracle to use
        uint24 UniswapFeePool;      // allows user defined fee pool to get price from ("3000" corresponds to 0.3%)
        uint256 PriceLine;          // price level to determine winner based off of the price oracle        
        Comparison Comparitor;      // enum defining direction taken by bet Maker enum: GREATER_THAN, EQUALS, LESS_THAN        
        bool MakerCancel;           // define if Maker has agreed to cancel bet        
        bool TakerCancel;           // defines if Taker has agreed to cancel bet        
    }
    
    // Mapping of all opened bets
    mapping(uint256 => Bets) public AllBets;

    fallback() external {

    }

    constructor(uint8 _protocolFee) {
        // Because Solidity can't perform decimal mult/div, multiply by PROTOCOL_FEE and divide by 10,000
        // PROTOCOL_FEE of 0001 equals 0.01% fee
        PROTOCOL_FEE = _protocolFee;
        OWNER = msg.sender;
    }

    receive() payable external {

    }

    modifier onlyOwner {
        require(msg.sender == OWNER, "Only owner can perform this action");
        _;
    }

    function changeUniV3Factory (address _newFactoryAddress) public onlyOwner {
        UNIV3FACTORY = _newFactoryAddress;
    }

    function changeProtocolFee(uint8 _newProtocolFee) external onlyOwner {
        PROTOCOL_FEE = _newProtocolFee;
    }

    function setUniswapOracleLibrary(address _UniLibAddr) external onlyOwner {
        UNISWAP_TWAP_LIBRARY = _UniLibAddr;
        twapGetter = UniV3TwapOracle(UNISWAP_TWAP_LIBRARY);
    }

    function depositTokens(address _tokenAddress, uint _amount) public {
        balances[msg.sender][_tokenAddress].depositedBalance += _amount;
        require(IERC20(_tokenAddress).transferFrom(msg.sender, address(this), _amount), "Deposit Failed");
    }

    // Withdraws _amount of tokens if they are avaiable
    function userWithdrawTokens(address _tokenAddress, uint _amount) public {
        uint tokensAvailable = balances[msg.sender][_tokenAddress].depositedBalance - balances[msg.sender][_tokenAddress].escrowedBalance;
        require(tokensAvailable >= _amount, "Insufficient Balance");
        balances[msg.sender][_tokenAddress].depositedBalance -= _amount;
        require(IERC20(_tokenAddress).transfer(msg.sender, _amount), "Withdraw Failed");
    }

    function createNewBet(BetAddresses memory _betAddresses, uint _amount, uint32 _time, OracleType _oracleName, uint24 _uniFeePool,
        uint256 _priceLine, Comparison _comparitor) internal {
        
        AllBets[BetNumber].betAddresses.Maker = _betAddresses.Maker;
        AllBets[BetNumber].betAddresses.Taker = _betAddresses.Taker;
        AllBets[BetNumber].betAddresses.SkinToken = _betAddresses.SkinToken;
        AllBets[BetNumber].BetAmount = _amount;
        AllBets[BetNumber].EndTime = block.timestamp + _time;
        AllBets[BetNumber].BetStatus = Status.WAITING_FOR_TAKER;

        if(_oracleName == OracleType.UNISWAP_V3) {
            address _token0 = twapGetter.getToken0(UNIV3FACTORY, _betAddresses.OracleAddressMain, _betAddresses.OracleAddress2, 3000);
            if(_betAddresses.OracleAddress2 == _token0){
                _betAddresses.OracleAddress2 = _betAddresses.OracleAddressMain;
                _betAddresses.OracleAddressMain = _token0;
            }
        }
        AllBets[BetNumber].betAddresses.OracleAddressMain = _betAddresses.OracleAddressMain;
        AllBets[BetNumber].betAddresses.OracleAddress2 = _betAddresses.OracleAddress2;
        AllBets[BetNumber].OracleName = _oracleName;
        AllBets[BetNumber].PriceLine = _priceLine;
        AllBets[BetNumber].UniswapFeePool = _uniFeePool;
        AllBets[BetNumber].Comparitor = _comparitor;
        AllBets[BetNumber].MakerCancel= false;
        AllBets[BetNumber].TakerCancel = false;
    }

    // Opens a new bet with freshly deposited tokens
    // what if user doesn't input one of the values or inputs a malicious value????????????????????????????    
    function depositAndBet(address _takerAddress, address _skinTokenAddress, uint _amount, uint32 _time, address _oracleAddressMain,
        address _oracleAddress2, OracleType _oracleName, uint24 _uniFeePool, uint256 _priceLine, Comparison _comparitor) public {
        
        require(_amount > 0, "Bet amount must be greater than 0");
        require(_takerAddress != msg.sender, "Maker and Taker cannot be the same");

        // should BetNumber be incremented here or later? This logic results in BetNumber[0] having no initialization        
        // and could allow for re-entry
        BetNumber++;

        BetAddresses memory _betAddresses;
        _betAddresses.Maker = msg.sender;
        _betAddresses.Taker = _takerAddress;        // can be 0x0000000000000000000000000000000000000000
        _betAddresses.SkinToken = _skinTokenAddress;
        _betAddresses.OracleAddressMain = _oracleAddressMain;
        _betAddresses.OracleAddress2 = _oracleAddress2;
        createNewBet(_betAddresses, _amount, _time, _oracleName, _uniFeePool, _priceLine, _comparitor);

        UserBets[msg.sender].push(BetNumber);
        balances[msg.sender][_skinTokenAddress].depositedBalance += _amount;
        balances[msg.sender][_skinTokenAddress].escrowedBalance += _amount;
        require(IERC20(_skinTokenAddress).transferFrom(msg.sender, address(this), _amount), "Deposit Failed");
    }

    function betWithUserBalance(address _takerAddress, address _skinTokenAddress, uint _amount, uint32 _time, address _oracleAddressMain,
        address _oracleAddress2, OracleType _oracleName, uint24 _uniFeePool, uint256 _priceLine, Comparison _comparitor) public {
        
        require(_amount > 0, "Bet amount must be greater than 0");
        require(_takerAddress != msg.sender, "Maker and Taker cannot be the same");
        //Check that Maker has required amount of tokens for bet
        require(balances[msg.sender][_skinTokenAddress].depositedBalance - balances[msg.sender][_skinTokenAddress].escrowedBalance >= _amount, "Insufficient Funds");
        BetNumber++;

        BetAddresses memory _betAddresses;
        _betAddresses.Maker = msg.sender;
        _betAddresses.Taker = _takerAddress;        // can be 0x0000000000000000000000000000000000000000
        _betAddresses.SkinToken = _skinTokenAddress;
        _betAddresses.OracleAddressMain = _oracleAddressMain;
        _betAddresses.OracleAddress2 = _oracleAddress2;
        createNewBet(_betAddresses, _amount, _time, _oracleName, _uniFeePool, _priceLine, _comparitor);

        UserBets[msg.sender].push(BetNumber);
        balances[msg.sender][_skinTokenAddress].escrowedBalance += _amount;
    } 

    function cancelBet(uint _betNumber) public {
        address _tokenAddress = AllBets[_betNumber].betAddresses.SkinToken;

        // Check that request was sent by bet Maker
        require(msg.sender == AllBets[_betNumber].betAddresses.Maker, "Only Maker can perform this action");
        // check that bet is not taken
        require(AllBets[_betNumber].BetStatus == Status.WAITING_FOR_TAKER, "Can't force cancel once Taker accepts");
        // check that the amount they want to withdraw is allowed
        require(AllBets[_betNumber].BetAmount <= balances[msg.sender][_tokenAddress].escrowedBalance);
        // Change status to "KILLED"
        AllBets[_betNumber].BetStatus = Status.KILLED;
        // subtract the bet amount from escrowedBalance
        balances[msg.sender][_tokenAddress].escrowedBalance -= AllBets[_betNumber].BetAmount;
    }

    function depositAndAcceptBet(uint _betNumber, uint _amount) public {
        //check if msg.sender can be taker
        require(msg.sender == AllBets[_betNumber].betAddresses.Taker || AllBets[_betNumber].betAddresses.Taker == address(0), 
            "Only Taker can accept");
        // require that the bet is not taken, killed, or completed
        require(AllBets[_betNumber].BetStatus == Status.WAITING_FOR_TAKER, "Action not allowed on this item");
        // require bet time not passed
        require(AllBets[_betNumber].EndTime > block.timestamp, "Action expired");
        
        // check the same amount is uesd
        require(_amount == AllBets[_betNumber].BetAmount, "Incorrect token amount");

        // Assign msg.sender to Taker if Taker is unassigned
        if(AllBets[_betNumber].betAddresses.Taker == address(0)){
            AllBets[_betNumber].betAddresses.Taker = msg.sender;
        }

        address _tokenAddress = AllBets[_betNumber].betAddresses.SkinToken;
        AllBets[_betNumber].BetStatus = Status.IN_PROCESS;
        UserBets[msg.sender].push(BetNumber);
        balances[msg.sender][_tokenAddress].depositedBalance += _amount;
        balances[msg.sender][_tokenAddress].escrowedBalance += _amount;
        require(IERC20(_tokenAddress).transferFrom(msg.sender, address(this), _amount), "Deposit Failed");
    }

    function acceptBetWithUserBalance(uint _betNumber, uint _amount) public {
        //check if msg.sender can be taker
        require(msg.sender == AllBets[_betNumber].betAddresses.Taker || AllBets[_betNumber].betAddresses.Taker == address(0), 
            "Only Taker can accept");
        // require that the bet is not taken, killed, or completed
        require(AllBets[_betNumber].BetStatus == Status.WAITING_FOR_TAKER, "Action not allowed on this item");
        // require bet time not passed
        require(AllBets[_betNumber].EndTime > block.timestamp, "Action expired");
        // check that Taker has required amount of tokens
        require(balances[msg.sender][AllBets[_betNumber].betAddresses.SkinToken].depositedBalance
            - balances[msg.sender][AllBets[_betNumber].betAddresses.SkinToken].escrowedBalance
            >= _amount, "Insufficient Funds");
        
        // Assign msg.sender to Taker if Taker is unassigned
        if(AllBets[_betNumber].betAddresses.Taker == address(0)){
            AllBets[_betNumber].betAddresses.Taker = msg.sender;
        }

        AllBets[_betNumber].BetStatus = Status.IN_PROCESS;
        UserBets[msg.sender].push(BetNumber);
        balances[msg.sender][AllBets[_betNumber].betAddresses.SkinToken].escrowedBalance += _amount;
    }

    // need to somehow check if oracle has gone dead or not updated in a long time
    function closeBet(uint _betNumber) public {
        // check _betNumber exists
        require(_betNumber <= BetNumber, "This bet does not exist");
        // check bet status
        require(AllBets[_betNumber].BetStatus == Status.IN_PROCESS, "Action not allowed: Status");
        // check correct time has passed
        require(block.timestamp >= AllBets[_betNumber].EndTime, "EndTime not reached");

        // check winner
        bool makerWins;
        uint256 currentPrice = getOraclePriceByBet(_betNumber);
        uint256 priceLine = AllBets[_betNumber].PriceLine;        

        if(currentPrice > priceLine){
            if(AllBets[_betNumber].Comparitor == Comparison.GREATER_THAN) {
                makerWins = true;
            }else{makerWins = false;}
        }else if(currentPrice < priceLine){
            if(AllBets[_betNumber].Comparitor == Comparison.LESS_THAN) {
                makerWins = true;
            }else{makerWins = false;}
        }else {
            if(AllBets[_betNumber].Comparitor == Comparison.EQUALS) {
                makerWins = true;
            }else{makerWins = false;}
        }

        uint amount = AllBets[_betNumber].BetAmount;

        if(makerWins){
            AllBets[_betNumber].BetStatus = Status.SETTLED;
            settleBalances(AllBets[_betNumber].betAddresses.Maker, AllBets[_betNumber].betAddresses.Taker, AllBets[_betNumber].betAddresses.SkinToken, amount);
        }else {
            AllBets[_betNumber].BetStatus = Status.SETTLED;
            settleBalances(AllBets[_betNumber].betAddresses.Taker, AllBets[_betNumber].betAddresses.Maker, AllBets[_betNumber].betAddresses.SkinToken, amount);
        }
    }

    function settleBalances(address _winningAddress, address _losingAddress, address _skinToken, uint amount) internal {
        // This should use SafeMath!!!!!!!!!!!!!!
        balances[_losingAddress][_skinToken].depositedBalance -= amount;
        balances[_losingAddress][_skinToken].escrowedBalance -= amount;
        balances[_winningAddress][_skinToken].depositedBalance += (amount*(10000-PROTOCOL_FEE))/10000;
        balances[_winningAddress][_skinToken].escrowedBalance -= amount;
        balances[address(this)][_skinToken].depositedBalance += (amount*PROTOCOL_FEE)/10000;
    }

    function requestBetCancel(uint _betNumber) public {
        // Require that request was sent by Maker or Taker
        require(msg.sender == AllBets[_betNumber].betAddresses.Maker || msg.sender == AllBets[_betNumber].betAddresses.Taker, "Only Maker or Taker can perform this action");
        // Require that bet is in a cancellable state ("IN_PROCESS")
        require(AllBets[_betNumber].BetStatus == Status.IN_PROCESS, "Status not IN_PROCESS");

        if(msg.sender == AllBets[_betNumber].betAddresses.Maker) {
            AllBets[_betNumber].MakerCancel = true;
        }else if(msg.sender == AllBets[_betNumber].betAddresses.Taker) {
            AllBets[_betNumber].TakerCancel = true;
        }

        //If Maker and Taker agree to cancel then refund each their tokens
        //If future versions have deposited LINK into an LINK oracle then this may need to be refunded
        if(AllBets[_betNumber].MakerCancel == true && AllBets[_betNumber].TakerCancel == true){
            AllBets[_betNumber].BetStatus = Status.CANCELED;
            balances[AllBets[_betNumber].betAddresses.Maker][AllBets[_betNumber].betAddresses.SkinToken].escrowedBalance -= AllBets[_betNumber].BetAmount;
            balances[AllBets[_betNumber].betAddresses.Taker][AllBets[_betNumber].betAddresses.SkinToken].escrowedBalance -= AllBets[_betNumber].BetAmount;
        }
    }

    function transferERC20(address _token, uint256 amount) external onlyOwner {
        require(amount <= balances[address(this)][_token].depositedBalance, "Insufficient Funds");
        balances[OWNER][_token].depositedBalance -= amount;
        require(IERC20(_token).transfer(OWNER, amount), "Withdraw Failed");
    }

    function withdrawEther(uint256 amount) external onlyOwner {
        require(amount <= address(this).balance, "Insufficient Funds");
        payable(OWNER).transfer(amount);
    }

    function checkClosable(uint _betNumber) external view returns(bool) {
        if(block.timestamp >= AllBets[_betNumber].EndTime && AllBets[_betNumber].BetStatus == Status.IN_PROCESS){return true;}
        else{return false;}
    }

    function getDecimals(address _oracleAddress) public view returns (uint8) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(_oracleAddress);
        return priceFeed.decimals();
    }

    function getChainlinkPrice(address _oracleAddress) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(_oracleAddress);
        (,int256 answer,,,) = priceFeed.latestRoundData();
        return uint256(answer / int256(10 ** getDecimals(_oracleAddress)));
    }

    function getOraclePriceByBet(uint256 _betNumber) public view returns (uint256) {
        uint256 CurrentPrice;
        if(AllBets[_betNumber].OracleName == OracleType.CHAINLINK) {
            if(AllBets[_betNumber].betAddresses.OracleAddress2 == address(0)){
                CurrentPrice = getChainlinkPrice(AllBets[_betNumber].betAddresses.OracleAddressMain);
            }else {
                CurrentPrice = getChainlinkPrice(AllBets[_betNumber].betAddresses.OracleAddressMain) / 
                    getChainlinkPrice(AllBets[_betNumber].betAddresses.OracleAddress2);
            }
        }else if(AllBets[_betNumber].OracleName == OracleType.UNISWAP_V3){
            uint8 _token0Decimals = ERC20(AllBets[_betNumber].betAddresses.OracleAddressMain).decimals();
            // address _factory, address _token1, address _token2, uint24 _fee, uint32 _twapInterval, uint8 _decimals
            CurrentPrice = twapGetter.convertToHumanReadable(UNIV3FACTORY, AllBets[_betNumber].betAddresses.OracleAddressMain,
                AllBets[_betNumber].betAddresses.OracleAddress2, AllBets[_betNumber].UniswapFeePool, uint32(60), _token0Decimals);
        }
        return CurrentPrice;
    }
}
