use std::{env, str::FromStr, time::Duration};

use alloy::{
    primitives::{Address, Bytes, U256},
    providers::{Provider, ProviderBuilder},
    signers::local::PrivateKeySigner,
    sol,
};
use anyhow::{Context, Result, bail};
use reqwest::Client;
use schmeckles_keeper::{LifecycleAction, SupraProofRequest, SupraProofResponse, lifecycle_action};
use tracing::{error, info, warn};
use url::Url;

sol! {
    #[sol(rpc)]
    interface ISupraPriceOracle {
        function latest() external view returns (uint256 price, uint64 publishTime);
        function parseHistorical(bytes calldata proof, uint64 minPublishTime, uint64 maxPublishTime)
            external returns (uint256 price, uint64 publishTime);
    }

    #[sol(rpc)]
    interface ISchmecklesMarket {
        struct OpenParams {
            uint16 capBps;
            uint128 maxPayout;
            uint32 pricingVolBps;
            uint16 jumpSizeBps;
            uint16 jumpWeightBps;
            uint16 feeBps;
        }

        struct Epoch {
            uint8 storedStatus;
            uint64 openedAt;
            uint64 tradingClose;
            uint64 expiry;
            uint64 settlementDeadline;
            uint64 reportPublishTime;
            uint256 strike;
            uint256 cap;
            uint256 maxPayout;
            uint32 pricingVolBps;
            uint16 jumpSizeBps;
            uint16 jumpWeightBps;
            uint16 feeBps;
            uint256 settlementPrice;
            uint256 payoutPerTicket;
            uint256 totalTickets;
            uint256 totalPaymentEscrow;
            uint256 totalProtocolFeeEscrow;
            uint256 totalPayoutLiability;
        }

        function activeEpochId() external view returns (uint256);
        function epochStatus(uint256 epochId) external view returns (uint8);
        function getEpoch(uint256 epochId) external view returns (Epoch memory);
        function updateLivePrice(bytes calldata proof)
            external returns (uint256 price, uint64 publishTime);
        function openEpoch(OpenParams calldata params) external returns (uint256 epochId);
        function settle(uint256 epochId, bytes calldata proof) external;
        function cancel(uint256 epochId) external;
    }
}

const MONAD_TESTNET_CHAIN_ID: u64 = 10_143;
const MON_USDT_PAIR_ID: u32 = 569;
const USDT_USD_PAIR_ID: u32 = 48;

#[derive(Debug, Clone)]
struct Config {
    rpc_url: Url,
    private_key: String,
    market_address: Address,
    oracle_address: Address,
    supra_proof_url: String,
    poll_interval: Duration,
    live_update_interval: u64,
    transaction_timeout: Duration,
    once: bool,
}

impl Config {
    fn from_env() -> Result<Self> {
        let _ = dotenvy::from_filename("contracts/.env");
        let _ = dotenvy::from_filename("../contracts/.env");
        let _ = dotenvy::dotenv();
        let rpc_url = required("MONAD_RPC_URL")?
            .parse()
            .context("invalid MONAD_RPC_URL")?;
        let private_key = normalize_private_key(required("PRIVATE_KEY")?);
        let market_address =
            Address::from_str(&required("MARKET_ADDRESS")?).context("invalid MARKET_ADDRESS")?;
        let oracle_address = Address::from_str(&required("SUPRA_ORACLE_ADDRESS")?)
            .context("invalid SUPRA_ORACLE_ADDRESS")?;
        let supra_proof_url = env::var("SUPRA_PROOF_URL")
            .unwrap_or_else(|_| "https://rpc-testnet-dora-2.supra.com".into());
        let poll_milliseconds = env_number("KEEPER_POLL_MILLISECONDS", 1_000)?;
        let live_update_interval = env_number("LIVE_UPDATE_INTERVAL_SECONDS", 20)?;
        let transaction_timeout =
            Duration::from_secs(env_number("TRANSACTION_TIMEOUT_SECONDS", 45)?);
        let once = env::var("KEEPER_ONCE").is_ok_and(|value| value == "1" || value == "true");

        if !private_key.starts_with("0x") || private_key.len() != 66 {
            bail!("PRIVATE_KEY must be a 32-byte 0x-prefixed testnet key");
        }
        Ok(Self {
            rpc_url,
            private_key,
            market_address,
            oracle_address,
            supra_proof_url: supra_proof_url.trim_end_matches('/').into(),
            poll_interval: Duration::from_millis(poll_milliseconds),
            live_update_interval,
            transaction_timeout,
            once,
        })
    }
}

fn required(name: &str) -> Result<String> {
    env::var(name).with_context(|| format!("missing required environment variable {name}"))
}

fn normalize_private_key(value: String) -> String {
    if value.len() == 64 && value.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        format!("0x{value}")
    } else {
        value
    }
}

fn env_number(name: &str, default: u64) -> Result<u64> {
    env::var(name)
        .map(|value| value.parse().with_context(|| format!("invalid {name}")))
        .unwrap_or(Ok(default))
}

async fn fetch_proof(client: &Client, base_url: &str) -> Result<Bytes> {
    let url = format!("{base_url}/get_proof");
    let request = SupraProofRequest {
        pair_indexes: vec![MON_USDT_PAIR_ID, USDT_USD_PAIR_ID],
        chain_type: "evm".into(),
    };
    let response = client
        .post(&url)
        .json(&request)
        .send()
        .await
        .with_context(|| format!("failed to request Supra proof from {url}"))?
        .error_for_status()
        .with_context(|| format!("Supra rejected request to {url}"))?
        .json::<SupraProofResponse>()
        .await
        .context("invalid Supra JSON response")?;
    response.proof(&[MON_USDT_PAIR_ID, USDT_USD_PAIR_ID])
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "schmeckles_keeper=info".into()),
        )
        .init();

    let config = Config::from_env()?;
    let signer = PrivateKeySigner::from_str(&config.private_key)
        .context("PRIVATE_KEY could not create a signer")?;
    let provider = ProviderBuilder::new()
        .with_chain_id(MONAD_TESTNET_CHAIN_ID)
        .wallet(signer)
        .connect_http(config.rpc_url.clone());
    let chain_id = provider
        .get_chain_id()
        .await
        .context("RPC chain-id check failed")?;
    if chain_id != MONAD_TESTNET_CHAIN_ID {
        bail!("refusing to run on chain {chain_id}; expected Monad Testnet 10143");
    }

    let market = ISchmecklesMarket::new(config.market_address, &provider);
    let oracle = ISupraPriceOracle::new(config.oracle_address, &provider);
    let http = Client::builder().timeout(Duration::from_secs(20)).build()?;

    info!(market = %config.market_address, oracle = %config.oracle_address, "keeper started");
    loop {
        if let Err(problem) = run_cycle(&config, &http, &market, &oracle).await {
            error!(error = %problem, "keeper cycle failed; will retry");
        }
        if config.once {
            break;
        }
        tokio::select! {
            _ = tokio::time::sleep(config.poll_interval) => {},
            _ = tokio::signal::ctrl_c() => {
                info!("shutdown requested");
                break;
            }
        }
    }
    Ok(())
}

async fn run_cycle<P: Provider>(
    config: &Config,
    http: &Client,
    market: &ISchmecklesMarket::ISchmecklesMarketInstance<&P>,
    oracle: &ISupraPriceOracle::ISupraPriceOracleInstance<&P>,
) -> Result<()> {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)?
        .as_secs();
    let epoch_id_u256 = market.activeEpochId().call().await?;
    let epoch_id: u64 = epoch_id_u256
        .try_into()
        .context("active epoch id exceeds u64")?;
    let (status, deadline, expiry) = if epoch_id == 0 {
        (0, 0, 0)
    } else {
        let status = market.epochStatus(U256::from(epoch_id)).call().await?;
        let epoch = market.getEpoch(U256::from(epoch_id)).call().await?;
        (status, epoch.settlementDeadline, epoch.expiry)
    };

    let action = lifecycle_action(epoch_id, status, now, deadline);
    if action == LifecycleAction::Settle {
        let proof = fetch_proof(http, &config.supra_proof_url).await?;
        match oracle
            .parseHistorical(proof.clone(), expiry, expiry + 2)
            .call()
            .await
        {
            Ok(verified) => {
                let call = market.settle(U256::from(epoch_id), proof);
                let pending = tokio::time::timeout(config.transaction_timeout, call.send())
                    .await
                    .context("settlement transaction submission timed out")??;
                let receipt = pending
                    .with_timeout(Some(config.transaction_timeout))
                    .get_receipt()
                    .await?;
                info!(
                    epoch_id,
                    price = %verified.price,
                    publish_time = verified.publishTime,
                    tx = %receipt.transaction_hash,
                    "settled epoch with Supra proof"
                );
            }
            Err(problem) => {
                warn!(
                    epoch_id,
                    expiry,
                    error = %problem,
                    "latest Supra proof is outside the settlement window; retrying"
                );
            }
        }
        return Ok(());
    }

    let needs_live_update = match oracle.latest().call().await {
        Ok(latest) => now.saturating_sub(latest.publishTime) >= config.live_update_interval,
        Err(problem) if problem.to_string().contains("0xcb08be81") => {
            warn!(error = %problem, "oracle has no valid live price yet; bootstrapping it");
            true
        }
        Err(problem) => bail!("failed to read latest oracle price: {problem}"),
    };
    if needs_live_update {
        let proof = fetch_proof(http, &config.supra_proof_url).await?;
        let call = market.updateLivePrice(proof);
        let pending = tokio::time::timeout(config.transaction_timeout, call.send())
            .await
            .context("live-price transaction submission timed out")??;
        let receipt = pending
            .with_timeout(Some(config.transaction_timeout))
            .get_receipt()
            .await?;
        info!(tx = %receipt.transaction_hash, "submitted live Supra proof");
    }

    match action {
        LifecycleAction::Wait | LifecycleAction::Settle => {}
        LifecycleAction::Open => {
            let params = ISchmecklesMarket::OpenParams {
                capBps: 100,
                maxPayout: 10_000_000,
                pricingVolBps: 12_000,
                jumpSizeBps: 75,
                jumpWeightBps: 1_000,
                feeBps: 100,
            };
            let call = market.openEpoch(params);
            let pending = tokio::time::timeout(config.transaction_timeout, call.send())
                .await
                .context("open-epoch transaction submission timed out")??;
            let receipt = pending
                .with_timeout(Some(config.transaction_timeout))
                .get_receipt()
                .await?;
            info!(tx = %receipt.transaction_hash, "opened epoch");
        }
        LifecycleAction::Cancel => {
            warn!(
                epoch_id,
                "settlement deadline passed; cancelling epoch for refunds"
            );
            let call = market.cancel(U256::from(epoch_id));
            let pending = tokio::time::timeout(config.transaction_timeout, call.send())
                .await
                .context("cancel transaction submission timed out")??;
            let receipt = pending
                .with_timeout(Some(config.transaction_timeout))
                .get_receipt()
                .await?;
            info!(epoch_id, tx = %receipt.transaction_hash, "cancelled epoch");
        }
    }
    Ok(())
}
