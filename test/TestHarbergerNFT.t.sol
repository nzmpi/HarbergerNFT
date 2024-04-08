//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/HarbergerNFT.sol";

contract TestHarbergerNFT is Test {
    Vm.Wallet deployer = vm.createWallet("deployer");
    address user = makeAddr("user");

    function test_valid_deployment(uint256 maxAmount, uint256 defaultPrice, uint256 taxRate) public {
        vm.skip(true);
        vm.assume(maxAmount > 0);
        vm.prank(deployer.addr);
        HarbergerNFT hNFT = new HarbergerNFT(maxAmount, defaultPrice, taxRate);

        assertEq(hNFT.DEPLOYER(), deployer.addr, "Wrong deployer");
        assertEq(hNFT.DEFAULT_PRICE(), defaultPrice, "Wrong default price");
        assertEq(hNFT.TAX_RATE(), taxRate, "Wrong tax rate");
    }

    function test_valid_mint_one() public {
        vm.skip(false);

        uint256 maxAmount = 1;
        uint256 defaultPrice = 0.01 ether;
        uint256 userId = 1;
        vm.prank(deployer.addr);
        HarbergerNFT hNFT = new HarbergerNFT(maxAmount, defaultPrice, 1);

        hoax(user, 2*defaultPrice);
        uint256 tokenId = hNFT.mint{value: 2*defaultPrice}(
            _getSignature(user, userId),
            userId,
            uint128(3*defaultPrice)
        );

        (
            address owner,
            uint256 currentPrice,
            uint256 depositLeft,
            uint256 timeLeft
        ) = hNFT.getTokenInfo(tokenId);

        assertEq(owner, user, "Wrong owner");
        assertEq(currentPrice, 3 * defaultPrice, "Wrong current price");
        assertEq(depositLeft, defaultPrice, "Wrong deposit left");
        assertEq(timeLeft, 10512000000, "Wrong time left");
    }

    function _getSignature(
        address _receiver,
        uint256 _userId
    ) internal view returns(bytes memory) {
        bytes32 messageHash = keccak256(bytes.concat(
            "\x19Ethereum Signed Message:\n",
            "52",
            bytes20(_receiver),
            bytes32(_userId)
        ));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployer.privateKey, messageHash);
        return bytes.concat(r, s, bytes1(v));
    }
}
