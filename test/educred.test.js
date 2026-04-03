const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("EduCred CW2 (based on CW1)", function () {
  async function deployFixture() {
    const [admin, complianceOfficer, student, treasuryManager, other] =
      await ethers.getSigners();

    const EduToken = await ethers.getContractFactory("EduToken");
    const eduToken = await EduToken.connect(admin).deploy(admin.address);
    await eduToken.waitForDeployment();

    const now = await time.latest();
    const saleStart = now + 10;
    const saleEnd = now + 3600;

    const rate = 1000n;
    const minContributionWei = ethers.parseEther("0.1");
    const maxContributionWei = ethers.parseEther("2");
    const hardCapTokens = ethers.parseUnits("100000", 18);

    const EduTokenSale = await ethers.getContractFactory("EduTokenSale");
    const sale = await EduTokenSale.connect(admin).deploy(
      admin.address,
      await eduToken.getAddress(),
      treasuryManager.address,
      complianceOfficer.address,
      rate,
      saleStart,
      saleEnd,
      minContributionWei,
      maxContributionWei,
      hardCapTokens
    );
    await sale.waitForDeployment();

    // CW2: sale contract must be able to mint, so make it the token owner
    await eduToken.connect(admin).transferOwnership(await sale.getAddress());

    return {
      admin,
      complianceOfficer,
      student,
      treasuryManager,
      other,
      eduToken,
      sale,
      saleStart,
      saleEnd,
      minContributionWei,
      maxContributionWei,
      hardCapTokens,
      rate
    };
  }

  it("1) deploys token and sale contracts", async function () {
    const { eduToken, sale } = await deployFixture();
    expect(await eduToken.getAddress()).to.not.equal(ethers.ZeroAddress);
    expect(await sale.getAddress()).to.not.equal(ethers.ZeroAddress);
  });

  it("2) ERC20 transfer updates balances (admin has initial supply)", async function () {
    const { admin, student, eduToken } = await deployFixture();
    const amount = ethers.parseUnits("100", 18);

    await eduToken.connect(admin).transfer(student.address, amount);
    expect(await eduToken.balanceOf(student.address)).to.equal(amount);
  });

  it("3) unauthorized user cannot update whitelist (access control)", async function () {
    const { other, student, sale } = await deployFixture();
    await expect(sale.connect(other).setWhitelist(student.address, true)).to.be
      .revertedWith("Not authorized");
  });

  it("4) compliance officer can update whitelist", async function () {
    const { complianceOfficer, student, sale } = await deployFixture();

    await expect(sale.connect(complianceOfficer).setWhitelist(student.address, true))
      .to.emit(sale, "WhitelistUpdated")
      .withArgs(student.address, true);

    expect(await sale.isWhitelisted(student.address)).to.equal(true);
  });

  it("5) non-whitelisted student cannot buy tokens", async function () {
    const { student, sale, saleStart, minContributionWei } = await deployFixture();

    await time.increaseTo(saleStart + 1);
    await expect(sale.connect(student).buyTokens({ value: minContributionWei })).to.be
      .revertedWith("Not whitelisted");
  });

  it("6) whitelisted student can buy tokens (CW2 minting)", async function () {
    const {
      complianceOfficer,
      student,
      sale,
      saleStart,
      minContributionWei,
      eduToken,
      rate
    } = await deployFixture();

    await sale.connect(complianceOfficer).setWhitelist(student.address, true);
    await time.increaseTo(saleStart + 1);

    const expectedTokens = minContributionWei * rate;

    const tx = await sale.connect(student).buyTokens({ value: minContributionWei });
    await expect(tx).to.emit(sale, "TokensPurchased");

    expect(await eduToken.balanceOf(student.address)).to.equal(expectedTokens);
  });

  it("7) cannot buy before sale start", async function () {
    const { complianceOfficer, student, sale, minContributionWei } = await deployFixture();

    await sale.connect(complianceOfficer).setWhitelist(student.address, true);

    await expect(sale.connect(student).buyTokens({ value: minContributionWei })).to.be
      .revertedWith("Sale not active");
  });

  it("8) owner can pause/unpause sale", async function () {
    const { admin, sale } = await deployFixture();

    await expect(sale.connect(admin).pauseSale()).to.emit(sale, "SalePaused");
    await expect(sale.connect(admin).unpauseSale()).to.emit(sale, "SaleUnpaused");
  });

  it("9) when paused, buyTokens reverts", async function () {
    const { admin, complianceOfficer, student, sale, saleStart, minContributionWei } =
      await deployFixture();

    await sale.connect(complianceOfficer).setWhitelist(student.address, true);
    await sale.connect(admin).pauseSale();
    await time.increaseTo(saleStart + 1);

    await expect(sale.connect(student).buyTokens({ value: minContributionWei })).to.be
      .revertedWithCustomError(sale, "EnforcedPause");
  });
});