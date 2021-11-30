// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

abstract contract IERC721Full is IERC721, IERC721Enumerable, IERC721Metadata {}

interface IERC2981Royalties {
    function royaltyInfo(uint256 _tokenId, uint256 _value)
        external
        view
        returns (address _receiver, uint256 _royaltyAmount);
}

interface IDistributor {
    function deposit() external payable;
    function isFrozen() external returns (bool);
}

contract CollectionMarket is Ownable, ReentrancyGuard {
    IDistributor distributorInterface;

    IERC721Full[] public supportedTokens;
    IERC2981Royalties[] public IRoyalties;

    uint256 constant TOTAL_NFTS_COUNT = 10000;

    struct Collection {
        bool active;
        uint256 id;
        uint256[] tokenIds;
        uint256[] tokenTypes;
        uint256 price;
        uint256 activeIndex; // index where the collection id is located on activeCollections
        uint256 userActiveIndex; // index where the collection id is located on userActiveCollections
        address owner;
        string name;
    }

    struct Purchase {
        Collection collection;
        address buyer;
    }

    struct AccountingInfo {
        uint256 totalHolderCut;
        uint256 communityTotalCut;
        uint256 community_cut;
        uint256 market_cut;
    } 

    event FilledCollection(uint256 collectionId);

    Collection[] public collections;
    uint256[] public activeCollections; // list of collectionIDs which are active
    mapping(address => uint256[]) public userActiveCollections; // list of collectionIDs which are active
    uint256 public maxPerCollection = 10;

    uint256 public communityHoldings = 0;
    uint256 public communityFeePercent = 0;
    uint256 public marketFeePercent = 0;

    uint256 public totalVolume = 0;
    uint256 public totalSales = 0;
    uint256 public movedItems = 0;
    uint256 public highestSalePrice = 0;

    bool public isMarketOpen = false;
    bool public emergencyDelisting = false;

    constructor(
        address distributorAddress,
        uint256 dist_fee,
        uint256 market_fee
    ) {
        require(dist_fee <= 100, "Give a percentage value from 0 to 100");
        require(market_fee <= 100, "Give a percentage value from 0 to 100");

        distributorInterface = IDistributor(distributorAddress);

        communityFeePercent = dist_fee;
        marketFeePercent = market_fee;
    }

    function setMaxPerCollection(uint256 max) external onlyOwner {
        maxPerCollection = max;
    }

    function getSupportedTokens(uint256 from, uint256 length) external view returns (address[] memory) {
        uint256 numActive = supportedTokens.length;
        if (from + length > numActive) {
            length = numActive - from;
        }

        address[] memory tokens = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            tokens[i] = address(supportedTokens[from + i]);
        }
        return tokens;
    }

    function addSupportedToken(address token) external onlyOwner {
        supportedTokens.push(IERC721Full(token));
        IRoyalties.push(IERC2981Royalties(token));
    }

    function openMarket() external onlyOwner {
        isMarketOpen = true;
    }

    function closeMarket() external onlyOwner {
        isMarketOpen = false;
    }

    function allowEmergencyDelisting() external onlyOwner {
        emergencyDelisting = true;
    }

    function totalCollections() external view returns (uint256) {
        return collections.length;
    }

    function totalActiveCollections() external view returns (uint256) {
        return activeCollections.length;
    }

    function getActiveCollections(uint256 from, uint256 length)
        external
        view
        returns (Collection[] memory collection)
    {
        uint256 numActive = activeCollections.length;
        if (from + length > numActive) {
            length = numActive - from;
        }

        Collection[] memory _collections = new Collection[](length);
        for (uint256 i = 0; i < length; i++) {
            _collections[i] = collections[activeCollections[from + i]];
        }
        return _collections;
    }

    function removeActiveCollection(uint256 index) internal {
        uint256 numActive = activeCollections.length;

        require(numActive > 0, "There are no active collections");
        require(index < numActive, "Incorrect index");

        activeCollections[index] = activeCollections[numActive - 1];
        collections[activeCollections[index]].activeIndex = index;
        activeCollections.pop();
    }

    function removeOwnerActiveCollection(address _owner, uint256 index) internal {
        uint256 numActive = userActiveCollections[_owner].length;

        require(numActive > 0, "There are no active collections for this user.");
        require(index < numActive, "Incorrect index");

        userActiveCollections[_owner][index] = userActiveCollections[_owner][
            numActive - 1
        ];
        collections[userActiveCollections[_owner][index]].userActiveIndex = index;
        userActiveCollections[_owner].pop();
    }

    function getMyActiveCollectionsCount() external view returns (uint256) {
        return userActiveCollections[msg.sender].length;
    }

    function getMyActiveCollections(uint256 from, uint256 length)
        external
        view
        returns (Collection[] memory collection)
    {
        uint256 numActive = userActiveCollections[msg.sender].length;

        if (from + length > numActive) {
            length = numActive - from;
        }

        Collection[] memory myCollections = new Collection[](length);

        for (uint256 i = 0; i < length; i++) {
            myCollections[i] = collections[userActiveCollections[msg.sender][i + from]];
        }
        return myCollections;
    }

    function addCollection(
        uint256[] memory tokenIds,
        uint256[] memory tokenTypes,
        uint256 price,
        string memory name
    ) external {
        require(isMarketOpen, "Market is closed.");
        require(tokenIds.length > 1, "Minimum 2 tokens must be present.");
        require(tokenIds.length <= maxPerCollection, "It's more than the max tokens per collection.");

        uint256 id = collections.length;
        
        Collection memory collection = Collection(
            true,
            id,
            tokenIds,
            tokenTypes,
            price,
            activeCollections.length, // activeIndex
            userActiveCollections[msg.sender].length, // userActiveIndex
            msg.sender,
            name
        );

        collections.push(collection);
        userActiveCollections[msg.sender].push(id);
        activeCollections.push(id);

        IERC721Full[] memory _supportedTokens = supportedTokens;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            _supportedTokens[tokenTypes[i]].transferFrom(msg.sender, address(this), tokenIds[i]);
        }
    }

    function updateCollection(uint256 id, uint256 price) external {
        require(id < collections.length, "Invalid Collection");
        require(collections[id].active, "Collection no longer active");
        require(collections[id].owner == msg.sender, "Invalid Owner");

        collections[id].price = price;
    }

    function cancelCollection(uint256 id) external {
        require(id < collections.length, "Invalid Collection");
        Collection memory collection = collections[id];
        require(collection.active, "Collection no longer active");
        require(collection.owner == msg.sender, "Invalid Owner");

        removeActiveCollection(collection.activeIndex);
        removeOwnerActiveCollection(msg.sender, collection.userActiveIndex);

        collections[id].active = false;

        IERC721Full[] memory _supportedTokens = supportedTokens;

        uint256 numTokens = collection.tokenIds.length;
        for (uint256 i = 0; i < numTokens; i++) {
            _supportedTokens[collection.tokenTypes[i]].transferFrom(
                address(this),
                collection.owner,
                collection.tokenIds[i]
            );
        }
    }

    function fulfillCollection(uint256 id) external payable nonReentrant {
        require(id < collections.length, "Invalid Collection");
        Collection memory collection = collections[id];
        require(collection.active, "Collection no longer active");
        require(msg.value >= collection.price, "Value Insufficient");
        require(msg.sender != collection.owner, "Owner cannot buy own collection");

        // Update global stats
        totalVolume += collection.price;
        totalSales += 1;
        movedItems += collection.tokenIds.length;

        if (collection.price > highestSalePrice) {
            highestSalePrice = collection.price;
        }

        // Update active collections
        collections[id].active = false;
        removeActiveCollection(collection.activeIndex);
        removeOwnerActiveCollection(collection.owner, collection.userActiveIndex);

        IERC2981Royalties[] memory _iroyalties = IRoyalties;
        IERC721Full[] memory _supportedTokens = supportedTokens;

        uint256 numTokens = collection.tokenIds.length;
        uint256 perTokenPrice = (collection.price * 1000) / numTokens / 1000;

        AccountingInfo memory info = AccountingInfo({
            totalHolderCut: 0,
            communityTotalCut: (perTokenPrice * communityFeePercent) / 100 * numTokens, 
            community_cut: (perTokenPrice * communityFeePercent) / 100 ,
            market_cut: (perTokenPrice * marketFeePercent) / 100
        });


        for (uint256 i = 0; i < numTokens; i++) {
            uint256 tokenId = collection.tokenIds[i];
            uint256 tokenType = collection.tokenTypes[i];

            (address originalMinter, uint256 royaltyAmount) = _iroyalties[tokenType]
                .royaltyInfo(tokenId, perTokenPrice);

            uint256 holder_cut = perTokenPrice -
                royaltyAmount -
                info.community_cut -
                info.market_cut;

            info.totalHolderCut += holder_cut;
            
            payable(originalMinter).transfer(royaltyAmount);
            _supportedTokens[tokenType].transferFrom(address(this), msg.sender, tokenId);
        }

        if(!distributorInterface.isFrozen()) {
            distributorInterface.deposit{value: info.communityTotalCut}();
        }
        else {
            communityHoldings += info.communityTotalCut;
        }

        payable(collection.owner).transfer(info.totalHolderCut);

        emit FilledCollection(id);
    }

    function adjustFees(uint256 newDistFee, uint256 newMarketFee)
        external
        onlyOwner
    {
        require(newDistFee <= 100, "Give a percentage value from 0 to 100");
        require(newMarketFee <= 100, "Give a percentage value from 0 to 100");

        communityFeePercent = newDistFee;
        marketFeePercent = newMarketFee;
    }

    function emergencyDelist(uint256[] memory collectionIDs) external {
        require(emergencyDelisting && !isMarketOpen, "Only in emergency.");
        uint256 numCollections = collectionIDs.length;
        for(uint256 j = 0; j < numCollections; j++){

            uint256 collectionID = collectionIDs[j];
            require(collectionID < collections.length, "Invalid Collection");

            Collection memory collection = collections[collectionID];
            uint256[] memory tokens = collection.tokenIds;
            uint256[] memory tokenTypes = collection.tokenTypes;
            IERC721Full[] memory _supportedTokens = supportedTokens;

            uint256 numTokens = collection.tokenIds.length;
            for(uint256 i = 0; i < numTokens; i++) {
                _supportedTokens[tokenTypes[i]].transferFrom(address(this), collection.owner, tokens[i]);
            }
        }
    }

    function setNewDistributor(address addr) external onlyOwner {
        distributorInterface = IDistributor(addr);
    }

    function collectDistributorShare() external onlyOwner {
        require(address(this).balance >= communityHoldings);
        communityHoldings = 0;
        distributorInterface.deposit{value: communityHoldings}();
    }

    function withdrawableBalance() public view returns (uint256 value) {
        if (address(this).balance <= communityHoldings) {
            return 0;
        }
        return address(this).balance - communityHoldings;
    }

    function withdrawBalance() external onlyOwner {
        uint256 withdrawable = withdrawableBalance();
        payable(_msgSender()).transfer(withdrawable);
    }

    function emergencyWithdraw() external onlyOwner {
        payable(_msgSender()).transfer(address(this).balance);
    }
}
