# Schmeckles

Schmeckles is a Monad Testnet market for five-minute MON/USD capped-call tickets. A buyer pays a
known premium, cannot be liquidated, and can never receive more than the disclosed maximum payout.
The contract reserves that maximum liability before every sale.

If markets and options are new to you, start with [exp.md](./exp.md). To fund a wallet and use the
live website, follow [docs/USER_GUIDE.md](./docs/USER_GUIDE.md). Operators should use
[docs/OPERATIONS.md](./docs/OPERATIONS.md).

## MVP status

| Component | State |
|---|---|
| Market lifecycle and solvency accounting | Implemented and tested in Solidity |
| Test collateral | Project-created `mUSDC`; 500-token CLI faucet per wallet every 24 hours |
| Oracle | Supra Pull proof verification; MON/USD derived from MON/USDT x USDT/USD |
| Pricing | Fixed-point Black-Scholes call spread plus bounded Jump Guard |
| Frontend | Contract reads, wallet writes, real-time wallet order history, accounting, and event refreshes |
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
docs/OPERATIONS.md             deployment and runbook
docs/USER_GUIDE.md             beginner website, faucet, purchase, claim, and refund guide
exp.md                         explanation from first principles
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
MONAD_RPC_URL=https://rpc.ankr.com/monad_testnet
SUPRA_PROOF_URL=https://rpc-testnet-dora-2.supra.com
```

`PRIVATE_KEY` may also be 64 hex characters without `0x`; the scripts normalize it in memory. Never
put it in `web/.env.local`, Vercel, a `NEXT_PUBLIC_*` variable, Git, or logs. Supra's testnet proof
endpoint is public and needs no API key.

Deployment and lifecycle commands are in [docs/OPERATIONS.md](./docs/OPERATIONS.md).

## Current Monad Testnet release

```text
mUSDC:         0xAcDFc40A79302da78A095267045D7cBa2c46fa83
Supra adapter: 0x42674E3c94787535B56Ffa1E74f7d320a5fd44e2
Market:        0x922c22B63ae9AC7885f5b3E06067ADA853B00dd6
Frontend:      https://schmeckles.vercel.app
```

This release uses a 15-second verified settlement observation window after live Supra sampling showed
that its component feeds can advance in multi-second jumps. The keeper continuously opens and settles
epochs while it is running.

## Security boundary

This is unaudited testnet software. It rejects unverified or malformed proofs, missing/duplicate
pairs, zero prices, unsupported decimals, stale/future live observations, and settlements unless
both feed timestamps are inside `[expiry, expiry + 15 seconds]`. Those checks are not a security audit
or a claim that the pricing model is economically correct.

Not financial advice.
