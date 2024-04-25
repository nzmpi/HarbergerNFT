//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title HarbergerNFT
 * @notice This contract is an example of an ERC721 token,
 * that implements the Harberger tax and a cheap mass minting feature.
 */
contract HarbergerNFT {
    // keccak256(abi.encode(uint256(keccak256("LIST_SLOT")) - 1)) & ~bytes32(uint256(0xff))
    uint256 constant LIST_SLOT = 36774421528551533216570696737164983923400338544039802950506299840970426934528;
    uint256 constant ONE_YEAR = 365 days;
    uint256 public immutable DEFAULT_PRICE;
    address public immutable DEPLOYER;
    // 1 == 0.1%
    uint256 public immutable TAX_RATE;
    uint256 _totalSupply;

    /**
     * @notice Token information
     * @param deposit The amount of ETH deposited to pay for tax
     * @param price The price of the token
     * @param priceTime The timestamp of the last price change
     * @param owner The owner of the token
     */
    struct TokenInfo {
        uint128 deposit;
        uint128 price;
        uint96 priceTime;
        address owner;
    }

    mapping(uint256 tokenId => TokenInfo) _tokenInfos;

    error InsufficientFunds();
    error InvalidMint();
    error InvalidSend();
    error InvalidSignature();
    error NotMinted();
    error NotOwner();
    error Reentry();

    event Bought(address indexed newOwner, uint256 indexed tokenId);
    event Deposited(address indexed donor, uint256 indexed tokenId, uint256 amount);
    event Minted(address indexed newOwner, uint256 indexed tokenId);
    event Withdrawn(address indexed sender, uint256 indexed tokenId, uint256 amount);

    /**
     * @notice A modifier that prevents reentrancies
     * @dev Uses transient storage to make it cheaper
     */
    modifier guard() {
        assembly {
            if eq(tload(0), 1) {
                // Reentry.selector
                mstore(0, 0x976f9b8400000000000000000000000000000000000000000000000000000000)
                revert(0, 4)
            }
            tstore(0, 1)
        }
        _;
        assembly {
            tstore(0, 0)
        }
    }

    /**
     * @notice Prepares the contract by filling the storage with
     * _maxAmount of bits
     * @param _maxAmount The maximum amount of tokens
     * @param _defaultPrice The default price
     * @param _taxRate The tax rate
     */
    constructor(uint256 _maxAmount, uint256 _defaultPrice, uint256 _taxRate) payable {
        require(_maxAmount > 0);
        DEPLOYER = msg.sender;
        DEFAULT_PRICE = _defaultPrice;
        TAX_RATE = _taxRate;

        uint256 len = _maxAmount / 256;
        uint256 slotNumber = LIST_SLOT;
        uint256 value = type(uint256).max;
        for (uint256 i; i < len; ++i) {
            assembly {
                sstore(slotNumber, value)
            }
            ++slotNumber;
        }

        len = _maxAmount % 256;
        if (len != 0) {
            value = 1;
            for (uint256 i; i < len; ++i) {
                value = (value << 1) | 1;
            }
            assembly {
                sstore(slotNumber, value)
            }
        }
    }

    /**
     * @notice Mint a new token
     * @param signature The signature signed by the deployer
     * @param userId The id of the user
     * @param newPrice The new price of a minted token
     * @return tokenId The id of the new token
     */
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

    /**
     * @notice Buy a minted token
     * @param tokenId The id of the token
     * @param newPrice The new price of the token
     */
    function buy(uint256 tokenId, uint128 newPrice) external payable guard {
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

        // Transfer ETH to the old owner
        // Does not revert if the transfer fails
        // to prevent a DoS attack
        if (oldOwnerAmount > 0) {
            (bool s,) = oldOwner.call{value: oldOwnerAmount}("");
            s; // remove unused warning
        }

        emit Bought(msg.sender, tokenId);
    }

    /**
     * @notice The owner can set the price of their token
     * @param tokenId The id of the token
     * @param newPrice The new price
     */
    function setPrice(uint256 tokenId, uint128 newPrice) external guard {
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

    /**
     * @notice Anyone can deposit ETH to a minted token
     * @param tokenId The id of the token
     */
    function deposit(uint256 tokenId) external payable guard {
        if (_tokenInfos[tokenId].owner == address(0)) revert NotMinted();
        _tokenInfos[tokenId].deposit += uint128(msg.value);
        emit Deposited(msg.sender, tokenId, msg.value);
    }

    /**
     * @notice The owner can withdraw ETH from their token deposit minus tax
     * @param tokenId The id of the token
     * @param amount The amount to withdraw
     */
    function withdraw(uint256 tokenId, uint256 amount) external guard {
        TokenInfo storage info = _tokenInfos[tokenId];
        if (msg.sender != info.owner) revert NotOwner();

        uint256 balance = info.deposit;
        uint256 taxToPay = _calculateTax(info.price, info.priceTime);
        if (taxToPay < balance) {
            unchecked {
                uint256 fundsLeft = balance - taxToPay;
                if (fundsLeft < amount) revert InsufficientFunds();

                info.deposit = uint128(balance - amount);
                (bool s,) = msg.sender.call{value: amount}("");
                if (!s) revert InvalidSend();
            }
        } else {
            revert InsufficientFunds();
        }

        emit Withdrawn(msg.sender, tokenId, amount);
    }

    /**
     * @notice Get information about a token
     * @param tokenId The id of the token
     * @return owner The owner of the token
     * @return price The price of the token
     * @return depositLeft The amount of ETH left in the deposit minus tax
     * @return timeLeft The ownership time left that is covered by the deposit
     */
    function getTokenInfo(uint256 tokenId)
        external
        view
        returns (address owner, uint256 price, uint256 depositLeft, uint256 timeLeft)
    {
        TokenInfo storage info = _tokenInfos[tokenId];
        depositLeft = info.deposit;
        price = info.price;
        uint256 taxToPay = _calculateTax(price, info.priceTime);
        owner = info.owner;
        if (taxToPay < depositLeft) {
            unchecked {
                timeLeft = ((depositLeft - taxToPay) * ONE_YEAR * 1000) / (price * TAX_RATE);
                depositLeft -= taxToPay;
            }
        } else {
            price = DEFAULT_PRICE;
            depositLeft = 0;
        }
    }

    /**
     * @notice Check if the signature is valid
     * @param _signature The signature
     * @param _userId The id of the user
     * @return true if the signature is valid, false otherwise
     */
    function _isSigValid(bytes calldata _signature, uint256 _userId) internal view returns (bool) {
        (bytes32 r, bytes32 s, uint8 v) = _splitSignature(_signature);
        bytes32 messageHash = keccak256(
            bytes.concat(
                "\x19Ethereum Signed Message:\n", "72", bytes20(msg.sender), bytes32(_userId), bytes20(address(this))
            )
        );

        // DEPLOYER is by default non-zero
        return DEPLOYER == ecrecover(messageHash, v, r, s);
    }

    /**
     * @notice Check if the user has minted and update the list
     * @param _userId The id of the user
     */
    function _verifyMint(uint256 _userId) internal {
        unchecked {
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
    }

    /**
     * @notice Split the signature
     * @dev Using calldata instead of memory to reduce gas usage
     */
    function _splitSignature(bytes calldata) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        r = bytes32(msg.data[132:164]);
        s = bytes32(msg.data[164:196]);
        v = uint8(bytes1(msg.data[196:204]));
    }

    /**
     * @notice Calculate the tax
     * @param _price The price of the token
     * @param _priceTime The price time
     * @return The tax
     */
    function _calculateTax(uint256 _price, uint256 _priceTime) internal view returns (uint256) {
        // TAX_RATE = 1000 == 100%
        return (_price * TAX_RATE * (block.timestamp - _priceTime)) / (ONE_YEAR * 1000);
    }

    // other ERC721 functions
}
