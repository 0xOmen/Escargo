// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.0 <0.9.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.0.0/contracts/access/Ownable.sol";

contract OnChainAllowlistContract is Ownable {

    mapping(address => bool) public allowlist;

    /**
     * @notice Takes an array of addresses and adds each to allowlist
     */
    function addToAllowlist(address[] calldata toAddAddresses) 
    external onlyOwner
    {
        for (uint i = 0; i < toAddAddresses.length; i++) {
            allowlist[toAddAddresses[i]] = true;
        }
    }

    /**
     * @notice Takes an array of addresses and removes each from allowlist
     */
    function removeFromAllowlist(address[] calldata toRemoveAddresses)
    external onlyOwner
    {
        for (uint i = 0; i < toRemoveAddresses.length; i++) {
            delete allowlist[toRemoveAddresses[i]];
        }
    }

    /**
     * @notice Checks if _tokenAddress if on allowlist and 'true'; returns bool
     */
    function allowlistFunc(address _tokenAddress) public view returns (bool)
    {
        require(allowlist[_tokenAddress], "NOT_IN_ALLOWLIST");

        if(allowlist[_tokenAddress] == true){
            return(true);
        }else{return(false);}
    }
}
