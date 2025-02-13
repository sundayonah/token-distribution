// types/index.ts

import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

export interface Signers {
    admin: SignerWithAddress;
    nodeOperator: SignerWithAddress;
    serviceProvider: SignerWithAddress;
    grantRecipient: SignerWithAddress;
}

export interface DeployedContracts {
    tokenDistribution: any; // Will be replaced with actual contract type after TypeChain generation
}

export interface DistributionConfig {
    startDate: number;
    nodeDistributionPeriod: number;
    serviceProviderPeriod: number;
    grantPeriod: number;
    claimWindow: number;
}