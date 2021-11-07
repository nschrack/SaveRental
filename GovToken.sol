// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;


contract GovToken{
    
    string public name = "Save Rental Token";
    string public symbol = "SRT";
    address payable public owner;
    uint public totalSupply;
    uint256 constant tokenPrice = 100; // token price, unit wei
    address public contractAddress;

    mapping(address => uint) balances;

    constructor(uint256 _totalSupply){
        owner = payable(msg.sender);
        totalSupply = _totalSupply;
        balances[msg.sender] = totalSupply;
    }

    function transfer(address to, uint amount) external {
        require(balances[msg.sender] >= amount, 'Not enough tokens');

        balances[msg.sender] -= amount;
        balances[to] += amount;
    }
    
    function balanceOf(address account) external view returns (uint) {
        return balances[account];
    }
    
    function tokenBalance(address _addr) public view returns (uint256) {
        return balances[_addr];
    }
    
    function mintTo(address _addr, uint256 _amount) public OnlyContract{ 
        totalSupply += _amount; // the total token supply increases
        balances[_addr] += _amount;
    }
    
    function mint(uint256 _amount) public OnlyTokenOwner {
        totalSupply += _amount; 
        balances[msg.sender] += _amount; 
    }
    
    function setContract(address _addr) public OnlyTokenOwner { 
        contractAddress = _addr; 
    }
    
    // Buy tokens from the token owner
    function buyToken() public payable {
        uint256 tokenNum = msg.value/tokenPrice; 
        
        owner.transfer(msg.value); 
        balances[owner] -= tokenNum; 
        balances[msg.sender] += tokenNum;  
    }


    modifier OnlyContract() {
        require(msg.sender == contractAddress, 'caller is not the contract owner.');
        _;
    }


    modifier OnlyTokenOwner() {
        require(msg.sender == owner, 'caller is not the token owner.');
        _;
    }

}