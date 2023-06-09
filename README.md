# Escargo
Smart Contract to escrow user defined bets and other data

Users can define an oracle using either Chainlink feeds or UniswapV3 oracles.  If the items being compared do not have a direct oracle then two oracles of the same type (e.g. both Chainlink or both Uniswap) can be defined.  For example, to compare price of Token A vs Token B where no A/B oracle exists, a user can queiry Uniswap oracles A/WETH and B/WETH.  Until a front-end is built, users must be very careful how they define A/B prices and oracles.

### DEFINITIONS
**Maker** - bet/escrow creator  
**Taker** - user who accepts terms of a bet/escrow  
**SkinToken** - Token used as collateral to settle a bet/escrow  
**PriceLine** - Price at which the bet/escrow is determined  

Currently any token can be used as the 'SkinToken' (collateral) in the bet however this will need to be limited in future versions as rebase tokens will negatively affect the account based system currently in use.  Both the 'Maker' and 'Taker' have to use the same SkinToken.

Currently, anyone can close a bet/escrow once all necessary chekcs are cleared.  

Maker can define taker address as "0x0000000000000000000000000000000000000000" allowing anyone to be Taker or they can limit it to a specific address.

The Escargo smart contract interfaces with a custom built UniV3TwapOracle smart contract to convert price to a human readable format and determine which token is the base token (aka Token0) in Uniswap pools.

### Contract Addresses - Sepolia
**UniV3TwapOracle** - 0xb255C27D27185aBe44Be0Cf25997AF1221DD6521

### Contracts - Goerli
**UniV3TwapOracle** - 0x20ad155ea921FeDb706126f7BdC18007fA55A4ff
