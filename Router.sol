pragma solidity >0.6.4;

interface IERC20 {
    function approve(address _spender, uint256 amount)
        external
        returns (bool);

    function allowance(address from, address to)
        external
        returns (uint256);

    function transferFrom(address dst, address to, uint256 amount)
        external
        returns (bool);

    function balanceOf(address user)
        external
        returns (uint256);
}

interface I1inch {

    function swap(IERC20 fromToken, IERC20 destToken, uint256 amount, uint256 minReturn, uint256[] calldata distribution, uint256 flags)
    external payable
    returns(uint256);

    function makeGasDiscount(uint256 gasSpent, uint256 returnAmount, bytes calldata msgSenderCalldata);

}

interface IUni {

    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
    external payable
    returns (uint[] memory amounts);

    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
    external
    returns (uint[] memory amounts);

    function WETH() external pure returns (address);
}

contract Router {

    mapping(address => mapping(address => uint256)) private balance;
    mapping(address => bool) validUser;
    address payable owner;

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    modifier onlyUser {
        require(validUser[msg.sender] == true);
        _;
    }

    event Received(address, uint);
    event Error(address);

    receive() external payable {
        if (validUser[msg.sender] == true) {
            balance[msg.sender][ETH] += msg.value;
            emit Received(msg.sender, msg.value);
        } else {
            balance[owner][ETH] += msg.value;
        }
    }

    fallback() external payable {
        revert();
    }

    I1inch OneSplit;
    IUni Uni;
    address ETH = address(0);
    constructor(address _oneSplit, address _Uni) payable {
        owner = payable(msg.sender);
        validUser[msg.sender] = true;
        balance[msg.sender][ETH] = msg.value;
        OneSplit = I1inch(_oneSplit);
        Uni = IUni(_Uni);
    }

    function addUser(address _user) external onlyOwner {
        validUser[_user] = true;
    }

    function removeUser(address _user) external onlyOwner {
        validUser[_user] = false;
    }

    function swap(address _fromToken, address _toToken, uint256 amountIn, uint256 minReturn, uint256[] calldata distribution, uint256 flags)
    external payable onlyUser {
        require(balance[msg.sender][_fromToken] >= amountIn, 'Insufficient Balance');
        if (_fromToken == ETH) {
            try OneSplit.swap{value: amountIn}(IERC20(ETH), IERC20(_toToken), amountIn, minReturn, distribution, flags)
            returns (uint256 amountOut) {
                balance[msg.sender][ETH] -= amountIn;
                balance[msg.sender][_toToken] += amountOut;
            } catch {
                emit Error(msg.sender);
                revert();
            }
        } else {
             try OneSplit.swap(IERC20(_toToken), IERC20(ETH), amountIn, minReturn, distribution, flags)
             returns (uint256 amountOut) {
                 balance[msg.sender][_fromToken] -= amountIn;
                 balance[msg.sender][ETH] += amountOut;
             } catch {
                emit Error(msg.sender);
                revert();
            }
        }
    }

    function swapETHForTokens(address token, uint amountIn, uint amountOutMin) external payable onlyUser {
        require(balance[msg.sender][ETH] >= amountIn, 'Insufficient Balance');
        address[] memory path = new address[](2);
        path[0] = Uni.WETH();
        path[1] = token;

        try Uni.swapExactETHForTokens{ value: amountIn }(amountOutMin, path, address(this), block.timestamp)
        returns (uint[] memory amounts) {
            balance[msg.sender][ETH] -= amountIn;
            balance[msg.sender][token] += amounts[1];
        } catch {
            emit Error(msg.sender);
            revert();
         }
    }

    function swapTokensForETH(address token, uint amountIn, uint amountOutMin) external payable onlyUser {
        require(balance[msg.sender][token] >= amountIn, 'Insufficient Balance');
        require(IERC20(token).approve(address(Uni), amountIn), 'approve failed.');
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = Uni.WETH();
        try Uni.swapExactTokensForETH(amountIn, amountOutMin, path, address(this), block.timestamp)
        returns (uint[] memory amounts) {
            balance[msg.sender][token] -= amountIn;
            balance[msg.sender][ETH] += amounts[1];
        } catch {
            emit Error(msg.sender);
            revert();
        }
    }

    function removeEth() external payable onlyUser {
        require(balance[msg.sender][ETH] > 0);
        payable(msg.sender).transfer(balance[msg.sender][ETH]);
        balance[msg.sender][ETH] = 0;
    }

    function removeTokens(IERC20 _token) external payable onlyUser {
        require(balance[msg.sender][address(_token)] > 0);
        require(_token.approve(msg.sender, balance[msg.sender][address(_token)]), 'approve failed.');
        _token.transferFrom(address(this), msg.sender, balance[msg.sender][address(_token)]);
        balance[msg.sender][address(_token)] = 0;
    }

    function drainETH() external payable onlyOwner {
        owner.transfer(address(this).balance);
    }

    function drainToken(IERC20 _token) external payable onlyOwner{
         require(_token.approve(msg.sender, _token.balanceOf(address(this))), 'approve failed.');
        _token.transferFrom(address(this), owner, _token.balanceOf(address(this)));
    }

    function getUserBalance(address user, address token) external view onlyUser returns (uint256) {
        return balance[user][token];
    }
}