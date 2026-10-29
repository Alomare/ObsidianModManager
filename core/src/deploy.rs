//! Deploy writes Kepler's patches next to the game's bundles; purge removes exactly those.

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::backup::backup_saves;
use crate::bundle::{self, Bundle, Entry, Variant};
use crate::compose::{Conflict, compose};
use crate::game::GameInstall;
use crate::gate::{GateReport, KNOWN_BUILDS, KnownBuild, check_build, sha256_file};
use crate::library::{Library, Profile};
use crate::{KeplerError, Result};

pub const STATE: &str = "deploy-state.json";
const TMP: &str = "kepler-tmp";

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DeployedFile {
    pub path: PathBuf,
    pub sha256: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DeployState {
    pub build: String,
    pub files: Vec<DeployedFile>,
    pub mods: Vec<String>,
    pub time: String,
}

pub struct DeployOptions<'a> {
    pub known_builds: &'a [KnownBuild],
    pub keep_backups: usize,
}

impl Default for DeployOptions<'static> {
    fn default() -> Self {
        DeployOptions { known_builds: KNOWN_BUILDS, keep_backups: 10 }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct DeployReport {
    pub patches: Vec<PathBuf>,
    pub conflicts: Vec<Conflict>,
    pub foreign: Vec<PathBuf>,
    pub backup: Option<PathBuf>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct PurgeReport {
    pub removed: Vec<PathBuf>,
    pub kept_changed: Vec<PathBuf>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Status {
    pub gate: GateReport,
    pub deployed: Option<DeployState>,
    pub foreign: Vec<PathBuf>,
}

/// `(bundle, N)` for a file named `<16 hex>.patch_<N>`.
fn patch_name(name: &str) -> Option<(String, u32)> {
    // NTFS ignores case, so `...AA.patch_0` and `...aa.patch_0` are the same file.
    let lower = name.to_ascii_lowercase();
    let (bundle, n) = lower.split_once(".patch_")?;
    let hex = bundle.len() == 16 && bundle.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b));
    if !hex || n.is_empty() || !n.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    Some((bundle.to_string(), n.parse().ok()?))
}

/// Every regular `*.patch_N` file in `contents` that the recorded state did not write.
fn foreign_patches(contents: &Path, state: Option<&DeployState>) -> Result<Vec<(String, u32, PathBuf)>> {
    let ours: Vec<&PathBuf> = state.map(|s| s.files.iter().map(|f| &f.path).collect()).unwrap_or_default();
    let mut out = Vec::new();
    if !contents.is_dir() {
        return Ok(out);
    }
    for e in std::fs::read_dir(contents)? {
        let e = e?;
        let p = e.path();
        if !e.file_type()?.is_file() || ours.contains(&&p) {
            continue;
        }
        if let Some((bundle, n)) = patch_name(&e.file_name().to_string_lossy()) {
            out.push((bundle, n, p));
        }
    }
    out.sort();
    Ok(out)
}

fn remove_all<'a>(paths: impl Iterator<Item = &'a PathBuf>) {
    for p in paths {
        let _ = std::fs::remove_file(p);
    }
}

fn load_state(data_dir: &Path) -> Result<Option<DeployState>> {
    match std::fs::read_to_string(data_dir.join(STATE)) {
        Ok(t) => Ok(Some(serde_json::from_str(&t)?)),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(e.into()),
    }
}

pub fn deploy(game: &GameInstall, data_dir: &Path, opts: &DeployOptions) -> Result<DeployReport> {
    let contents = game.contents();
    let gate = check_build(&game.root, opts.known_builds)?;
    let build = gate.build.clone().ok_or_else(|| KeplerError::UnsupportedBuild(gate.clone()))?;
    for e in std::fs::read_dir(&contents)? {
        let p = e?.path();
        if p.is_file() && p.extension().is_some_and(|x| x == TMP) {
            std::fs::remove_file(p)?;
        }
    }
    let previous = load_state(data_dir)?;
    let lib = Library::open(data_dir)?;
    let mut profile = Profile::load(data_dir)?;
    profile.sync(&lib)?;
    let comp = compose(&lib, &profile)?;

    // Plan every slot before changing anything, so a refusal leaves the previous deploy in place.
    let foreign = foreign_patches(&contents, previous.as_ref())?;
    let mut plan = Vec::new();
    for bundle in comp.bundles.keys() {
        let base = contents.join(bundle);
        if !base.is_file() {
            return Err(KeplerError::UnknownBundle(bundle.clone()));
        }
        let taken: Vec<u32> = foreign.iter().filter(|(b, _, _)| b == bundle).map(|(_, n, _)| *n).collect();
        let mut slot = 0;
        while taken.contains(&slot) {
            slot += 1;
        }
        if taken.iter().any(|&n| n > slot) {
            return Err(KeplerError::ForeignPatchGap { bundle: bundle.clone(), missing: slot });
        }
        plan.push((bundle, base, contents.join(format!("{bundle}.patch_{slot}"))));
    }
    let backup = backup_saves(&game.saves_dir, &data_dir.join("backups"), opts.keep_backups)?;

    let mut temps = Vec::new();
    for (bundle, base, target) in &plan {
        let mut b = Bundle { props: bundle::read_file(base)?.props, entries: Vec::new() };
        for p in &comp.bundles[*bundle] {
            let v = Variant { lang: 0, data: p.data.clone(), stream_size: 0 };
            b.entries.push(Entry { type_hash: p.type_hash, name_hash: p.name_hash, flags: p.flags, variants: vec![v] });
        }
        b.sort_entries();
        let tmp = target.with_extension(format!("{}.{TMP}", target.extension().unwrap().to_string_lossy()));
        temps.push((tmp.clone(), target.clone()));
        if let Err(e) = bundle::write_file(&tmp, &b) {
            remove_all(temps.iter().map(|(t, _)| t));
            return Err(e);
        }
    }
    let files = temps
        .iter()
        .map(|(tmp, p)| Ok(DeployedFile { path: p.clone(), sha256: sha256_file(tmp)? }))
        .collect::<Result<Vec<_>>>()?;
    let mods = profile.mods.iter().filter(|m| m.enabled).map(|m| m.id.clone()).collect();
    let state = DeployState { build, files, mods, time: chrono::Local::now().to_rfc3339() };

    // The old patches go only now, when the new set is ready. The state is recorded before
    // any rename, so a crash midway still leaves every live patch listed for purge.
    purge(game, data_dir)?;
    std::fs::create_dir_all(data_dir)?;
    let state_tmp = data_dir.join(format!("{STATE}.{TMP}"));
    std::fs::write(&state_tmp, serde_json::to_string_pretty(&state)? + "\n")?;
    std::fs::rename(&state_tmp, data_dir.join(STATE))?;
    let mut done: Vec<&PathBuf> = Vec::new();
    for (tmp, target) in &temps {
        let occupied = target.symlink_metadata().is_ok();
        let renamed = if occupied { Err(std::io::Error::other("another file already has this name")) } else { std::fs::rename(tmp, target) };
        if let Err(e) = renamed {
            remove_all(done.iter().copied());
            remove_all(temps.iter().map(|(t, _)| t));
            let _ = std::fs::remove_file(data_dir.join(STATE));
            return Err(KeplerError::DeployFailed(format!("{}: {e}", target.display())));
        }
        done.push(target);
    }
    let foreign_paths = foreign.into_iter().filter(|(b, _, _)| comp.bundles.contains_key(b)).map(|(_, _, p)| p).collect();
    Ok(DeployReport { patches: state.files.into_iter().map(|f| f.path).collect(), conflicts: comp.conflicts, foreign: foreign_paths, backup })
}

/// Removes the patches the last deploy recorded. Never consults the build gate.
pub fn purge(_game: &GameInstall, data_dir: &Path) -> Result<PurgeReport> {
    let mut report = PurgeReport { removed: Vec::new(), kept_changed: Vec::new() };
    let Some(state) = load_state(data_dir)? else { return Ok(report) };
    for f in state.files {
        if !f.path.is_file() {
            continue;
        }
        if sha256_file(&f.path)? == f.sha256 {
            std::fs::remove_file(&f.path)?;
            report.removed.push(f.path);
        } else {
            report.kept_changed.push(f.path);
        }
    }
    std::fs::remove_file(data_dir.join(STATE))?;
    Ok(report)
}

pub fn status(game: &GameInstall, data_dir: &Path, known: &[KnownBuild]) -> Result<Status> {
    let deployed = load_state(data_dir)?;
    let foreign = foreign_patches(&game.contents(), deployed.as_ref())?.into_iter().map(|(_, _, p)| p).collect();
    Ok(Status { gate: check_build(&game.root, known)?, deployed, foreign })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::bundle::{self, Bundle, Entry, Variant};
    use crate::gate::fake_build;
    use crate::library::{Library, Profile};
    use crate::testutil::{put, spaced_tempdir};
    use crate::KeplerError;
    use std::collections::BTreeMap;

    struct World {
        _t: tempfile::TempDir,
        game: GameInstall,
        data: PathBuf,
        opts: DeployOptions<'static>,
    }

    fn base(name: u64) -> Bundle {
        let v = Variant { lang: 0, data: b"vanilla".to_vec(), stream_size: 0 };
        Bundle { props: [9; 256], entries: vec![Entry { type_hash: 1, name_hash: name, flags: 0, variants: vec![v] }] }
    }

    /// Bundles `..aa` and `..bb`, one mod per bundle (`mod-aa`, `mod-bb`), both enabled.
    fn world() -> World {
        let t = spaced_tempdir();
        let game = GameInstall { root: t.path().join("game"), saves_dir: t.path().join("saves") };
        put(&game.saves_dir, "profile.sav", b"save");
        std::fs::create_dir_all(game.contents()).unwrap();
        bundle::write_file(&game.contents().join("00000000000000aa"), &base(1)).unwrap();
        bundle::write_file(&game.contents().join("00000000000000bb"), &base(2)).unwrap();
        let known = fake_build(&game.root, &["contents/00000000000000aa", "contents/00000000000000bb"]);
        let data = t.path().join("data");
        let lib = Library::open(&data).unwrap();
        for b in ["aa", "bb"] {
            let d = t.path().join(format!("stage-{b}"));
            let json = format!(
                r##"{{"kepler":1,"id":"mod-{b}","version":"1.0.0","name":{{"en":"{b}"}},
                   "resources":[{{"type":"#0000000000000001","name":"#00000000000000f0","bundle":"00000000000000{b}","data":"r.bin"}}]}}"##
            );
            put(&d, "kepler.json", json.as_bytes());
            put(&d, "r.bin", b"modded");
            lib.install(&d).unwrap();
        }
        let mut p = Profile::default();
        p.sync(&lib).unwrap();
        p.set_enabled("mod-aa", true).unwrap();
        p.set_enabled("mod-bb", true).unwrap();
        p.save(&data).unwrap();
        World { _t: t, game, data, opts: DeployOptions { known_builds: known, keep_backups: 10 } }
    }

    fn snapshot(dir: &Path) -> BTreeMap<String, String> {
        std::fs::read_dir(dir)
            .unwrap()
            .map(|e| e.unwrap().path())
            .filter(|p| p.is_file())
            .map(|p| (p.file_name().unwrap().to_string_lossy().to_string(), crate::gate::sha256_file(&p).unwrap()))
            .collect()
    }

    fn patch(w: &World, name: &str) -> PathBuf {
        w.game.contents().join(name)
    }

    #[test]
    fn deploy_writes_one_patch_per_bundle_and_purge_restores() {
        let w = world();
        let before = snapshot(&w.game.contents());
        let r = deploy(&w.game, &w.data, &w.opts).unwrap();
        assert_eq!(r.patches.len(), 2);
        let p = bundle::read_file(&patch(&w, "00000000000000aa.patch_0")).unwrap();
        assert_eq!(p.props, [9u8; 256]);
        assert_eq!(p.entries[0].variants[0].data, b"modded");
        assert!(r.backup.is_some());
        assert!(status(&w.game, &w.data, w.opts.known_builds).unwrap().deployed.is_some());
        purge(&w.game, &w.data).unwrap();
        assert_eq!(snapshot(&w.game.contents()), before);
        assert!(status(&w.game, &w.data, w.opts.known_builds).unwrap().deployed.is_none());
    }

    #[test]
    fn slot_follows_foreign_patches() {
        let w = world();
        bundle::write_file(&patch(&w, "00000000000000aa.patch_0"), &base(7)).unwrap();
        bundle::write_file(&patch(&w, "00000000000000aa.patch_1"), &base(8)).unwrap();
        let r = deploy(&w.game, &w.data, &w.opts).unwrap();
        assert!(r.patches.contains(&patch(&w, "00000000000000aa.patch_2")));
        assert_eq!(r.foreign.len(), 2);
        purge(&w.game, &w.data).unwrap();
        assert!(patch(&w, "00000000000000aa.patch_1").exists(), "foreign patches are never removed");
    }

    #[test]
    fn foreign_gap_is_refused() {
        let w = world();
        bundle::write_file(&patch(&w, "00000000000000aa.patch_0"), &base(7)).unwrap();
        bundle::write_file(&patch(&w, "00000000000000aa.patch_2"), &base(8)).unwrap();
        assert!(matches!(deploy(&w.game, &w.data, &w.opts), Err(KeplerError::ForeignPatchGap { missing: 1, .. })));
        assert!(!patch(&w, "00000000000000bb.patch_0").exists());
    }

    #[test]
    fn redeploy_replaces_previous_patches() {
        let w = world();
        deploy(&w.game, &w.data, &w.opts).unwrap();
        let mut p = Profile::load(&w.data).unwrap();
        p.set_enabled("mod-bb", false).unwrap();
        p.save(&w.data).unwrap();
        let r = deploy(&w.game, &w.data, &w.opts).unwrap();
        assert_eq!(r.patches, vec![patch(&w, "00000000000000aa.patch_0")]);
        assert!(!patch(&w, "00000000000000bb.patch_0").exists());
    }

    #[test]
    fn deploy_cleans_leftover_tmp_files() {
        let w = world();
        put(&w.game.contents(), "00000000000000aa.patch_0.kepler-tmp", b"junk");
        deploy(&w.game, &w.data, &w.opts).unwrap();
        assert!(!patch(&w, "00000000000000aa.patch_0.kepler-tmp").exists());
    }

    #[test]
    fn deploy_rolls_back_when_a_rename_fails() {
        let w = world();
        put(&patch(&w, "00000000000000bb.patch_0"), "blocker", b"x");
        assert!(matches!(deploy(&w.game, &w.data, &w.opts), Err(KeplerError::DeployFailed(_))));
        assert!(!patch(&w, "00000000000000aa.patch_0").exists());
        assert!(!patch(&w, "00000000000000aa.patch_0.kepler-tmp").exists());
        assert!(!w.data.join(STATE).exists());
    }

    #[test]
    fn gate_failure_writes_nothing() {
        let w = world();
        bundle::write_file(&w.game.contents().join("00000000000000aa"), &base(5)).unwrap();
        let before = snapshot(&w.game.contents());
        assert!(matches!(deploy(&w.game, &w.data, &w.opts), Err(KeplerError::UnsupportedBuild(_))));
        assert_eq!(snapshot(&w.game.contents()), before);
        assert!(!w.data.join("backups").exists());
    }

    #[test]
    fn purge_works_when_gate_fails() {
        let w = world();
        deploy(&w.game, &w.data, &w.opts).unwrap();
        bundle::write_file(&w.game.contents().join("00000000000000aa"), &base(5)).unwrap();
        assert_eq!(purge(&w.game, &w.data).unwrap().removed.len(), 2);
    }

    #[test]
    fn failed_redeploy_keeps_the_previous_deploy() {
        let w = world();
        deploy(&w.game, &w.data, &w.opts).unwrap();
        std::fs::remove_file(w.data.join("mods/mod-bb/r.bin")).unwrap();
        assert!(deploy(&w.game, &w.data, &w.opts).is_err());
        assert!(patch(&w, "00000000000000aa.patch_0").exists() && patch(&w, "00000000000000bb.patch_0").exists());
        assert!(w.data.join(STATE).exists());
    }

    #[test]
    fn foreign_patch_in_upper_case_is_respected() {
        let w = world();
        bundle::write_file(&patch(&w, "00000000000000AA.patch_0"), &base(7)).unwrap();
        let r = deploy(&w.game, &w.data, &w.opts).unwrap();
        assert!(r.patches.contains(&patch(&w, "00000000000000aa.patch_1")));
        purge(&w.game, &w.data).unwrap();
        assert_eq!(bundle::read_file(&patch(&w, "00000000000000AA.patch_0")).unwrap(), base(7));
    }

    #[test]
    fn state_is_written_atomically_and_removed_on_rollback() {
        let w = world();
        put(&w.data, "deploy-state.json.kepler-tmp", b"torn");
        deploy(&w.game, &w.data, &w.opts).unwrap();
        assert!(!w.data.join("deploy-state.json.kepler-tmp").exists());
        purge(&w.game, &w.data).unwrap();
        put(&patch(&w, "00000000000000bb.patch_0"), "blocker", b"x");
        assert!(deploy(&w.game, &w.data, &w.opts).is_err());
        assert!(!w.data.join(STATE).exists());
    }

    #[test]
    fn purge_keeps_patches_changed_by_someone_else() {
        let w = world();
        deploy(&w.game, &w.data, &w.opts).unwrap();
        bundle::write_file(&patch(&w, "00000000000000aa.patch_0"), &base(6)).unwrap();
        let r = purge(&w.game, &w.data).unwrap();
        assert_eq!(r.kept_changed, vec![patch(&w, "00000000000000aa.patch_0")]);
        assert!(patch(&w, "00000000000000aa.patch_0").exists());
    }
}
