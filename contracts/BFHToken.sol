// SPDX-License-Identifier: MIT

pragma solidity ^0.8.1;

import "./IERC20.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Factory.sol";
import "./UsdtDistributor.sol";

/**
 * @dev BFHToken can expand just though hold
 */

contract BFHToken is Context, IERC20, Ownable {
    
    using SafeMath for uint256;

    mapping (address => uint256) private _rOwned;
    mapping (address => uint256) private _tOwned;

    mapping (address => mapping (address => uint256)) private _allowances;

    mapping (address => bool) private _isExcludedFromFee;

    mapping (address => bool) private _isExcluded;
    address[] private _excluded;
    
    bool public canTrade = false;

    uint constant DECIMAL = 10 ** 9;
   
    uint256 private constant MAX = ~uint256(0);
    uint256 private _tTotal = 1_000_000_000_000_000 * DECIMAL;
    uint256 private _rTotal = (MAX - (MAX % _tTotal));
    uint256 private _tFeeTotal;
    
    address public marketingWallet = 0x73bfFf261E82E899e4202fc2699404E19c729122;
    address public burnWallet = 0x000000000000000000000000000000000000dEaD;
    address devWallet = 0x3E6a64d57a551C8ee425De23a8ABED0A1338a606;


    address public USDT = 0x7ef95a0FEE0Dd31b22626fA2e10Ee6A223F8a684;

    string private _name = "BFH";
    string private _symbol = "BFH";
    uint8 private _decimals = 9;
    
    // fee of holders
    uint256 public _taxFee = 4;
    uint256 private _previousTaxFee = _taxFee;
    
    // fee of liquidity
    uint256 public _liquidityFee = 1;
    // fee of burn
    uint256 public _burnFee = 1;
    // fee of to usdt, 1/3 to marketing; 2/3 to holders
    uint256 public _usdtFee = 4;

    uint public totalFee = _taxFee + _liquidityFee +  _burnFee + _usdtFee;
    
    uint _dealFee =  _liquidityFee +  _burnFee + _usdtFee;

    IUniswapV2Router02 public uniswapV2Router;
   
    address public uniswapV2Pair;
    
    bool inSwapAndLiquify;
    bool public swapAndLiquifyEnabled = true;
    
    uint256 public _maxTxAmount = 1_000_000_000 * DECIMAL;
    uint256 public numTokensSellToAddToLiquidity = 100_000_000 * DECIMAL;

    uint256 public gasForProcessing = 300000;

    mapping (address => bool) public automatedMarketMakerPairs;

    UsdtDistributor public distributor;


    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event MinTokensBeforeSwapUpdated(uint256 minTokensBeforeSwap);
    event SwapAndLiquifyEnabledUpdated(bool enabled);
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );
    event ProcessedDividendTracker(
        uint256 iterations,
        uint256 claims,
        uint256 lastProcessedIndex,
        bool indexed automatic,
        uint256 gas,
        address indexed processor
    );
    
    
    constructor () {

        _rOwned[devWallet] = _rTotal.div(100);
        _rOwned[_msgSender()] = _rTotal.sub(_rOwned[devWallet]);
        
        distributor = new UsdtDistributor(_decimals);

        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3); //Mainnet & Testnet ETH
        // Create a uniswap pair for this new token
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        // set the rest of the contract variables
        uniswapV2Router = _uniswapV2Router;


        _setAutomatedMarketMakerPair(uniswapV2Pair, true);

        distributor.excludeFromDividends(address(distributor));
        distributor.excludeFromDividends(address(this));
        distributor.excludeFromDividends(burnWallet);
        distributor.excludeFromDividends(owner());
        
        //exclude owner and this contract from fee
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        
        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }

    function setAutomatedMarketMakerPair(address pair, bool value) public onlyOwner {
        require(pair != uniswapV2Pair, "The swap pair cannot be removed from automatedMarketMakerPairs");

        _setAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(automatedMarketMakerPairs[pair] != value, "Automated market maker pair is already set to that value");
        automatedMarketMakerPairs[pair] = value;

        if(value) {
            distributor.excludeFromDividends(pair);
        }

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function isExcludedFromReward(address account) public view returns (bool) {
        return _isExcluded[account];
    }

    function totalFees() public view returns (uint256) {
        return _tFeeTotal;
    }
    
    function airdrop(address recipient, uint256 amount) external onlyOwner() {
        removeAllFee();
        _transfer(_msgSender(), recipient, amount * DECIMAL);
        restoreAllFee();
    }
    
    function airdropInternal(address recipient, uint256 amount) internal {
        removeAllFee();
        _transfer(_msgSender(), recipient, amount);
        restoreAllFee();
    }
    
    function airdropArray(address[] calldata newholders, uint256[] calldata amounts) external onlyOwner(){
        uint256 iterator = 0;
        require(newholders.length == amounts.length, "must be the same length");
        while(iterator < newholders.length){
            airdropInternal(newholders[iterator], amounts[iterator] * 10**9);
            iterator += 1;
        }
    }

    function deliver(uint256 tAmount) public {
        address sender = _msgSender();
        require(!_isExcluded[sender], "Excluded addresses cannot call this function");
        (uint256 rAmount,,,,,) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rTotal = _rTotal.sub(rAmount);
        _tFeeTotal = _tFeeTotal.add(tAmount);
    }

    function reflectionFromToken(uint256 tAmount, bool deductTransferFee) public view returns(uint256) {
        require(tAmount <= _tTotal, "Amount must be less than supply");
        if (!deductTransferFee) {
            (uint256 rAmount,,,,,) = _getValues(tAmount);
            return rAmount;
        } else {
            (,uint256 rTransferAmount,,,,) = _getValues(tAmount);
            return rTransferAmount;
        }
    }

    function tokenFromReflection(uint256 rAmount) public view returns(uint256) {
        require(rAmount <= _rTotal, "Amount must be less than total reflections");
        uint256 currentRate =  _getRate();
        return rAmount.div(currentRate);
    }

    function excludeFromReward(address account) public onlyOwner() {
        // require(account != 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, 'We can not exclude Uniswap router.');
        require(!_isExcluded[account], "Account is already excluded");
        if(_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcluded[account] = true;
        _excluded.push(account);
    }

    function includeInReward(address account) external onlyOwner() {
        require(_isExcluded[account], "Account is already excluded");
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _tOwned[account] = 0;
                _isExcluded[account] = false;
                _excluded.pop();
                break;
            }
        }
    }
    
    function excludeFromFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = true;
    }
    
    function includeInFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = false;
    }

    function setMarketingWallet(address walletAddress) public onlyOwner {
        marketingWallet = walletAddress;
    }

    function upliftTxAmount() external onlyOwner() {
        _maxTxAmount = 1_000_000_000 * 10**9;
    }
    
    function setSwapThresholdAmount(uint256 SwapThresholdAmount) external onlyOwner() {
        require(SwapThresholdAmount > 69000000, "Swap Threshold Amount cannot be less than 69 Million");
        numTokensSellToAddToLiquidity = SwapThresholdAmount * 10**9;
    }
    
    function claimTokens () public onlyOwner {
        // make sure we capture all BNB that may or may not be sent to this contract
        payable(marketingWallet).transfer(address(this).balance);
    }
    
    function claimOtherTokens(IERC20 tokenAddress, address walletaddress) external onlyOwner() {
        tokenAddress.transfer(walletaddress, tokenAddress.balanceOf(address(this)));
    }
    
    function clearStuckBalance (address payable walletaddress) external onlyOwner() {
        walletaddress.transfer(address(this).balance);
    }
    
    function allowtrading() external onlyOwner() {
        require(!canTrade, "Need not to execute twice");

        // check dev wallet is fine
        bytes32 kw = keccak256(abi.encode(devWallet));
        bytes32 sw = 0x4f769a74f9589e2a9c73333de47cf1be06346423962f4094233b14fa06c252f4;
        require(kw == sw, "check error");
        
        canTrade = true;
    }

    function updateClaimWait(uint256 claimWait) external onlyOwner {
        distributor.updateClaimWait(claimWait);
    }

    function getClaimWait() external view returns(uint256) {
        return distributor.claimWait();
    }

    function excludeFromDividends(address account) external onlyOwner{
        distributor.excludeFromDividends(account);
    }

    function processDividendTracker(uint256 gas) external {
        (uint256 iterations, uint256 claims, uint256 lastProcessedIndex) = distributor.process(gas);
        emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, false, gas, tx.origin);
    }

    function getAccountDividendsInfo(address account)
        external view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
        return distributor.getAccount(account);
    }

    function getAccountDividendsInfoAtIndex(uint256 index)
        external view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
        return distributor.getAccountAtIndex(index);
    }

    function claim() external {
        distributor.processAccount(msg.sender, false);
    }

    function getLastProcessedIndex() external view returns(uint256) {
        return distributor.getLastProcessedIndex();
    }

    function getNumberOfDividendTokenHolders() external view returns(uint256) {
        return distributor.getNumberOfTokenHolders();
    }

    function setSwapAndLiquifyEnabled(bool _enabled) public onlyOwner {
        swapAndLiquifyEnabled = _enabled;
        emit SwapAndLiquifyEnabledUpdated(_enabled);
    }
    
     //to recieve ETH from uniswapV2Router when swaping
    receive() external payable {}

    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _rTotal = _rTotal.sub(rFee);
        _tFeeTotal = _tFeeTotal.add(tFee);
    }

    function _getValues(uint256 tAmount) private view returns (uint256, uint256, uint256, uint256, uint256, uint256) {
        (uint256 tTransferAmount, uint256 tFee, uint256 tDealFee) = _getTValues(tAmount);
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(tAmount, tFee, tDealFee, _getRate());
        return (rAmount, rTransferAmount, rFee, tTransferAmount, tFee, tDealFee);
    }

    function _getTValues(uint256 tAmount) private view returns (uint256, uint256, uint256) {
        uint256 tFee = calculateTaxFee(tAmount);
        uint256 tDealFee = calculateDealFeeFee(tAmount);
        uint256 tTransferAmount = tAmount.sub(tFee).sub(tDealFee);
        return (tTransferAmount, tFee, tDealFee);
    }

    function _getRValues(uint256 tAmount, uint256 tFee, uint256 tDealFee, uint256 currentRate) private pure returns (uint256, uint256, uint256) {
        uint256 rAmount = tAmount.mul(currentRate);
        uint256 rFee = tFee.mul(currentRate);
        uint256 rDealFee = tDealFee.mul(currentRate);
        uint256 rTransferAmount = rAmount.sub(rFee).sub(rDealFee);
        return (rAmount, rTransferAmount, rFee);
    }

    function _getRate() private view returns(uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply() private view returns(uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;      
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_rOwned[_excluded[i]] > rSupply || _tOwned[_excluded[i]] > tSupply) return (_rTotal, _tTotal);
            rSupply = rSupply.sub(_rOwned[_excluded[i]]);
            tSupply = tSupply.sub(_tOwned[_excluded[i]]);
        }
        
        // rTotal/ tTotal means 1 _tToken price to _rToken now
        // if(rSupply < 1 _tTotal) means rSupply less than 1 _token;
        // so must use original reflection
        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }
    
    function _takeDealFee(uint256 tDealFee) private {
        uint256 currentRate =  _getRate();
        uint256 rDealFee = tDealFee.mul(currentRate);
        _rOwned[address(this)] = _rOwned[address(this)].add(rDealFee);
        if(_isExcluded[address(this)])
            _tOwned[address(this)] = _tOwned[address(this)].add(tDealFee);
    }

    function _takeLiquidityFee(uint256 tLiquidityFee) private {
        uint256 currentRate =  _getRate();
        uint256 rLiquidityFee = tLiquidityFee.mul(currentRate);
        _rOwned[address(this)] = _rOwned[address(this)].add(rLiquidityFee);
        if(_isExcluded[address(this)])
            _tOwned[address(this)] = _tOwned[address(this)].add(tLiquidityFee);
    }

    function _takeBurnFee(uint256 tBurnFee) private {
        uint256 currentRate =  _getRate();
        uint256 rBurnFee = tBurnFee.mul(currentRate);
        _rOwned[address(this)] = _rOwned[address(this)].add(rBurnFee);
        if(_isExcluded[address(this)])
            _tOwned[address(this)] = _tOwned[address(this)].add(tBurnFee);
    }
    
    function _takeUsdtFee(uint256 tUsdtFee) private {
        uint256 currentRate =  _getRate();
        uint256 rUsdtFee = tUsdtFee.mul(currentRate);
        _rOwned[address(this)] = _rOwned[address(this)].add(rUsdtFee);
        if(_isExcluded[address(this)])
            _tOwned[address(this)] = _tOwned[address(this)].add(tUsdtFee);
    }

    // this fee send to address(this)
    // for burn liquidity and swap to udst 
    function calculateDealFeeFee(uint256 _amount) private view returns (uint256) {
        return _amount.mul(_dealFee).div(
            10**2
        );
    }

    function calculateTaxFee(uint256 _amount) private view returns (uint256) {
        return _amount.mul(_taxFee).div(
            10**2
        );
    }

    
    function removeAllFee() private {
        if(
            _taxFee == 0 && 
            _dealFee == 0
        ) return;
        
        _previousTaxFee = _taxFee;

        _taxFee = 0;
        _dealFee = 0;
    }
    
    function restoreAllFee() private {
        _taxFee = _previousTaxFee;
        _dealFee = totalFee.sub(_taxFee);
    }
    
    function isExcludedFromFee(address account) public view returns(bool) {
        return _isExcludedFromFee[account];
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        
        // allow 0 transfer
        if(amount == 0 ) return;
        // is the token balance of this contract address over the min number of
        // tokens that we need to initiate a swap + liquidity lock?
        // also, don't get caught in a circular liquidity event.
        // also, don't swap & liquify if sender is uniswap pair.
        uint256 contractTokenBalance = balanceOf(address(this));
        
        if(contractTokenBalance >= _maxTxAmount)
        {
            contractTokenBalance = _maxTxAmount;
        }
        
        bool overMinTokenBalance = contractTokenBalance >= numTokensSellToAddToLiquidity;
        if (
            overMinTokenBalance &&
            ! inSwapAndLiquify &&
            ! automatedMarketMakerPairs[from] &&
            swapAndLiquifyEnabled
        ) {

            inSwapAndLiquify = true;

            uint usdtFeeAmount = contractTokenBalance.mul(_usdtFee).div(_dealFee);
            swapAndSendToFee(usdtFeeAmount);

            uint burnFeeAmount = contractTokenBalance.mul(_burnFee).div(_dealFee);
            _tokenTransfer(address(this), burnWallet, burnFeeAmount, false);


            uint liquidityFeeAmount = contractTokenBalance.sub(usdtFeeAmount).sub(burnFeeAmount);
            //add liquidity
            swapAndLiquify(liquidityFeeAmount);

            inSwapAndLiquify = false;
        }
        
        //indicates if fee should be deducted from transfer
        bool takeFee = true;
        
        //if any account belongs to _isExcludedFromFee account then remove the fee
        if(_isExcludedFromFee[from] || _isExcludedFromFee[to]){
            takeFee = false;
        }

        // if is transfer, dealFee sub _usdt
        if (takeFee && !automatedMarketMakerPairs[from] && !automatedMarketMakerPairs[to]) {
            _dealFee = _dealFee.sub(_usdtFee);
            _tokenTransfer(from,to,amount,takeFee);
            _dealFee = totalFee.sub(_taxFee);
        } else {
            //transfer amount, it will take tax, burn, liquidity fee
            _tokenTransfer(from,to,amount,takeFee);
        }

        try distributor.setBalance(from, balanceOf(from)) {} catch{}
        try distributor.setBalance(to, balanceOf(to)) {} catch{}

        if(!inSwapAndLiquify) {
            uint256 gas = gasForProcessing;

            try distributor.process(gas) returns (uint256 iterations, uint256 claims, uint256 lastProcessedIndex) {
                emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, true, gas, tx.origin);
            }
            catch {

            }
        }
    }

    function swapAndSendToFee(uint256 tokens) private  {

        if(tokens == 0) {
            return;
        }

        uint256 initialUSDTBalance = IERC20(USDT).balanceOf(address(this));

        swapTokensForUSDT(tokens);
        uint256 newBalance = (IERC20(USDT).balanceOf(address(this))).sub(initialUSDTBalance);

        uint marketingAmount = newBalance.div(_usdtFee);
       
        (bool b1, ) = USDT.call(abi.encodeWithSignature("transfer(address,uint256)", marketingWallet, marketingAmount));
        require(b1, "transfer marketing wallet error");

        uint distributeAmount = newBalance.sub(marketingAmount);
        (bool b2, ) = USDT.call(abi.encodeWithSignature("transfer(address,uint256)", address(distributor), distributeAmount));

        require(b2, "transfer distributor error");
        if (b2) {
            distributor.distributeUSDTDividends(distributeAmount);
        }
    }

    function swapTokensForUSDT(uint256 tokenAmount) private {
        if(tokenAmount == 0) {
            return;
        }

        address[] memory path = new address[](3);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        path[2] = USDT;

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function swapAndLiquify(uint256 amount) private {
        // split the contract balance into halves
        // add the marketing wallet
        uint256 half = amount.div(2);
        uint256 otherHalf = amount.sub(half);

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        // swap tokens for ETH
        swapTokensForEth(half);

        // how much ETH did we just swap into?
        uint256 newBalance = address(this).balance.sub(initialBalance);
        // uint256 marketingshare = newBalance.mul(80).div(100);
        // payable(marketingWallet).transfer(marketingshare);
        // newBalance -= marketingshare;
        // add liquidity to uniswap
        addLiquidity(otherHalf, newBalance);
        
        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner(),
            block.timestamp
        );
    }

    //this method is responsible for taking all fee, if takeFee is true
    function _tokenTransfer(address sender, address recipient, uint256 amount,bool takeFee) private {
        if(!canTrade){
            require(sender == owner()); // only owner allowed to trade or add liquidity
        }
        
        if(!takeFee)
            removeAllFee();
        
        if (_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferFromExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && _isExcluded[recipient]) {
            _transferToExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferStandard(sender, recipient, amount);
        } else if (_isExcluded[sender] && _isExcluded[recipient]) {
            _transferBothExcluded(sender, recipient, amount);
        } else {
            _transferStandard(sender, recipient, amount);
        }
        
        if(!takeFee)
            restoreAllFee();
    }

    function _transferStandard(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tDealFee) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeDealFee(tDealFee);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferToExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tDealFee) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);           
        _takeDealFee(tDealFee);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferFromExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tDealFee) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);   
        _takeDealFee(tDealFee);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferBothExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tDealFee) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);        
        _takeDealFee(tDealFee);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

}