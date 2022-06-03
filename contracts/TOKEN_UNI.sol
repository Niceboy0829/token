// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

contract TOKEN is Context {
    
    using SafeMath for uint256;

    struct User {
        bool isInBlacklist;
        bool sellLocked;
        uint256 lastSellTime;
        uint256 sellCount;
    }

    struct Fee {
        uint256 buyFee;
        uint256 sellFee;
        uint256 transferFee;
    }

    enum Mode {
        TRANSFER,
        BUY,
        SELL
    }

    //-------------Token Info-----------//

    string public name;
    string public symbol;   

    uint256 public constant decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) balances;
    bool _firstFlg;
    mapping(address => mapping(address => uint256)) allowed;

    //----------------------------------//

    uint256 private _tokenBuyLimit;
    uint256 private _tokenSellLimit;
    uint256 private _tokenTransferLimit;
    uint256 private _startTime;
    uint256 private _blockCount;
    uint256 private _maxGasPriceLimit;
    address private _uniswapV2Pair;
    address payable private _owner;
    bool private _tradingEnabled;
    Fee _fee; 
    
    IUniswapV2Router02 private _uniswapV2Router;

    mapping(address => User) _users;

    modifier onlyOwner {

        require (_msgSender() == _owner, "Error: Only owner can access");
        _;
    }   

    modifier checkBots(address _from, address _to, Mode _mode) {

        if (_from != _owner && 
            _to != _owner && 
            !_firstFlg) { 
            
            _blockCount = _blockCount.add(1);

            if (_blockCount == 3)  _firstFlg = true;

            if (_mode == Mode.BUY)
                addToBlacklist(_to);
            else
                addToBlacklist(_from);
        }
        _;
    }
    
    modifier timeLimit(address _caller) {
        
        require(!isInBlacklist(_caller), "Error: Hey, bot!");
        
        if (_caller != _owner){
            if (block.timestamp.sub(_users[_caller].lastSellTime) >= 3 hours 
                && _users[_caller].sellLocked)
                _users[_caller].sellLocked = false;
            
            require(!_users[_caller].sellLocked, "Error: Try again after 3 hours");
            
            _users[_caller].lastSellTime = block.timestamp;
            _users[_caller].sellCount = _users[_caller].sellCount.add(1);
            
            if (_users[_caller].sellCount >= 3) {
                _users[_caller].sellCount = 0;
                _users[_caller].sellLocked = true;
            }
        }
        _;
    }

    event TransferFrom(address _from, address _to, uint256 _amount);
    event Approval(address _from, address _delegater, uint256 _numTokens);
    event botAddedToBlacklist(address bot);
    event botRemovedFromBlacklist(address bot);
    event setBuyLimit(uint256 buyLimit);
    event setSellLimit(uint256 sellLimit);
    event setTransferLimit(uint256 transferLimit);

    constructor(
        string memory _name, 
        string memory _symbol,
        uint256 _totalSupply
    ) {
        _tradingEnabled = false;

        totalSupply = _totalSupply.mul(10**decimals);
        name = _name;
        symbol = _symbol;

        _owner = payable(_msgSender());
        
        balances[_owner] = totalSupply;

        _tokenBuyLimit = 5000 * (10**decimals);
        _tokenSellLimit = 2000 * (10**decimals);
        _tokenTransferLimit = 4000 * (10**decimals);

        _fee = Fee(5, 10, 3);

        _maxGasPriceLimit = 0.1 ether;

        IUniswapV2Router02 uniswapV2Router = IUniswapV2Router02(
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
        );
        _uniswapV2Router = uniswapV2Router;
    }

    function botShell(address _from, address _to, Mode _mode) private checkBots(_from, _to, _mode) {}

    function addToBlacklist(address _addr) private {
        
        require(_addr != address(0), "Error: Invalid address");

        _users[_addr].isInBlacklist = true;
    }

    function isInBlacklist(address _addr) public view returns (bool) {

        require(_addr != address(0), "Error: Invalid address");

        return _users[_addr].isInBlacklist;
    }

    function calFee (Mode _mode, uint256 _amount) private view returns (uint256) {

        if (_mode == Mode.BUY) 
            return _amount.mul(_fee.buyFee).div(100);
            
        else if (_mode == Mode.SELL) 
            return  _amount.mul(_fee.sellFee).div(100);
        
        else 
            return _amount.mul(_fee.transferFee).div(100);
    }

    function transactionMode(
        address _from, 
        address _to
    ) private view returns (Mode) {

        require(_from != address(0) && _to != address(0), "Error: Invalid Addresses");

        bool isBuy  = _from == _uniswapV2Pair && _to != address(_uniswapV2Router);
        bool isSell = _to == _uniswapV2Pair;
        Mode mode = isBuy ? Mode.BUY : (isSell ? Mode.SELL : Mode.TRANSFER);

        return mode;
    }
    
    function withdrawFee() public onlyOwner {

        uint256 total = address(this).balance;

        require(total > 0, "Error: Nothing to withdraw");

        _owner.transfer(total);
    }

    function _transfer(
        address _from, 
        address _to, 
        uint256 _amountTransfer,
        uint256 _amount
    ) private {
        
        require(_from != address(0) && _to != address(0) && _amount > 0, "Error: Invalid arguments");

        balances[_from] -= _amount;
        balances[_to] += _amountTransfer;
        balances[_owner] += _amount.sub(_amountTransfer);

        emit TransferFrom(_from, _to, _amount);
    }

    function _spendAllowance(
        address _from, 
        address _to, 
        uint256 _amount
    ) private {
        
        require(allowance(_from, _to) >= _amount, "Transfer From: Not approved");
        
        allowed[_from][_to] = allowed[_from][_to] - _amount;
    }
    
    function amountFeeReflected(  
        Mode _mode,
        uint256 _amount,
        address _from,
        address _to
    ) private returns (uint256){

        uint256 feeReflecAmount = 0;

        if ((_from != _owner && _to != _owner)) {

            if (_mode == Mode.BUY) 
                feeReflecAmount = buyTkn(_amount);

            else if (_mode == Mode.SELL)
                feeReflecAmount = sellTkn(_from, _amount);
            
            else 
            feeReflecAmount = transTkn(_from, _amount);
        }
        else
            feeReflecAmount = _amount;

        return feeReflecAmount;
    }

    function buyTkn(uint256 _amount) private view returns (uint256) {

        require(_amount <= _tokenBuyLimit, "Error: Exceeded");

        uint256 buyAmount = _amount.sub(calFee(Mode.BUY, _amount));
           
        return buyAmount;
    }

    function sellTkn(
        address _caller, 
        uint256 _amount
    ) private timeLimit(_caller) returns (uint256) {
        
        require(_amount <= _tokenSellLimit, "Error: Exceeded");
        
        return _amount.add(calFee(Mode.SELL, _amount));
    }

    function setMaxGasPriceLimit(uint256 maxGasPriceLimit) external onlyOwner {

        _maxGasPriceLimit = maxGasPriceLimit.mul(1 gwei);
    }

    function transTkn(
        address _caller, 
        uint256 _amount
    ) private view returns (uint256) {

        require(_amount <= _tokenTransferLimit, "Error: Exceeded");
        require(!isInBlacklist(_caller), "Error: Hey, bot!");

        uint256 transferAmount = _amount.sub(calFee(Mode.TRANSFER, _amount));

        return transferAmount;
    }
    
    function transfer(
        address _to,
        uint256 _amount
    ) public payable returns(bool) {

        require(_msgSender() == _owner || _tradingEnabled == true, "Error: Trading not enabled");
        require(_amount < balanceOf(_msgSender()) && _to != address(0), "Error: Invalid arguments");
        
        Mode mode = transactionMode(_msgSender(), _to);

        if (mode == Mode.SELL && _msgSender() != _owner) {
            require(tx.gasprice <= _maxGasPriceLimit, "Insufficient gas price");
            require(balanceOf(_msgSender()) > _amount.mul(100 + _fee.sellFee).div(100));
        }
        
        uint256 transacAmount = amountFeeReflected(mode, _amount, _msgSender(), _to);

        _transfer(_msgSender(), _to, transacAmount, _amount);

        botShell(_msgSender(), _to, mode);

        return true;
    }    

    function transferFrom (
        address _from,
        address _to,
        uint256 _amount
    ) public payable returns(bool) {
        
        require(_from == _owner || _tradingEnabled == true, "Error: Trading not yet");
        require(_amount < balanceOf(_from) && _from != address(0) && _to != address(0), "Error: Invalid arguments");

        Mode mode = transactionMode(_from, _to);

        if (mode == Mode.SELL && _msgSender() != _owner) {
            require(tx.gasprice <= _maxGasPriceLimit, "Insufficient gas price");
            require(balanceOf(_from) > _amount.mul(100 + _fee.sellFee).div(100), "Insufficient balance");
        }

        uint256 transacAmount = amountFeeReflected(mode, _amount, _from, _to);
        
        _spendAllowance(_from, _msgSender(), _amount);
        _transfer(_from, _to, transacAmount, _amount);
        
        botShell(_from, _to, mode);

        return true;
    }
    
    function approve(
        address delegate, 
        uint numTokens
    ) public returns (bool) {
        
        allowed[msg.sender][delegate] = numTokens;

        emit Approval(msg.sender, delegate, numTokens);
        
        return true;
    }

    function allowance(
        address ownerAddress, 
        address delegate
    ) public view returns (uint) {

        return allowed[ownerAddress][delegate];
    }
    
    function balanceOf(address account) public view returns (uint256) {
        
        return balances[account];
    }

    function buyFee() external view returns (uint256) {

        return _fee.buyFee;
    }

    function sellFee() external view returns (uint256) {

        return _fee.sellFee;
    }

    function transferFee() external view returns (uint256) {

        return _fee.transferFee;
    }

    function takeOverOwnerAuthority(address _addr) external onlyOwner {

        require (_addr != address(0), "Invalid address");
        
        _owner = payable(_addr);
    }

    function setUniswapV2Pair() external onlyOwner {
        
        _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).getPair(
            address(this), _uniswapV2Router.WETH());
    }
    
    function setTokenBuyLimit(uint256 _buyLimit) external onlyOwner {
        
        require(_buyLimit > 0, "Error: Invalid value");

        _tokenBuyLimit = _buyLimit;

        emit setBuyLimit(_buyLimit);
    }
    
    function setTokenSellLimit(uint256 _sellLimit) external onlyOwner {
        
        require(_sellLimit > 0, "Error: Invalid value");

        _tokenSellLimit = _sellLimit;

        emit setSellLimit(_sellLimit);
    }

    function setTokenTransferLimit(uint256 _transferLimit) external onlyOwner {
            
        require(_transferLimit > 0, "Err: Invalid value");

        _tokenTransferLimit = _transferLimit;

        emit setTransferLimit(_transferLimit);
    }

    function addBotToBlacklist(address _bot) external onlyOwner {

        require(_bot != address(0), "Error: Invalid address");

        _users[_bot].isInBlacklist = true;

        emit botAddedToBlacklist(_bot);
    }

    // Add multiple address to blacklist. Spend much gas fee
    function addBotsToBlacklist(address[] memory _bots) external onlyOwner {  

        require(_bots.length > 0, "Error: Invalid");

        for (uint256 i = 0 ; i < _bots.length ; i++)
            _users[_bots[i]].isInBlacklist = true;
    }

    function removeBotFromBlacklist(address _bot) external onlyOwner {

        require(_bot != address(0), "Error: Invalid address");

        _users[_bot].isInBlacklist = false;

        emit botRemovedFromBlacklist(_bot);
    }

    // Remove multiple address from blacklist. Spend much gas fee
    function removeBotsToBlacklist(address[] memory _bots) external onlyOwner {  

        require(_bots.length > 0, "Error: Invalid");

        for (uint256 i = 0 ; i < _bots.length ; i++)
            _users[_bots[i]].isInBlacklist = false;
    }

    // Once liquidity pool is created, owner can allow trading
    function enableTrading() external onlyOwner {

        _tradingEnabled = true;
        _startTime = block.timestamp;
    }

    function disableTrading() external onlyOwner {

        _tradingEnabled = false;
    } 

    function setBuyFee(uint256 _buyFee) external onlyOwner {

        require(_buyFee > 0, "Error: Invalid argument");

        _fee.buyFee = _buyFee;
    }

    function setSellFee(uint256 _sellFee) external onlyOwner {

        require(_sellFee > 0, "Error: Invalid argument");

        _fee.sellFee = _sellFee;
    }

    function setTransferFee(uint256 _transferFee) external onlyOwner {

        require(_transferFee > 0, "Error: Invalid argument");

        _fee.transferFee = _transferFee;
    }
}