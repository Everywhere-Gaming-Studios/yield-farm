pragma solidity 0.6.12;

import '@uniswap/lib/contracts/libraries/TransferHelper.sol';
import "@openzeppelin/contracts/math/SafeMath.sol";
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import './utils/Context.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import './Hp.sol';

contract MasterChefHp is Ownable {
    using SafeMath for uint256;
    using SafeIERC20 for IIERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     
        uint256 rewardDebt; 
    }

    // Info of each pool.
    struct PoolInfo {
        IIERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. HPs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that HPs distribution occurs.
        uint256 accHpPerShare; // Accumulated HPs per share, times 1e12.
    }

    // The HP TOKEN!
    Hp public hp;
    // Dev address.
    address public devaddr;
    // HP tokens created per block.
    uint256 public hpPerBlock;
    // Bonus muliplier for early hp makers.
    uint256 public BONUS_MULTIPLIER = 1;

    //DepositFee
    uint256 public depositFee;
    //WithdrawFee
    uint256 public withdrawFee;


    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when HP mining starts.
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SwapNewToken(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        Hp _hp,
        address _devaddr,
        uint256 _hpPerBlock,
        uint256 _startBlock,
        uint256 _depositFee,
        uint256 _withdrawFee
    ) public {
        hp = _hp;
        devaddr = _devaddr;
        hpPerBlock = _hpPerBlock;
        startBlock = _startBlock;
        depositFee = _depositFee;
        withdrawFee = _withdrawFee;

        // staking pool
        poolInfo.push(PoolInfo({
            lpToken: _hp,
            allocPoint: 1000,
            lastRewardBlock: startBlock,
            accHpPerShare: 0
        }));

        totalAllocPoint = 1000;

    }

    function updateDepositFee(uint256 _depositFee) public onlyOwner {
        depositFee = _depositFee;
    }

    function updateWithdrawFee(uint256 _withdrawFee) public onlyOwner {
        withdrawFee = _withdrawFee;
    }

    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IIERC20 _lpToken, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accHpPerShare: 0
        }));
        updateStakingPool();
    }

    // Update the given pool's HP allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        if (prevAllocPoint != _allocPoint) {
            updateStakingPool();
        }
    }

    function updateStakingPool() internal {
        uint256 length = poolInfo.length;
        uint256 points = 0;
        for (uint256 pid = 1; pid < length; ++pid) {
            points = points.add(poolInfo[pid].allocPoint);
        }
        if (points != 0) {
            points = points.div(3);
            totalAllocPoint = totalAllocPoint.sub(poolInfo[0].allocPoint).add(points);
            poolInfo[0].allocPoint = points;
        }
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending HPs on frontend.
    function pendingHp(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accHpPerShare = pool.accHpPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 hpReward = multiplier.mul(hpPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accHpPerShare = accHpPerShare.add(hpReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accHpPerShare).div(1e12).sub(user.rewardDebt);
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
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 hpReward = multiplier.mul(hpPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        hp.mint(devaddr, hpReward.div(10));
        pool.accHpPerShare = pool.accHpPerShare.add(hpReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChefHp for HP allocation.
    function deposit(uint256 _pid, uint256 _amount) public {

        require (_pid != 0, 'deposit HP by staking');

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accHpPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeHpTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            if (depositFee > 0) {
                uint256 _depositFee = _amount.mul(depositFee).div(10000);
                uint256 _namount = _amount.sub(depositFee);
                pool.lpToken.safeTransferFrom(address(msg.sender), devaddr, _depositFee);
                pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _namount);
                user.amount = user.amount.add(_amount).sub(depositFee);
            } else {
                pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
                user.amount = user.amount.add(_amount);            
            }
        }
        user.rewardDebt = user.amount.mul(pool.accHpPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChefHp.
    function withdraw(uint256 _pid, uint256 _amount) public {

        require (_pid != 0, 'withdraw HP by unstaking');

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accHpPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeHpTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            if (withdrawFee > 0) {
                uint256 _withdrawFee = _amount.mul(withdrawFee).div(10000);
                uint256 _namount = _amount.
                pool.lpToken.safeTransfer(devaddr, _withdrawFee);
                pool.lpToken.safeTransfer(address(this), _namount);
                user.amount = user.amount.sub(_amount);
            } else {
                pool.lpToken.safeTransfer(address(msg.sender), _amount);
                user.amount = user.amount.sub(_amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accHpPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Stake HP tokens to MasterChefHp
    function enterStaking(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        updatePool(0);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accHpPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeHpTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accHpPerShare).div(1e12);
        emit Deposit(msg.sender, 0, _amount);
    }

    // Withdraw HP tokens from STAKING.
    function leaveStaking(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(0);
        uint256 pending = user.amount.mul(pool.accHpPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeHpTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accHpPerShare).div(1e12);
        emit Withdraw(msg.sender, 0, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Transfers original tokens ownership based on the actual dev. USED ONLY IN EMERGENCY CASE FOR FUTURE UPDATES.
    function safeTokenTransferOwnership(address _address, uint256 _option) public onlyOwner {
        if(_option == 0) {
            hp.transferOwnership(_address);
        }
        if(_option == 1) {
            this.transferOwnership(_address);
        }
    }
    /*********************************/

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }
}