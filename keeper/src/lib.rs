use alloy::primitives::Bytes;
use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LifecycleAction {
    Wait,
    Open,
    Settle,
    Cancel,
}

pub fn lifecycle_action(
    active_epoch_id: u64,
    status: u8,
    now: u64,
    settlement_deadline: u64,
) -> LifecycleAction {
    if active_epoch_id == 0 || status == 4 || status == 5 {
        LifecycleAction::Open
    } else if status == 3 && now > settlement_deadline {
        LifecycleAction::Cancel
    } else if status == 3 {
        LifecycleAction::Settle
    } else {
        LifecycleAction::Wait
    }
}

#[derive(Debug, Serialize)]
pub struct SupraProofRequest {
    pub pair_indexes: Vec<u32>,
    pub chain_type: String,
}

#[derive(Debug, Deserialize)]
pub struct SupraProofResponse {
    pub pair_indexes: Vec<u32>,
    pub proof_bytes: String,
}

impl SupraProofResponse {
    pub fn proof(self, required_pairs: &[u32]) -> Result<Bytes> {
        for required in required_pairs {
            if !self.pair_indexes.contains(required) {
                bail!("Supra response omitted requested pair {required}");
            }
        }
        if self.proof_bytes.is_empty() {
            bail!("Supra response did not contain proof bytes");
        }
        let stripped = self
            .proof_bytes
            .strip_prefix("0x")
            .unwrap_or(&self.proof_bytes);
        hex::decode(stripped)
            .map(Bytes::from)
            .with_context(|| "Supra returned invalid hex proof bytes")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lifecycle_decisions_cover_open_settle_cancel_and_wait() {
        assert_eq!(lifecycle_action(0, 0, 100, 0), LifecycleAction::Open);
        assert_eq!(lifecycle_action(7, 1, 100, 500), LifecycleAction::Wait);
        assert_eq!(lifecycle_action(7, 3, 500, 600), LifecycleAction::Settle);
        assert_eq!(lifecycle_action(7, 3, 601, 600), LifecycleAction::Cancel);
        assert_eq!(lifecycle_action(7, 4, 601, 600), LifecycleAction::Open);
        assert_eq!(lifecycle_action(7, 5, 601, 600), LifecycleAction::Open);
    }

    #[test]
    fn parses_supra_hex_proof_and_checks_pairs() {
        let response: SupraProofResponse =
            serde_json::from_str(r#"{"pair_indexes":[569,48],"proof_bytes":"0x0102a0ff"}"#)
                .unwrap();
        let proof = response.proof(&[569, 48]).unwrap();
        assert_eq!(proof.as_ref(), &[1, 2, 0xa0, 0xff]);
    }

    #[test]
    fn rejects_missing_pair_or_bad_proof() {
        let missing = SupraProofResponse {
            pair_indexes: vec![569],
            proof_bytes: "00".into(),
        };
        assert!(missing.proof(&[569, 48]).is_err());

        let bad = SupraProofResponse {
            pair_indexes: vec![569, 48],
            proof_bytes: "not-hex".into(),
        };
        assert!(bad.proof(&[569, 48]).is_err());
    }
}
