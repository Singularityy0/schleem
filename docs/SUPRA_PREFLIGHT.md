# Supra preflight for Monad Testnet

Verified on 2026-08-29 against official Supra infrastructure and Monad Testnet.

| Item | Value |
|---|---|
| Monad chain ID | `10143` (`0x279f`) |
| Monad RPC | `https://testnet-rpc.monad.xyz` |
| Supra Pull verifier | `0xF8522B7fcE37439b98A2be282d413A44269028bE` |
| Supra Pull storage | `0xf0e852BC3F940447862D6b67e5B9807E64B433F6` |
| Proof REST base | `https://rpc-testnet-dora-2.supra.com` |
| MON/USDT pair | `569` |
| USDT/USD pair | `48` |

Official sources:

- [Supra Pull Oracle integration](https://docs.supra.com/oracles/data-feeds/pull-oracle)
- [Supra pair list](https://docs.supra.com/oracles/data-feeds/data-feeds-index)
- [Official pull client examples](https://github.com/Entropy-Foundation/oracle-pull-example)

## Live result

The public endpoint accepted:

```json
{"pair_indexes":[569,48],"chain_type":"evm"}
```

The official Monad verifier decoded a real proof as:

```text
pairs:      [569, 48]
prices:     [27160000000000000, 100000000]
decimals:   [18, 8]
timestamps: millisecond Unix timestamps
```

That observation represents MON/USDT `0.02716` and USDT/USD `1.00`. The adapter derives an
8-decimal MON/USD price of `2716000` (`$0.02716000`). No API key or subscription is required for
this testnet proof endpoint.

## Verification and rejection rules

`SupraPriceOracle` calls `verifyOracleProofV2(bytes)` on the official verifier, then rejects:

- a proof whose parallel result arrays have different lengths;
- missing or duplicate pair IDs;
- zero component or composite prices;
- decimals above 36;
- invalid or future live timestamps; and
- settlement unless both raw millisecond timestamps are within the exact two-second window.

It stores only a successfully verified live composite. The market accepts live observations no more
than 60 seconds old.

## Settlement availability constraint

Supra's documented `/get_proof` request returns the latest proof; it does not accept a historical
timestamp. The keeper therefore polls every second and must capture a proof at expiry. It first
simulates `parseHistorical` onchain, then submits that same proof to `settle`.

If the keeper misses `[expiry, expiry + 2]`, it cannot choose a later observation. After the
ten-minute settlement deadline, anyone can cancel the epoch and buyers can reclaim their full
payments. For a production system, durable proof capture and redundant keepers are mandatory.
