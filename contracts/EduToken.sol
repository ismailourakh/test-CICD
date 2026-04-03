// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract EduToken is ERC20, Ownable {
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 10 ** 18;

    constructor(address _initialOwner)
        ERC20("EduCred Token", "EDU")
        Ownable(_initialOwner)
    {
        _mint(_initialOwner, INITIAL_SUPPLY);
    }

    /// @notice CW2: allow the owner (typically the Sale contract) to mint tokens on purchase.
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}