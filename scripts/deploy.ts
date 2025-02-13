// scripts/deploy.ts

import { ethers, upgrades } from "hardhat";

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);

    const TokenDistribution = await ethers.getContractFactory("TokenDistribution");

    // Set distribution start date to 1 day from now
    const startDate = Math.floor(Date.now() / 1000) + 86400;

    const tokenDistribution = await upgrades.deployProxy(
        TokenDistribution,
        [deployer.address, startDate],
        { initializer: 'initialize' }
    );

    await tokenDistribution.waitForDeployment();
    console.log("TokenDistribution deployed to:", await tokenDistribution.getAddress());
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });