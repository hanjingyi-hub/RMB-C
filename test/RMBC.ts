import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { network } from "hardhat";

const { viem, networkHelpers } = await network.create();
const units = (amount: number) => BigInt(amount) * 1_000_000n;

describe("RMBC", function () {
  async function deployRMBCFixture() {
    const [owner, minter, alice, bob] = await viem.getWalletClients();
    const rmbc = await viem.deployContract("RMBC", [owner.account.address]);

    return { rmbc, owner, minter, alice, bob };
  }

  it("sets USDC-style metadata and owner", async function () {
    const { rmbc, owner } = await networkHelpers.loadFixture(deployRMBCFixture);

    assert.equal(await rmbc.read.name(), "RMB Coin");
    assert.equal(await rmbc.read.symbol(), "RMBC");
    assert.equal(String(await rmbc.read.decimals()), "6");
    assert.equal((await rmbc.read.owner()).toLowerCase(), owner.account.address.toLowerCase());
  });

  it("allows the owner to configure minters and mint within allowance", async function () {
    const { rmbc, minter, alice, bob } = await networkHelpers.loadFixture(deployRMBCFixture);

    await rmbc.write.configureMinter([minter.account.address, units(100)]);
    await rmbc.write.mint([alice.account.address, units(40)], { account: minter.account });
    await rmbc.write.transfer([bob.account.address, units(15)], { account: alice.account });

    assert.equal(await rmbc.read.balanceOf([alice.account.address]), units(25));
    assert.equal(await rmbc.read.balanceOf([bob.account.address]), units(15));
    assert.equal(await rmbc.read.totalSupply(), units(40));
    assert.equal(await rmbc.read.minterAllowance([minter.account.address]), units(60));
  });

  it("rejects minting above a minter's configured allowance", async function () {
    const { rmbc, minter, alice } = await networkHelpers.loadFixture(deployRMBCFixture);

    await rmbc.write.configureMinter([minter.account.address, units(10)]);

    await assert.rejects(
      rmbc.write.mint([alice.account.address, units(11)], { account: minter.account }),
    );
  });

  it("blocks transfers while paused", async function () {
    const { rmbc, minter, alice, bob } = await networkHelpers.loadFixture(deployRMBCFixture);

    await rmbc.write.configureMinter([minter.account.address, units(25)]);
    await rmbc.write.mint([alice.account.address, units(25)], { account: minter.account });
    await rmbc.write.pause();

    await assert.rejects(
      rmbc.write.transfer([bob.account.address, units(1)], { account: alice.account }),
    );

    await rmbc.write.unpause();
    await rmbc.write.transfer([bob.account.address, units(1)], { account: alice.account });

    assert.equal(await rmbc.read.balanceOf([bob.account.address]), units(1));
  });

  it("allows configured minters to burn their own balances", async function () {
    const { rmbc, minter } = await networkHelpers.loadFixture(deployRMBCFixture);

    await rmbc.write.configureMinter([minter.account.address, units(20)]);
    await rmbc.write.mint([minter.account.address, units(20)], { account: minter.account });
    await rmbc.write.burn([units(5)], { account: minter.account });

    assert.equal(await rmbc.read.balanceOf([minter.account.address]), units(15));
    assert.equal(await rmbc.read.totalSupply(), units(15));
  });

  it("prevents non-minters from burning", async function () {
    const { rmbc, minter, alice } = await networkHelpers.loadFixture(deployRMBCFixture);

    await rmbc.write.configureMinter([minter.account.address, units(10)]);
    await rmbc.write.mint([alice.account.address, units(10)], { account: minter.account });

    await assert.rejects(
      rmbc.write.burn([units(1)], { account: alice.account }),
    );
  });

  it("blocks denied accounts and can destroy their funds", async function () {
    const { rmbc, minter, alice, bob } = await networkHelpers.loadFixture(deployRMBCFixture);

    await rmbc.write.configureMinter([minter.account.address, units(50)]);
    await rmbc.write.mint([alice.account.address, units(50)], { account: minter.account });
    await rmbc.write.deny([alice.account.address]);

    await assert.rejects(
      rmbc.write.transfer([bob.account.address, units(1)], { account: alice.account }),
    );

    await rmbc.write.destroyDeniedFunds([alice.account.address]);

    assert.equal(await rmbc.read.balanceOf([alice.account.address]), 0n);
    assert.equal(await rmbc.read.totalSupply(), 0n);
  });

  it("prevents non-owners from configuring minters", async function () {
    const { rmbc, minter, alice } = await networkHelpers.loadFixture(deployRMBCFixture);

    await assert.rejects(
      rmbc.write.configureMinter([alice.account.address, units(1)], { account: minter.account }),
    );
  });
});
