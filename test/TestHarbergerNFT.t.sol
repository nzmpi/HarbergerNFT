//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/HarbergerNFT.sol";
import "./ExpensiveNFT.sol";
import {BadUser} from "./BadUser.sol";

contract TestHarbergerNFT is Test {
    Vm.Wallet deployer = vm.createWallet("deployer");
    address immutable user = makeAddr("user");
    address immutable anotherUser = makeAddr("another user");
    uint256 constant defaultPrice = 0.01 ether;
    uint256 constant taxRate = 1;
    uint256 constant userId = 1;

    function test_valid_deployment(uint256 maxAmount, uint256 defPrice, uint256 txRate) public {
        vm.skip(true);
        vm.assume(maxAmount > 0);
        txRate = bound(txRate, 0, 10000);
        vm.prank(deployer.addr);
        HarbergerNFT hNFT = new HarbergerNFT(maxAmount, defPrice, txRate);

        assertEq(hNFT.DEPLOYER(), deployer.addr, "Wrong deployer");
        assertEq(hNFT.DEFAULT_PRICE(), defPrice, "Wrong default price");
        assertEq(hNFT.TAX_RATE(), txRate, "Wrong tax rate");
    }

    function test_valid_mint_one() public {
        vm.skip(false);
        uint256 maxAmount = 100;
        vm.prank(deployer.addr);
        HarbergerNFT hNFT = new HarbergerNFT(maxAmount, defaultPrice, taxRate);

        vm.expectEmit();
        emit HarbergerNFT.Minted(user, userId - 1);

        hoax(user, 2 * defaultPrice);
        uint256 tokenId = hNFT.mint{value: user.balance}(
            _getSignature(user, userId, address(hNFT)),
            userId,
            uint128(3 * defaultPrice)
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

        vm.warp(block.timestamp + timeLeft);
        (
            owner,
            currentPrice,
            depositLeft,
            timeLeft
        ) = hNFT.getTokenInfo(tokenId);

        assertEq(owner, user, "Wrong owner after time skip");
        assertEq(currentPrice, defaultPrice, "Wrong current price after time skip");
        assertEq(depositLeft, 0, "Wrong deposit left after time skip");
        assertEq(timeLeft, 0, "Wrong time left after time skip");
    }

    function test_valid_mint_two() public {
        vm.skip(false);
        uint256 maxAmount = 100;
        vm.prank(deployer.addr);
        HarbergerNFT hNFT = new HarbergerNFT(maxAmount, defaultPrice, taxRate);

        hoax(user, 2 * defaultPrice);
        uint256 tokenId = hNFT.mint{value: user.balance}(
            _getSignature(user, userId + 90, address(hNFT)),
            userId + 90,
            uint128(3*defaultPrice)
        );

        hoax(anotherUser, 2 * defaultPrice);
        uint256 anotherTokenId = hNFT.mint{value: defaultPrice}(
            _getSignature(anotherUser, userId + 42, address(hNFT)),
            userId + 42,
            uint128(5)
        );

        (
            address owner,
            uint256 currentPrice,
            uint256 depositLeft,
            uint256 timeLeft
        ) = hNFT.getTokenInfo(tokenId);

        assertEq(owner, user, "Wrong owner");
        assertEq(user.balance, 0, "Wrong user balance");
        assertEq(currentPrice, 3 * defaultPrice, "Wrong current price");
        assertEq(depositLeft, defaultPrice, "Wrong deposit left");
        assertEq(timeLeft, 10512000000, "Wrong time left");

        (
            address anotherOwner,
            uint256 anotherCurrentPrice,
            uint256 anotherDepositLeft,
            uint256 anotherTimeLeft
        ) = hNFT.getTokenInfo(anotherTokenId);

        assertEq(anotherOwner, anotherUser, "Wrong another owner");
        assertEq(anotherUser.balance, defaultPrice, "Wrong another user balance");
        assertEq(anotherCurrentPrice, defaultPrice, "Wrong another current price");
        assertEq(anotherDepositLeft, 0, "Wrong another deposit left");
        assertEq(anotherTimeLeft, 0, "Wrong another time left");
    }

    function test_gasUsage_one_mint() public {
        vm.skip(false);
        uint256 maxAmount = 10;

        vm.startPrank(deployer.addr);
        HarbergerNFT hNFT = new HarbergerNFT(maxAmount, defaultPrice, taxRate);
        ExpensiveNFT eNFT = new ExpensiveNFT(maxAmount, defaultPrice, taxRate);
        vm.stopPrank();

        hoax(user, 2 * defaultPrice);
        uint256 gasBefore = gasleft();
        hNFT.mint{value: user.balance}(
            _getSignature(user, userId, address(hNFT)),
            userId,
            uint128(3 * defaultPrice)
        );
        uint256 gasSpentHNFT = gasBefore - gasleft();

        hoax(user, 2 * defaultPrice);
        gasBefore = gasleft();
        eNFT.mint{value: user.balance}(
            _getSignature(user, userId, address(eNFT)),
            userId,
            uint128(3 * defaultPrice)
        );
        uint256 gasSpentENFT = gasBefore - gasleft();

        // should be at least 20% cheaper 
        assertLe(gasSpentHNFT * 100 / gasSpentENFT, 80, "Wrong gas usage");

        console.log("hNFT:", gasSpentHNFT);
        console.log("eNFT:", gasSpentENFT);

        console.log("%%:", gasSpentHNFT * 100 / gasSpentENFT);
    }

    function test_gasUsage_10000_mint() public {
        vm.skip(false);
        uint256 maxAmount = 10000;

        vm.startPrank(deployer.addr);
        uint256 gasBefore = gasleft();
        HarbergerNFT hNFT = new HarbergerNFT(maxAmount, defaultPrice, taxRate);
        uint256 gasSpentHNFT = gasBefore - gasleft();
        gasBefore = gasleft();
        ExpensiveNFT eNFT = new ExpensiveNFT(maxAmount, defaultPrice, taxRate);
        uint256 gasSpentENFT = gasBefore - gasleft();
        vm.stopPrank();

        for (uint256 i; i < 10000; ++i) {
            hoax(user, 2 * defaultPrice);
            gasBefore = gasleft();
            hNFT.mint{value: user.balance}(
                _getSignature(user, i, address(hNFT)),
                i,
                uint128(3 * defaultPrice)
            );
            gasSpentHNFT += gasBefore - gasleft();
        }
        
        for (uint256 i; i < 10000; ++i) {
            hoax(user, 2 * defaultPrice);
            gasBefore = gasleft();
            eNFT.mint{value: user.balance}(
                _getSignature(user, i, address(eNFT)),
                i,
                uint128(3 * defaultPrice)
            );
            gasSpentENFT += gasBefore - gasleft();
        }

        // should be at least 20% cheaper 
        assertLe(gasSpentHNFT * 100 / gasSpentENFT, 80, "Wrong gas usage");

        console.log("hNFT:", gasSpentHNFT);
        console.log("eNFT:", gasSpentENFT);

        console.log("%%:", gasSpentHNFT * 100 / gasSpentENFT);
    }

    function test_buy() public {
        vm.skip(false);
        vm.warp(1); // reset time

        uint256 maxAmount = 6000;
        uint256 defPrice = 1 ether;
        uint256 txRate = 100;

        vm.prank(deployer.addr);
        HarbergerNFT hNFT = new HarbergerNFT(maxAmount, defPrice, txRate);        

        hoax(user, 5 * defPrice);
        uint256 tokenId = hNFT.mint{value: user.balance}(
            _getSignature(user, userId, address(hNFT)),
            userId,
            uint128(10 * defPrice)
        );

        (,,, uint256 timeLeft) = hNFT.getTokenInfo(tokenId);
        // skip half of the payed time
        vm.warp(block.timestamp + timeLeft / 2);

        vm.expectEmit();
        emit HarbergerNFT.Bought(anotherUser, tokenId);

        hoax(anotherUser, 11 * defPrice);
        hNFT.buy{value: anotherUser.balance}(tokenId, uint128(5 * defPrice));

        (
            address owner,
            uint256 currentPrice,
            uint256 depositLeft,
        ) = hNFT.getTokenInfo(tokenId);

        assertEq(owner, anotherUser, "Wrong owner");
        assertEq(user.balance, (10 + 4 / 2) * defPrice, "Wrong user balance");
        assertEq(currentPrice, 5 * defPrice, "Wrong current price");
        assertEq(depositLeft, defPrice, "Wrong deposit left");

        // skip to time when deposit is 0
        vm.warp(block.timestamp + timeLeft);
        vm.prank(user);
        hNFT.buy{value: 2 * defPrice}(tokenId, uint128(100 * defPrice));

        (
            owner,
            currentPrice,
            depositLeft,
            timeLeft
        ) = hNFT.getTokenInfo(tokenId);

        assertEq(owner, user, "Wrong owner 2");
        assertEq(anotherUser.balance, 0, "Wrong another user balance");
        assertEq(currentPrice, 100 * defPrice, "Wrong current price 2");
        assertEq(depositLeft, defPrice, "Wrong deposit left 2");
        assertEq(timeLeft, 3153600, "Wrong time left");
    }

    function test_setPrice() public {
        vm.skip(false);
        vm.warp(1); // reset time

        uint256 maxAmount = 666;
        vm.prank(deployer.addr);
        HarbergerNFT hNFT = new HarbergerNFT(maxAmount, defaultPrice, taxRate);
      
        hoax(user, 4 * defaultPrice);
        uint256 tokenId = hNFT.mint{value: user.balance}(
            _getSignature(user, userId, address(hNFT)),
            userId,
            uint128(5 * defaultPrice)
        );

        (
            address owner,
            uint256 currentPrice,
            uint256 depositLeft,
            uint256 timeLeft
        ) = hNFT.getTokenInfo(tokenId);

        vm.warp(block.timestamp + timeLeft / 2);
        vm.prank(user);
        hNFT.setPrice(tokenId, uint128(10 * defaultPrice));

        (
            owner,
            currentPrice,
            depositLeft,
            timeLeft
        ) = hNFT.getTokenInfo(tokenId);

        assertEq(owner, user, "Wrong owner");
        assertEq(currentPrice, 10 * defaultPrice, "Wrong current price");
        assertEq(depositLeft, 0.015 ether, "Wrong deposit left");
        assertEq(timeLeft, 4730400000, "Wrong time left");

        vm.warp(block.timestamp + timeLeft);
        vm.prank(user);
        hNFT.setPrice(tokenId, uint128(100 * defaultPrice));

        (
            ,
            currentPrice,
            depositLeft,
            timeLeft
        ) = hNFT.getTokenInfo(tokenId);

        assertEq(currentPrice, defaultPrice, "Wrong current price 2");
        assertEq(depositLeft, 0, "Wrong deposit left 2");
        assertEq(timeLeft, 0, "Wrong time left 2");
    }

    function test_deposit_and_withdraw() public {
        vm.skip(false);
        vm.warp(1); // reset time

        uint256 maxAmount = 42;
        vm.prank(deployer.addr);
        HarbergerNFT hNFT = new HarbergerNFT(maxAmount, defaultPrice, taxRate);
      
        hoax(user, 3 * defaultPrice);
        uint256 tokenId = hNFT.mint{value: 2 * defaultPrice}(
            _getSignature(user, userId, address(hNFT)),
            userId,
            uint128(5 * defaultPrice)
        );

        vm.expectEmit();
        emit HarbergerNFT.Deposited(user, tokenId, defaultPrice);

        vm.prank(user);
        hNFT.deposit{value: defaultPrice}(tokenId);

        (
            address owner,
            uint256 currentPrice,
            uint256 depositLeft,
            uint256 timeLeft
        ) = hNFT.getTokenInfo(tokenId);

        assertEq(owner, user, "Wrong owner");
        assertEq(currentPrice, 5 * defaultPrice, "Wrong current price");
        assertEq(depositLeft, 2 * defaultPrice, "Wrong deposit left");
        assertEq(timeLeft, 12614400000, "Wrong time left");
        assertEq(
            address(hNFT).balance,
            3 * defaultPrice,
            "Wrong contract balance"
        );

        hoax(anotherUser, 10 ether);
        hNFT.deposit{value: anotherUser.balance}(tokenId);

        (
            owner,
            currentPrice,
            depositLeft,
            timeLeft
        ) = hNFT.getTokenInfo(tokenId);

        assertEq(owner, user, "Wrong owner 2");
        assertEq(currentPrice, 5 * defaultPrice, "Wrong current price 2");
        assertEq(depositLeft, 2 * defaultPrice + 10 ether, "Wrong deposit left 2");
        assertEq(timeLeft, 6319814400000, "Wrong time left 2");
        assertEq(
            address(hNFT).balance,
            3 * defaultPrice + 10 ether,
            "Wrong contract balance 2"
        );

        vm.expectEmit();
        emit HarbergerNFT.Withdrawn(user, tokenId, 5 ether);

        vm.warp(block.timestamp + timeLeft / 2);
        vm.prank(user);
        hNFT.withdraw(tokenId, 5 ether);

        (
            owner,
            currentPrice,
            depositLeft,
            timeLeft
        ) = hNFT.getTokenInfo(tokenId);

        assertEq(owner, user, "Wrong owner 3");
        assertEq(currentPrice, 5 * defaultPrice, "Wrong current price 3");
        assertEq(depositLeft, defaultPrice, "Wrong deposit left 3");
        assertEq(timeLeft, 6307200000, "Wrong time left 3");
        assertEq(
            address(hNFT).balance,
            3 * defaultPrice + 5 ether,
            "Wrong contract balance 3"
        );
    }

    function test_invalid_signer() public {
        vm.skip(false);
        uint256 maxAmount = 10000;

        vm.prank(deployer.addr);
        HarbergerNFT hNFT = new HarbergerNFT(maxAmount, defaultPrice, taxRate);

        deployer = vm.createWallet("fake deployer");
        hoax(user, 2 * defaultPrice);
        vm.expectRevert(HarbergerNFT.InvalidSignature.selector);
        hNFT.mint{value: user.balance}(
            _getSignature(user, userId, address(hNFT)),
            userId,
            uint128(3 * defaultPrice)
        );
    }

    function test_invalid_sig_message() public {
        vm.skip(false);
        uint256 maxAmount = 3000;

        vm.prank(deployer.addr);
        HarbergerNFT hNFT = new HarbergerNFT(maxAmount, defaultPrice, taxRate);
        
        bytes32 messageHash = keccak256(bytes.concat(
            "\x19Ethereum Signed Message:\n",
            "96",
            bytes32(bytes20(user)),
            bytes32(userId),
            bytes32(bytes20(address(hNFT)))
        ));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployer.privateKey, messageHash);
        bytes memory signature = bytes.concat(r, s, bytes1(v));

        hoax(user, 2 * defaultPrice);
        vm.expectRevert(HarbergerNFT.InvalidSignature.selector);
        hNFT.mint{value: user.balance}(
            signature,
            userId,
            uint128(3 * defaultPrice)
        );
    }

    function test_invalid_receiver() public {
        vm.skip(false);
        uint256 maxAmount = 7000;

        vm.prank(deployer.addr);
        HarbergerNFT hNFT = new HarbergerNFT(maxAmount, defaultPrice, taxRate);

        hoax(user, 2 * defaultPrice);
        vm.expectRevert(HarbergerNFT.InvalidSignature.selector);
        hNFT.mint{value: user.balance}(
            _getSignature(anotherUser, userId, address(hNFT)),
            userId,
            uint128(3 * defaultPrice)
        );
    }

    function test_invalid_userId() public {
        vm.skip(false);
        uint256 maxAmount = 7000;

        vm.prank(deployer.addr);
        HarbergerNFT hNFT = new HarbergerNFT(maxAmount, defaultPrice, taxRate);

        hoax(user, 2 * defaultPrice);
        vm.expectRevert(HarbergerNFT.InvalidSignature.selector);
        hNFT.mint{value: user.balance}(
            _getSignature(user, userId + 1, address(hNFT)),
            userId,
            uint128(3 * defaultPrice)
        );

        hoax(user, 2 * defaultPrice);
        vm.expectRevert(HarbergerNFT.InvalidMint.selector);
        hNFT.mint{value: user.balance}(
            _getSignature(user, maxAmount + 1, address(hNFT)),
            maxAmount + 1,
            uint128(3 * defaultPrice)
        );
    }

    function test_invalid_double_mint() public {
        vm.skip(false);
        uint256 maxAmount = 700;

        vm.prank(deployer.addr);
        HarbergerNFT hNFT = new HarbergerNFT(maxAmount, defaultPrice, taxRate);

        hoax(user, 2 * defaultPrice);
        hNFT.mint{value: user.balance}(
            _getSignature(user, userId, address(hNFT)),
            userId,
            uint128(3 * defaultPrice)
        );

        hoax(user, 2 * defaultPrice);
        vm.expectRevert(HarbergerNFT.InvalidMint.selector);
        hNFT.mint{value: user.balance}(
            _getSignature(user, userId, address(hNFT)),
            userId,
            uint128(3 * defaultPrice)
        );
    }

    function test_invalid_buy() public {
        vm.skip(false);
        uint256 maxAmount = 7;

        vm.prank(deployer.addr);
        HarbergerNFT hNFT = new HarbergerNFT(maxAmount, defaultPrice, taxRate);

        hoax(user, 2 * defaultPrice);
        vm.expectRevert(HarbergerNFT.NotMinted.selector);
        hNFT.buy{value: 2 * defaultPrice}(1, uint128(2 * defaultPrice));
    }

    function test_invalid_reentry() public {
        vm.skip(false);
        uint256 maxAmount = 777;

        vm.prank(deployer.addr);
        HarbergerNFT hNFT = new HarbergerNFT(maxAmount, defaultPrice, taxRate);

        BadUser bUser = new BadUser{value: 1 ether}(hNFT);
        uint256 tokenId = bUser.mint(
            _getSignature(address(bUser), userId, address(hNFT)),
            userId,
            uint128(defaultPrice)
        );

        hoax(anotherUser, defaultPrice);
        hNFT.buy{value: anotherUser.balance}(tokenId, uint128(2 * defaultPrice));
        
        assertEq(address(bUser).balance, 0, "Wrong balance");
    }

    function test_invalid_setPrice() public {
        vm.skip(false);
        uint256 maxAmount = 8888;

        vm.prank(deployer.addr);
        HarbergerNFT hNFT = new HarbergerNFT(maxAmount, defaultPrice, taxRate);

        vm.expectRevert(HarbergerNFT.NotOwner.selector);
        vm.prank(anotherUser);
        hNFT.setPrice(0, uint128(2 * defaultPrice));

        hoax(user, 2 * defaultPrice);
        uint256 tokenId = hNFT.mint{value: user.balance}(
            _getSignature(user, userId, address(hNFT)),
            userId,
            uint128(defaultPrice)
        );

        vm.expectRevert(HarbergerNFT.NotOwner.selector);
        vm.prank(anotherUser);
        hNFT.setPrice(tokenId, uint128(2 * defaultPrice));
    }

    function test_invalid_deposit() public {
        vm.skip(false);
        uint256 maxAmount = 9;

        vm.prank(deployer.addr);
        HarbergerNFT hNFT = new HarbergerNFT(maxAmount, defaultPrice, taxRate);

        vm.expectRevert(HarbergerNFT.NotMinted.selector);
        hoax(user, 2 * defaultPrice);
        hNFT.deposit{value: user.balance}(0);
    }

    function test_invalid_withdraw() public {
        vm.skip(false);
        uint256 maxAmount = 100000;

        vm.prank(deployer.addr);
        HarbergerNFT hNFT = new HarbergerNFT(maxAmount, defaultPrice, taxRate);
        BadUser bUser = new BadUser{value: 2 * defaultPrice}(hNFT);

        vm.expectRevert(HarbergerNFT.NotOwner.selector);
        bUser.withdraw(0, 1 ether);

        uint256 tokenId = bUser.mint(
            _getSignature(address(bUser), userId, address(hNFT)),
            userId,
            uint128(5 * defaultPrice)
        );

        vm.expectRevert(HarbergerNFT.InsufficientFunds.selector);
        bUser.withdraw(tokenId, 10 ether);

        vm.deal(address(hNFT), 10 ether);
        vm.expectRevert(HarbergerNFT.InsufficientFunds.selector);
        bUser.withdraw(tokenId, 10 ether);

        vm.expectRevert(HarbergerNFT.InvalidSend.selector);
        bUser.withdraw(tokenId, defaultPrice);
    }

    function _getSignature(
        address _receiver,
        uint256 _userId,
        address _contract
    ) internal view returns(bytes memory) {
        bytes32 messageHash = keccak256(bytes.concat(
            "\x19Ethereum Signed Message:\n",
            "72",
            bytes20(_receiver),
            bytes32(_userId),
            bytes20(_contract)
        ));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployer.privateKey, messageHash);
        return bytes.concat(r, s, bytes1(v));
    }
}
