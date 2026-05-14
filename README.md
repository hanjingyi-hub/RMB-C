# RMBC

RMBC is a USDC-style ERC-20 stablecoin prototype with centralized issuer controls:

- 6 decimals, matching USDC-style accounting.
- Owner-controlled minters with per-minter mint allowances.
- Minter-controlled burning for redemption-style flows.
- Pause and unpause controls for emergency response.
- Denylist controls that block transfers, approvals, minting, and burning involving denied accounts.
- Owner ability to destroy funds held by denied accounts.
- EIP-2612 `permit` approvals for gasless allowance signatures.

This is a smart contract scaffold, not a full stablecoin business. Real USDC-like issuance also needs reserve custody, attestations, compliance operations, key management, monitoring, audits, legal review, and chain deployment controls.

## Install

```bash
npm install
```

## Build

```bash
npm run build
```

## Test

```bash
npm test
```

## Deploy Locally

```bash
npm run deploy:local
```

The deploy script makes the deployer the initial owner. After deployment, the owner should configure one or more minters with `configureMinter`.
