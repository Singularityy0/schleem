# Four-minute MVP demo

Run this only after the go/no-go checks in [OPERATIONS.md](./OPERATIONS.md) pass.

## Before the walkthrough

1. Keep the passing Solidity, Rust, and frontend verification summaries available.
2. Confirm the Rust keeper is healthy and the oracle price is less than 60 seconds old.
3. Use a buyer wallet with test MON and faucet-funded mUSDC.
4. Open the deployed Vercel app and connect the buyer wallet.

## 0:00-0:45 - fixed-risk product

Show the payoff chart. The payout is zero below the strike, linear between strike and cap, and fixed
at `10 mUSDC` above the cap. The buyer pays once and cannot be liquidated.

## 0:45-1:30 - live, disclosed quote

Show the verified MON/USD price and its age. Select two tickets and point out the fixed-point
Black-Scholes base, Jump Guard, protocol fee, total payment, and `20 mUSDC` maximum payout. Explain
that model price is a reference, not a promise of profit.

## 1:30-2:15 - reserve before sale

Approve mUSDC and buy. Show contract accounting refresh after the purchase event. Maximum reserved
liability increases by exactly `20 mUSDC`, while the full payment enters refundable escrow.

## 2:15-3:15 - verified settlement

At expiry, show the keeper retrieving the latest Supra Pull proof and submitting it. The Supra
verifier authenticates both component feeds and timestamps onchain. The maximum reserve becomes the exact
aggregate claim liability.

For a separate failure-path demo, stop the keeper through the settlement deadline, cancel, and show
that the full buyer payment becomes refundable with no fee earned.

## 3:15-4:00 - claim and invariant

Claim the payout. Show the wallet balance and claimable liability change together. End with:

```text
contract balance >= reserved + claimable + refundable + accrued fees
```

Disclose that mUSDC is project-created test money, the software is unaudited, and the market is on
Monad Testnet.
