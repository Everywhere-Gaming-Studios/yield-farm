pragma solidity 0.6.12;

import './utils/Context.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import "@openzeppelin/contracts/math/SafeMath.sol";
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import './Ticket.sol';

// TicketReceipt
contract TicketReceipt is BEP20('TicketReceipt Token', 'TRECEIPT') {
    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner (MasterChef).
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }

    function burn(address _from ,uint256 _amount) public onlyOwner {
        _burn(_from, _amount);
    }

    // The TICKET TOKEN!
    Ticket public ticket;


    constructor(
        Ticket _ticket
    ) public {
        ticket = _ticket;
    }

    // Safe ticket transfer function, just in case if rounding error causes pool to not have enough TICKETs.
    function safeTicketTransfer(address _to, uint256 _amount) public onlyOwner {
        uint256 ticketBal = ticket.balanceOf(address(this));
        if (_amount > ticketBal) {
            ticket.transfer(_to, ticketBal);
        } else {
            ticket.transfer(_to, _amount);
        }
    }
}