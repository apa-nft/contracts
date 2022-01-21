// SPDX-License-Identifier: Unlicense
pragma solidity  ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract ERC721Mock is ERC721 {
    constructor(string memory name, string memory symbol)
        ERC721(name, symbol)
    {} // solhint-disable-line

    function mint(uint256 tokenId) external {
        _mint(msg.sender, tokenId);
    }
}
