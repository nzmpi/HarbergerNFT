//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract ExpensiveNFT {
    uint256 public immutable DEFAULT_PRICE;
    address public immutable DEPLOYER;
    // 1 == 0.1%
    uint256 public immutable TAX_RATE;
    uint256 _totalSupply;

    struct TokenInfo {
        uint128 deposit;
        uint128 price;
        uint96 priceTime;
        address owner;
    }

    mapping(bytes signature => bool) _isUsed;
    mapping(uint256 tokenId => TokenInfo) _tokenInfos;

    error InsufficientFunds();
    error InvalidMint();
    error InvalidSignature();

    event Minted(address indexed newOwner, uint256 indexed tokenId);

    constructor(uint256 _maxAmount, uint256 _defaultPrice, uint256 _taxRate) payable {
        require(_maxAmount > 0);
        DEPLOYER = msg.sender;
        DEFAULT_PRICE = _defaultPrice;
        TAX_RATE = _taxRate;
    }

    function mint(bytes calldata signature, uint256 userId, uint128 newPrice)
        external
        payable
        returns (uint256 tokenId)
    {
        if (msg.value < DEFAULT_PRICE) revert InsufficientFunds();
        if (!_isSigValid(signature, userId)) revert InvalidSignature();
        if (_isUsed[signature]) revert InvalidMint();
        _isUsed[signature] = true;

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

    function _isSigValid(
        bytes calldata _signature,
        uint256 _userId
    ) internal view returns (bool) {
        (bytes32 r, bytes32 s, uint8 v) = _splitSignature(_signature);
        bytes32 messageHash = keccak256(bytes.concat(
            "\x19Ethereum Signed Message:\n",
            "72",
            bytes20(msg.sender),
            bytes32(_userId),
            bytes20(address(this))
        ));

        // DEPLOYER is by default non-zero
        return DEPLOYER == ecrecover(messageHash, v, r, s);
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
}
