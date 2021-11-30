// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

abstract contract IERC721Full is IERC721, IERC721Enumerable, IERC721Metadata {}

contract DistributorV1 is Ownable, ReentrancyGuard {
    IERC721Full nftContract;

    uint256 constant TOTAL_NFTS_COUNT = 10000;

    mapping(uint256 => uint256) public givenRewards;
    uint256 public totalGivenRewardsPerToken = 0;
    bool public isFrozen = false;

    constructor(address nft_address) {
        nftContract = IERC721Full(nft_address);
    }

    function freeze() external onlyOwner {
        isFrozen = true;
    }

    function unfreeze() external onlyOwner {
        isFrozen = false;
    }

    function getGivenRewardsPerToken(uint256 from, uint256 length)
        external
        view
        returns (uint256[] memory rewards)
    {
        if (from + length > TOTAL_NFTS_COUNT) {
            length = TOTAL_NFTS_COUNT - from;
        }

        uint256[] memory _givenRewards = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            _givenRewards[i] = givenRewards[i];
        }
        return _givenRewards;
    }

    function deposit() external payable {
        require(!isFrozen, "Distributor is frozen.");
        totalGivenRewardsPerToken +=
            (msg.value * 10_000) /
            TOTAL_NFTS_COUNT /
            10_000;
    }

    function getAddressRewards(address owner)
        external
        view
        returns (uint256 amount)
    {
        uint256 numTokens = nftContract.balanceOf(owner);
        uint256 rewards = 0;

        for (uint256 i = 0; i < numTokens; i++) {
            uint256 tokenId = nftContract.tokenOfOwnerByIndex(owner, i);
            if (tokenId < TOTAL_NFTS_COUNT) {
                rewards += totalGivenRewardsPerToken - givenRewards[tokenId];
            }
        }

        return rewards;
    }

    function getTokensRewards(uint256[] calldata tokenIds)
        external
        view
        returns (uint256 amount)
    {
        uint256 numTokens = tokenIds.length;
        uint256 rewards = 0;

        // Rewards of tokens owned by the sender
        for (uint256 i = 0; i < numTokens; i++) {
            uint256 tokenId = tokenIds[i];
            if (tokenId < TOTAL_NFTS_COUNT) {
                rewards += totalGivenRewardsPerToken - givenRewards[tokenId];
            }
        }

        return rewards;
    }

    function claimRewardsRange(uint256 from, uint256 length) external {
        require(!isFrozen, "Distributor is frozen.");
        uint256 numTokens = nftContract.balanceOf(msg.sender);
        require(from + length <= numTokens, "Out of index");

        uint256 rewards = 0;

        // Rewards of tokens owned by the sender
        for (uint256 i = 0; i < length; i++) {
            uint256 tokenId = nftContract.tokenOfOwnerByIndex(
                msg.sender,
                i + from
            );
            if (tokenId < TOTAL_NFTS_COUNT) {
                rewards += totalGivenRewardsPerToken - givenRewards[tokenId];
                givenRewards[tokenId] = totalGivenRewardsPerToken;
            }
        }

        payable(msg.sender).transfer(rewards);
    }

    function claimRewards() external {
        require(!isFrozen, "Distributor is frozen.");

        uint256 numTokens = nftContract.balanceOf(msg.sender);
        uint256 rewards = 0;

        // Rewards of tokens owned by the sender
        for (uint256 i = 0; i < numTokens; i++) {
            uint256 tokenId = nftContract.tokenOfOwnerByIndex(msg.sender, i);
            if (tokenId < TOTAL_NFTS_COUNT) {
                rewards += totalGivenRewardsPerToken - givenRewards[tokenId];
                givenRewards[tokenId] = totalGivenRewardsPerToken;
            }
        }

        payable(msg.sender).transfer(rewards);
    }

    function emergencyWithdraw() external onlyOwner {
        payable(_msgSender()).transfer(address(this).balance);
    }
}
