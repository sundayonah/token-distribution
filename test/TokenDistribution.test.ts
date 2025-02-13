import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";

describe("TokenDistribution", function () {
    let TokenDistribution: Contract;
    let tokenDistribution: Contract;
    let admin: Signer, nodeOperator1: Signer, nodeOperator2: Signer, serviceProvider1: Signer, serviceProvider2: Signer, grantRecipient1: Signer, grantRecipient2: Signer;

    beforeEach(async function () {
        [admin, nodeOperator1, nodeOperator2, serviceProvider1, serviceProvider2, grantRecipient1, grantRecipient2] = await ethers.getSigners();

        const TokenDistributionFactory = await ethers.getContractFactory("TokenDistribution");
        tokenDistribution = await TokenDistributionFactory.deploy();
        await tokenDistribution.deployed();

        await tokenDistribution.initialize(await admin.getAddress(), Math.floor(Date.now() / 1000));
    });

    it("should initialize with correct values", async function () {
        expect(await tokenDistribution.totalSupply()).to.equal(ethers.utils.parseEther("7000000000"));
        expect(await tokenDistribution.balanceOf(await admin.getAddress())).to.equal(ethers.utils.parseEther("900000000"));
    });

    it("should add node operators", async function () {
        await tokenDistribution.connect(admin).addNodeOperators([await nodeOperator1.getAddress(), await nodeOperator2.getAddress()]);
        expect(await tokenDistribution.isNodeOperator(await nodeOperator1.getAddress())).to.be.true;
        expect(await tokenDistribution.isNodeOperator(await nodeOperator2.getAddress())).to.be.true;
    });

    it("should add service providers", async function () {
        await tokenDistribution.connect(admin).addServiceProviders([await serviceProvider1.getAddress(), await serviceProvider2.getAddress()]);
        expect(await tokenDistribution.isServiceProvider(await serviceProvider1.getAddress())).to.be.true;
        expect(await tokenDistribution.isServiceProvider(await serviceProvider2.getAddress())).to.be.true;
    });

    it("should add grant recipients", async function () {
        await tokenDistribution.connect(admin).addGrantRecipients([await grantRecipient1.getAddress(), await grantRecipient2.getAddress()]);
        expect(await tokenDistribution.isGrantRecipient(await grantRecipient1.getAddress())).to.be.true;
        expect(await tokenDistribution.isGrantRecipient(await grantRecipient2.getAddress())).to.be.true;
    });

    it("should distribute node tokens", async function () {
        await tokenDistribution.connect(admin).addNodeOperators([await nodeOperator1.getAddress()]);
        await ethers.provider.send("evm_increaseTime", [30 * 24 * 60 * 60]); // Increase time by 30 days
        await ethers.provider.send("evm_mine", []);

        await tokenDistribution.connect(admin).distributeNodeTokens();
        expect(await tokenDistribution.balanceOf(await nodeOperator1.getAddress())).to.equal(ethers.utils.parseEther("5833333"));
    });

    it("should distribute service provider tokens", async function () {
        await tokenDistribution.connect(admin).addServiceProviders([await serviceProvider1.getAddress()]);
        await ethers.provider.send("evm_increaseTime", [180 * 24 * 60 * 60]); // Increase time by 180 days
        await ethers.provider.send("evm_mine", []);

        await tokenDistribution.connect(admin).distributeServiceProviderTokens();
        expect(await tokenDistribution.balanceOf(await serviceProvider1.getAddress())).to.equal(ethers.utils.parseEther("500000"));
    });

    it("should distribute grant tokens", async function () {
        await tokenDistribution.connect(admin).addGrantRecipients([await grantRecipient1.getAddress()]);
        await ethers.provider.send("evm_increaseTime", [365 * 24 * 60 * 60]); // Increase time by 365 days
        await ethers.provider.send("evm_mine", []);

        await tokenDistribution.connect(admin).distributeGrantTokens();
        expect(await tokenDistribution.balanceOf(await grantRecipient1.getAddress())).to.equal(ethers.utils.parseEther("6000000"));
    });

    it("should reclaim unclaimed node tokens", async function () {
        await tokenDistribution.connect(admin).addNodeOperators([await nodeOperator1.getAddress()]);
        await ethers.provider.send("evm_increaseTime", [30 * 24 * 60 * 60]); // Increase time by 30 days
        await ethers.provider.send("evm_mine", []);

        await tokenDistribution.connect(admin).reclaimUnclaimedNodeTokens();
        expect(await tokenDistribution.balanceOf(await admin.getAddress())).to.equal(ethers.utils.parseEther("900000000"));
    });

    it("should cancel a transaction", async function () {
        await tokenDistribution.connect(admin).addNodeOperators([await nodeOperator1.getAddress()]);
        await ethers.provider.send("evm_increaseTime", [30 * 24 * 60 * 60]); // Increase time by 30 days
        await ethers.provider.send("evm_mine", []);

        await tokenDistribution.connect(admin).distributeNodeTokens();
        await tokenDistribution.connect(admin).cancelTransaction(await nodeOperator1.getAddress(), ethers.utils.parseEther("5833333"));
        expect(await tokenDistribution.balanceOf(await nodeOperator1.getAddress())).to.equal(0);
        expect(await tokenDistribution.balanceOf(await admin.getAddress())).to.equal(ethers.utils.parseEther("900000000"));
    });
});