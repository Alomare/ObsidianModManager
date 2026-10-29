//! Errors returned by kepler-core.

use thiserror::Error;

#[derive(Debug, Error)]
pub enum KeplerError {
    #[error("not a resource name or #hash: {0}")]
    BadRef(String),
}

pub type Result<T> = std::result::Result<T, KeplerError>;
