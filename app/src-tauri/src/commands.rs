//! Tauri commands: thin calls into obsidian-core. Each one that changes something returns a fresh
//! snapshot.

use std::path::PathBuf;
use std::sync::Mutex;

use obsidian_core::ObsidianError;
use serde::Serialize;
use tauri::State;

use crate::app_settings::AppSettings;
use crate::snapshot::{GateCache, Snapshot, snapshot as read_snapshot};

pub struct Ctx {
    pub data: PathBuf,
    pub gate: Mutex<GateCache>,
}

/// An error for the UI: `code` is the core error's name, which the UI turns into a catalog key
/// (`app.error.<code>`); `message` is the English text, shown when the catalog has no entry.
#[derive(Debug, Serialize)]
pub struct CmdError {
    pub code: String,
    pub message: String,
}

impl From<ObsidianError> for CmdError {
    fn from(e: ObsidianError) -> Self {
        let debug = format!("{e:?}");
        let code = debug.split(|c: char| !c.is_alphanumeric()).next().unwrap_or("Other").to_string();
        CmdError { code, message: e.to_string() }
    }
}

impl From<std::io::Error> for CmdError {
    fn from(e: std::io::Error) -> Self {
        CmdError { code: "Io".into(), message: e.to_string() }
    }
}

pub type CmdResult<T> = Result<T, CmdError>;

pub fn fresh(ctx: &Ctx) -> CmdResult<Snapshot> {
    let settings = AppSettings::load(&ctx.data);
    let mut gate = ctx.gate.lock().unwrap_or_else(|p| p.into_inner());
    Ok(read_snapshot(&ctx.data, &settings, &mut gate)?)
}

#[tauri::command]
pub fn snapshot(ctx: State<'_, Ctx>) -> CmdResult<Snapshot> {
    fresh(&ctx)
}

#[tauri::command]
pub fn get_app_settings(ctx: State<'_, Ctx>) -> AppSettings {
    AppSettings::load(&ctx.data)
}

#[tauri::command]
pub fn set_app_settings(ctx: State<'_, Ctx>, settings: AppSettings) -> CmdResult<AppSettings> {
    settings.save(&ctx.data)?;
    Ok(AppSettings::load(&ctx.data))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn errors_carry_the_variant_name() {
        let e: CmdError = ObsidianError::ProfileExists("A".into()).into();
        assert_eq!((e.code.as_str(), e.message.as_str()), ("ProfileExists", "a profile named A already exists"));
        let e: CmdError = ObsidianError::LastProfile.into();
        assert_eq!(e.code, "LastProfile");
    }
}
