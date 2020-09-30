/*
     Ample Harvest - Option Protocol for Ampleforth

     Deployments: 
     Factory - 0xe4ec34BA64954dea49Cd2044867C580EDa8743e8 (rinkeby)

*/

pragma solidity ^0.5.0;
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v2.5.0/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v2.5.0/contracts/token/ERC20/ERC20Detailed.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v2.5.0/contracts/token/ERC20/ERC20Mintable.sol";

import "github.com/smartcontractkit/chainlink/evm-contracts/src/v0.5/ChainlinkClient.sol";

contract DSMath {
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "ds-math-sub-underflow");
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }

    function min(uint x, uint y) internal pure returns (uint z) {
        return x <= y ? x : y;
    }
    function max(uint x, uint y) internal pure returns (uint z) {
        return x >= y ? x : y;
    }
    function imin(int x, int y) internal pure returns (int z) {
        return x <= y ? x : y;
    }
    function imax(int x, int y) internal pure returns (int z) {
        return x >= y ? x : y;
    }

    uint constant WAD = 10 ** 9; //CHANGE: changed to Ampleforth precision
    uint constant RAY = 10 ** 27;

    function wmul(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, y), WAD / 2) / WAD;
    }
    function rmul(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, y), RAY / 2) / RAY;
    }
    function wdiv(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, WAD), y / 2) / y;
    }
    function rdiv(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, RAY), y / 2) / y;
    }

    // This famous algorithm is called "exponentiation by squaring"
    // and calculates x^n with x as fixed-point and n as regular unsigned.
    //
    // It's O(log n), instead of O(n) for naive repeated multiplication.
    //
    // These facts are why it works:
    //
    //  If n is even, then x^n = (x^2)^(n/2).
    //  If n is odd,  then x^n = x * x^(n-1),
    //   and applying the equation for even x gives
    //    x^n = x * (x^2)^((n-1) / 2).
    //
    //  Also, EVM division is flooring and
    //    floor[(n-1) / 2] = floor[n / 2].
    //
    function rpow(uint x, uint n) internal pure returns (uint z) {
        z = n % 2 != 0 ? x : RAY;

        for (n /= 2; n != 0; n /= 2) {
            x = rmul(x, x);

            if (n % 2 != 0) {
                z = rmul(z, x);
            }
        }
    }
    
}



contract ParentType { 
    
 using SafeMath for uint256; 
 
 uint256 constant public MAX_UINT = 2**256 - 1;
 uint256 constant public CONTRACT_SIZE = 100000000000; //100 AMPL  
 
 address public uAMPL = 0x027dbcA046ca156De9622cD1e2D907d375e53aa7; 
 address public uLINK = 0x01BE23585060835E02B77ef475b0Cc51aA1e0709;
 
 address public rinkebyOracle = 0x7AFe1118Ea78C1eae84ca8feE5C65Bc76CcF879e;
 
 bytes32 public alarmID = "4fff47c3982b4babba6a7dd694c9b204";
 bytes32 public httpID = "6d1bfe27e7034b1d87b5270556b17277";
 
 uint256 public target = 109;
 
 enum Type {PUT,CALL}

}

contract Owned {
    address public owner;
    address public newOwner;
    event OwnershipTransferred(address indexed _from, address indexed _to);

    constructor() public {
        owner = msg.sender;
    }

    modifier onlyOwner {
        if (msg.sender != owner) revert();
        _;
    }

    function transferOwnership(address _newOwner) onlyOwner public {
        newOwner = _newOwner;
    }
 
    function acceptOwnership() public {
        if (msg.sender == newOwner) {
           emit OwnershipTransferred(owner, newOwner);
            owner = newOwner;
        }
    }
 }


contract OptionFactory is ParentType, ChainlinkClient, Owned {
    
    //flat mapping of all contracts created: 
    mapping (uint256 => address) public optionsContracts;
    uint256 public totalContracts;
    uint256 public oracle_strike; 
    
    // series ==  expiry x strike x type
    mapping (uint256 =>  mapping (int256 => mapping (uint256 => address))) public tokenForSeries;
    mapping (uint256 =>  mapping (int256 => mapping (uint256 => address))) public claimForSeries;
    
    constructor() public  {
        
         setPublicChainlinkToken();    
    }
    
    
    /// @author Michael Colson
    /// @notice Write a new options contract. If the ERC-20 contract for this option doesn't exist,
    /// it is created. 
    /// @param strike The price difference from the target that the option will be exercisable if it is above (CALL) or below (PUT)
    /// @param expiry Unix time stamp. The option can be exercied early (American) any time up to this date. A separate Claim token 
    /// can be used by the writer to get their collateral back if their contracts were not exercised after expiry.
    /// @param optionType 0 to write a put option, 1 to write a call option.
    /// @param contracts The quanity of contracts to write. Each one requries 100 AMPL of collateral for a standardized contract.
    function writeOptionsContract(int256 strike, uint256 expiry, uint256 optionType, uint256 contracts) public {
        require (expiry > now);
        require (contracts != 0);
        
        //TO-DO: Decide wheter to keep collateral in factory or in a per token basis
        IERC20 collateral = IERC20(uAMPL); 
        collateral.transferFrom(msg.sender, address(this),CONTRACT_SIZE * contracts); 
        
        if(tokenForSeries[expiry][strike][optionType] == address(0)) {
        
           OptionsContract option = new OptionsContract(strike,expiry,Type(optionType),msg.sender);
           ClaimToken claim = new ClaimToken(strike,expiry,Type(optionType),msg.sender);
           collateral.transfer(address(option),CONTRACT_SIZE * contracts);
           
           //mint the initial token and transfer to sender
           option.mint(msg.sender,contracts);
           claim.mint(msg.sender,contracts);
           
           optionsContracts[totalContracts] = address(option);
           tokenForSeries[expiry][strike][optionType] = address(option);
           claimForSeries[expiry][strike][optionType] = address(claim);
           totalContracts++;
           
        } else {
            
            //mint an existing token and transfer to sender: 
            OptionsContract oc = OptionsContract(tokenForSeries[expiry][strike][optionType]);
            ClaimToken ct = ClaimToken(claimForSeries[expiry][strike][optionType]);
            collateral.transfer(address(oc),CONTRACT_SIZE * contracts);
            
            oc.mint(msg.sender,contracts);
            ct.mint(msg.sender,contracts);
        }
        
        emit OptionsWritten(msg.sender, strike, expiry, optionType, contracts); 
    }
    
    /// @author Michael Colson
    /// @notice Will start a Chainlink alarm clock to pipe the latest market info into the contract.
    /// Only the current admin can call this function.
    function startPriceFeed() public onlyOwner {
       Chainlink.Request memory req = buildChainlinkRequest(alarmID, address(this), this.requestStrike.selector);
       req.addUint("until", now + 5 minutes);
       sendChainlinkRequestTo(rinkebyOracle, req, 1 ether);
    }
    
    /// @author Michael Colson
    /// @notice Will request AMPL vWAP at the desired precision via HTTP Get oracles.
    function requestStrike(bytes32 _requestId) public recordChainlinkFulfillment(_requestId) { 
        
        Chainlink.Request memory request = buildChainlinkRequest(httpID, address(this), this.receiveStrike.selector);
        
        //Request VWAP from anyblock API: 
        // Set the URL to perform the GET request on
        request.add("get", "https://api.eth.events/market/AMPL_USD_via_ALL/daily-volume/");
        request.add("queryParams", "access_token=813718aa-f0c5-4427-b846-25a5cfaf4b28");
        // Set the path to find the desired data in the API response, where the response format is:
        // {"USD":243.33}
        request.add("path", "overallVWAP");
        
        // Multiply the result by 100 to remove decimals and measure it as a % deviation from the target (3 decimal precision)
        request.addInt("times", 100); 
        
        sendChainlinkRequestTo(rinkebyOracle, request, 0.1 ether);
    }
    
    function systemStrike() public view returns (uint256) {
        return oracle_strike; 
    }
    
    function receiveStrike(bytes32 _requestId, uint256 _vwap) public recordChainlinkFulfillment(_requestId) {
        oracle_strike = _vwap; 
        
        Chainlink.Request memory req = buildChainlinkRequest(alarmID, address(this), this.requestStrike.selector);
        req.addUint("until", now + 5 minutes);
        sendChainlinkRequestTo(rinkebyOracle, req, 1 ether);
    }
    
    /// @author Michael Colson
    /// @notice distance. This is what the strike prices of the options are compared against. 
    /// The deviation of the current vWAP and ideal price target. 
    function distance() public view returns (int) {
        return int256(target) - int256(oracle_strike);
    }
    
       
    /// @author Michael Colson
    /// @notice d2. The difference between current deviation and a given strike price.
    /// **May be used in a future DEX compoment as part of premium and option valuation calcualations.
    function d2(int stk) public view returns (int) {
        return distance() - stk;
    }
    
    //Security: -- Make sure tokens are valid to prevent relasing collateral to counterfeit tokens.
    
     /// @author Michael Colson
     /// @notice exercise. When given the address of a token created by this factory, it will determine if conditions are met.
     /// It will then release the due collateral at a rate of (balance / tokenSupply) * amount worth of AMPL.
     /// @param token Address of the token, must be in msg.sender's wallet. 
     /// @param amount Amount of tokens to exercise.
    function exercise(address token,uint amount) public {
        OptionsContract oc = OptionsContract(token);
        
        //Verification: 
        int   strike = oc.strike();
        uint  expiry = oc.expiry();
        uint  ot = uint(oc.optionality());
       
        address series = tokenForSeries[expiry][strike][ot];
        require(token == series);
        require (now <= expiry); 
        
        //Validation and collateral settlement
        if (strike == 0 && distance() != 0) revert();
        if (ot == 0 && strike < distance() && strike != 0) revert();
        if (ot == 1 && strike > distance() && strike != 0) revert();
        
        oc.exercise(amount, msg.sender);
        emit OptionExercised(msg.sender,token,amount,ot);
    }
    
    /// @author Michael Colson
    /// @notice claim - Will unconditionally return collateral if it's matching 
    /// option is not exercised. can only be called after expiry timestamp.
    function claim(address token, uint amount) public {
         ClaimToken ct = ClaimToken(token);
        
        //Verification: 
        int  strike = ct.strike();
        uint  expiry = ct.expiry();
        uint  ot = uint(ct.optionality());
       
        address series = claimForSeries[expiry][strike][ot];
        require(token == series);
        require (now > expiry); 
        
        OptionsContract oc = OptionsContract(tokenForSeries[expiry][strike][ot]);
        uint sup = ct.totalSupply(); 
        
        oc.redeem(amount,sup,msg.sender);
        
        ct.exercise(amount, msg.sender);
        emit CollateralRedeemed(msg.sender, token, amount);
        
        
    }
    
    /// @author Michael Colson
    /// @notice wdChainLink - Remove chainlink tokens.      
    function wdChainLink(uint256 amt) public onlyOwner { 
        IERC20 tokens = IERC20(uLINK); 
        tokens.transfer(msg.sender,amt);
    }
    
    event OptionsWritten(address writer, int256 strike, uint256 expiry, uint256 optionType, uint contracts); 
    event OptionExercised(address burner,address token, uint256 amount, uint256 optionType);
    event CollateralRedeemed(address redeemer, address token, uint256 amount);
    
}


contract OptionsContract is ParentType, ERC20, ERC20Detailed, ERC20Mintable { 
    
    int256 public strike; 
    uint256 public expiry; 
    address writer; 
    address factory;
    
    Type public optionality;
    
    constructor(int256 stk, uint256 exp, Type optionType, address wrt) public ERC20Detailed("Option","O",0) {
        strike = stk;
        expiry = exp;
        writer = wrt;
        optionality = optionType; 
        factory = msg.sender;
    }
    
    //Security: -- Now only factory can call exercise.
    //NEW: exercise at token-level now only burns the token. 
    function exercise(uint amount, address holder) public {
        require(msg.sender == factory);
       
         //Collateral settlement: 
        IERC20 collateral = IERC20(uAMPL); 
        uint bal = collateral.balanceOf(address(this));
        uint  ts = collateral.totalSupply();
        
        collateral.transfer(holder, (bal / ts) * amount); //(balance * amount) / totalSupply (for Rebase)
       
        
        _burn(holder, amount);
    }
    
    
    //NEW: Compliment function to claim - Since option contract now 
    //stores all funds directly, redeem releases the options collateral
    //back when factory burns a claim token. 
    function redeem(uint amount, uint supply, address holder) public {
         require(msg.sender == factory);
         
         IERC20 collateral = IERC20(uAMPL); 
         uint bal = collateral.balanceOf(address(this));
        
         collateral.transfer(holder, (bal / supply) * amount);
         
    }
   
}

contract ClaimToken is ParentType, ERC20, ERC20Detailed, ERC20Mintable { 
    
    int256 public strike; 
    uint256 public expiry; 
    address writer; 
    address factory;
    
    Type public optionality;
    
    constructor(int256 stk, uint256 exp, Type optionType, address wrt) public ERC20Detailed("Claim","C",0) {
        strike = stk;
        expiry = exp;
        writer = wrt;
        optionality = optionType; 
        factory = msg.sender;
    }
    
    function exercise(uint amount, address holder) public {
       
        require(msg.sender == factory); 
        _burn(holder, amount);
    }
    
}


