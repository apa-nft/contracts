// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "../APAGovernance.sol";
import "./ERC721Mock.sol";

contract APAGovernanceTest is DSTest {
    APAGovernance private apaGov;
    Market private apaMkt;
    //PartyAnimals apaToken;
    ERC721Mock private mockToken;

    function setUp() public {
        
        mockToken = new ERC721Mock("Mock", "MOCK");
        apaMkt = new Market(mockToken.address,1,1);

        apaGov = new APAGovernance(
            mockToken.address;  //apatoken testnet address
            apaMarket.address; //apaMarket testnet address
            30,                                         //proposer APAs
            200,                                        //quorum per apa
            40                                         //quorum per address
        );
    }

    function testStart() public {
        assertEq(apaGov.proposerAPAs, 30);
    }
}
