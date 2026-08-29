# Schmeckles operations runbook

This runbook deploys and operates the MVP on Monad Testnet. Use only a dedicated testnet burner
wallet containing no real assets.

## 1. Prerequisites

- Foundry (`forge` and `cast`)
- Rust toolchain
- Node 22.13 or later
- test MON for the deployer/keeper and each buyer wallet
- Vercel CLI access to the intended team/project

Supra Pull's testnet REST endpoint is public; there is no oracle API key to obtain.

## 2. Configure the keeper wallet

```powershell
Copy-Item contracts/.env.example contracts/.env
```

Edit `contracts/.env`:

```dotenv
PRIVATE_KEY=0xYOUR_TESTNET_ONLY_DEPLOYER_AND_KEEPER_KEY
MONAD_RPC_URL=https://testnet-rpc.monad.xyz
SUPRA_PROOF_URL=https://rpc-testnet-dora-2.supra.com
```

The private key may omit `0x`; the entry points normalize valid 64-character hex in memory. Never
put it in the frontend, Vercel, or Git. See [SUPRA_PREFLIGHT.md](./SUPRA_PREFLIGHT.md).

## 3. Verify the release

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
cd ..
```

## 4. Deploy to Monad Testnet

```powershell
cd contracts
.\scripts\deploy-monad.ps1
```

The script deploys `TestUSDC`, `SupraPriceOracle`, and `SchmecklesMarket`; mints `10,000 mUSDC` to
the operator; and deposits it as initial market collateral. The Supra adapter is fixed to official
pull verifier `0xF8522B7fcE37439b98A2be282d413A44269028bE` and pair IDs `569` and `48`.

Copy the three deployment addresses from Forge output or
`contracts/broadcast/Deploy.s.sol/10143/run-latest.json` into `contracts/.env`:

```dotenv
MUSDC_ADDRESS=0x...
SUPRA_ORACLE_ADDRESS=0x...
MARKET_ADDRESS=0x...
```

Verify all three addresses have bytecode before continuing.

## 5. Start the keeper

Current release addresses:

```dotenv
MUSDC_ADDRESS=0xF2E29cfd193c3dF30709c0f9104Cce15A82C8bb8
SUPRA_ORACLE_ADDRESS=0xf91F9Df392e380EAfB84F1212B222F1c33dE3673
MARKET_ADDRESS=0x97aCD4eeBA9a42a1060BBA53dDABBe0673606985
```

The keeper reads `contracts/.env` from the repository root or `../contracts/.env` from `keeper/`.

```powershell
cd keeper
cargo run --release
```

Expected first run: verify chain `10143`, fetch and submit a Supra proof, then open epoch 1. Keep the
process running continuously: Supra's endpoint returns the latest proof, so the one-second polling loop
must capture both feed timestamps inside the two-second settlement window. Submission and receipt
waits are bounded to 45 seconds so a degraded RPC cannot silently freeze the lifecycle.

For one diagnostic cycle:

```powershell
$env:KEEPER_ONCE='1'
cargo run --release
Remove-Item Env:KEEPER_ONCE
```

### Deploy the keeper to Render

The repository root includes `render.yaml` for a single native Rust background worker. In Render,
create a **Blueprint**, connect this repository, and select the root `render.yaml`. Render will ask
for the two values marked `sync: false`:

```dotenv
MONAD_RPC_URL=https://YOUR_DEDICATED_MONAD_TESTNET_RPC
PRIVATE_KEY=0xYOUR_TESTNET_ONLY_KEEPER_KEY
```

The blueprint already contains the current market, Supra adapter, public Supra proof endpoint, and
safe polling defaults. If deploying a new contract release, replace `MARKET_ADDRESS` and
`SUPRA_ORACLE_ADDRESS` in the Render service environment with the new addresses. Keep exactly one
worker instance running. Render background workers do not have a free plan; the blueprint requests
the `starter` plan.

After deployment, the logs must show chain ID `10143`, a successful Supra live-price update, and an
epoch-open transaction. A build completing by itself is not proof that the keeper is operating.

To rotate the current release to a fresh keeper wallet before deploying it, leave the current owner
key only in ignored `contracts/.env` and run:

```powershell
cd contracts
.\scripts\set-keeper.ps1 -NewKeeperAddress 0xYOUR_NEW_KEEPER_WALLET_ADDRESS
```

Then put only the fresh keeper wallet's private key in Render. The owner key never belongs in Render.

## 6. Fund a buyer with mUSDC

There is no web faucet. On the buyer's machine:

```powershell
cd contracts
$env:PRIVATE_KEY='0xBUYER_TESTNET_ONLY_KEY'
$env:MUSDC_ADDRESS='0xDEPLOYED_MUSDC'
$env:MONAD_RPC_URL='https://testnet-rpc.monad.xyz'
.\scripts\faucet.ps1
```

The caller receives exactly `500 mUSDC` once per 24 hours. They still need test MON for faucet,
approval, purchase, claim, and refund gas.

With the keeper running and an epoch in `Trading`, a buyer can exercise approve + buy from the CLI:

```powershell
.\scripts\stress-buy.ps1 -Quantity 3
```

The script reads the live contract quote, adds 5% maximum slippage, approves only that amount, and
submits the purchase. Use separate test wallets when load-testing the per-wallet position path.

## 7. Run and deploy the frontend

Copy `web/.env.example` to `web/.env.local` and set only public values:

```dotenv
NEXT_PUBLIC_MARKET_ADDRESS=0xDEPLOYED_MARKET
NEXT_PUBLIC_MUSDC_ADDRESS=0xDEPLOYED_MUSDC
NEXT_PUBLIC_MONAD_RPC_URL=https://testnet-rpc.monad.xyz
NEXT_PUBLIC_SITE_URL=http://localhost:3000
```

Run locally with `npm run dev`. From `web/`, deploy only to the intended Vercel project:

```powershell
npx vercel --prod
```

The keeper belongs in a separate protected process, never in Vercel's browser-facing environment.

## 8. Go/no-go checks

Go only when:

- chain ID is `10143` and all three deployed addresses contain bytecode;
- market collateral/oracle addresses and keeper match the release;
- the market holds `10,000 mUSDC` initial collateral;
- a real Supra proof refreshes the live price;
- an epoch opens, locks, and settles with both timestamps in `[expiry, expiry + 2]`;
- a buyer can faucet, approve, buy, and claim;
- a missed settlement can cancel and refund;
- frontend event refreshes mirror onchain state; and
- no private key appears in Git, browser bundles, Vercel variables, or logs.

This is testnet-only, unaudited software.
