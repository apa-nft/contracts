// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import "./Market.sol";


contract APAGovernance {
    IERC721Enumerable immutable apaContract;
    Market immutable apaMkt;
    address immutable apaToken;
    address immutable apaMarket;//new testnet market address

    enum BallotType {perAPA, perAddress}
    enum Status { Active, Certified, FailedQuorum}
    
    struct Proposal {
        uint id;
        uint end;
        uint quorum;
        address author;
        string name;
        string description;
        BallotType ballotType;  // 0 = perAPA   1= perAddress
        Status status;
        Option[] options;
    }

    struct Option {
        uint id;
        uint numVotes;
        string name;
    }
 
    address public manager;
    uint public proposerApas; 
    uint public quorumPerAPA;
    uint public quorumPerAddress;
    uint public nextPropId;
    //Proposal[] public proposals;
    mapping(uint => Proposal) public proposals;
    mapping(address => bool) public certifiers;
    mapping(uint => mapping(address => bool)) public voters;
    mapping(uint => mapping(uint => bool)) public votedAPAs;
    
   
    constructor(
        address _apaToken, 
        address _apaMarket, 
        uint _proposerAPAs, 
        uint _quorumPerAddress, 
        uint _quorumPerAPA
    ) {
        manager = msg.sender;
        apaToken = _apaToken;
        apaMarket = _apaMarket;
        apaContract = IERC721Enumerable(_apaToken);
        apaMkt = Market(_apaMarket);
        proposerApas =_proposerAPAs;
        quorumPerAPA = _quorumPerAPA;
        quorumPerAddress = _quorumPerAddress;
    }

    modifier onlyManager() {
        require(msg.sender == manager, 'only manager can execute this function');
        _;
    } 

    function setProposerApas(uint minApas) public onlyManager() {
        require (minApas != 0, "set minimum to at least one APA ");
        proposerApas = minApas;
    }

    function createProposal(
        string memory _name, 
        string memory _desc,
        string[] memory _optionNames,
        uint duration, //in days
        BallotType _ballotType //0=perAPA 1=perAddress
    ) external {

        address proposer = msg.sender;
        uint numAPAs = apaContract.balanceOf(proposer);
        require((numAPAs >= proposerApas || isLegendary(proposer)), 'Need more APAs');

        proposals[nextPropId].id = nextPropId;
        proposals[nextPropId].author = proposer;
        proposals[nextPropId].name = _name;
        proposals[nextPropId].description = _desc;
        proposals[nextPropId].end = block.timestamp + duration * 1 days;
        proposals[nextPropId].ballotType = _ballotType;
        proposals[nextPropId].status = Status.Active;   
        for(uint i = 0; i <= _optionNames.length - 1; i++){
            proposals[nextPropId].options.push(Option(i, 0, _optionNames[i]));
        }

        if(_ballotType == BallotType.perAPA){
            proposals[nextPropId].quorum = quorumPerAPA;
        } else {
            proposals[nextPropId].quorum = quorumPerAddress;
        }
        nextPropId+=1;
    }

    function isLegendary(address _proposer) internal view returns (bool) {
        for(uint i=9980; i <= 9999; i++){
            if(apaContract.ownerOf(i) == _proposer){
                return true;
            } 
        }
        return false;        
    }

    function countRegularVotes(
        uint256 proposalId, 
        uint _voterBalance, 
        address _voter, 
        BallotType ballotType
    ) internal returns(uint256) {
        uint256 numOfVotes = 0;
        uint currentAPA;

        for(uint256 i=0; i < _voterBalance; i++){
                //get current APA
            currentAPA = apaContract.tokenOfOwnerByIndex(_voter, i);
            //check if APA has already voted
            if(!votedAPAs[proposalId][currentAPA]){
                //count APA as voted
                if (ballotType == BallotType.perAddress) {
                    require(!voters[proposalId][_voter], "Voter has already voted");
                    return 1;
                }
                votedAPAs[proposalId][currentAPA] = true;
                numOfVotes++;
            }
        }
        return numOfVotes;
    }

    function countMarketVotes(uint256 proposalId, address _voter, BallotType ballotType) internal returns(uint256) {
        Market.Listing[] memory activeListings;
        uint256 totalListings =apaMkt.totalActiveListings();
        activeListings =apaMkt.getActiveListings(0,totalListings);
        //uint256 activeListingCount = apaMkt.getMyActiveListingsCount();
        //activeListings = apaMkt.getMyActiveListings(0, activeListingCount);
        uint256 numOfVotes = 0;
        uint currentAPA;
        
        for(uint256 i=0; i < totalListings; i++){
            //get user Apas from Market (will be skipped if no market apas)
            if (activeListings[i].owner == _voter){
                currentAPA = activeListings[i].tokenId;
                //check if APA has already voted
                if(!votedAPAs[proposalId][currentAPA]){

                    if (ballotType == BallotType.perAddress) {
                        require(!voters[proposalId][_voter], "Voter has already voted");
                        return 1;
                    }
                    //count APA as voted
                    votedAPAs[proposalId][currentAPA] = true;
                    numOfVotes++;
                }              
            }
        }
        return numOfVotes;
    }
    function vote(uint256 proposalId, uint256 optionId) external {
        address voter = msg.sender;
        uint256 voterBalance = apaContract.balanceOf(voter);
        require(proposals[proposalId].status == Status.Active, "Not an Active Proposal");
        require(block.timestamp <= proposals[proposalId].end, "Proposal has Expired");
        require(voterBalance != 0, "Need at least one APA to cast a vote");
        BallotType ballotType = proposals[proposalId].ballotType;
        
        //1 vote per APA 
        if(ballotType == BallotType.perAPA){
            uint256 eligibleVotes = countRegularVotes(proposalId, voterBalance, voter, ballotType) + countMarketVotes(proposalId, voter, ballotType);
            require(eligibleVotes >= 1, "Vote count is zero");
            //count votes
            proposals[proposalId].options[optionId].numVotes += eligibleVotes;
        }

        //1 vote per address
        if(ballotType == BallotType.perAddress){
            if(countRegularVotes(proposalId, voterBalance, voter, ballotType) > 0  || countMarketVotes(proposalId, voter, ballotType) > 0  ){ // if countRegularVotes() is true countMarketVotes() wont be evaluated
                proposals[proposalId].options[optionId].numVotes += 1;
                voters[proposalId][voter] = true;
            }
        }
         
    }

    function certifyResults(uint proposalId) external returns(Status) {
        require(certifiers[msg.sender], "must be certifier to certify results");
        require(block.timestamp >= proposals[proposalId].end, "Proposal has not yet ended");
        require(proposals[proposalId].status == Status.Active, "Not an Active Proposal");
        bool quorumMet;

        for(uint i=0; i <= proposals[proposalId].options.length; i++){
            if(proposals[proposalId].options[i].numVotes >= proposals[nextPropId].quorum) 
                quorumMet = true;
        }

        if(!quorumMet) 
            proposals[proposalId].status = Status.FailedQuorum;
        else 
            proposals[proposalId].status = Status.Certified;

        return proposals[proposalId].status;
    }

    function getVoteCount(uint proposalId) external view returns(Option[] memory){
        return proposals[proposalId].options;
    }

    function addCertifier(address newCertifier) external onlyManager(){
        certifiers[newCertifier] = true;
    }

    function removeCertifier(address newCertifier) external onlyManager(){
        certifiers[newCertifier] = false;
    }

    function setManager(address newManager) external onlyManager(){
        manager = newManager;
    }

    function setQuorumPerAPA(uint newQuorum) external onlyManager(){
        require(newQuorum >= 1, "must have at least one winning vote");
        quorumPerAPA = newQuorum;
    }

    function setQuorumPerAddress(uint newQuorum) external onlyManager(){
        require(newQuorum >= 1, "must have at least one winning vote");
        quorumPerAddress = newQuorum;
    }

    function setQuorumByProposal(uint proposalId, uint newQuorum) external onlyManager(){
        require(proposals[proposalId].status == Status.Active, "Not an Active Proposal");
        require(newQuorum >= 1, "must have at least one winning vote");
        proposals[proposalId].quorum = newQuorum;
    }

    function getProposals()
        external
        view
        returns (Proposal[] memory _proposals)
    {
        Proposal[] memory _props = new Proposal[](nextPropId);
        for (uint256 i = 0; i <= nextPropId-1; i++) {  
            _props[i] = proposals[i];
        }

        return _props;
    }
}
