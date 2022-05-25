
pragma solidity 0.6.12;

import '@uniswap/lib/contracts/libraries/TransferHelper.sol';
import "@openzeppelin/contracts/math/SafeMath.sol";
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import './utils/Context.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import './Ticket.sol';
import './TicketReceipt.sol'

contract MasterChefTicket is Ownable {
    using SafeMath for uint256;
    using SafeIERC20 for IIERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of TICKETs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accTicketPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accTicketPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IIERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. TICKETs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that TICKETs distribution occurs.
        uint256 accTicketPerShare; // Accumulated TICKETs per share, times 1e12. See below.
    }

    // The TICKET TOKEN!
    Ticket public ticket;
    // The SYRUP TOKEN!
    TicketReceipt public receipt;
    // Dev address.
    address public devaddr;
    // TICKET tokens created per block.
    uint256 public ticketPerBlock;
    // Bonus muliplier for early ticket makers.
    uint256 public BONUS_MULTIPLIER = 1;

    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when TICKET mining starts.
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SwapNewToken(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        Ticket _ticket,
        TicketReceipt _receipt,
        address _devaddr,
        uint256 _ticketPerBlock,
        uint256 _startBlock
    ) public {
        ticket = _ticket;
        receipt = _receipt;
        devaddr = _devaddr;
        ticketPerBlock = _ticketPerBlock;
        startBlock = _startBlock;

        // staking pool
        poolInfo.push(PoolInfo({
            lpToken: _ticket,
            allocPoint: 1000,
            lastRewardBlock: startBlock,
            accTicketPerShare: 0
        }));

        totalAllocPoint = 1000;

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
            accTicketPerShare: 0
        }));
        updateStakingPool();
    }

    // Update the given pool's TICKET allocation point. Can only be called by the owner.
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

    // View function to see pending TICKETs on frontend.
    function pendingTicket(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accTicketPerShare = pool.accTicketPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 ticketReward = multiplier.mul(ticketPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accTicketPerShare = accTicketPerShare.add(ticketReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accTicketPerShare).div(1e12).sub(user.rewardDebt);
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
        uint256 ticketReward = multiplier.mul(ticketPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        ticket.mint(devaddr, ticketReward.div(10));
        ticket.mint(address(receipt), ticketReward);
        pool.accTicketPerShare = pool.accTicketPerShare.add(ticketReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChefTicket for TICKET allocation.
    function deposit(uint256 _pid, uint256 _amount) public {

        require (_pid != 0, 'deposit TICKET by staking');

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accTicketPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeTicketTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accTicketPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChefTicket.
    function withdraw(uint256 _pid, uint256 _amount) public {

        require (_pid != 0, 'withdraw TICKET by unstaking');

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accTicketPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeTicketTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accTicketPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Stake TICKET tokens to MasterChefTicket
    function enterStaking(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        updatePool(0);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accTicketPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeTicketTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accTicketPerShare).div(1e12);

        receipt.mint(msg.sender, _amount);
        emit Deposit(msg.sender, 0, _amount);
    }

    // Withdraw TICKET tokens from STAKING.
    function leaveStaking(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(0);
        uint256 pending = user.amount.mul(pool.accTicketPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeTicketTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accTicketPerShare).div(1e12);

        receipt.burn(msg.sender, _amount);
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

    // Safe ticket transfer function, just in case if rounding error causes pool to not have enough TICKETs.
    function safeTicketTransfer(address _to, uint256 _amount) internal {
        receipt.safeTicketTransfer(_to, _amount);
    }
    

    // Mints new Ticket to make new investment phases in the future. PUBLICLY ANNOUNCED WHEN USED.
    function safeInvestmentRound(address _to, uint256 _amount) public onlyOwner {
        ticket.mint(_to, _amount);
    }

    // Burns Liana tokens of an user. USED ONLY TO PREVENT RUG PULLS.
    function safeLianaBurn(address _address, uint256 _amount) public onlyOwner {
        receipt.burn(_address, _amount);
    }

    // Transfers original tokens ownership based on the actual dev. USED ONLY IN EMERGENCY CASE FOR FUTURE UPDATES.
    function safeTokenTransferOwnership(address _address, uint256 _option) public onlyOwner {
        if(_option == 0) {
            ticket.transferOwnership(_address);
        }
        if(_option == 1) {
            receipt.transferOwnership(_address);
        }
        if(_option == 2) {
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