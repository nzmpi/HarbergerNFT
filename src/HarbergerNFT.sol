//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract HarbergerNFT {
    uint256 constant ONE_YEAR = 365 days;
    // keccak256(abi.encode(uint256(keccak256("LIST.SLOT")) - 1)) & ~bytes32(uint256(0xff))
    uint256 constant LIST_SLOT = 5337290524970025835332862666762577392465496233594089120533011026829033552640;
    address public immutable DEPLOYER;
    uint256 public immutable DEFAULT_PRICE;
    // 1 == 0.1%
    uint256 public immutable TAX_RATE;
    uint256 _totalSupply;

    struct TokenInfo {
        uint128 deposit;
        uint128 price;
        uint96 priceTime;
        address owner;
    }

    mapping(uint256 tokenId => TokenInfo) _tokenInfos;

    error InsufficientFunds();
    error NotOwner();
    error InvalidMint();
    error InvalidSignature();
    error NotMinted();
    error Reentry();

    event Minted(address indexed newOwner, uint256 indexed tokenId);

    modifier lock() {
        uint256 isLocked;
        assembly {
            isLocked := tload(0)
        }
        if (isLocked != 0) revert Reentry();
        assembly {
            tstore(0, 1)
        }
        _;
        assembly {
            tstore(0, 0)
        }
    }

    constructor(uint256 _maxAmount, uint256 _defaultPrice, uint256 _taxRate) payable {
        require(_maxAmount > 0);
        DEPLOYER = msg.sender;
        DEFAULT_PRICE = _defaultPrice;
        TAX_RATE = _taxRate;

        uint256 len = _maxAmount / 256 + 1;
        uint256 slotNumber;
        uint256 max = type(uint256).max;
        for (uint256 i; i < len; ++i) {
            slotNumber = LIST_SLOT + i;
            assembly {
                sstore(slotNumber, max)
            }
        }
    }

    function mint(bytes calldata signature, uint256 userId, uint128 newPrice)
        external
        payable
        returns (uint256 tokenId)
    {
        if (msg.value < DEFAULT_PRICE) revert InsufficientFunds();
        if (!_isSigValid(signature, userId)) revert InvalidSignature();
        _verifyMint(userId);
        
        unchecked {
            tokenId = _totalSupply;
            TokenInfo storage info = _tokenInfos[tokenId];
            info.deposit = uint128(msg.value - DEFAULT_PRICE);
            info.price = newPrice;
            info.priceTime = uint96(block.timestamp);
            info.owner = msg.sender;
            ++_totalSupply;
        }

        emit Minted(msg.sender, tokenId);
    }

    function buy(uint256 tokenId, uint128 newPrice) external payable {
        TokenInfo storage info = _tokenInfos[tokenId];
        address oldOwner = info.owner;
        if (oldOwner == address(0)) revert NotMinted();
        uint256 balance = info.deposit;
        uint256 price = info.price;
        uint256 taxToPay = _calculateTax(price, info.priceTime);
        uint256 priceToSell;
        uint256 oldOwnerAmount;
        if (taxToPay < balance) {
            priceToSell = price;
            unchecked {
                oldOwnerAmount = balance - taxToPay + price;
            }
        } else {
            priceToSell = DEFAULT_PRICE;
        }

        if (msg.value < priceToSell) revert InsufficientFunds();
        info.owner = msg.sender;
        info.price = newPrice;
        info.priceTime = uint96(block.timestamp);
        info.deposit = uint128(msg.value - priceToSell);

        if (oldOwnerAmount > 0) {
            // TODO fix this
            (bool s,) = oldOwner.call{value: oldOwnerAmount}("");
            s;
        }
    }

    function setPrice(uint256 tokenId, uint128 newPrice) external {
        TokenInfo storage info = _tokenInfos[tokenId];
        if (msg.sender != info.owner) revert NotOwner();

        uint256 taxToPay = _calculateTax(info.price, info.priceTime);
        uint256 balance = info.deposit;
        if (taxToPay < balance) {
            unchecked {
                balance -= taxToPay;
            }
        } else {
            balance = 0;
        }

        info.deposit = uint128(balance);
        info.price = newPrice;
        info.priceTime = uint96(block.timestamp);
    }

    function deposit(uint256 tokenId) external payable {
        _tokenInfos[tokenId].deposit += uint128(msg.value);
    }

    //TODO: double check this
    function withdraw(uint256 tokenId, uint256 amount) external {
        TokenInfo storage info = _tokenInfos[tokenId];
        if (msg.sender != info.owner) revert NotOwner();

        uint256 balance = info.deposit;
        uint256 taxToPay = _calculateTax(info.price, info.priceTime);
        if (taxToPay < balance) {
            unchecked {
                uint256 fundsLeft = balance - taxToPay;
                if (fundsLeft < amount) revert InsufficientFunds();

                info.deposit = uint128(fundsLeft - amount);
                (bool s,) = msg.sender.call{value: amount}("");
                require(s, "Failed to send funds");
            }
        } else {
            revert InsufficientFunds();
        }
    }

    function getTokenInfo(uint256 tokenId) external view returns (
        address owner,
        uint256 currentPrice,
        uint256 depositLeft,
        uint256 timeLeft
    ) {
        TokenInfo storage info = _tokenInfos[tokenId];
        depositLeft = info.deposit;
        currentPrice = info.price;
        uint256 taxToPay = _calculateTax(currentPrice, info.priceTime);
        owner = info.owner;
        if (taxToPay < depositLeft) {
            unchecked {
                timeLeft =
                    ((depositLeft - taxToPay) * ONE_YEAR * 1000) / (currentPrice * TAX_RATE);
                depositLeft -= taxToPay;
            }
        } else {
            currentPrice = DEFAULT_PRICE;
            depositLeft = 0;
        }
    }

    function _isSigValid(
        bytes calldata _signature,
        uint256 _userId
    ) internal view returns (bool) {
        (bytes32 r, bytes32 s, uint8 v) = _splitSignature(_signature);
        bytes32 messageHash = keccak256(bytes.concat(
            "\x19Ethereum Signed Message:\n",
            "52", 
            bytes20(msg.sender),
            bytes32(_userId)
        ));

        // DEPLOYER is by default non-zero
        return DEPLOYER == ecrecover(messageHash, v, r, s);
    }

    function _verifyMint(uint256 _userId) internal {
        uint256 slotNumber = _userId / 256 + LIST_SLOT;
        uint256 offsetInSlot = _userId % 256;

        uint256 value;
        assembly {
            value := sload(slotNumber)
        }
 
        uint256 hasMinted = (value >> offsetInSlot) & 1;
        if (hasMinted == 0) revert InvalidMint();
        value &= ~(1 << offsetInSlot);

        assembly {
            sstore(slotNumber, value)
        }
    }
    
    function _splitSignature(bytes calldata) internal pure returns (
        bytes32 r,
        bytes32 s,
        uint8 v
    ) {
        r = bytes32(msg.data[132:164]);
        s = bytes32(msg.data[164:196]);
        v = uint8(bytes1(msg.data[196:204]));
    }

    function _calculateTax(uint256 _price, uint256 _priceTime) 
        internal
        view
        returns (uint256)
    {
        uint256 elapsedTime = block.timestamp - _priceTime;
        return (_price * TAX_RATE * elapsedTime) / (ONE_YEAR * 1000);
    }

    // other ERC721 functions
}