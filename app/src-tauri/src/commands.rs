//! Tauri commands: thin calls into obsidian-core. Each one that changes something returns a fresh
//! snapshot.

use std::path::{Path, PathBuf};
use std::sync::Mutex;

use obsidian_core::images;
use obsidian_core::deploy::{ChangesWaiting, DeployOptions, changes_waiting, deploy as core_deploy, purge as core_purge};
use obsidian_core::game::{GameInstall, ensure_closed};
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

/// A new profile, empty or a copy of `copy_of`.
#[tauri::command]
pub async fn create_profile(ctx: State<'_, Ctx>, name: String, copy_of: Option<String>) -> CmdResult<Snapshot> {
    let _turn = ctx.turn();
    profiles::create(&ctx.data, &name, copy_of.as_deref())?;
    fresh(&ctx)
}

#[tauri::command]
pub async fn rename_profile(ctx: State<'_, Ctx>, from: String, to: String) -> CmdResult<Snapshot> {
    let _turn = ctx.turn();
    profiles::rename(&ctx.data, &from, &to)?;
    fresh(&ctx)
}

#[tauri::command]
pub async fn delete_profile(ctx: State<'_, Ctx>, name: String) -> CmdResult<Snapshot> {
    let _turn = ctx.turn();
    profiles::delete(&ctx.data, &name)?;
    fresh(&ctx)
}

/// Sets the player's image for a mod or a profile (`owner` "mod" or "profile"), or removes it.
#[tauri::command]
pub async fn set_image(ctx: State<'_, Ctx>, owner: String, key: String, path: Option<PathBuf>) -> CmdResult<Snapshot> {
    let _turn = ctx.turn();
    let owner = if owner == "profile" { images::Owner::Profile } else { images::Owner::Mod };
    images::set(&ctx.data, owner, &key, path.as_deref())?;
    fresh(&ctx)
}

/// Consent belongs to the active profile; it reaches the game through the settings file.
#[tauri::command]
pub async fn set_consent(ctx: State<'_, Ctx>, on: bool) -> CmdResult<Snapshot> {
    let _turn = ctx.turn();
    live_edit(&ctx, |_, p| {
        p.consent = on;
        Ok(())
    })
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Backup {
    /// `YYYYMMDD-HHMMSS`, maybe with `-2`.
    pub name: String,
    pub path: PathBuf,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SystemInfo {
    pub data_dir: PathBuf,
    pub backups: Vec<Backup>,
    /// The folder chosen in Settings; `None` when the game is found through Steam.
    pub chosen_game_dir: Option<PathBuf>,
}

#[tauri::command]
pub fn system_info(ctx: State<'_, Ctx>) -> SystemInfo {
    let backups = obsidian_core::backup::list_backups(&ctx.data.join("backups"))
        .into_iter()
        .map(|p| Backup { name: p.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default(), path: p })
        .collect();
    SystemInfo { data_dir: ctx.data.clone(), backups, chosen_game_dir: AppSettings::load(&ctx.data).game_dir }
}

/// Uses the game in `path`, or finds it through Steam again when `path` is null. A folder without
/// the game's `contents` folder is refused.
#[tauri::command]
pub async fn set_game_dir(ctx: State<'_, Ctx>, path: Option<PathBuf>) -> CmdResult<Snapshot> {
    let _turn = ctx.turn();
    if let Some(p) = &path
        && !p.join("contents").is_dir()
    {
        return Err(ObsidianError::GameNotFound(p.display().to_string()).into());
    }
    let mut s = AppSettings::load(&ctx.data);
    s.game_dir = path;
    s.save(&ctx.data)?;
    ctx.gate.lock().unwrap_or_else(|p| p.into_inner()).forget();
    fresh(&ctx)
}

/// Checks the game build again (the answer is kept per folder otherwise).
#[tauri::command]
pub async fn check_game(ctx: State<'_, Ctx>) -> CmdResult<Snapshot> {
    let _turn = ctx.turn();
    ctx.gate.lock().unwrap_or_else(|p| p.into_inner()).forget();
    fresh(&ctx)
}

/// Opens a folder the app knows in Explorer: the game, the data folder, or one save backup.
#[tauri::command]
pub fn open_folder(ctx: State<'_, Ctx>, app: tauri::AppHandle, path: PathBuf) -> CmdResult<()> {
    use tauri_plugin_opener::OpenerExt;
    let known = path.starts_with(&ctx.data) || find(&AppSettings::load(&ctx.data)).is_some_and(|g| path == g.root);
    if !known {
        return Err(CmdError { code: "Io".into(), message: format!("not a folder Obsidian opens: {}", path.display()) });
    }
    app.opener().open_path(path.to_string_lossy(), None::<&str>).map_err(|e| CmdError { code: "Io".into(), message: e.to_string() })
}

#[tauri::command]
pub async fn import_paths(ctx: State<'_, Ctx>, paths: Vec<PathBuf>) -> CmdResult<ImportBatch> {
    let _turn = ctx.turn();
    let game = find(&AppSettings::load(&ctx.data));
    let results = import_all(&ctx.data, game.as_ref(), &paths);
    Ok(ImportBatch { snapshot: fresh(&ctx)?, results })
}

/// Saves a change to options or keys and writes the settings file the loader reads, so the change
/// reaches the game at the next launch (also while the game runs).
fn live_edit(ctx: &Ctx, f: impl FnOnce(&Library, &mut Profile) -> obsidian_core::Result<()>) -> CmdResult<Snapshot> {
    let lib = Library::open(&ctx.data)?;
    let mut p = Profile::load(&ctx.data)?;
    p.sync(&lib)?;
    f(&lib, &mut p)?;
    p.save(&ctx.data)?;
    if let Some(g) = find(&AppSettings::load(&ctx.data)) {
        obsidian_core::edit::write_settings(&lib, &p, &g.saves_dir)?;
    }
    fresh(ctx)
}

/// `value` null resets the option to its default.
#[tauri::command]
pub async fn set_option(ctx: State<'_, Ctx>, id: String, option: String, value: Option<serde_json::Value>) -> CmdResult<Snapshot> {
    let _turn = ctx.turn();
    live_edit(&ctx, |lib, p| obsidian_core::edit::set_option(lib, p, &id, &option, value.as_ref()).map(|_| ()))
}

/// `key` null resets the keybind to the mod's default.
#[tauri::command]
pub async fn set_key(ctx: State<'_, Ctx>, id: String, keybind: String, key: Option<String>) -> CmdResult<Snapshot> {
    let _turn = ctx.turn();
    live_edit(&ctx, |lib, p| obsidian_core::edit::set_key(lib, p, &id, &keybind, key.as_deref()))
}

/// Deletes a mod from the library; it leaves every profile. Bundled mods are refused.
#[tauri::command]
pub async fn remove_mod(ctx: State<'_, Ctx>, id: String) -> CmdResult<Snapshot> {
    let _turn = ctx.turn();
    Library::open(&ctx.data)?.remove(&id)?;
    live_edit(&ctx, |_, _| Ok(()))
}

const STEAM_LAUNCH: &str = "steam://rungameid/394510";

fn game_of(ctx: &Ctx) -> CmdResult<GameInstall> {
    Ok(find(&AppSettings::load(&ctx.data)).ok_or_else(|| ObsidianError::GameNotFound(String::new()))?)
}

/// Deploys when changes are waiting, then calls `launch`. A failed deploy launches nothing.
pub fn play_with(data: &Path, game: Option<&GameInstall>, launch: impl FnOnce() -> CmdResult<()>) -> CmdResult<()> {
    let game = game.ok_or_else(|| ObsidianError::GameNotFound(String::new()))?;
    ensure_closed()?;
    let lib = Library::open(data)?;
    let mut p = Profile::load(data)?;
    p.sync(&lib)?;
    if changes_waiting(&lib, &p, data)? == ChangesWaiting::Waiting {
        core_deploy(game, data, &DeployOptions::default())?;
    }
    launch()
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DeployDone {
    pub snapshot: Snapshot,
    /// Mods written into the game.
    pub mods: usize,
    pub backup: bool,
}

#[tauri::command]
pub async fn deploy(ctx: State<'_, Ctx>) -> CmdResult<DeployDone> {
    let _turn = ctx.turn();
    let game = game_of(&ctx)?;
    ensure_closed()?;
    let r = core_deploy(&game, &ctx.data, &DeployOptions::default())?;
    let snapshot = fresh(&ctx)?;
    Ok(DeployDone { mods: if r.patches.is_empty() { 0 } else { snapshot.mods.iter().filter(|m| m.on).count() }, backup: r.backup.is_some(), snapshot })
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PurgeDone {
    pub snapshot: Snapshot,
    pub removed: usize,
    /// Files another tool changed after Obsidian wrote them; left in place.
    pub kept: usize,
}

#[tauri::command]
pub async fn purge(ctx: State<'_, Ctx>) -> CmdResult<PurgeDone> {
    let _turn = ctx.turn();
    let game = game_of(&ctx)?;
    ensure_closed()?;
    let r = core_purge(&game, &ctx.data)?;
    Ok(PurgeDone { snapshot: fresh(&ctx)?, removed: r.removed.len(), kept: r.kept_changed.len() })
}

#[tauri::command]
pub async fn play(ctx: State<'_, Ctx>, app: tauri::AppHandle) -> CmdResult<Snapshot> {
    use tauri_plugin_opener::OpenerExt;
    let _turn = ctx.turn();
    let game = find(&AppSettings::load(&ctx.data));
    play_with(&ctx.data, game.as_ref(), || {
        app.opener().open_url(STEAM_LAUNCH, None::<&str>).map_err(|e| CmdError { code: "Launch".into(), message: e.to_string() })
    })?;
    fresh(&ctx)
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

    #[test]
    fn play_does_not_launch_after_a_failed_deploy() {
        let t = tempfile::tempdir().unwrap();
        let data = t.path().join("data");
        std::fs::create_dir_all(t.path().join("game/contents")).unwrap();
        let game = obsidian_core::game::find_game(Some(&t.path().join("game"))).unwrap();
        let launched = std::cell::Cell::new(false);
        let launch = || {
            launched.set(true);
            Ok(())
        };

        // Nothing on and nothing deployed: no deploy needed, so Play launches.
        play_with(&data, Some(&game), launch).unwrap();
        assert!(launched.replace(false));

        // A mod switched on needs a deploy, which fails on this fake game (no known build).
        mod_folder(&t.path().join("m"), "1.0.0");
        import_all(&data, Some(&game), &[t.path().join("m")]);
        with_profile(&data, |p| p.set_enabled("a.drop", true)).unwrap();
        let e = play_with(&data, Some(&game), launch).unwrap_err();
        assert!(!launched.get(), "nothing launches after a failed deploy");
        assert_ne!(e.code, "", "{e:?}");
        assert_eq!(play_with(&data, None, launch).unwrap_err().code, "GameNotFound");
    }
}
