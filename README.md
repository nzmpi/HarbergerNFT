## HarbergerNFT

This is an experiment to create an NFT with [the Harberger Tax](https://en.wikipedia.org/wiki/Harberger_Tax)
and a cheap mass minting feature.

## How to use

The HarbergerNFT contract is in the `src` folder. And all tests are in the `test` folder.

To run tests use `forge test -vv` (you need to install
[Foundry](https://book.getfoundry.sh/getting-started/installation) first). 
To turn off some of the test functions change `vm.skip(false)` to `vm.skip(true)` and vice versa.

## How it works

- In `constructor(uint256 _maxAmount, uint256 _defaultPrice, uint256 _taxRate)` we save 
the deployer address, the default price and the tax rate. We also reserve `_maxAmount` of bits
in storage starting from [`LIST_SLOT`](https://github.com/nzmpi/HarbergerNFT/blob/master/src/HarbergerNFT.sol#L11),
which creates an "allowlist", where every bit corresponds to the position in the list.

- In `mint(bytes calldata signature, uint256 userId, uint128 newPrice)` users provide their 
`signature` with the corresponding `userId`, which is signed by the deployer off-chain. 
`userId` corresponds to the position in the allowlist. Then the contract checks if `signature` 
is valid and if the bit in the `userId` position equals `1`. If it is, it mints a token and 
updates the allowlist to avoid the signature replay attack. And finally, the contract 
updates the token info: the amount of ETH deposited to pay for tax, the new price, the time
when the price was changed, and the owner address.

- Using the `buy(uint256 tokenId, uint128 newPrice)` function any user can buy any minted token.
The price depends on the deposit left of the current owner. If the deposit left is less than
the tax owned, then the price is `DEFAULT_PRICE`. Otherwise, the price is the one set by
the owner. Then the contract updates the token info and sends ETH to the old owner.

- To change the price of a token owners can use the `setPrice(uint256 tokenId, uint128 newPrice)`
function. The contract will recalculate the deposit and update the token info.

- Any user can deposit ETH to a minted token using the `deposit(uint256 tokenId)` function. 
And only owners can withdraw ETH from their deposit using 
`withdraw(uint256 tokenId, uint256 amount)`. 

- To get the token info users can use the `getTokenInfo(uint256 tokenId)` function, which
will return the address of the owner, the price of the token, the deposit left (minus tax) and 
the time left (in seconds) until the price is set to the default one.

Additionally, the contract uses `transient` storage for the reentrancy guard. 

## TODO

Make it a proper ERC721 token, maybe add frontend.