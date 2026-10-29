//! Errors returned by kepler-core.

use thiserror::Error;

#[derive(Debug, Error)]
pub enum KeplerError {
    #[error("not a resource name or #hash: {0}")]
    BadRef(String),
    #[error("unexpected bundle version {0:#x}")]
    BadBundleVersion(u32),
    #[error("bundle is truncated")]
    TruncatedBundle,
    #[error("bundle has unexpected data after the last entry")]
    TrailingData,
    #[error(transparent)]
    Io(#[from] std::io::Error),
}

pub type Result<T> = std::result::Result<T, KeplerError>;
