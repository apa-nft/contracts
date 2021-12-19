// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import "./Market.sol";


contract APAGovernor {
    IERC721Enumerable immutable apaContract;
    Market immutable apaMkt;

    enum BallotType {perAPA, perAddress}
    enum Status { Accepted, Rejected, Active }
    enum Votes { Yes, No }

    struct Proposal {
        uint id;
        address author;
        string name;
        string description;
        uint end;
        uint votesYes;
        uint votesNo;
        BallotType ballotType;  // 0 = perAPA   1= perAddress
        Status status;
    }
 
    address public manager;
    uint public proposerApas; 
    uint public nextPropId;
    Proposal[] public proposals;
    mapping(uint => mapping(address => bool)) public voters;
    mapping(uint => mapping(uint => bool)) public votedAPAs;
    address public apaToken = 0x9E491465BbD22B62D7d27E0Ff35d4e263228ba5C;
    address public apaMarket = 0xc7BE0807843396c22f5B3D550872D0Cb9f113165;

    constructor() {
        manager = msg.sender;
        apaContract = IERC721Enumerable(apaToken);
        apaMkt = Market(apaMarket);
        proposerApas =30;
    }

    modifier onlyManager() {
        require(msg.sender == manager, 'only manager can execute this function');
        _;
    } 

    modifier verifyNumApas() {
        // Check if sender has minimum number of APAs
        require(apaContract.balanceOf(msg.sender) >= proposerApas, 'Need more APAs');
        _;
    }

    function setProposerApas(uint minApas) public onlyManager() {
        require (minApas != 0, "set minimum to at least one APA ");
        proposerApas = minApas;
    }

    function createProposal(
        string memory _name, 
        string memory _desc,
        uint duration, //in days
        BallotType _ballotType //0=perAPA 1=perAddress
        ) external verifyNumApas()  {
            proposals.push( Proposal({
                id: nextPropId,
                author: msg.sender,
                name: _name,
                description: _desc,
                end: block.timestamp + duration * 1 days,
                votesYes: 0,
                votesNo: 0,
                ballotType: _ballotType,
                status: Status.Active
                })
            );
            nextPropId+=1;

    }

    function vote(uint proposalId , Votes _vote) external {
        uint voterBalance = apaContract.balanceOf(msg.sender);
        require(voterBalance != 0, "Need at least one APA to cast a vote");
        require(block.timestamp <= proposals[proposalId].end, "Proposal has Expired");
        require(proposals[proposalId].status == Status.Active, "Proposal does not exist");

        uint currentAPA;
        uint ineligibleCount=0;
        uint userActListings=0;

        Market.Listing[] memory activeListings;
        uint totalListings =apaMkt.totalActiveListings();
        activeListings =apaMkt.getActiveListings(0,totalListings);

        uint iterations;
        if (voterBalance >= totalListings){
            iterations = voterBalance;
        }
        else iterations = totalListings;

        //get user Apas from wallet
        for(uint i=0; i <= iterations-1; i++){

            if(i <= voterBalance - 1){
                //get current APA
                currentAPA = apaContract.tokenOfOwnerByIndex(msg.sender, i);
                //check if APA has already voted
                if(!votedAPAs[proposalId][currentAPA]){
                    //count APA as voted
                    votedAPAs[proposalId][currentAPA] = true;
                    //check Ballot Type
                    if(proposals[proposalId].ballotType == BallotType.perAddress){
                        require(!voters[proposalId][msg.sender], "Voter has already voted");
                        break;//break if one vote per address, 
                    }
                }
                else ineligibleCount+=1;
            }
        
            //get user Apas from Market (will be skipped if no market apas)
            if(i <= totalListings - 1){

                if (activeListings[i].owner == msg.sender){
                    currentAPA = activeListings[i].tokenId;
                    //check if APA has already voted
                    if(!votedAPAs[proposalId][currentAPA]){
                        //count APA as voted
                        votedAPAs[proposalId][currentAPA] = true;
                        userActListings++;
                        //check Ballot Type
                        if(proposals[proposalId].ballotType == BallotType.perAddress){
                            require(!voters[proposalId][msg.sender], "Voter has already voted");
                            break;//break if one vote per address, 
                        }
                    }              
                }
            }
        }
        int eligibleVotes = int(voterBalance) + int(userActListings) - int(ineligibleCount);

      
        //1 vote per APA 
       if(proposals[proposalId].ballotType == BallotType.perAPA){
            require(eligibleVotes >= 1, "All APA's have voted");

            if (_vote == Votes.Yes){
                proposals[proposalId].votesYes += uint(eligibleVotes);
            }
            else {
                proposals[proposalId].votesNo += uint(eligibleVotes);
            }
            
        }

        //1 vote per address
        if(proposals[proposalId].ballotType == BallotType.perAddress){
            if (_vote == Votes.Yes){
                proposals[proposalId].votesYes += 1;
            }
            if (_vote == Votes.No){
                proposals[proposalId].votesNo += 1;
            }
            //mark voter as voted
            voters[proposalId][msg.sender] = true;
        }
         
    }
  
    function certifyResults(uint proposalId) external onlyManager() returns(Status) {
            //make sure proposal has ended
            require(block.timestamp >= proposals[proposalId].end, "Proposal has not yet ended");
            if(proposals[proposalId].votesYes - proposals[proposalId].votesNo >= 1) {
                proposals[proposalId].status = Status.Accepted;
            }
            else proposals[proposalId].status = Status.Rejected;
        return proposals[proposalId].status;
    }

    function getProposals() view external returns(Proposal[] memory){
        return proposals;
    }
}