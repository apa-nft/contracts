// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import "./Market.sol";


contract APAGovernance {
    IERC721Enumerable immutable apaContract;
    Market immutable apaMkt;

    enum BallotType {perAPA, perAddress}
    enum Status { Active, Certified, FailedQuorum}
    
    struct Proposal {
        uint id;
        address author;
        string name;
        string description;
        Option[] options;
        uint end;
        BallotType ballotType;  // 0 = perAPA   1= perAddress
        Status status;
        uint quorum;
    }

    struct Option {
        uint id;
        string name;
        uint numVotes;
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
    address public apaToken = 0x9E491465BbD22B62D7d27E0Ff35d4e263228ba5C;
    address public apaMarket = 0xc7BE0807843396c22f5B3D550872D0Cb9f113165;//new testnet market address

    constructor() {
        manager = msg.sender;
        apaContract = IERC721Enumerable(apaToken);
        apaMkt = Market(apaMarket);
        proposerApas =30;
        quorumPerAPA = 200;
        quorumPerAddress = 40;
    }

    modifier onlyManager() {
        require(msg.sender == manager, 'only manager can execute this function');
        _;
    } 

    modifier verifyNumApas() {
        bool isLegendary;
        uint numAPAs = apaContract.balanceOf(msg.sender);
        for(uint i=9980; i <= 9999; i++){
            if(apaContract.ownerOf(i) == msg.sender){
                isLegendary = true;
                break;
            } 
        }
        require((numAPAs >= proposerApas || isLegendary), 'Need more APAs');
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
    ) external verifyNumApas()  {
        proposals[nextPropId].id = nextPropId;
        proposals[nextPropId].author = msg.sender;
        proposals[nextPropId].name = _name;
        proposals[nextPropId].description = _desc;
        proposals[nextPropId].end = block.timestamp + duration * 1 days;
        proposals[nextPropId].ballotType = _ballotType;
        proposals[nextPropId].status = Status.Active;   
        for(uint i = 0; i <= _optionNames.length - 1; i++){
            proposals[nextPropId].options.push(Option(i, _optionNames[i], 0));
        }

        if(_ballotType == BallotType.perAPA){
            proposals[nextPropId].quorum = quorumPerAPA;
        } else {
            proposals[nextPropId].quorum = quorumPerAddress;
        }
        nextPropId+=1;
    }
    function countRegularVotes(uint256 proposalId, BallotType ballotType) internal returns(uint256) {
        uint256 voterBalance = apaContract.balanceOf(msg.sender);
        uint256 numOfVotes = 0;
        uint currentAPA;

        for(uint256 i=0; i < voterBalance; i++){
                //get current APA
            currentAPA = apaContract.tokenOfOwnerByIndex(msg.sender, i);
            //check if APA has already voted
            if(!votedAPAs[proposalId][currentAPA]){
                //count APA as voted
                if (ballotType == BallotType.perAddress) {
                    require(!voters[proposalId][msg.sender], "Voter has already voted");
                    return 1;
                }
                votedAPAs[proposalId][currentAPA] = true;
                numOfVotes++;
            }
        }

        return numOfVotes;
    }

    function countMarketVotes(uint256 proposalId, BallotType ballotType) internal returns(uint256) {
        Market.Listing[] memory activeListings;
        uint256 totalListings =apaMkt.totalActiveListings();
        activeListings =apaMkt.getActiveListings(0,totalListings);
        uint256 numOfVotes = 0;
        uint currentAPA;
        
        for(uint256 i=0; i < totalListings; i++){
            //get user Apas from Market (will be skipped if no market apas)
            if (activeListings[i].owner == msg.sender){
                currentAPA = activeListings[i].tokenId;
                //check if APA has already voted
                if(!votedAPAs[proposalId][currentAPA]){

                    if (ballotType == BallotType.perAddress) {
                        require(!voters[proposalId][msg.sender], "Voter has already voted");
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
        uint256 voterBalance = apaContract.balanceOf(msg.sender);
        require(proposals[proposalId].status == Status.Active, "Not an Active Proposal");
        require(block.timestamp <= proposals[proposalId].end, "Proposal has Expired");
        require(voterBalance != 0, "Need at least one APA to cast a vote");
        BallotType ballotType = proposals[proposalId].ballotType;
        
        //1 vote per APA 
        if(ballotType == BallotType.perAPA){
            uint256 eligibleVotes = countRegularVotes(proposalId,ballotType) + countMarketVotes(proposalId,ballotType);
            require(eligibleVotes >= 1, "Vote count is zero");
            //count votes
            proposals[proposalId].options[optionId].numVotes += eligibleVotes;
        }

        //1 vote per address
        if(ballotType == BallotType.perAddress){
            if(countRegularVotes(proposalId,ballotType) > 0  || countMarketVotes(proposalId,ballotType) > 0  ){ // if countRegularVotes() is true countMarketVotes() wont be evaluated
                proposals[proposalId].options[optionId].numVotes += 1;
                voters[proposalId][msg.sender] = true;
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
