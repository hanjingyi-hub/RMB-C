import { network } from "hardhat";

const { viem, networkName } = await network.create();
const [deployer] = await viem.getWalletClients();

console.log(`Deploying RMBC to ${networkName}...`);
console.log(`Initial owner: ${deployer.account.address}`);

const rmbc = await viem.deployContract("RMBC", [deployer.account.address]);

console.log(`RMBC deployed at: ${rmbc.address}`);
