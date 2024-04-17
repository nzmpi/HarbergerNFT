//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../src/HarbergerNFT.sol";

contract BadUser {
    HarbergerNFT immutable hNFT;
    uint256 tknId;
    
    constructor(HarbergerNFT _hNFT) payable {
        hNFT = _hNFT;
    }
    
    function mint(
        bytes calldata signature,
        uint256 userId,
        uint128 newPrice
    ) external returns (uint256 tokenId) {
        tokenId = hNFT.mint{value: address(this).balance}(signature, userId, newPrice);
        tknId = tokenId;
    }

    receive() external payable {
        hNFT.deposit{value: 1}(tknId);
    }
}