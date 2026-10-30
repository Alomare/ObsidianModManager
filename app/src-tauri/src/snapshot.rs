//! Everything the UI shows, read from core in one go. Every command returns a fresh snapshot, so
//! the UI never keeps its own copy of the library or the profile.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use obsidian_core::compose::compose;
use obsidian_core::deploy::{ChangesWaiting, changes_waiting, status};
use obsidian_core::game::{GameInstall, find_game, is_running};
use obsidian_core::gate::{KNOWN_BUILDS, check_build};
use obsidian_core::hash::{display_name, display_text};
use obsidian_core::library::{ImportInfo, Library, Profile};
use obsidian_core::manifest::{Localized, Manifest, Scope};
use obsidian_core::options::{OptionKind, effective_values, parse_keybinds};
use obsidian_core::{Result, loader, profiles};
use serde::Serialize;
use serde_json::Value;

use crate::app_settings::AppSettings;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum GameState {
    Supported,
    Unknown,
    Running,
    NotFound,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct OptionRow {
    pub id: String,
    /// toggle, number, choice, key or color.
    pub kind: &'static str,
    pub label: Localized,
    pub description: Localized,
    pub default: Value,
    pub value: Value,
    pub min: Option<f64>,
    pub max: Option<f64>,
    pub step: Option<f64>,
    pub choices: Vec<String>,
    /// A change needs a deploy (it picks resources, or it is part of a session mod's mod set).
    pub deploy: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct KeyRow {
    pub id: String,
    pub label: Localized,
    pub default: String,
    /// The key set by the player, if any.
    pub key: Option<String>,
    /// Other enabled mods using the same key.
    pub clash: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ModRow {
    pub id: String,
    pub name: Localized,
    pub description: Localized,
    pub authors: Vec<String>,
    /// `None` for an imported legacy mod, which has no version of its own.
    pub version: Option<String>,
    pub scope: &'static str,
    pub bundled: bool,
    pub on: bool,
    pub options: Vec<OptionRow>,
    pub keybinds: Vec<KeyRow>,
    /// The game resources the mod changes, as `bundle/name`.
    pub files: Vec<String>,
    /// Enabled mods that change a resource this mod changes too.
    pub overlaps: Vec<String>,
    pub import: Option<ImportInfo>,
    pub source: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ConflictRow {
    pub resource: String,
    /// In load order; the last one wins.
    pub mods: Vec<String>,
    pub winner: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProfileRow {
    pub name: String,
    /// Mods switched on, counting only those in the library.
    pub on: usize,
    pub consent: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Snapshot {
    /// In load order.
    pub mods: Vec<ModRow>,
    pub profile: String,
    pub profiles: Vec<String>,
    pub profile_rows: Vec<ProfileRow>,
    pub consent: bool,
    pub conflicts: Vec<ConflictRow>,
    pub changes: ChangesWaiting,
    pub game: GameState,
    pub game_dir: Option<PathBuf>,
    pub crash_culprit: Option<String>,
    pub portable: bool,
    pub version: &'static str,
}

/// Whether the game build at a folder is supported. Hashing the game files takes a moment, so the
/// answer is kept per folder until `forget` (Settings, "Check again").
#[derive(Default)]
pub struct GateCache(Option<(PathBuf, bool)>);

impl GateCache {
    fn supported(&mut self, root: &Path) -> bool {
        if let Some((r, ok)) = &self.0
            && r == root
        {
            return *ok;
        }
        let ok = check_build(root, KNOWN_BUILDS).is_ok_and(|g| g.build.is_some());
        self.0 = Some((root.to_path_buf(), ok));
        ok
    }
    pub fn forget(&mut self) {
        self.0 = None;
    }
}

/// The game in the folder chosen in Settings, else the one Steam knows. A chosen folder counts
/// only when it holds the game's `contents` folder.
pub fn find(settings: &AppSettings) -> Option<GameInstall> {
    find_game(settings.game_dir.as_deref()).ok().filter(|g| g.contents().is_dir())
}

/// The path as Windows shows it: Steam stores library paths with `/` and a lowercase drive letter.
fn tidy(p: &Path) -> PathBuf {
    if !cfg!(windows) {
        return p.to_path_buf();
    }
    let s = p.to_string_lossy().replace('/', "\\");
    let mut c = s.chars();
    match (c.next(), s.as_bytes().get(1)) {
        (Some(d), Some(b':')) => PathBuf::from(d.to_ascii_uppercase().to_string() + c.as_str()),
        _ => PathBuf::from(s),
    }
}

/// A game file as people read it: its name, then the last part of its bundle's name, as in
/// `lua/settings/status_settings (boot)`. Unknown names stay `#hash`.
fn resource_label(bundle: &str, name: &str) -> String {
    let b = display_text(bundle);
    format!("{name} ({})", b.rsplit('/').next().unwrap_or(&b))
}

fn localized(v: Option<&Value>) -> Localized {
    v.and_then(|v| serde_json::from_value(v.clone()).ok()).unwrap_or_default()
}

/// The option and keybind rows of one mod, with the player's values from the profile.
fn option_rows(m: &Manifest, profile: &Profile) -> Result<Vec<OptionRow>> {
    let specs = m.option_specs()?;
    let values = effective_values(&specs, profile.options.get(&m.id));
    Ok(specs
        .iter()
        .zip(&m.options)
        .map(|(s, raw)| {
            let (min, max, step) = match &s.kind {
                OptionKind::Number { min, max, step } => (*min, *max, *step),
                _ => (None, None, None),
            };
            let deploy = m.resources.iter().any(|r| r.when.contains_key(&s.id)) || (m.scope == Scope::Session && !s.client) || m.entry.is_none();
            OptionRow {
                id: s.id.clone(),
                kind: s.kind.name(),
                label: localized(raw.get("label")),
                description: localized(raw.get("description")),
                default: s.default.clone(),
                value: values[&s.id].clone(),
                min,
                max,
                step,
                choices: if let OptionKind::Choice(c) = &s.kind { c.clone() } else { Vec::new() },
                deploy,
            }
        })
        .collect())
}

pub fn snapshot(data: &Path, settings: &AppSettings, gate: &mut GateCache) -> Result<Snapshot> {
    let lib = Library::open(data)?;
    if let Some(dir) = loader::find_bundled_dir() {
        lib.install_bundled(&dir)?;
    }
    let mut profile = Profile::load(data)?;
    profile.sync(&lib)?;
    profile.save(data)?;
    let manifests: BTreeMap<String, Manifest> = lib.list()?.into_iter().map(|m| (m.id.clone(), m)).collect();
    let comp = compose(&lib, &profile)?;

    let conflicts: Vec<ConflictRow> = comp
        .conflicts
        .iter()
        .map(|c| {
            let mut mods = c.losers.clone();
            mods.push(c.winner.clone());
            ConflictRow { resource: resource_label(&c.bundle, &display_name(c.name_hash)), mods, winner: c.winner.clone() }
        })
        .collect();

    // Effective key per enabled mod and keybind, to find clashes.
    let mut used: BTreeMap<String, Vec<String>> = BTreeMap::new();
    for e in profile.mods.iter().filter(|e| e.enabled) {
        if let Some(m) = manifests.get(&e.id) {
            for k in parse_keybinds(&m.keybinds)? {
                let key = profile.keys.get(&m.id).and_then(|s| s.get(&k.id)).cloned().unwrap_or(k.default);
                used.entry(key).or_default().push(m.id.clone());
            }
        }
    }

    let mut mods = Vec::new();
    for e in &profile.mods {
        let Some(m) = manifests.get(&e.id) else { continue };
        let keybinds = parse_keybinds(&m.keybinds)?
            .into_iter()
            .zip(&m.keybinds)
            .map(|(k, raw)| {
                let key = profile.keys.get(&m.id).and_then(|s| s.get(&k.id)).cloned();
                let effective = key.clone().unwrap_or_else(|| k.default.clone());
                let clash = if e.enabled { used.get(&effective).into_iter().flatten().filter(|id| **id != m.id).cloned().collect() } else { Vec::new() };
                KeyRow { id: k.id, label: localized(raw.get("label")), default: k.default, key, clash }
            })
            .collect();
        let mut overlaps: Vec<String> = conflicts.iter().filter(|c| c.mods.contains(&m.id)).flat_map(|c| c.mods.iter().filter(|id| **id != m.id).cloned()).collect();
        overlaps.sort();
        overlaps.dedup();
        // An imported legacy mod has no version of its own unless its Nexus file name gave one.
        let unversioned = m.extra.get("legacy") == Some(&Value::Bool(true)) && m.version == semver::Version::new(0, 0, 0);
        mods.push(ModRow {
            id: m.id.clone(),
            name: m.name.clone(),
            description: m.description.clone().unwrap_or_default(),
            authors: m.authors.clone(),
            version: if unversioned { None } else { Some(m.version.to_string()) },
            scope: if m.scope == Scope::Client { "client" } else { "session" },
            bundled: m.is_bundled(),
            on: e.enabled,
            options: option_rows(m, &profile)?,
            keybinds,
            files: m.resources.iter().map(|r| resource_label(r.bundle.as_deref().unwrap_or_default(), &display_text(&r.name_text))).collect(),
            overlaps,
            import: lib.import_info(&m.id),
            source: m.extra.get("source").and_then(Value::as_str).map(str::to_string),
        });
    }

    let game_install = find(settings);
    let game = match &game_install {
        None => GameState::NotFound,
        Some(_) if is_running() => GameState::Running,
        Some(g) if gate.supported(&g.root) => GameState::Supported,
        Some(_) => GameState::Unknown,
    };
    let crash_culprit = game_install.as_ref().and_then(|g| status(g, data, KNOWN_BUILDS).ok()).and_then(|s| s.crash_culprit);
    let portable = std::env::current_exe().ok().and_then(|e| e.parent().map(|d| d.join("portable.txt").is_file())).unwrap_or(false);

    Ok(Snapshot {
        mods,
        profile: profiles::active(data)?,
        profile_rows: profiles::list(data)?
            .into_iter()
            .map(|name| {
                let p = Profile::load_named(data, &name).unwrap_or_default();
                let on = p.mods.iter().filter(|e| e.enabled && manifests.contains_key(&e.id)).count();
                ProfileRow { name, on, consent: p.consent }
            })
            .collect(),
        profiles: profiles::list(data)?,
        consent: profile.consent,
        conflicts,
        changes: changes_waiting(&lib, &profile, data).unwrap_or(ChangesWaiting::Waiting),
        game,
        game_dir: game_install.map(|g| tidy(&g.root)),
        crash_culprit,
        portable,
        version: env!("CARGO_PKG_VERSION"),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn put(dir: &Path, name: &str, text: &str) {
        std::fs::create_dir_all(dir).unwrap();
        std::fs::write(dir.join(name), text).unwrap();
    }

    #[test]
    fn snapshot_lists_mods_with_versions_options_and_conflicts() {
        let t = tempfile::tempdir().unwrap();
        let data = t.path().join("data");
        let lib = Library::open(&data).unwrap();
        for (id, legacy, version) in [("a.one", false, "1.2.0"), ("legacy.two", true, "0.0.0")] {
            let d = t.path().join(id);
            let extra = if legacy { r#","legacy":true"# } else { "" };
            put(&d, "obsidian.json", &format!(
                r##"{{"obsidian":1,"id":"{id}","version":"{version}","name":{{"en":"{id}"}},"scope":"client","entry":"main.lua"{extra},
                   "options":[{{"id":"fast","type":"toggle","default":false,"label":{{"en":"Fast"}}}}],
                   "keybinds":[{{"id":"toggle","default":"f8"}}],
                   "resources":[{{"type":"#0000000000000001","name":"#00000000000000f0","bundle":"00000000000000aa","data":"r.bin"}}]}}"##
            ));
            put(&d, "main.lua", "return true\n");
            put(&d, "r.bin", id);
            lib.install(&d).unwrap();
        }
        let mut p = Profile::load(&data).unwrap();
        p.sync(&lib).unwrap();
        p.set_order(&["legacy.two".into(), "a.one".into()]);
        p.set_enabled("a.one", true).unwrap();
        p.set_enabled("legacy.two", true).unwrap();
        p.options.entry("a.one".into()).or_default().insert("fast".into(), Value::Bool(true));
        p.save(&data).unwrap();
        let settings = AppSettings { game_dir: Some(t.path().join("no game here")), ..Default::default() };
        let s = snapshot(&data, &settings, &mut GateCache::default()).unwrap();

        let a = s.mods.iter().find(|m| m.id == "a.one").unwrap();
        let two = s.mods.iter().find(|m| m.id == "legacy.two").unwrap();
        assert_eq!(a.version.as_deref(), Some("1.2.0"));
        assert_eq!(two.version, None, "imports show no version");
        assert_eq!((a.options[0].value.clone(), a.options[0].label["en"].as_str(), a.options[0].deploy), (Value::Bool(true), "Fast", false));
        assert_eq!(a.keybinds[0].clash, vec!["legacy.two"], "both use f8");
        assert_eq!(a.overlaps, vec!["legacy.two"]);
        assert_eq!(s.conflicts.len(), 1);
        assert_eq!((s.conflicts[0].mods.clone(), s.conflicts[0].winner.as_str()), (vec!["legacy.two".to_string(), "a.one".to_string()], "a.one"));
        let order: Vec<&str> = s.mods.iter().map(|m| m.id.as_str()).filter(|id| *id != "obsidian.qol").collect();
        assert_eq!(order, ["legacy.two", "a.one"]);
        assert_eq!((s.game, s.profile.as_str(), s.changes), (GameState::NotFound, "Default", ChangesWaiting::Waiting));
    }
}
