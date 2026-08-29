# Schmeckles explained from zero

This guide assumes you have never traded an option and may be new to blockchains. It takes you from
the basic product idea to what the code, oracle, faucet, keeper, and frontend actually do.

## 1. The idea in plain English

Schmeckles sells a five-minute ticket that benefits if MON goes up against the US dollar.

The buyer pays once. There is no borrowed position, margin call, or liquidation. If MON does not
rise enough, the buyer can lose the premium paid for the ticket. If MON rises, the ticket pays
according to a formula, but the payout stops at a disclosed maximum.

The running MVP uses project-created test money called `mUSDC`. It has no real-world value.

## 2. Spot markets, derivatives, and options

Suppose one MON is worth `$4.00`. That is the **spot price**: the price now. Buying MON directly
means a `$0.10` move changes the value of each MON by `$0.10`.

A **derivative** is a contract whose result is derived from something else. Here, that something is
MON/USD. The buyer does not receive MON; the ticket's later payment is calculated from MON/USD.

A **call option** benefits when a price rises above a level called the **strike**. An ordinary call
can keep gaining value as the asset rises. Schmeckles adds an upper strike, or **cap**, so the
maximum payment is known before anyone trades.

## 3. The capped-call payoff

Each epoch defines:

- `K`: the lower strike;
- `H`: the upper strike or cap;
- `M`: the maximum payout per ticket.

For `K = $4.00`, `H = $4.04`, and `M = 10 mUSDC`:

| Settlement price | Payout |
|---:|---:|
| `$3.99` | `0 mUSDC` |
| `$4.00` | `0 mUSDC` |
| `$4.01` | `2.5 mUSDC` |
| `$4.02` | `5 mUSDC` |
| `$4.03` | `7.5 mUSDC` |
| `$4.04` or higher | `10 mUSDC` |

The formula is:

```text
payout = M * clamp((settlement price - K) / (H - K), 0, 1)
```

`clamp` keeps the fraction between zero and one. Therefore the payout is always between `0` and
`M`.

## 4. Premium, payout, profit, and risk

The **premium** is the amount paid to buy the ticket. The **payout** is what the contract owes after
settlement. They are different.

```text
buyer profit or loss = payout - premium
```

If a ticket costs `1 mUSDC`, a zero payout means a `1 mUSDC` loss. A `5 mUSDC` payout means a
`4 mUSDC` profit. A `10 mUSDC` payout means a `9 mUSDC` profit.

"Fixed risk" does not mean "safe profit." It means the buyer knows the maximum loss, while the
seller and contract know the maximum payout.

## 5. Why the market reserves collateral

Before selling one ticket with `M = 10 mUSDC`, the contract protects a full `10 mUSDC`. Before
selling three, it protects `30 mUSDC`.

Importantly, the contract checks that collateral **before** accepting the new premium. A seller
cannot use the buyer's incoming payment to pretend the ticket was already covered.

Buyer payments stay refundable until a successful settlement. If settlement becomes impossible and
the epoch times out, the buyer can recover the whole payment and the protocol earns no fee.

## 6. The solvency rule

The contract tracks:

- `C`: mUSDC held by the market;
- `R`: maximum payout reserved for unsettled tickets;
- `L`: settled payouts not yet claimed;
- `E`: buyer payments that remain refundable;
- `F`: earned protocol fees not yet withdrawn.

It must maintain:

```text
C >= R + L + E + F
```

Only collateral above those protected obligations is free for the operator to withdraw. Tests cover
this accounting across purchases, settlement, claims, cancellation, and refunds.

## 7. One five-minute epoch

An **epoch** is one market round:

1. The keeper submits a fresh Supra proof containing MON/USDT and USDT/USD.
2. The keeper opens an epoch. That price becomes the strike.
3. Trading is open for 270 seconds.
4. Trading locks for the final 30 seconds.
5. The epoch expires after 300 seconds.
6. The keeper captures a Supra proof whose two timestamps fall in the expiry window.
7. The contract verifies the report and calculates every ticket's payout.
8. Buyers claim their own payout.

If no valid report settles the epoch by ten minutes after expiry, anyone may cancel it. Buyers then
pull their own refunds. There is no loop over every user.

## 8. What Supra does

A blockchain cannot independently observe the dollar price of MON. Supra publishes cryptographic
price proofs, and its Pull verifier contract checks them onchain. The available proof contains
MON/USDT and USDT/USD, so the adapter multiplies them to derive MON/USD instead of assuming USDT is
always exactly one dollar.

This project is configured for:

```text
Monad Testnet chain ID: 10143
Supra Pull verifier:    0xF8522B7fcE37439b98A2be282d413A44269028bE
MON/USDT pair ID:       569
USDT/USD pair ID:       48
```

For normal quoting, live prices may be at most 60 seconds old. For settlement, the publication
timestamp must be inside:

```text
[epoch expiry, epoch expiry + 15 seconds]
```

The report can be submitted later, but the observation inside it must belong to that fixed window.
This prevents a keeper from choosing a later price after seeing which result is favorable.

The adapter rejects malformed or unverified proofs, missing or duplicate pair IDs, zero prices,
unsupported decimals, future timestamps, and any settlement where either feed is outside the window.

## 9. How the ticket price is calculated

The base reference is a zero-interest-rate **Black-Scholes call spread**:

```text
base = M / (H - K) * (call(K) - call(H))
```

Its inputs are the live spot price, strike, cap, time remaining, and disclosed annualized
volatility. Solidity cannot use ordinary floating-point numbers, so the implementation uses
18-decimal fixed-point logarithm, exponential, square-root, and normal-CDF approximations.

The tests compare the result with high-precision reference vectors and cover expiry behavior. This
is a transparent pricing reference, not a guarantee of economic fairness. Black-Scholes assumptions
do not perfectly describe short-horizon crypto markets.

## 10. The Jump Guard and fee

Crypto can jump. The quote therefore evaluates the ticket at a disclosed upward stress price and
adds a fraction of any amount by which that stressed payoff exceeds the Black-Scholes base.

```text
stressed spot = live spot * (1 + jump size)
jump guard    = jump weight * max(stressed payout - base, 0)
risk adjusted = base + jump guard
all in        = risk adjusted + protocol fee
```

The adjustment is bounded. The all-in price is capped at the ticket's maximum payout, even after
rounding the protocol fee.

The initial keeper parameters are visible in code: 1% cap width, `10 mUSDC` maximum payout, 120%
annualized pricing volatility, 0.75% stress jump, 10% stress weight, and 1% protocol fee. They are
choices for an experimental testnet market, not measured promises.

## 11. What mUSDC really is

`mUSDC` is an ERC-20-compatible token deployed by this project on Monad Testnet. It is not canonical
USDC, not backed by dollars, and not redeemable.

The deployment mints `10,000 mUSDC` to seed market collateral. A user funds their own wallet by
calling the token's faucet from the command line:

```powershell
cd contracts
.\scripts\faucet.ps1
```

The faucet mints exactly `500 mUSDC` to the calling wallet. That same wallet cannot claim again for
24 hours. There is deliberately no faucet button on the website.

The wallet still needs a small amount of test MON to pay gas for the faucet, approval, purchase,
claim, or refund. mUSDC pays the ticket premium; MON pays network gas.

## 12. Who holds which key

For the MVP, one dedicated burner wallet can deploy contracts, own the market, and run the keeper.
It needs test MON because it submits transactions throughout the lifecycle, not only at deployment.

The buyer controls a separate wallet in their browser or CLI. The buyer also needs test MON.

`PRIVATE_KEY` belongs only in `contracts/.env` or the keeper's server-side secret environment. It
never belongs in browser code or Vercel's public variables. Supra's testnet proof endpoint is public
and does not require an API key.

## 13. What the Rust keeper does

The Rust service is the automation layer:

- verifies that the RPC is Monad Testnet chain `10143`;
- fetches public EVM proof bytes from Supra Pull;
- submits verified live prices onchain;
- opens a new epoch when the previous one is complete;
- polls at expiry and captures a proof in the verified 15-second window;
- settles inside the allowed deadline; or
- cancels a missed epoch so buyers can refund.

It polls state; it does not custody buyer assets or maintain a separate trading database. If it
stops, the Solidity timeout path protects users from permanent lockup.

## 14. What the frontend does

The Next.js page reads the deployed contracts directly. It shows the active epoch, oracle price and
age, quote components, payoff chart, market accounting, wallet balance and allowance, faucet
cooldown, and the connected wallet's position.

It watches contract events and refreshes after purchases, price updates, settlement, claims,
cancellation, and refunds. It does not invent fallback market figures. With missing addresses or a
failed read, it shows an unavailable/configuration state.

Wallet actions are client-signed: approve mUSDC, buy, claim, or refund. No server receives the
buyer's private key.

## 15. What is real and what remains experimental

| Part | Meaning |
|---|---|
| mUSDC | Real token contract, but economically worthless test collateral |
| Payoff and reserves | Enforced by tested Solidity |
| Supra adapter | Real Pull verifier integration using public testnet proofs |
| Black-Scholes | Real fixed-point implementation with vectors; unaudited |
| Keeper | Real Rust transaction service; requires secrets and reliable hosting |
| Frontend | Real contract state and wallet transactions after addresses are configured |
| Mainnet readiness | No; testnet-only and unaudited |

The remaining proof of readiness is operational: a deployed Testnet epoch must complete end to end
with the keeper running continuously through its settlement window.

## 16. A simple demo explanation

Use this sequence:

1. "This is a five-minute ticket on MON going up."
2. "The buyer pays once and cannot be liquidated."
3. "Payout rises between the strike and cap, then stops at 10 mUSDC."
4. "The contract protects the full 10 mUSDC before selling one ticket."
5. "Supra verifies both prices used to derive the MON/USD settlement observation."
6. "If settlement misses its deadline, the buyer can recover the whole payment."
7. "mUSDC is project-created test money; MON is still needed for gas."

## 17. Glossary

**Spot price:** The price now.

**Derivative:** A contract whose result depends on another asset or price.

**Call:** An option that benefits from an upward move.

**Strike (`K`):** The price where payout begins.

**Cap (`H`):** The price where payout reaches its maximum.

**Maximum payout (`M`):** The most one ticket can pay.

**Premium:** What the buyer pays for the ticket.

**Expiry:** The predetermined end of the option.

**Epoch:** One complete five-minute round.

**Collateral:** Tokens held to cover obligations.

**Reserve:** Collateral protected for maximum unsettled payouts.

**Escrow:** Buyer payments kept refundable until settlement succeeds.

**Settlement:** Converting an authenticated expiry price into a payout.

**Oracle:** A mechanism for verifying external data onchain.

**Keeper:** A service that submits maintenance transactions.

**Volatility:** A measure of how strongly prices tend to move.

**Solvency:** Having enough assets to cover all protected obligations.

## 18. The shortest accurate summary

Schmeckles is an unaudited Monad Testnet experiment for five-minute MON upside tickets. The buyer's
loss is limited to the premium, the payout is capped, and the contract reserves the full cap before
a sale. Supra supplies verified prices, fixed-point Black-Scholes supplies a visible base quote, and
a Rust keeper advances the lifecycle. The project-created mUSDC token has no real value.
