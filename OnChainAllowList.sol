// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.0 <0.9.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.0.0/contracts/access/Ownable.sol";

contract OnChainAllowlistContract is Ownable {

    mapping(address => bool) public allowlist;

    /**
     * @notice Add to whitelist
     */
    function addToAllowlist(address[] calldata toAddAddresses) 
    external onlyOwner
    {
        for (uint i = 0; i < toAddAddresses.length; i++) {
            allowlist[toAddAddresses[i]] = true;
        }
    }

    /**
     * @notice Remove from whitelist
     */
    function removeFromAllowlist(address[] calldata toRemoveAddresses)
    external onlyOwner
    {
        for (uint i = 0; i < toRemoveAddresses.length; i++) {
            delete allowlist[toRemoveAddresses[i]];
        }
    }

    /**
     * @notice Function with whitelist
     */
    function allowlistFunc() public view
    {
        require(allowlist[msg.sender], "NOT_IN_ALLOWLIST");

        // Do some useful stuff
    }
}
