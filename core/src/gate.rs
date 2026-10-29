//! Build gate: Kepler deploys only to game builds whose files it knows.

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct GateReport {
    pub build: Option<String>,
    pub mismatches: Vec<String>,
}
