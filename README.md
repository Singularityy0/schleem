# Schmeckles

**A fully collateralized, five-minute MON/USD capped-call market on Monad Testnet.**

Schmeckles turns a complex crypto option into a simple bounded ticket: pay a known mUSDC premium,
take a view on whether MON will rise before expiry, never face liquidation, and never receive more
than the displayed maximum payout. The market reserves that maximum liability before accepting a
purchase.

> Testnet-only, unaudited software. `mUSDC` is a project-created test token, not Circle USDC, and
> cannot be redeemed. Nothing here is financial advice.

## 1. Submission links

| Item | Link / address |
|---|---|
| Live application | [schmeckles.vercel.app](https://schmeckles.vercel.app) |
| Source | [github.com/Singularityy0/schleem](https://github.com/Singularityy0/schleem) |
| Network | Monad Testnet, chain ID `10143` |
| Market | [`0x922c...dd6`](https://testnet.monadvision.com/address/0x922c22B63ae9AC7885f5b3E06067ADA853B00dd6) |
| Supra adapter | [`0x4267...4e2`](https://testnet.monadvision.com/address/0x42674E3c94787535B56Ffa1E74f7d320a5fd44e2) |
| mUSDC | [`0xAcDF...a83`](https://testnet.monadvision.com/address/0xAcDFc40A79302da78A095267045D7cBa2c46fa83) |
| Research basis | [Kończal (2025), *Pricing Options on the Cryptocurrency Futures Contracts*](https://arxiv.org/html/2506.14614v1) |

The contracts and frontend are deployed. The Rust keeper is intentionally a private outbound-only
process, currently run by the operator rather than hosted as a public service. A live epoch requires
that keeper to remain online.

## 2. The problem

Crypto derivatives usually force a retail user to reason about leverage, liquidation, margin,
unbounded exposure, volatility surfaces, and opaque market-maker pricing. Short-expiry products add
three engineering problems:

1. **Buyer risk must be understandable.** The user should know both maximum loss and maximum payout
   before signing.
2. **The market must remain solvent.** A premium cannot be allowed to finance the liability created
   by its own purchase.
3. **Expiry must be objective and live.** A privileged keeper should not be able to type in a
   favorable settlement price, and oracle failure should not trap user funds.

Schmeckles addresses these constraints with a capped payoff, pre-funded liability reserves, a
verifiable Supra price at expiry, and a refund path when settlement is unavailable.

## 3. Research basis and our inference

The design is informed by Julia Kończal's 2025 paper,
[*Pricing Options on the Cryptocurrency Futures Contracts*](https://arxiv.org/html/2506.14614v1)
([arXiv:2506.14614v1](https://arxiv.org/abs/2506.14614)). The paper calibrates Black–Scholes,
Variance Gamma, Merton Jump Diffusion, Kou, Heston, and Bates/stochastic-volatility-with-jumps models
against regulated BTC and ETH futures call-option data across eight maturities.

Its relevant empirical result is that plain Black–Scholes produced the largest aggregate errors,
while jump-aware models performed materially better: Kou was best for BTC in the reported metrics,
and stochastic volatility with jumps had the lowest ETH MAPE. The paper's broader conclusion is
that crypto prices' volatility and discontinuous jumps are important pricing inputs and that no one
model is universally best across assets, maturities, and error measures.

### What we implemented from that insight

We made the following engineering inference:

> Black–Scholes is useful as a transparent, deterministic reference, but a crypto quote should not
> rely on diffusion-only pricing as if jumps did not exist.

Schmeckles therefore combines:

- an on-chain, zero-rate, fixed-point Black–Scholes **call-spread reference**;
- a disclosed **Jump Guard** that partially prices an explicit upward stress scenario;
- a hard payout cap and full pre-reservation of that cap; and
- a displayed fee, added only after the two risk components.

This is an MVP risk adjustment, not an implementation or calibration of Kou, Bates, Merton Jump
Diffusion, or the paper's dataset. The paper studies longer-dated BTC/ETH options on futures; this
project offers five-minute MON/USD spot-settled tickets. We adopted the paper's design lesson, not a
claim that its numerical conclusions transfer directly to MON.

## 4. The product

Each epoch lasts five minutes. Its strike is the verified MON/USD price when the epoch opens. The
current keeper configuration sets:

| Parameter | Current value | Meaning |
|---|---:|---|
| Strike, `K` | MON/USD at open | Price MON must exceed before payoff begins |
| Cap, `H` | `K + 1%` | Price at which the ticket reaches maximum payout |
| Maximum payout, `M` | `10 mUSDC` | Maximum received per ticket |
| Pricing volatility, `sigma` | `120%` annualized | Black–Scholes model input |
| Jump stress, `j` | `+0.75%` | Spot shock used by Jump Guard |
| Jump weight, `w` | `10%` | Fraction of stress gap added to the quote |
| Protocol fee, `f` | `1%` | Fee on the risk-adjusted quote |
| Trading close | 30 seconds before expiry | Prevents last-instant purchases |
| Settlement window | expiry through expiry + 15 seconds | Both Supra feed timestamps must fall here |
| Settlement timeout | 10 minutes after expiry | Then anyone can cancel and unlock refunds |

One ticket has a simple outcome:

- MON at or below strike: payout is `0`;
- MON between strike and cap: payout rises linearly; and
- MON at or above cap: payout is exactly `10 mUSDC`.

The buyer's maximum loss is the premium paid. There is no loan, margin call, or liquidation.

## 5. Mathematics implemented on-chain

Let `S_T` be the verified MON/USD settlement price, `K` the strike, `H` the cap, and `M` the maximum
mUSDC payout. The ticket payoff is:

$$
P(S_T) = M\,\frac{\min(\max(S_T-K,0),H-K)}{H-K}.
$$

This is a scaled call spread: long one call at `K`, short one call at `H`, then normalized so its
maximum value is `M`.

### Black–Scholes reference

For this five-minute MVP the contract uses zero interest, so the call reference is:

$$
c(S,X,\tau,\sigma)=S\,N(d_1)-X\,N(d_2),
$$

$$
d_1=\frac{\ln(S/X)+\tfrac{1}{2}\sigma^2\tau}{\sigma\sqrt{\tau}},
\qquad
d_2=d_1-\sigma\sqrt{\tau}.
$$

The normalized call-spread reference per ticket is:

$$
B=\operatorname{clamp}_{[0,M]}
\left(\frac{M}{H-K}\left[c(S,K,\tau,\sigma)-c(S,H,\tau,\sigma)\right]\right).
$$

The Solidity library evaluates logarithm, exponential, square root, and the normal CDF using signed
18-decimal fixed-point arithmetic. Reference vectors, boundary behavior, and expiry convergence are
covered by tests.

### Jump Guard and all-in quote

The stress spot and stress payoff are:

$$
S_j=S(1+j), \qquad P_j=P(S_j).
$$

Only an adverse-to-the-market upside gap is added, and only by the disclosed weight:

$$
G=w\max(P_j-B,0), \qquad R=B+G.
$$

The displayed premium is:

$$
Q=\min\left(R+\lceil fR\rceil,M\right).
$$

The frontend reads `B`, `G`, `R`, the fee, and `Q` directly from `quote()`; these are not hardcoded
display values. The cap keeps both quote and payout bounded, but it does not prove that the premium
is a statistically fair MON option price.

## 6. Game theory and mechanism design

Schmeckles is best described as a small on-chain commitment game, not as a proof of a Nash
equilibrium.

| Actor | Choice / incentive | Contract-enforced constraint |
|---|---|---|
| Buyer | Buy quantity `q` only when their subjective value exceeds the premium | Pays no more than signed `maxPremium`; maximum loss is payment; maximum payout is `qM` |
| Market owner / capital provider | Supply collateral in exchange for settled premium and fees | Cannot withdraw reserved, claimable, refundable, or fee liabilities |
| Keeper | Keep prices fresh, open epochs, and settle them | Cannot supply an arbitrary settlement number; `settle` requires a valid Supra proof in the exact expiry window |
| Oracle verifier | Attest to MON/USDT and USDT/USD observations | Adapter rejects malformed, missing, duplicate, zero, unsupported-decimal, stale, future, and out-of-window data |
| Any account | Restore liveness after failure | Can cancel after the settlement deadline; buyers then recover their full payment |

The central solvency invariant is:

$$
\text{mUSDC balance} \ge R_{reserved}+L_{claimable}+E_{refundable}+F_{accrued}.
$$

Before a purchase transfers the buyer's premium, the market verifies that existing free collateral
can reserve `qM`. Therefore incoming payment cannot fund its own maximum payout. At successful
settlement the reserve becomes the exact claim liability; at timeout it is released while the full
buyer payment stays refundable.

This changes the strategic surface:

- the buyer does not have to assess counterparty leverage or liquidation risk;
- the operator cannot improve solvency by selling more undercollateralized tickets;
- the keeper may delay service, but cannot forge a settlement value and does not gain the cancelled
  buyer escrow; and
- quote slippage is bounded by the buyer's transaction parameter.

What remains outside this mechanism is equally important: there is no competitive market maker,
dynamic volatility calibration, hedging engine, decentralized keeper set, or formal equilibrium
proof. The owner still controls keeper rotation and test-token minting.

## 7. Why Monad

Monad makes this design practical without abandoning standard EVM tooling:

- **EVM compatibility:** the same Solidity, Foundry, `viem`, wallet, and Rust Alloy workflow used in
  the Ethereum ecosystem works here. Monad documents full EVM bytecode and Ethereum JSON-RPC
  compatibility in its [architecture overview](https://docs.monad.xyz/).
- **Short feedback loop:** Monad documents 400 ms blocks and 800 ms finality. That is a good fit for
  repeated oracle updates, two user transactions (`approve` then `buy`), and five-minute epochs.
- **On-chain transparency at usable cadence:** quotes, purchases, accounting, settlement, claims,
  and refunds remain contract state/events instead of moving to a centralized matching server.
- **Room to scale:** the architecture can add more markets and keepers while preserving the same
  liability checks and verified settlement interface.

### Monad limitations encountered

- Chain speed cannot solve **oracle liveness**. Supra proofs arrive on an external cadence, and both
  component timestamps must align with the contract window.
- Fast chains expose **cross-system clock edges**. A fresh Supra proof can be slightly ahead of the
  latest Monad block timestamp; the keeper deliberately holds a fetched proof for 2.5 seconds before
  submission.
- Public RPC service is still infrastructure with **rate limits and log-range limits**. The keeper
  retries bounded operations and the frontend scans events in small chunks, but a production system
  needs paid/redundant RPCs or an indexer.
- Testnet is not a production guarantee. Monad's
  [testnet changelog](https://docs.monad.xyz/developer-essentials/changelog) documents active protocol
  revisions and previous re-genesis operations.
- Higher throughput does not provide market liquidity, calibrate volatility, decentralize the
  keeper, audit contracts, or turn mUSDC into a redeemable stablecoin.

## 8. Architecture and lifecycle

```text
Supra Pull REST (pair 569 MON/USDT + pair 48 USDT/USD)
                              |
                              v
                    Rust keeper (Alloy)
                     |                 |
              update/open/settle       | proof
                     v                 v
             SchmecklesMarket <--- Supra verifier on Monad
                     |
          +----------+-----------+
          |                      |
       mUSDC                 Next.js + viem
   collateral/faucet       reads/events/writes
                                  |
                              user wallet
```

The browser never receives the keeper key. The keeper accepts no inbound traffic and never
custodies buyer funds; it fetches proofs and submits lifecycle transactions directly to Monad.

```text
Trading (270 s) -> Locked (30 s) -> AwaitingSettlement
                                           | valid proof in [expiry, expiry+15s]
                                           v
                                        Settled -> buyer claims payout
                                           |
                      no settlement by expiry+600s
                                           v
                                        Cancelled -> buyer claims full refund
```

MON/USD is not assumed from a USDT peg. The adapter verifies both feeds and composes:

$$
\text{MON/USD}=\text{MON/USDT}\times\text{USDT/USD}.
$$

## 9. What is implemented

| Layer | Implementation |
|---|---|
| Solidity market | Epoch state machine, live quote, bounded purchases, settlement, cancellation, claims, refunds, protected withdrawals |
| Pricing | Fixed-point Black–Scholes call spread, explicit Jump Guard, fee rounding, full-precision multiplication/division |
| Oracle | Supra Pull V2 proof verification and two-feed MON/USD composition |
| Test collateral | Six-decimal mUSDC with a CLI-only `500 mUSDC` faucet per wallet per rolling 24 hours |
| Rust keeper | Chain-ID preflight, proof fetch/submission, price refresh, epoch open, historical settlement, timeout cancellation, bounded RPC waits |
| Frontend | Contract reads and wallet writes, event-driven refresh, live solvency accounting, quote breakdown, and wallet order history |
| Tests | Unit, reference-vector, fuzz, oracle-rejection, lifecycle, and accounting-invariant coverage |

Repository layout:

```text
contracts/
  src/                 token, oracle adapter, math libraries, and market
  script/Deploy.s.sol  deployment plus 10,000 mUSDC initial collateral
  scripts/             deploy, faucet, keeper rotation, and stress-buy commands
  test/                unit, fuzz, lifecycle, rejection, and invariant tests
keeper/                Rust lifecycle automation
web/                   Next.js contract-connected client
docs/USER_GUIDE.md     beginner product and trading walkthrough
docs/OPERATIONS.md     deployment and operator runbook
```

## 10. Security properties and limitations

Implemented defenses:

- maximum payout reserved before accepting payment;
- protected liabilities cannot be withdrawn;
- non-reentrant token-moving entry points;
- exact balance-delta checks for collateral transfers;
- `maxPremium` slippage protection;
- verified Supra proof parsing with strict shape, pair, decimal, timestamp, and price checks;
- both component feed timestamps required inside `[expiry, expiry + 15 seconds]`;
- keeper-only settlement but permissionless post-timeout cancellation; and
- full refund of payment after cancellation.

Known limitations:

- unaudited contracts and one current owner/keeper trust domain;
- keeper liveness is centralized and currently depends on an operator machine;
- static `120%` volatility and deterministic Jump Guard are not calibrated to a live MON options
  surface;
- no on-chain hedging, liquidity providers, governance, upgrade path, or decentralized automation;
- per-wallet faucet cooldown is Sybil-prone because one person can create multiple wallets;
- mUSDC owner minting is acceptable only for testnet collateral seeding;
- event history is read from RPC logs rather than a production indexer; and
- a 15-second settlement window is an engineering compromise between precision and observed
  two-feed proof cadence.

## 11. Run locally against the current deployment

### Prerequisites

- Git
- [Foundry](https://getfoundry.sh/) (`forge` and `cast`)
- [Rust](https://rustup.rs/)
- Node.js `22.13` or newer
- PowerShell 7 for the included `.ps1` scripts
- a disposable EVM wallet configured for Monad Testnet with test MON for gas

Never use a wallet that holds real assets. An Ethereum-style private key is also the private key for
the same address on Monad because both use EVM accounts; there is no separate "Monad private key."

### 11.1 Clone and test

```powershell
git clone https://github.com/Singularityy0/schleem.git
cd schleem

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

### 11.2 Fund the buyer wallet with test assets

First obtain test MON from a Monad faucet for transaction gas. Then claim project mUSDC from the
repository root:

```powershell
cd contracts
.\scripts\faucet.ps1 `
  -TokenAddress 0xAcDFc40A79302da78A095267045D7cBa2c46fa83 `
  -RpcUrl https://rpc.ankr.com/monad_testnet `
  -PromptForPrivateKey
```

Enter the private key for the **same disposable wallet address used on the website**. The masked
prompt signs an on-chain `faucet()` transaction locally; the private key is not sent to Schmeckles.
That wallet receives exactly `500 mUSDC` and can call the faucet again after 24 hours.

### 11.3 Run the frontend locally

```powershell
cd ..\web
Copy-Item .env.example .env.local
```

Set these public values in `web/.env.local`:

```dotenv
NEXT_PUBLIC_MARKET_ADDRESS=0x922c22B63ae9AC7885f5b3E06067ADA853B00dd6
NEXT_PUBLIC_MUSDC_ADDRESS=0xAcDFc40A79302da78A095267045D7cBa2c46fa83
NEXT_PUBLIC_MONAD_RPC_URL=https://rpc.ankr.com/monad_testnet
NEXT_PUBLIC_SITE_URL=http://localhost:3000
```

Then run:

```powershell
npm run dev
```

Open `http://localhost:3000`, connect the funded wallet, verify `Trading` and a fresh observation,
then use **Approve & buy**. The position appears in **Your orders** after confirmation and updates
from contract events. Claim or refund when the epoch exposes that action.

Running the UI does not start the keeper. The current deployment advances only while its authorized
operator keeper is online.

## 12. Deploy and run your own full stack

### 12.1 Configure and deploy contracts

```powershell
Copy-Item contracts/.env.example contracts/.env
```

Edit ignored `contracts/.env`:

```dotenv
PRIVATE_KEY=0xYOUR_FUNDED_TESTNET_ONLY_DEPLOYER_KEY
MONAD_RPC_URL=https://rpc.ankr.com/monad_testnet
SUPRA_PROOF_URL=https://rpc-testnet-dora-2.supra.com
```

Supra Pull testnet proofs are public; no API key is required. With test MON in the deployer wallet:

```powershell
cd contracts
.\scripts\deploy-monad.ps1
```

The deployment creates mUSDC, the Supra adapter, and the market, then deposits `10,000 mUSDC` of
initial collateral. Copy the three addresses printed by Forge (also stored in
`broadcast/Deploy.s.sol/10143/run-latest.json`) into `contracts/.env`:

```dotenv
MUSDC_ADDRESS=0xYOUR_DEPLOYED_MUSDC
SUPRA_ORACLE_ADDRESS=0xYOUR_DEPLOYED_ADAPTER
MARKET_ADDRESS=0xYOUR_DEPLOYED_MARKET
```

### 12.2 Start the authorized Rust keeper

The deployer is the initial owner and keeper. For separation, create a second testnet wallet, fund
it with test MON, and rotate the contract before starting the service:

```powershell
.\scripts\set-keeper.ps1 -NewKeeperAddress 0xYOUR_KEEPER_ADDRESS
cd ..\keeper
Copy-Item .env.example .env
```

Set the keeper wallet's key and your new addresses in ignored `keeper/.env`:

```dotenv
MONAD_RPC_URL=https://rpc.ankr.com/monad_testnet
PRIVATE_KEY=0xYOUR_FUNDED_TESTNET_ONLY_KEEPER_KEY
MARKET_ADDRESS=0xYOUR_DEPLOYED_MARKET
SUPRA_ORACLE_ADDRESS=0xYOUR_DEPLOYED_ADAPTER
SUPRA_PROOF_URL=https://rpc-testnet-dora-2.supra.com
KEEPER_POLL_MILLISECONDS=1000
LIVE_UPDATE_INTERVAL_SECONDS=20
PROOF_CHAIN_CATCHUP_MILLISECONDS=2500
TRANSACTION_TIMEOUT_SECONDS=45
RUST_LOG=schmeckles_keeper=info
```

Run it continuously:

```powershell
cargo run --release
```

Expected behavior is: chain `10143` preflight, a verified live Supra update, epoch open, regular
price refreshes, settlement after expiry, then the next epoch. The keeper needs no public port or
URL; it talks directly to Supra and the deployed Monad contracts.

### 12.3 Point the frontend at your deployment

Put your market and mUSDC addresses in `web/.env.local`, run `npm run dev`, or configure the same
`NEXT_PUBLIC_*` values in your own Vercel project and deploy from `web/`:

```powershell
cd ..\web
npx vercel --prod
```

Only public addresses/RPC URLs belong in Vercel. Never put an owner, buyer, or keeper private key in
the frontend or a `NEXT_PUBLIC_*` variable.

## 13. Stress test

Fund one or more disposable buyer wallets with test MON and mUSDC. Put the active buyer key and your
release addresses only in ignored `contracts/.env`, keep the Rust keeper running, and execute during
`Trading`:

```powershell
cd contracts
.\scripts\stress-buy.ps1 -Quantity 3
```

The script reads the on-chain quote, adds a 5% `maxPremium` ceiling, approves only that amount, and
submits the purchase. Use multiple wallets for concurrency tests, watch the frontend order history,
and verify after every lifecycle transition that:

```text
collateral balance >= reserved + claimable + refundable + accrued fees
```

The full operational checklist is in [docs/OPERATIONS.md](./docs/OPERATIONS.md). A beginner-focused
website walkthrough is in [docs/USER_GUIDE.md](./docs/USER_GUIDE.md).

## 14. Acknowledgement

The pricing rationale was informed by Julia Kończal,
[*Pricing Options on the Cryptocurrency Futures Contracts*](https://arxiv.org/html/2506.14614v1),
arXiv:2506.14614v1 (2025), licensed CC BY 4.0. Schmeckles is an independent implementation and is
not affiliated with the author, Monad, Supra, Circle, or the exchanges/data studied in the paper.
