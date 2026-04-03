// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./EduToken.sol";

contract EduTokenSale is Ownable, Pausable {
    // ===== State Variables =====
    EduToken public immutable eduToken;
    address public treasuryManager;
    address public complianceOfficer;

    uint256 public rate;
    uint256 public saleStart;
    uint256 public saleEnd;
    uint256 public minContributionWei;
    uint256 public maxContributionWei;
    uint256 public hardCapTokens;
    uint256 public totalTokensSold;

    mapping(address => bool) public isWhitelisted;
    mapping(address => uint256) public contributionOf;

    // ===== Events =====
    event TokensPurchased(address indexed _buyerAddress, uint256 _ethAmountWei, uint256 _tokenAmount);
    event WhitelistUpdated(address indexed _walletAddress, bool _status);
    event TreasuryManagerUpdated(address indexed _newTreasuryManager);
    event ComplianceOfficerUpdated(address indexed _newComplianceOfficer);
    event FundsWithdrawn(address indexed _toAddress, uint256 _amountWei);
    event SalePaused(address indexed _byAddress);
    event SaleUnpaused(address indexed _byAddress);

    // ===== Modifiers =====
    modifier onlyTreasuryOrOwner() {
        require(msg.sender == treasuryManager || msg.sender == owner(), "Not authorized");
        _;
    }

    modifier onlyComplianceOrOwner() {
        require(msg.sender == complianceOfficer || msg.sender == owner(), "Not authorized");
        _;
    }

    // ===== Constructor =====
    constructor(
        address _initialOwner,
        address _tokenAddress,
        address _treasuryManager,
        address _complianceOfficer,
        uint256 _rate,
        uint256 _saleStart,
        uint256 _saleEnd,
        uint256 _minContributionWei,
        uint256 _maxContributionWei,
        uint256 _hardCapTokens
    ) Ownable(_initialOwner) {
        require(_tokenAddress != address(0), "Invalid token");
        require(_treasuryManager != address(0), "Invalid treasury");
        require(_complianceOfficer != address(0), "Invalid compliance");
        require(_saleEnd > _saleStart, "Invalid sale window");
        require(_maxContributionWei >= _minContributionWei, "Invalid contribution range");
        require(_rate > 0, "Invalid rate");

        eduToken = EduToken(_tokenAddress);
        treasuryManager = _treasuryManager;
        complianceOfficer = _complianceOfficer;
        rate = _rate;
        saleStart = _saleStart;
        saleEnd = _saleEnd;
        minContributionWei = _minContributionWei;
        maxContributionWei = _maxContributionWei;
        hardCapTokens = _hardCapTokens;
    }

    // ===== Admin Functions =====
    function setWhitelist(address _walletAddress, bool _status) external onlyComplianceOrOwner {
        isWhitelisted[_walletAddress] = _status;
        emit WhitelistUpdated(_walletAddress, _status);
    }

    function setTreasuryManager(address _newTreasuryManager) external onlyOwner {
        require(_newTreasuryManager != address(0), "Invalid treasury");
        treasuryManager = _newTreasuryManager;
        emit TreasuryManagerUpdated(_newTreasuryManager);
    }

    function setComplianceOfficer(address _newComplianceOfficer) external onlyOwner {
        require(_newComplianceOfficer != address(0), "Invalid compliance");
        complianceOfficer = _newComplianceOfficer;
        emit ComplianceOfficerUpdated(_newComplianceOfficer);
    }

    function pauseSale() external onlyOwner {
        _pause();
        emit SalePaused(msg.sender);
    }

    function unpauseSale() external onlyOwner {
        _unpause();
        emit SaleUnpaused(msg.sender);
    }

    function isSaleActive() external view returns (bool) {
        return !paused() && block.timestamp >= saleStart && block.timestamp <= saleEnd;
    }

    function buyTokens() external payable whenNotPaused {
        require(block.timestamp >= saleStart && block.timestamp <= saleEnd, "Sale not active");
        require(isWhitelisted[msg.sender], "Not whitelisted");
        require(msg.value >= minContributionWei, "Below min contribution");

        uint256 newContribution = contributionOf[msg.sender] + msg.value;
        require(newContribution <= maxContributionWei, "Above max contribution");

        uint256 tokenAmount = msg.value * rate;
        require(totalTokensSold + tokenAmount <= hardCapTokens, "Hard cap exceeded");

        contributionOf[msg.sender] = newContribution;
        totalTokensSold += tokenAmount;

        // MINT ON PURCHASE (CW2 requirement)
        eduToken.mint(msg.sender, tokenAmount);

        emit TokensPurchased(msg.sender, msg.value, tokenAmount);
    }

    function withdrawFunds(uint256 _amountWei) external onlyTreasuryOrOwner {
        require(address(this).balance >= _amountWei, "Insufficient ETH");
        (bool success, ) = payable(treasuryManager).call{value: _amountWei}("");
        require(success, "Withdraw failed");
        emit FundsWithdrawn(treasuryManager, _amountWei);
    }
}