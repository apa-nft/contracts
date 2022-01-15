// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "./lib/ERC2981PerTokenRoyalties.sol";

contract PartyAnimals is
    ERC721Enumerable,
    ERC2981PerTokenRoyalties,
    ReentrancyGuard,
    Ownable
{
    using Strings for uint256;
    uint256 public constant ROYALTY_VALUE = 300; // 4% using 2 decimals - 10000 = 100, 0 = 0
    uint256 public constant MAX_MINTABLE = 10000;
    uint256 public constant MAX_PER_CLAIM = 10;
    uint256 public constant INITIAL_CLAIM_PRICE = 2 ether;
    uint256 public constant POST_5000_PRICE = 1.5 ether;

    bool public canClaim = false;
    bool public canClaimAirdrop = false;
    uint256 public numHonoraries = 0;
    uint256 public minted = 0;

    bytes32 merkleRoot;
    uint256 public airdropNumber = 0;
    mapping(address => uint256) redeemTracker;
    mapping(uint256 => bool) redeemedIDs;

    string baseUri = "https://partyanimals.xyz/id/";
    mapping(uint256 => uint256) public givenRewards;
    uint256 public totalProjectedRewards = 0;
    uint256 public post5000Extra = 0;

    // tokenID mapping
    mapping(uint256 => uint256) indexer;
    uint256 indexerLength = MAX_MINTABLE;
    mapping(uint256 => uint256) tokenIDMap;
    mapping(uint256 => uint256) takenImages;

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet recognizedContracts;

    uint256 public withdrawn = 0;
    uint256 gross = 0;

    event Claim(uint256 indexed _id);
    event Redeem(uint256 indexed _id);

    /* *************** */
    /* Minting Rewards */
    /* *************** */
    function getFirstRewardComponent(uint256 index)
        internal
        pure
        returns (uint256 r2)
    {
        uint256 reward = getPrice(index) * 400;
        reward = (reward * (MAX_MINTABLE - index));
        reward = reward / 1000 / MAX_MINTABLE;
        return reward;
    }

    function getProjectedReward(uint256 index)
        public
        view
        returns (uint256 reward)
    {
        if (index >= 5000) return 0;
        if (redeemedIDs[index]) return 0;
        return getFirstRewardComponent(index) + post5000Extra;
    }

    function getCurrentReward(uint256 index)
        public
        view
        returns (uint256 reward)
    {
        if (index == minted - 1) return 0;
        return
            (getProjectedReward(index) * (minted * 1000)) / MAX_MINTABLE / 1000;
    }

    function getPrice(uint256 index) internal pure returns (uint256 price) {
        if (index >= 5000) return POST_5000_PRICE;
        return INITIAL_CLAIM_PRICE - ((index * 10**18) / MAX_MINTABLE);
    }

    function getNextBatchPrice(uint256 amount)
        public
        view
        returns (uint256 batchPrice)
    {
        uint256 totalPrice = 0;
        uint256 index = minted;
        for (uint8 i = 0; i < amount; i++) {
            totalPrice += getPrice(index + i);
        }
        return totalPrice;
    }

    function getRewards() external view returns (uint256 value) {
        uint256 rewards = 0;
        uint256 numTokens = balanceOf(msg.sender);
        for (uint256 i = 0; i < numTokens; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(msg.sender, i);
            uint256 currentReward = getCurrentReward(tokenId);
            if (givenRewards[tokenId] < currentReward) {
                uint256 tokenReward = currentReward - givenRewards[tokenId];
                rewards += tokenReward;
            }
        }
        return rewards;
    }

    function claimRewards() external {
        uint256 rewards = 0;
        uint256 numTokens = balanceOf(msg.sender);
        for (uint256 i = 0; i < numTokens; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(msg.sender, i);
            uint256 currentReward = getCurrentReward(tokenId);
            if (givenRewards[tokenId] < currentReward) {
                uint256 tokenReward = currentReward - givenRewards[tokenId];
                rewards += tokenReward;
                givenRewards[tokenId] += tokenReward;
            }
        }
        require(rewards > 0, "Your token rewards are 0.");
        payable(msg.sender).transfer(rewards);
    }

    /* *************** */
    /*     Minting     */
    /* *************** */
    function getImageIDs(uint256 from, uint256 length) external view returns (uint256[] memory)  {
        require(from + length <= minted, "Exceeds number of minted.");

        uint256[] memory imageIDs = new uint256[](length);

        for(uint256 i = 0; i < length; i++) {
            imageIDs[i] = tokenIDMap[from + i]; 
        }
        
        return imageIDs;
    }

    // Think of it as an array of 10_000 elements, where we take
    //    a random index, and then we want to make sure we don't
    //    pick it again.
    // If it hasn't been picked, the mapping points to 0, otherwise
    //    it will point to the index which took its place
    function getNextImageID(uint256 index) internal returns (uint256) {
        uint256 nextImageID = indexer[index];

        // if it's 0, means it hasn't been picked yet
        if (nextImageID == 0) {
            nextImageID = index;
        }
        // Swap last one with the picked one.
        // Last one can be a previously picked one as well, thats why we check
        if (indexer[indexerLength - 1] == 0) {
            indexer[index] = indexerLength - 1;
        } else {
            indexer[index] = indexer[indexerLength - 1];
        }
        indexerLength -= 1;
        return nextImageID;
    }

    function enoughRandom() internal view returns (uint256) {
        if (MAX_MINTABLE - minted == 0) return 0;
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        block.difficulty,
                        block.timestamp,
                        msg.sender,
                        blockhash(block.number)
                    )
                )
            ) % (indexerLength);
    }

    function toggleClaimability() external onlyOwner {
        canClaim = !canClaim;
    }

    function toggleAirdropClaimability() external onlyOwner {
        canClaimAirdrop = !canClaimAirdrop;
    }

    function mintAPA(address receiver, uint256 nextTokenIndex) internal {
        uint256 nextIndexerId = enoughRandom();
        uint256 nextImageID = getNextImageID(nextIndexerId);
        assert(takenImages[nextImageID] == 0);
        takenImages[nextImageID] = 1;
        tokenIDMap[nextTokenIndex] = nextImageID;
        _safeMint(receiver, nextTokenIndex);
    }

    function claim(uint256 n) public payable nonReentrant {
        require(
            canClaim,
            "Party Animals: it's not possible to claim just yet."
        );
        require(
            MAX_MINTABLE - airdropNumber - minted > 0,
            "Party Animals: not enough Party Animals left to mint."
        );
        require(n > 0, "Party Animals: not enough Party Animals left to mint.");
        require(n <= MAX_PER_CLAIM);
        if (n > MAX_MINTABLE - airdropNumber - minted) {
            n = MAX_MINTABLE - airdropNumber - minted;
        }

        uint256 total_cost = getNextBatchPrice(n);
        require(msg.value >= total_cost);
        gross += total_cost;

        uint256 excess = msg.value - total_cost;
        payable(address(this)).transfer(total_cost);

        for (uint256 i = 0; i < n; i++) {
            uint256 nextIndex = minted;
            minted += 1;

            mintAPA(_msgSender(), nextIndex);
            _setTokenRoyalty(nextIndex, _msgSender(), ROYALTY_VALUE);
            totalProjectedRewards += getProjectedReward(nextIndex);

            emit Claim(nextIndex);
        }
    
        if(excess > 0) {
            payable(_msgSender()).transfer(excess);
        }
    }

    /* ******************* */
    /*      Airdrops       */
    /* ******************* */
    function addHonoraries(address[] calldata honoraries) external onlyOwner {
        uint256 honoraryID = numHonoraries + 10000;
        for (uint256 i = 0; i < honoraries.length; i++) {
            tokenIDMap[honoraryID] = honoraryID;
            _safeMint(honoraries[i], honoraryID);

            emit Claim(honoraryID);

            honoraryID += 1;
        }

        numHonoraries += honoraries.length;
    }

    function setAirdropDetails(uint256 number, bytes32 root)
        external
        onlyOwner
    {
        require(minted + number <= MAX_MINTABLE);
        airdropNumber = number;
        merkleRoot = root;
    }

    function getClaimedAirdrops(address account)
        external
        view
        returns (uint256)
    {
        return redeemTracker[account];
    }

    function redeem(
        address account,
        uint256 totalGiven,
        uint256 requesting,
        bytes32[] memory proof
    ) external nonReentrant {
        require(
            canClaimAirdrop,
            "Party Animals: it's not possible to claim the airdrop at the moment."
        );
        require(minted + requesting <= MAX_MINTABLE);
        require(airdropNumber >= requesting);
        require(redeemTracker[account] + requesting <= totalGiven);
        require(
            _verify(_leaf(account, totalGiven), proof),
            "Invalid merkle proof"
        );

        uint256 nextId = minted;
        for (uint256 i = 0; i < requesting; i++) {
            mintAPA(account, nextId);
            _setTokenRoyalty(nextId, account, ROYALTY_VALUE);

            redeemedIDs[nextId] = true;
            emit Redeem(nextId);

            nextId += 1;
        }

        minted += requesting;
        airdropNumber -= requesting;
        redeemTracker[account] += requesting;
    }

    function _leaf(address account, uint256 totalGiven)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(account, totalGiven));
    }

    function _verify(bytes32 leaf, bytes32[] memory proof)
        internal
        view
        returns (bool)
    {
        return MerkleProof.verify(proof, merkleRoot, leaf);
    }

    /* ****************** */
    /*       ERC721       */
    /* ****************** */
    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );
        string memory baseURI = _baseURI();
        uint256 imageID = tokenIDMap[tokenId];
        return
            bytes(baseURI).length > 0
                ? string(abi.encodePacked(baseURI, imageID.toString()))
                : "";
    }

    function setBaseUri(string memory uri) external onlyOwner {
        baseUri = uri;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseUri;
    }

    function withdrawableBalance() public view returns (uint256 value) {
        return
            gross -
            ((totalProjectedRewards * (minted * 1000)) / MAX_MINTABLE / 1000) -
            withdrawn;
    }

    function withdrawBalance() external onlyOwner {
        uint256 withdrawable = withdrawableBalance();
        require(address(this).balance > withdrawable);

        withdrawn += withdrawable;
        payable(_msgSender()).transfer(withdrawable);
    }

    function emergencyWithdraw() external onlyOwner {
        payable(_msgSender()).transfer(address(this).balance);
    }

    receive() external payable {}

    fallback() external payable {}

    /* ****************** */
    /* Contract Authority */
    /* ****************** */
    function recognizeContract(address newContract) external onlyOwner {
        if (!recognizedContracts.contains(newContract)) {
            assert(recognizedContracts.add(newContract));
        }
    }

    function isContractRecognized(address newContract)
        external
        view
        returns (bool isRecognized)
    {
        return recognizedContracts.contains(newContract);
    }

    function getRecognizedContracts()
        external
        view
        returns (address[] memory contracts)
    {
        return recognizedContracts.values();
    }

    /// @inheritdoc	ERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721Enumerable, ERC2981Base)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    constructor(
        string memory nftName,
        string memory nftSymbol,
        string memory baseTokenURI
    ) ERC721(nftName, nftSymbol) Ownable() {
        baseUri = baseTokenURI;

        // uint256 cumulative = 0;
        // for (uint128 i = 5000; i < 10000; i++) {
        //     cumulative += getFirstRewardComponent(i);
        // }
        // post5000Extra = cumulative / 5000;
        post5000Extra = 0.15003 ether;
    }
}