//! Tauri commands: thin calls into obsidian-core. Each one that changes something returns a fresh
//! snapshot.

use std::path::{Path, PathBuf};
use std::sync::Mutex;

use obsidian_core::game::GameInstall;
use obsidian_core::import::import_path;
use obsidian_core::library::{InstallOutcome, Library, Profile};
use obsidian_core::manifest::{Localized, load_manifest};
use obsidian_core::{ObsidianError, profiles};
use serde::Serialize;
use tauri::State;

use crate::app_settings::AppSettings;
use crate::snapshot::{GateCache, Snapshot, find, snapshot as read_snapshot};

pub struct Ctx {
    pub data: PathBuf,
    pub gate: Mutex<GateCache>,
    /// Held by each command that reads or changes the library or profile. The commands are async,
    /// so they run off the window's thread and the window stays responsive; this keeps them in turn.
    pub work: Mutex<()>,
}

impl Ctx {
    fn turn(&self) -> std::sync::MutexGuard<'_, ()> {
        self.work.lock().unwrap_or_else(|p| p.into_inner())
    }
}

/// An error for the UI: `code` is the core error's name, which the UI turns into a catalog key
/// (`app.error.<code>`); `message` is the English text, shown when the catalog has no entry.
#[derive(Debug, Clone, Serialize)]
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

/// Loads the active profile in step with the library, lets `f` change it, and saves it.
fn with_profile(data: &Path, f: impl FnOnce(&mut Profile) -> obsidian_core::Result<()>) -> CmdResult<()> {
    let lib = Library::open(data)?;
    let mut p = Profile::load(data)?;
    p.sync(&lib)?;
    f(&mut p)?;
    p.save(data)?;
    Ok(())
}

/// The outcome of one dropped or picked path. The UI writes the notice from it.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportResult {
    /// The file or folder name.
    pub file: String,
    pub ok: bool,
    /// installed, updated or reinstalled.
    pub kind: &'static str,
    pub name: Localized,
    /// `None` for an imported legacy mod, which has no version of its own.
    pub version: Option<String>,
    pub old_version: Option<String>,
    pub error: Option<CmdError>,
}

#[derive(Debug, Serialize)]
pub struct ImportBatch {
    pub snapshot: Snapshot,
    pub results: Vec<ImportResult>,
}

fn import_one(data: &Path, game: Option<&GameInstall>, path: &Path) -> obsidian_core::Result<ImportResult> {
    let game = game.ok_or_else(|| ObsidianError::GameNotFound(String::new()))?;
    let lib = Library::open(data)?;
    let r = import_path(path, game, &lib)?;
    let m = load_manifest(&lib.mod_dir(&r.id))?;
    let versioned = !r.legacy || r.version != semver::Version::new(0, 0, 0);
    let version = versioned.then(|| r.version.to_string());
    let (kind, old_version) = match r.outcome {
        InstallOutcome::Added => ("installed", None),
        InstallOutcome::Replaced { old_version } if old_version == r.version => ("reinstalled", None),
        InstallOutcome::Replaced { old_version } => ("updated", versioned.then(|| old_version.to_string())),
    };
    Ok(ImportResult { file: String::new(), ok: true, kind, name: m.name, version, old_version, error: None })
}

/// Imports each path in turn; one failure doesn't stop the rest. New mods join the active profile
/// switched off.
pub fn import_all(data: &Path, game: Option<&GameInstall>, paths: &[PathBuf]) -> Vec<ImportResult> {
    let results: Vec<ImportResult> = paths
        .iter()
        .map(|p| {
            let file = p.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_else(|| p.display().to_string());
            match import_one(data, game, p) {
                Ok(r) => ImportResult { file, ..r },
                Err(e) => ImportResult { file, ok: false, kind: "", name: Localized::new(), version: None, old_version: None, error: Some(e.into()) },
            }
        })
        .collect();
    if results.iter().any(|r| r.ok) {
        let _ = with_profile(data, |_| Ok(()));
    }
    results
}

#[tauri::command]
pub async fn snapshot(ctx: State<'_, Ctx>) -> CmdResult<Snapshot> {
    let _turn = ctx.turn();
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

#[tauri::command]
pub async fn set_enabled(ctx: State<'_, Ctx>, id: String, on: bool) -> CmdResult<Snapshot> {
    let _turn = ctx.turn();
    with_profile(&ctx.data, |p| p.set_enabled(&id, on))?;
    fresh(&ctx)
}

#[tauri::command]
pub async fn set_order(ctx: State<'_, Ctx>, ids: Vec<String>) -> CmdResult<Snapshot> {
    let _turn = ctx.turn();
    with_profile(&ctx.data, |p| {
        p.set_order(&ids);
        Ok(())
    })?;
    fresh(&ctx)
}

#[tauri::command]
pub async fn use_profile(ctx: State<'_, Ctx>, name: String) -> CmdResult<Snapshot> {
    let _turn = ctx.turn();
    profiles::use_profile(&ctx.data, &name)?;
    fresh(&ctx)
}

#[tauri::command]
pub async fn import_paths(ctx: State<'_, Ctx>, paths: Vec<PathBuf>) -> CmdResult<ImportBatch> {
    let _turn = ctx.turn();
    let game = find(&AppSettings::load(&ctx.data));
    let results = import_all(&ctx.data, game.as_ref(), &paths);
    Ok(ImportBatch { snapshot: fresh(&ctx)?, results })
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

    fn mod_folder(dir: &std::path::Path, version: &str) {
        std::fs::create_dir_all(dir).unwrap();
        std::fs::write(dir.join("obsidian.json"), format!(r#"{{"obsidian":1,"id":"a.drop","version":"{version}","name":{{"en":"Drop"}},"scope":"client","entry":"main.lua"}}"#)).unwrap();
        std::fs::write(dir.join("main.lua"), "return true
").unwrap();
    }

    #[test]
    fn import_paths_reports_a_bad_drop() {
        let t = tempfile::tempdir().unwrap();
        let data = t.path().join("data");
        std::fs::create_dir_all(t.path().join("game/contents")).unwrap();
        let game = obsidian_core::game::find_game(Some(&t.path().join("game"))).unwrap();
        let txt = t.path().join("notes.txt");
        std::fs::write(&txt, "hello").unwrap();
        let empty = t.path().join("empty");
        std::fs::create_dir_all(&empty).unwrap();
        let before = Library::open(&data).unwrap().list().unwrap().len();

        let r = import_all(&data, Some(&game), &[txt.clone(), empty]);
        let codes: Vec<&str> = r.iter().map(|r| r.error.as_ref().map_or("", |e| e.code.as_str())).collect();
        assert_eq!(codes, ["UnsupportedArchive", "NothingToImport"]);
        assert!(r.iter().all(|r| !r.ok));
        assert_eq!((r[0].file.as_str(), r[1].file.as_str()), ("notes.txt", "empty"));
        assert_eq!(Library::open(&data).unwrap().list().unwrap().len(), before, "the library is unchanged");
        assert_eq!(import_all(&data, None, &[txt])[0].error.as_ref().unwrap().code, "GameNotFound");
    }

    #[test]
    fn import_paths_says_installed_updated_or_reinstalled() {
        let t = tempfile::tempdir().unwrap();
        let data = t.path().join("data");
        std::fs::create_dir_all(t.path().join("game/contents")).unwrap();
        let game = obsidian_core::game::find_game(Some(&t.path().join("game"))).unwrap();
        let (v1, v2) = (t.path().join("v1"), t.path().join("v2"));
        mod_folder(&v1, "1.0.0");
        mod_folder(&v2, "1.1.0");
        let kinds = |p: &std::path::Path| {
            let r = import_all(&data, Some(&game), &[p.to_path_buf()]).remove(0);
            (r.ok, r.kind, r.name["en"].clone(), r.version, r.old_version)
        };
        assert_eq!(kinds(&v1), (true, "installed", "Drop".into(), Some("1.0.0".into()), None));
        assert_eq!(kinds(&v2), (true, "updated", "Drop".into(), Some("1.1.0".into()), Some("1.0.0".into())));
        assert_eq!(kinds(&v2).1, "reinstalled");
        let profile = Profile::load(&data).unwrap();
        assert!(profile.mods.iter().any(|m| m.id == "a.drop" && !m.enabled), "new mods join the profile switched off");
    }
}
