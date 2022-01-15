// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract ERC721Mock is ERC721 {
    constructor(string memory name, string memory symbol)
        ERC721(name, symbol)
    {} // solhint-disable-line

    function mint(uint256 tokenId) external {
        _mint(msg.sender, tokenId);
    }
}