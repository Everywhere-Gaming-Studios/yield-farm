pragma solidity >=0.6.12;
pragma experimental ABIEncoderV2;
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/IMasterChef.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IStrategy.sol";


contract MasterChef is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;
    using BoringERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of COSMICs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accCosmicPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accCosmicPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. COSMICs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that COSMICs distribution occurs.
        uint256 accCosmicPerShare;   // Accumulated COSMICs per share, times 1e12. See below.
        uint16 depositFeeBP;      // Deposit fee in basis points
    }

    // The cosmic TOKEN!
    Cosmic public cosmic;
    // Dev address.
    address public devaddr;
    // cosmic tokens created per block.
    uint256 public cosmicPerBlock;
    // Bonus muliplier for early cosmic makers.
    uint256 public constant BONUS_MULTIPLIER = 1;
    // Deposit Fee address
    address public feeAddress;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    /// @notice Address of each `IStrategy`.
    IStrategy[] public strategies;
    /// @notice Address of the LP token for each MCHEF pool.
    IERC20[] public lpToken;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetFeeAddress(address indexed user, address indexed newAddress);
    event SetDevAddress(address indexed user, address indexed newAddress);
    event UpdateEmissionRate(address indexed user, uint256 cosmicPerBlock);

    constructor(
        Cosmic _cosmic,
        address _devaddr,
        address _feeAddress,
        uint256 _cosmicPerBlock
        ) public {
        cosmic = _cosmic;
        devaddr = _devaddr;
        feeAddress = _feeAddress;
        cosmicPerBlock = _cosmicPerBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, address _lpToken, uint16 _depositFeeBP,  IStrategy _strategy,  bool _withUpdate) public onlyOwner {
        require(_depositFeeBP <= 10000, "add: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        strategies.push(_strategy);
        lpToken.push(IERC20(_lpToken));
        poolInfo.push(PoolInfo({
        lpToken : IBEP20(_lpToken),
        allocPoint : _allocPoint,
        lastRewardBlock : lastRewardBlock,
        accCosmicPerShare : 0,
        depositFeeBP : _depositFeeBP
        }));
    }

    // Update the given pool's cosmic allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP,  IStrategy _strategy, bool _withUpdate) public onlyOwner {
        require(_depositFeeBP <= 10000, "set: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
        if (address(strategies[_pid]) != address(_strategy)) {
                if (address(strategies[_pid]) != address(0)) {
                    _withdrawAllFromStrategy(_pid, strategies[_pid]);
                }
                if (address(_strategy) != address(0)) {
                    _depositAllToStrategy(_pid, _strategy);
                }
                strategies[_pid] = _strategy; 
            }
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending COSMICs on frontend.
    function pendingCosmic(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accCosmicPerShare = pool.accCosmicPerShare;
        uint256 lpSupply;
        if (address(strategies[_pid]) != address(0)) {
            lpSupply = pool.lpToken.balanceOf(address(this)).add(strategies[_pid].balanceOf());
        }
        else {
            lpSupply = pool.lpToken.balanceOf(address(this));
        }
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 cosmicReward = multiplier.mul(cosmicPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accCosmicPerShare = accCosmicPerShare.add(cosmicReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accCosmicPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply;
        if (address(strategies[_pid]) != address(0)) {
                lpSupply = pool.lpToken.balanceOf(address(this)).add(strategies[_pid].balanceOf());
            }
            else {
                lpSupply = pool.lpToken.balanceOf(address(this));
        }
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 cosmicReward = multiplier.mul(cosmicPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        cosmic.mint(devaddr, cosmicReward.div(12));
        cosmic.mint(address(this), cosmicReward);
        pool.accCosmicPerShare = pool.accCosmicPerShare.add(cosmicReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for cosmic allocation.
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accCosmicPerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                safeCosmicTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            if (pool.depositFeeBP > 0) {
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                user.amount = user.amount.add(_amount).sub(depositFee);
            } else {
                user.amount = user.amount.add(_amount);
            }
            IStrategy _strategy = strategies[_pid];
            if (address(_strategy) != address(0)) {
                uint256 _amount1 = pool.lpToken.balanceOf(address(this));
                lpToken[_pid].safeTransfer(address(_strategy), _amount1);
                _strategy.deposit();
            }
        }
        user.rewardDebt = user.amount.mul(pool.accCosmicPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }
    

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        uint256 balance = pool.lpToken.balanceOf(address(this));
        IStrategy strategy = strategies[_pid];
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accCosmicPerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0) {
            safeCosmicTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            if (_amount > balance) {
                uint256 missing = _amount.sub(balance);
                uint256 withdrawn = strategy.withdraw(missing);
                _amount = balance.add(withdrawn);
            }   
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accCosmicPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        uint256 balance = pool.lpToken.balanceOf(address(this));
        IStrategy strategy = strategies[_pid];
        if (amount > balance) {
                uint256 missing = amount.sub(balance);
                uint256 withdrawn = strategy.withdraw(missing);
                amount = balance.add(withdrawn);
            }   
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe cosmic transfer function, just in case if rounding error causes pool to not have enough COSMICs.
    function safeCosmicTransfer(address _to, uint256 _amount) internal {
        uint256 cosmicBal = cosmic.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > cosmicBal) {
            transferSuccess = cosmic.transfer(_to, cosmicBal);
        } else {
            transferSuccess = cosmic.transfer(_to, _amount);
        }
        require(transferSuccess, "safeCosmicTransfer: transfer failed");
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
        emit SetDevAddress(msg.sender, _devaddr);
    }

    function setFeeAddress(address _feeAddress) public {
        require(msg.sender == feeAddress, "setFeeAddress: FORBIDDEN");
        feeAddress = _feeAddress;
        emit SetFeeAddress(msg.sender, _feeAddress);
    }

    //Pancake has to add hidden dummy pools inorder to alter the emission, here we make it simple and transparent to all.
    function updateEmissionRate(uint256 _cosmicPerBlock) public onlyOwner {
        massUpdatePools();
        cosmicPerBlock = _cosmicPerBlock;
        emit UpdateEmissionRate(msg.sender, _cosmicPerBlock);
    }

    function massHarvestFromStrategies() external {
        uint256 len = strategies.length;
        for (uint256 i = 0; i < len; ++i) {
            if (address(strategies[i]) != address(0)) {
                strategies[i].harvest();
            }
        }
    }

    function _depositAllToStrategy(uint256 _pid, IStrategy _strategy) internal {
        IERC20 _lpToken = lpToken[_pid];
        uint256 _strategyBalanceBefore = _strategy.balanceOf();
        uint256 _balanceBefore = _lpToken.balanceOf(address(this));
        require(address(_lpToken) == _strategy.want(), '!lpToken');

        if (_balanceBefore > 0) {
            _lpToken.safeTransfer(address(_strategy), _balanceBefore);
            _strategy.deposit();

            uint256 _strategyBalanceAfter = _strategy.balanceOf();
            uint256 _strategyBalanceDiff = _strategyBalanceAfter.sub(_strategyBalanceBefore);

            require(_strategyBalanceDiff == _balanceBefore, '!balance1');

            uint256 _balanceAfter = _lpToken.balanceOf(address(this));
            require(_balanceAfter == 0, '!balance2');
        }
    }

    function _withdrawAllFromStrategy(uint256 _pid, IStrategy _strategy) internal {
        IERC20 _lpToken = lpToken[_pid];
        uint256 _strategyBalance = _strategy.balanceOf();
        require(address(_lpToken) == _strategy.want(), '!lpToken');

        if (_strategyBalance > 0) {
            _strategy.withdraw(_strategyBalance);
            uint256 _currentBalance = _lpToken.balanceOf(address(this));

            require(_currentBalance >= _strategyBalance, '!balance1');

            _strategyBalance = _strategy.balanceOf();
            require(_strategyBalance == 0, '!balance2');
        }
    }

}