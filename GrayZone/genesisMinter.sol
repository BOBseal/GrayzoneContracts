// SPDX-License-Identifier: MIT

/*
NFT=>
LINEA TESTNET = 0x1b7D000a6d73D0aF7Afb572E605d263cDBdfA4cc
*/
pragma solidity ^0.8.17;

import"./ZonePass.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract GenesisMint {
    ZONEPASS public pass;
    address public dropFeeToken;
    uint256 public nonce;
    string uri_ = "QmPFKfS3nY7cGikcF2gKGJG1KMiXwfJn7JhmoXAGSgyBSA";
    address owner;
    uint256 public dropPrice = 0 ether;
    mapping(uint256 => address) public claimers;
    mapping(address =>bool) public claimed;

    constructor(address weth , address _pass){
        dropFeeToken = weth;
        owner = msg.sender;
        pass = ZONEPASS(_pass);
    }

    function Claim() public{
        require(claimed[msg.sender] ==  false ,"Claimed Pass Already");
        //IERC20(dropFeeToken).transferFrom(msg.sender ,address(this), dropPrice);
        pass.mint(msg.sender , uri_);
        claimed[msg.sender] = true;
        claimers[nonce] = msg.sender;
        nonce++;
    }

    function withdrawFee( address token ,uint256 amount) public{
        require(msg.sender == owner);
        IERC20(token).transfer(msg.sender , amount);
    }

    function changeFeeDetails(address token , uint256 amount) public{
        require(msg.sender == owner);
        dropFeeToken = token;
        dropPrice = amount;
    }

    function changeUri(string memory uri) public {
        require(msg.sender == owner);
        uri_ = uri;
    }
}