# Schmeckles website guide for first-time options users

This guide explains every important item on [schmeckles.vercel.app](https://schmeckles.vercel.app)
and walks through funding, buying, settlement, claiming, and refunds. It assumes no previous options
or blockchain trading experience.

> **Testnet only:** mUSDC and test MON have no real-world value. Schmeckles is unaudited experimental
> software, not a savings product and not financial advice. Use a dedicated testnet-only wallet that
> has never held real assets.

## 1. The product in one minute

Schmeckles sells five-minute tickets that can pay if MON/USD finishes above a starting price.

- You pay an upfront **premium** in project-created test money called **mUSDC**.
- The starting MON/USD price is the **strike**.
- At or below the strike, the payout is zero.
- Between the strike and the **cap**, the payout rises in a straight line.
- At or above the cap, the payout stops increasing at the displayed **maximum payout**.
- Your maximum loss is the premium you paid. There is no borrowing, margin call, or liquidation.
- Maximum payout is not maximum profit. Profit or loss is `payout - total payment`.

For one ticket with a `10 mUSDC` maximum payout:

| MON/USD at settlement | Ticket result |
|---|---|
| At or below strike | `0 mUSDC` payout |
| Halfway from strike to cap | About `5 mUSDC` payout |
| At or above cap | `10 mUSDC` payout |

The exact premium, strike, and cap are shown before you buy.

## 2. What you need

You need:

1. An EVM browser wallet such as MetaMask or Rabby.
2. The wallet set to **Monad Testnet**, chain ID `10143`.
3. A small amount of test MON for transaction gas.
4. mUSDC from the command-line faucet.
5. The project repository and Foundry's `cast` command for the faucet script.
6. An active market showing the green **Trading** status.

Keep two currencies separate in your mind:

| Currency | Purpose |
|---|---|
| Test MON | Pays blockchain gas for faucet, approval, buy, claim, and refund transactions |
| mUSDC | Pays the ticket premium and receives payouts/refunds; it is not real USDC |

Current mUSDC details:

```text
Name:     Monad Test USDC
Symbol:   mUSDC
Decimals: 6
Address:  0xAcDFc40A79302da78A095267045D7cBa2c46fa83
```

You may import this token address into the wallet to see its balance there. The website can read the
balance even if the token is not manually imported.

## 3. Connect the wallet

1. Open [schmeckles.vercel.app](https://schmeckles.vercel.app).
2. Confirm the header says **Monad Testnet**.
3. Click **Connect wallet**.
4. Approve the wallet connection.
5. If requested, approve adding or switching to Monad Testnet.
6. Confirm the shortened address in the header matches the wallet you intend to use.

Connecting only shares the selected public address. The website cannot read the private key.

## 4. Fund that exact wallet with 500 mUSDC

The faucet is CLI-only. It mints exactly `500 mUSDC` to the wallet signing the faucet transaction,
once per rolling 24 hours. The wallet needs a small amount of test MON for gas.

The private key entered below must belong to the same public address connected on the website. If a
different key signs the faucet call, the mUSDC goes to that different wallet.

### Safest supported method: masked prompt

Open a terminal in the repository. From Git Bash on Windows:

```bash
cd ~/schleem/contracts

powershell.exe -ExecutionPolicy Bypass \
  -File ./scripts/faucet.ps1 \
  -TokenAddress 0xAcDFc40A79302da78A095267045D7cBa2c46fa83 \
  -RpcUrl https://rpc.ankr.com/monad_testnet \
  -PromptForPrivateKey
```

From PowerShell:

```powershell
cd C:\Users\anany\schleem\contracts

.\scripts\faucet.ps1 `
  -TokenAddress 0xAcDFc40A79302da78A095267045D7cBa2c46fa83 `
  -RpcUrl https://rpc.ankr.com/monad_testnet `
  -PromptForPrivateKey
```

At the masked prompt, enter the dedicated testnet wallet's private key. The key is used locally by
`cast` to sign the transaction; it is not printed and is not sent to the website. Never enter a seed
phrase, and never use a wallet that has held real assets.

Successful output begins with:

```text
Claiming 500 mUSDC. This wallet can claim again after 24 hours.
```

It then prints a successful Monad transaction receipt. Return to the website and click **Refresh**.
The **Wallet balance** should show `500.00 mUSDC`.

### Faucet problems

- **FaucetCooldown:** that wallet already claimed and must wait until the displayed next eligibility.
- **Insufficient funds for gas:** fund the wallet with test MON; mUSDC cannot pay gas.
- **Balance remains zero:** compare the connected browser address with the address derived from the
  key used by the script, confirm the transaction succeeded, and click **Refresh**.
- **Wrong token:** use the current mUSDC address in this guide, not an address from an older release.
- **`cast` not found:** install Foundry or make sure `~/.foundry/bin` is available.

## 5. Read the main market card

### “MON rises before expiry”

This describes the bet. The payout uses the authenticated MON/USD observation at expiry, not any
temporary price seen earlier during the five-minute round.

### Epoch number

An **epoch** is one complete five-minute market round. `Epoch #2` means this is the second round on
the deployed market. Positions do not carry into the next epoch.

### Status badge

| Status | Meaning | What you can do |
|---|---|---|
| **Trading** | Purchases are open | Buy tickets while time remains |
| **Locked** | Final 30 seconds before expiry | No new purchases; wait |
| **Awaiting settlement** | Expiry passed; keeper is submitting a verified Supra report | Wait |
| **Settled** | Payout per ticket is final | Click **Claim payout** if you bought |
| **Cancelled** | Settlement deadline was missed | Click **Claim refund** if you bought |

### Refresh

The page listens for contract events and normally updates automatically. **Refresh** forces a new
read from Monad when a wallet transaction or keeper event has just completed.

## 6. Understand the payoff chart

- **Supra spot:** the latest verified MON/USD price. It can move after the epoch opens.
- **Strike:** MON/USD when the keeper opened the epoch. Payout begins only above this level.
- **Cap:** the level where payout reaches its maximum.
- **Flat line below strike:** payout is zero.
- **Rising line between strike and cap:** payout increases proportionally.
- **Flat line after cap:** payout stays at the maximum even if MON rises further.
- **Purple marker:** the current verified spot price relative to the payoff curve.

Buying does not mean you receive MON. You receive an onchain ticket whose result is calculated from
MON/USD.

## 7. Understand the displayed contract terms

| Label | Plain-English meaning |
|---|---|
| **Strike** | The MON/USD price where payout starts; fixed when the epoch opens |
| **Cap** | The price where payout stops increasing |
| **Width** | Percentage distance from strike to cap |
| **Max payout** | Most one ticket can return; currently `10 mUSDC` per ticket |
| **Time left** | Countdown to expiry; buying closes 30 seconds before this reaches zero |
| **Volatility** | Annualized pricing-model input; not a prediction or promised future movement |
| **Jump stress** | Extra upward price shock considered by the risk adjustment |
| **Jump weight** | Fraction of the stressed result added to the quote |
| **Protocol fee** | Fee included in the total payment and earned only after successful settlement |

The initial `120% volatility` may look large because it is annualized. The actual contract lasts
only five minutes.

## 8. Understand the quote panel

Set **Quantity** with the minus and plus buttons. The website supports 1–25 tickets per purchase.

| Quote line | Meaning |
|---|---|
| **Black–Scholes call spread** | Transparent mathematical base estimate for the capped ticket |
| **Jump Guard** | Additional amount for a disclosed short-horizon upward stress scenario |
| **Risk-adjusted price** | Black–Scholes base plus Jump Guard |
| **Protocol fee** | Fee added to the risk-adjusted price |
| **Total payment** | Actual quoted premium for the selected quantity |
| **Wallet balance** | Connected wallet's current mUSDC balance |
| **Max payout** | Quantity multiplied by maximum payout per ticket; not guaranteed profit |

The pricing model is a quote, not a prediction. A ticket can still pay zero.

### Example

Suppose one ticket shows:

```text
Total payment: 2.05 mUSDC
Max payout:   10.00 mUSDC
```

- If settlement is at or below strike: payout `0`; loss `2.05 mUSDC`.
- If payout is `5`: profit `5 - 2.05 = 2.95 mUSDC`.
- If payout reaches `10`: profit `10 - 2.05 = 7.95 mUSDC`.

## 9. Buy a ticket step by step

Before buying, verify all of these:

- The connected address is correct.
- Status is **Trading**.
- **Observation age** is not red and is at most 60 seconds.
- The market says **Solvent**.
- Wallet balance covers **Total payment**.
- You understand that the full premium can be lost.

Then:

1. Choose the quantity.
2. Review total payment and maximum payout.
3. Click **Approve & buy**.
4. If allowance is insufficient, the wallet first asks for an **approval** transaction.
5. Confirm approval and wait for it to complete.
6. The wallet then asks for the **buy** transaction. Confirm it.
7. Wait for **Purchase finalized on Monad Testnet**.
8. Confirm **Position** shows the expected ticket count and **Your orders** contains the epoch.

Approval does not buy the ticket. It lets the market transfer up to the approved mUSDC amount. The
second transaction makes the purchase. If sufficient allowance already exists, only the buy request
may appear.

The website permits up to 1% quote movement between display and execution. The contract transfers
the actual live quoted payment, never more than that limit. If the quote moves beyond it or trading
locks first, the purchase reverts and the ticket is not created.

## 10. What happens after buying

1. The market immediately protects the full maximum payout for every ticket sold.
2. Your premium remains refundable until successful settlement.
3. Trading locks for the final 30 seconds.
4. At expiry, the keeper submits a Supra proof from the contract's 15-second observation window.
5. The contract verifies both MON/USDT and USDT/USD and derives MON/USD.
6. The payout per ticket becomes final.

Keep the browser open if convenient, but the position exists onchain and does not disappear if the
page is closed.

### Your orders

This panel reads every epoch position belonging to the connected wallet. It updates after purchase,
settlement, cancellation, claim, and refund events. It shows the epoch, status, total tickets,
premium paid, strike, and current payout/refund amount. Multiple purchases made by the same wallet
in one epoch are combined because the contract stores one aggregate position per wallet per epoch.

The history remains available after the keeper opens a newer epoch. Use its **Claim epoch payout**
or **Claim epoch refund** button to close an older position.

## 11. Claim a payout or refund

### Settled epoch

When an order becomes **Claim ready**, the **Your orders** panel shows **Claim epoch payout**.

1. Click **Claim epoch payout** on the correct epoch.
2. Confirm the wallet transaction and gas fee.
3. Wait for **Payout claimed**.

Click claim even when payout is zero; it marks that position closed onchain.

### Cancelled epoch

If settlement does not complete by the displayed settlement deadline, the epoch becomes
**Cancelled** and the order becomes **Refund ready**.

1. Click **Claim epoch refund** on the correct epoch.
2. Confirm the wallet transaction.
3. The full premium paid for that position returns to the wallet.

The protocol fee is not earned on a cancelled epoch.

## 12. Understand the solvency monitor

The monitor reads accounting directly from the market contract.

| Label | Meaning |
|---|---|
| **Collateral (C)** | All mUSDC held by the market |
| **Reserved (R)** | Maximum payout protected for unsettled tickets |
| **Claimable (L)** | Settled payouts buyers have not claimed yet |
| **Refundable (E)** | Buyer payments still protected for possible refunds |
| **Fees (F)** | Earned protocol fees not withdrawn yet |
| **Free** | Collateral remaining after all protected obligations |

The displayed rule is:

```text
C >= R + L + E + F
```

**Solvent** means the contract currently has enough mUSDC to cover those protected obligations. It
does not mean a ticket is guaranteed to be profitable.

## 13. Understand “Live infrastructure”

| Label | Meaning |
|---|---|
| **Supra MON/USD** | Latest onchain-verified composite price |
| **Observation age** | Seconds since that verified price was published; red means stale |
| **Position** | Tickets owned by the connected wallet in the active epoch |
| **Settlement deadline** | Last time the keeper may settle before cancellation becomes available |
| **Faucet: CLI only** | mUSDC must be claimed with the PowerShell script, not a web button |

The contract rejects live observations older than 60 seconds. If age is red, wait for the keeper to
submit a new proof before attempting a purchase.

## 14. Common website situations

### “Waiting for an active onchain epoch”

No epoch is open. The keeper may be offline, starting, or moving from a completed epoch to the next.

### Buy button is disabled

Typical reasons are: wallet not connected, status is not Trading, insufficient mUSDC, or another
transaction is pending.

### Approval succeeded but buy failed

The quote may have moved, trading may have locked, or the wallet may have rejected the second
transaction. Approval alone does not spend the premium. Refresh and buy during the next Trading
window.

### Wallet shows tokens but website shows zero

Check that the selected address and Monad Testnet are correct, then click Refresh. Also verify the
token address is the current mUSDC release.

### Observation age is red

Do not buy. Wait for a successful keeper price update and refresh.

### Transaction is pending

Do not repeatedly click. Check the wallet activity and Monad explorer, then refresh after it confirms.

## 15. Security rules

- Use only a disposable testnet wallet.
- Never paste a seed phrase anywhere.
- Never put a buyer private key into the website, Vercel, Git, screenshots, or chat.
- Use the faucet's masked prompt instead of putting the key in a command argument.
- Verify contract addresses against the **Current Monad Testnet release** section in
  [README.md](../README.md).
- Remember that mUSDC is project-created test money and cannot be redeemed for dollars.

## 16. Beginner checklist

```text
[ ] I am using a testnet-only wallet.
[ ] The wallet has test MON for gas.
[ ] The website is on Monad Testnet.
[ ] The connected address is the wallet I funded with the CLI faucet.
[ ] Wallet balance shows 500 mUSDC after refreshing.
[ ] Status is Trading and observation age is fresh.
[ ] I reviewed total payment and understand it can be fully lost.
[ ] I confirmed approval, then confirmed buy.
[ ] Position shows my ticket count.
[ ] After expiry, I claimed payout or refund when the button appeared.
```

For the underlying research, options math, and mechanism design, read [README.md](../README.md).
For keeper and deployment operations, read [OPERATIONS.md](./OPERATIONS.md).
