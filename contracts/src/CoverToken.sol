// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title CoverToken
/// @notice Shares in a Stepwell's first-loss layer. Only the Stepwell mints and burns them.
/// @dev Balances belong to an epoch. When a loss wipes the layer out, the Stepwell starts a new
///      epoch and every older balance reads as zero, so a fresh layer is never diluted by void
///      shares. Shares cannot be transferred: an underwriter's notice period would be pointless
///      if the shares could be handed to someone else.
contract CoverToken {
    string public name;
    string public symbol;
    uint8 public immutable decimals;
    address public immutable stepwell;

    uint256 public epoch;
    uint256 public totalSupply;
    mapping(address => uint256) private _balance;
    mapping(address => uint256) private _epochOf;

    event Transfer(address indexed from, address indexed to, uint256 value);

    error OnlyStepwell();
    error NotTransferable();

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
        stepwell = msg.sender;
    }

    modifier onlyStepwell() {
        if (msg.sender != stepwell) revert OnlyStepwell();
        _;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _epochOf[account] == epoch ? _balance[account] : 0;
    }

    function mint(address to, uint256 amount) external onlyStepwell {
        if (_epochOf[to] != epoch) {
            _epochOf[to] = epoch;
            _balance[to] = 0;
        }
        _balance[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external onlyStepwell {
        _balance[from] = balanceOf(from) - amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }

    /// @notice Voids every balance. Called when a loss destroys the whole layer.
    function wipe() external onlyStepwell {
        epoch += 1;
        totalSupply = 0;
    }

    function transfer(address, uint256) external pure returns (bool) {
        revert NotTransferable();
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        revert NotTransferable();
    }

    function approve(address, uint256) external pure returns (bool) {
        revert NotTransferable();
    }

    function allowance(address, address) external pure returns (uint256) {
        return 0;
    }
}
