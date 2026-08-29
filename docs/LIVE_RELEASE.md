# Live Monad Testnet release

Release date: 2026-08-29

## Public endpoints and contracts

| Item | Value |
|---|---|
| Frontend | [https://schmeckles.vercel.app](https://schmeckles.vercel.app) |
| Vercel project | `singularityy0s-projects/web` |
| mUSDC | `0xF2E29cfd193c3dF30709c0f9104Cce15A82C8bb8` |
| Supra adapter | `0xf91F9Df392e380EAfB84F1212B222F1c33dE3673` |
| Market | `0x97aCD4eeBA9a42a1060BBA53dDABBe0673606985` |
| Supra Pull verifier | `0xF8522B7fcE37439b98A2be282d413A44269028bE` |

## Deployment evidence

- [mUSDC creation](https://testnet.monadvision.com/tx/0x6241ea5606bde03a345390a93476217fae3cd464cd08144fdb11822fb9868fb7)
- [Supra adapter creation](https://testnet.monadvision.com/tx/0x07c002c8804cd35ef12813b17494052608767d6ce8d99ff73ce9653c3d46fc3f)
- [Market creation](https://testnet.monadvision.com/tx/0x6042d1d334d3397b2672676e1025180b920b34272467be74c0e360db1cd8a8ad)
- [10,000 mUSDC collateral deposit](https://testnet.monadvision.com/tx/0xcbb385b6d70aae924b2f4ecc92a06becca2474ece5884fbe64b8355db1df9cac)

## Identical-bytecode staging lifecycle evidence

- [CLI faucet claim](https://testnet.monadvision.com/tx/0x3b8f1af65cfee914c10f7477451d66dbb0cff06f1a701858817e1727fadd68a8)
- [Three-ticket CLI stress purchase](https://testnet.monadvision.com/tx/0x94252357d147be8bedd8dc2be6597272ec6a2d2cc8a3ac2980e303f812b83df8)
- [Strict Supra settlement](https://testnet.monadvision.com/tx/0x7fe9ed32d6d147770c45b33118f7d67750811c49bd05f2ff81666cde8929da06)
- [Position close/claim](https://testnet.monadvision.com/tx/0xe5b46ebbeaaf15457d5049a87f7e5361b9d0762936745f23f526666f77239aa2)

The staging market used the same compiled runtime as the clean release. It ran on chain `10143`, was
backed by the official Supra Pull verifier with pair IDs `569` and `48`, remained solvent after
settlement, held three tickets, and reserved `30 mUSDC`. MON finished below strike, so the correct
payout was zero and the position closed successfully.

The keeper is intentionally not left running after validation because it spends test MON on regular
proof updates. Start it before opening the site for trading and keep it alive through expiry.
