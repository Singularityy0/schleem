# Schmeckles

Schmeckles is a Monad Testnet market for five-minute MON/USD capped-call tickets. A buyer pays a
known premium, cannot be liquidated, and can never receive more than the disclosed maximum payout.
The contract reserves that maximum liability before every sale.

If markets and options are new to you, start with [exp.md](./exp.md). Operators should use
[docs/OPERATIONS.md](./docs/OPERATIONS.md).

## MVP status

| Component | State |
|---|---|
| Market lifecycle and solvency accounting | Implemented and tested in Solidity |
| Test collateral | Project-created `mUSDC`; 500-token CLI faucet per wallet every 24 hours |
| Oracle | Supra Pull proof verification; MON/USD derived from MON/USDT x USDT/USD |
| Pricing | Fixed-point Black-Scholes call spread plus bounded Jump Guard |
| Frontend | Contract reads, wallet writes, countdowns, accounting, and event refreshes |
| Keeper | Rust service for Supra proofs, opening, settlement, and cancellation |
| Network | Deployed on Monad Testnet (`10143`) |
| Hosting | Live on Vercel at `schmeckles.vercel.app` |

`mUSDC` is not Circle USDC and is not redeemable. It is testnet money created by this project.
Every wallet also needs test MON for gas.

## Architecture

```text
Supra Pull REST (pairs 569 + 48)
                 |
                 v
           Rust keeper --------> Supra Pull verifier on Monad
                 |                           |
                 v                           v
        SchmecklesMarket <---------- SupraPriceOracle
                 |
                 +---- TestUSDC (mUSDC)
                 |
                 +---- Next.js client on Vercel
```

No oracle API key is required. The browser never receives the keeper private key. The chain is the
source of truth; the Rust process automates lifecycle transactions and never custodies buyer funds.

## Repository map

```text
contracts/
  src/TestUSDC.sol             testnet token and rate-limited faucet
  src/SupraPriceOracle.sol     Supra verification and MON/USD composition
  src/BlackScholes.sol         fixed-point zero-rate call-spread reference
  src/CappedCallMath.sol       capped payoff, Jump Guard, and fee calculation
  src/SchmecklesMarket.sol     lifecycle and liability-safe accounting
  script/Deploy.s.sol          Monad Testnet deployment and initial collateral
  scripts/                     PowerShell deployment, faucet, and stress-buy commands
  test/                        unit, fuzz, rejection, lifecycle, and invariant tests
keeper/                        Rust lifecycle keeper
web/                           Next.js contract-connected frontend
docs/SUPRA_PREFLIGHT.md        verified Supra and Monad integration details
docs/LIVE_RELEASE.md           addresses and onchain smoke-test transactions
docs/OPERATIONS.md             deployment and runbook
exp.md                         explanation from first principles
proposal.md                    product proposal
```

## Verify locally

Required: Foundry, Rust, and Node 22.13 or later.

```powershell
cd contracts
forge test
forge build --sizes

cd ..\keeper
cargo clippy --all-targets -- -D warnings
cargo test

cd ..\web
npm ci
npm run lint
npm run build
```

## Secrets and deployment

Copy `contracts/.env.example` to `contracts/.env` and use a dedicated testnet-only wallet:

```dotenv
PRIVATE_KEY=0xYOUR_TESTNET_ONLY_KEY
MONAD_RPC_URL=https://testnet-rpc.monad.xyz
SUPRA_PROOF_URL=https://rpc-testnet-dora-2.supra.com
```

`PRIVATE_KEY` may also be 64 hex characters without `0x`; the scripts normalize it in memory. Never
put it in `web/.env.local`, Vercel, a `NEXT_PUBLIC_*` variable, Git, or logs. Supra's testnet proof
endpoint is public and needs no API key.

Deployment and lifecycle commands are in [docs/OPERATIONS.md](./docs/OPERATIONS.md).

## Current Monad Testnet release

```text
mUSDC:         0xF2E29cfd193c3dF30709c0f9104Cce15A82C8bb8
Supra adapter: 0xf91F9Df392e380EAfB84F1212B222F1c33dE3673
Market:        0x97aCD4eeBA9a42a1060BBA53dDABBe0673606985
Frontend:      https://schmeckles.vercel.app
```

The identical final bytecode completed a staging smoke test: the CLI faucet funded a wallet,
`stress-buy.ps1` bought three tickets, the contract reserved `30 mUSDC`, Supra settled with both raw
timestamps inside the strict window, the market remained solvent, and the buyer closed the position.
The release addresses above are a clean copy with no active epoch; starting the keeper opens epoch 1.

## Security boundary

This is unaudited testnet software. It rejects unverified or malformed proofs, missing/duplicate
pairs, zero prices, unsupported decimals, stale/future live observations, and settlements unless
both feed timestamps are inside `[expiry, expiry + 2 seconds]`. Those checks are not a security audit
or a claim that the pricing model is economically correct.

Not financial advice.
