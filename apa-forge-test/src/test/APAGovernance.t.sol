// SPDX-License-Identifier: Unlicense
pragma solidity  ^0.8.0;

import "ds-test/test.sol";
import "../APAGovernance.sol";
import "./ERC721Mock.sol";

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

contract APAGovernanceTest is DSTest {
    APAGovernance private apaGov;
    Market private apaMkt;
    ERC721Mock private mockToken;
    address owner;

    function setUp() public {
        
        mockToken = new ERC721Mock("Mock", "MOCK");
        apaMkt = new Market(address(mockToken),1,1);
        owner = address(this);

        apaGov = new APAGovernance(
            address(mockToken),  //apatoken testnet address
            address(apaMkt), //apaMarket testnet address
            30,                                         //proposer APAs
            200,                                        //quorum per apa
            40                                         //quorum per address
        );

        //mint some nfts
        for(uint i = 0; i<=30; i++){
            mockToken.mint(i);
        }
        //mint a legendary
        mockToken.mint(9980);

        //open Market 
        apaMkt.openMarket();
        mockToken.setApprovalForAll(address(apaMkt), true);

        apaMkt.addListing(1,10000000000000000000);
        apaMkt.addListing(2,10000000000000000000);
        apaMkt.addListing(3,10000000000000000000);
        apaMkt.addListing(4,10000000000000000000);

        //populate proposal array with 2 samples
        string[] memory _options  = new string[](4);
        _options[0] = ("option 1");
        _options[1] = ("option 2");
        _options[2] = ("option 3");
       
        uint proposalId = apaGov.createProposal(
            "Proposal 1", 
            "Description 1",
            _options,
            3, //in days
            APAGovernance.BallotType.perAPA //0=perAPA 1=perAddress
            );

        _options[0] = ("option A");
        _options[1] = ("option B");
        _options[2] = ("option C");
        _options[3] = ("option D");

        proposalId = apaGov.createProposal(
            "Proposal 2", 
            "Description 2",
            _options,
            3, //in days
            APAGovernance.BallotType.perAddress //0=perAPA 1=perAddress
            );
    }

    //test createProposal()
    function testCreateProposal() public {
        string[] memory _options = new string[](3);
        _options[0] = ("option 1");
        _options[1] = ("option 2");
        _options[2] = ("option 3");
       
        uint proposalId = apaGov.createProposal(
            "Proposal 3", 
            "Description 3",
            _options,
            3, //in days
            APAGovernance.BallotType.perAPA //0=perAPA 1=perAddress
            );
        assertEq(proposalId, 2);

        proposalId = apaGov.createProposal(
            "Proposal 4", 
            "Description 4",
            _options,
            3, //in days
            APAGovernance.BallotType.perAddress //0=perAPA 1=perAddress
            );
        assertEq(proposalId, 3);

        //test getProposals()
        APAGovernance.Proposal[] memory proposals = new APAGovernance.Proposal[](3);
        proposals = apaGov.getProposals();
        assertEq(proposals.length,apaGov.nextPropId());
        assertEq(proposals[1].quorum, 200);
        assertEq(proposals[2].quorum, 40);
        assertEq(proposals[2].options[1].id, 1);
        assertEq(proposals[1].author, owner);
    }
    
    function testVote() public {
        uint propId = 0;
        uint optionId = 2;

        //add some listings to apa market
        require(apaMkt.isMarketOpen()==true,"Market Closed");
        //apaGov.vote(propId, optionId);
        
        //assertEq(apaGov.numOfVotes(),mockToken.balanceOf(owner) );

     //   APAGovernance.Proposal[] memory proposals = new APAGovernance.Proposal[](3);
     //   proposals = apaGov.getProposals();
        //assertEq(proposals[propId].options[optionId].numVotes, mockToken.balanceOf(owner));
        
    }
    
    
    //test setProposerAPA()
    function testProposerApas() public {
        for(uint i=1; i<=9999; i++){
            apaGov.setProposerApas(i);
            assertEq(apaGov.proposerApas(),i);
        }
    }
    function testFailProposerApasLow() public {
            apaGov.setProposerApas(0);
    }
    function testFailProposerApasHi() public {
            apaGov.setProposerApas(10005);
    }
    //test setQuorumPerAPA()
    function testSetQuorumPerAPA() public {
        for(uint i=1; i<=9999; i++){
            apaGov.setQuorumPerAPA(i);
            assertEq(apaGov.quorumPerAPA(),i);
        }
    }
    function testFailSetQuorumPerAPALow() public {
            apaGov.setQuorumPerAPA(0);
    }
    function testFailSetQuorumPerAPAHi() public {
            apaGov.setQuorumPerAPA(10005);
    }
    //test setQuorumPerAddress()
    function testSetQuorumPerAddress() public {
        for(uint i=1; i<=9999; i++){
            apaGov.setQuorumPerAddress(i);
            assertEq(apaGov.quorumPerAddress(),i);
        }
    }
    function testFailSetQuorumPerAddressLow() public {
            apaGov.setQuorumPerAddress(0);
    }
    function testFailSetQuorumPerAddressHi() public {
            apaGov.setQuorumPerAddress(10005);
    }
   
}
