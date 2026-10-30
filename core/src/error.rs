//! Errors returned by obsidian-core.

use thiserror::Error;

#[derive(Debug, Error)]
pub enum ObsidianError {
    #[error("not a resource name or #hash: {0}")]
    BadRef(String),
    #[error("unexpected bundle version {0:#x}")]
    BadBundleVersion(u32),
    #[error("bundle is truncated")]
    TruncatedBundle,
    #[error("bundle has unexpected data after the last entry")]
    TrailingData,
    #[error("invalid Lua bytecode: {0}")]
    InvalidBytecode(String),
    #[error("HELLDIVERS was not found in these Steam libraries: {0}")]
    GameNotFound(String),
    #[error("obsidian.json, {field}: {reason}")]
    BadManifest { field: String, reason: String },
    #[error("archive type not supported yet (use a folder or a .zip): {0}")]
    UnsupportedArchive(String),
    #[error("nothing to import: no obsidian.json and no game bundle files in {0}")]
    NothingToImport(String),
    #[error("{0} is not a bundle of this game")]
    UnknownBundle(String),
    #[error("bundle {bundle}, entry {entry}: resources with several languages or streamed data cannot be imported yet")]
    UnsupportedLegacyEntry { bundle: String, entry: String },
    #[error("mod {0} is in the profile but not in the library")]
    ModMissing(String),
    #[error("the LuaJIT 2.0 compiler was not found (looked in {0}); run tools/build-luajit.cmd or set OBSIDIAN_LUAJIT")]
    CompilerUnavailable(String),
    #[error("Lua error in {chunk}: {message}")]
    CompileFailed { chunk: String, message: String },
    #[error("option {option}: {value} is not an allowed value")]
    BadOptionValue { option: String, value: String },
    #[error("mod {mod_id}: {name} belongs to Obsidian Loader; use \"entry\" to run a script at boot")]
    ReservedResource { mod_id: String, name: String },
    #[error("Obsidian Loader files were not found (looked in {0})")]
    LoaderMissing(String),
    #[error("{0} comes with Obsidian and can't be removed; turn it off instead")]
    BundledMod(String),
    #[error("{mod_id} has no keybind {keybind}")]
    UnknownKeybind { mod_id: String, keybind: String },
    #[error("{0:?} can't be a profile name: use 1 to 40 characters, none of \\ / : * ? \" < > |")]
    ProfileName(String),
    #[error("a profile named {0} already exists")]
    ProfileExists(String),
    #[error("there is no profile named {0}")]
    ProfileMissing(String),
    #[error("the last profile can't be deleted")]
    LastProfile,
    #[error("mod {mod_id} has no option {option}")]
    UnknownOption { mod_id: String, option: String },
    #[error("mod {mod_id}: every resource needs a bundle in this version")]
    BundleRequired { mod_id: String },
    #[error("game build not recognised: {}", .0.mismatches.join(", "))]
    UnsupportedBuild(crate::gate::GateReport),
    #[error("bundle {bundle}: patch_{missing} is missing below another tool's patches, so the game would skip them")]
    ForeignPatchGap { bundle: String, missing: u32 },
    #[error("close the game first")]
    GameRunning,
    #[error("deploy failed and was undone: {0}")]
    DeployFailed(String),
    #[error(transparent)]
    Json(#[from] serde_json::Error),
    #[error(transparent)]
    Io(#[from] std::io::Error),
}

pub type Result<T> = std::result::Result<T, ObsidianError>;
