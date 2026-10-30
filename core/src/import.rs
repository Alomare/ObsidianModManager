//! Importing mods: Obsidian mods as they are, legacy whole-bundle mods as resource-level changes.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use crate::bundle::{self, Entry};
use crate::game::GameInstall;
use crate::hash::{format_name, format_type, hash_name};
use crate::library::{InstallOutcome, Library};
use crate::manifest::{self, Manifest, Payload, ResourceSpec, Scope, write_manifest};
use crate::{ObsidianError, Result};

#[derive(Debug, Clone, PartialEq)]
pub struct ImportReport {
    pub id: String,
    pub legacy: bool,
    pub outcome: InstallOutcome,
    /// The version now in the library.
    pub version: semver::Version,
    pub changed: usize,
    pub added: usize,
    pub removed_ignored: usize,
}

pub fn import_path(src: &Path, game: &GameInstall, lib: &Library) -> Result<ImportReport> {
    let extracted;
    let root: &Path = if src.is_dir() {
        src
    } else if src.extension().is_some_and(|x| x.eq_ignore_ascii_case("zip")) {
        extracted = tempfile::tempdir()?;
        unzip(src, extracted.path())?;
        extracted.path()
    } else {
        return Err(ObsidianError::UnsupportedArchive(src.display().to_string()));
    };
    let stem = src.file_stem().map(|s| s.to_string_lossy().to_string()).unwrap_or_default();

    let mut files = Vec::new();
    walk(root, &mut files)?;
    if let Some(m) = shallowest_manifest(&files) {
        let dir = m.parent().unwrap();
        let outcome = lib.install(dir)?;
        let m = manifest::load_manifest(dir)?;
        return Ok(ImportReport { id: m.id, legacy: false, outcome, version: m.version, changed: 0, added: 0, removed_ignored: 0 });
    }

    let bundles: Vec<&PathBuf> = files.iter().filter(|p| p.file_name().is_some_and(|n| is_bundle_name(&n.to_string_lossy()))).collect();
    if bundles.is_empty() {
        return Err(ObsidianError::NothingToImport(src.display().to_string()));
    }
    let staged = tempfile::tempdir()?;
    let (mut changed, mut added, mut removed_ignored) = (0, 0, 0);
    let mut resources = Vec::new();
    let entry_key = (hash_name("lua"), hash_name(crate::loader::ENTRY));
    let mut entry_file = None;
    for path in bundles {
        let name = path.file_name().unwrap().to_string_lossy().to_string();
        let vanilla_path = game.contents().join(&name);
        if !vanilla_path.is_file() {
            return Err(ObsidianError::UnknownBundle(name));
        }
        let vanilla: BTreeMap<(u64, u64), Entry> =
            bundle::read_file(&vanilla_path)?.entries.into_iter().map(|e| ((e.type_hash, e.name_hash), e)).collect();
        let modded = bundle::read_file(path)?;
        let keys: Vec<(u64, u64)> = modded.entries.iter().map(|e| (e.type_hash, e.name_hash)).collect();
        removed_ignored += vanilla.keys().filter(|k| !keys.contains(k)).count();
        for e in modded.entries {
            match vanilla.get(&(e.type_hash, e.name_hash)) {
                Some(v) if *v == e => continue,
                Some(_) => changed += 1,
                None => added += 1,
            }
            let entry = format!("{}-{}", hex16(e.type_hash), hex16(e.name_hash));
            let v = match e.variants.as_slice() {
                [v] if v.lang == 0 && v.stream_size == 0 => v,
                _ => return Err(ObsidianError::UnsupportedLegacyEntry { bundle: name.clone(), entry }),
            };
            if name == crate::loader::BUNDLE && (e.type_hash, e.name_hash) == entry_key {
                // Obsidian Loader takes the place of this resource, so the mod's version runs as the entry.
                std::fs::write(staged.path().join("entry.bin"), &v.data)?;
                entry_file = Some(PathBuf::from("entry.bin"));
                continue;
            }
            let rel = PathBuf::from("res").join(&name).join(format!("{entry}.bin"));
            std::fs::create_dir_all(staged.path().join(rel.parent().unwrap()))?;
            std::fs::write(staged.path().join(&rel), &v.data)?;
            resources.push(ResourceSpec {
                type_text: format_type(e.type_hash),
                name_text: format_name(e.name_hash),
                type_hash: e.type_hash,
                name_hash: e.name_hash,
                bundle: Some(name.clone()),
                flags: e.flags,
                payload: Payload::Data(rel),
                when: BTreeMap::new(),
            });
        }
    }
    if changed + added == 0 {
        // Usually the game files were already modded by hand, so there is nothing to compare against.
        return Err(ObsidianError::NothingToImport(format!(
            "{} (the mod matches the game files exactly; if you installed the mod by hand before, verify the game files in Steam first)",
            src.display()
        )));
    }
    // A Nexus download keeps the same id across versions, so a newer file updates the mod.
    let (id, version, name) = match nexus_file(&stem) {
        Some(n) => (n.id(), n.version, n.name),
        None => (legacy_id(&stem), semver::Version::new(0, 0, 0), stem),
    };
    let m = Manifest {
        obsidian: 1,
        id,
        version,
        name: [("en".to_string(), name)].into(),
        description: None,
        authors: Vec::new(),
        scope: Scope::Session,
        entry: entry_file,
        resources,
        options: Vec::new(),
        keybinds: Vec::new(),
        modules: Vec::new(),
        requires: Vec::new(),
        conflicts: Vec::new(),
        loader_api: 1,
        extra: [("legacy".to_string(), serde_json::Value::Bool(true))].into(),
    };
    write_manifest(staged.path(), &m)?;
    let file = src.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
    let info = crate::library::ImportInfo { date: chrono::Local::now().to_rfc3339(), file };
    std::fs::write(staged.path().join(crate::library::IMPORT_INFO), serde_json::to_string_pretty(&info)? + "
")?;
    let outcome = lib.install(staged.path())?;
    Ok(ImportReport { id: m.id, legacy: true, outcome, version: m.version, changed, added, removed_ignored })
}

pub(crate) fn unzip(src: &Path, to: &Path) -> Result<()> {
    let mut z = zip::ZipArchive::new(std::fs::File::open(src)?).map_err(|e| ObsidianError::UnsupportedArchive(e.to_string()))?;
    z.extract(to).map_err(|e| ObsidianError::UnsupportedArchive(e.to_string()))
}

fn shallowest_manifest(files: &[PathBuf]) -> Option<&PathBuf> {
    files.iter().filter(|p| p.file_name().is_some_and(|n| n == manifest::FILE)).min_by_key(|p| p.components().count())
}

/// The folder under `root` that holds `obsidian.json`, nearest the top.
pub(crate) fn mod_folder(root: &Path) -> Result<Option<PathBuf>> {
    let mut files = Vec::new();
    walk(root, &mut files)?;
    Ok(shallowest_manifest(&files).and_then(|m| m.parent()).map(Path::to_path_buf))
}

fn walk(dir: &Path, out: &mut Vec<PathBuf>) -> Result<()> {
    for e in std::fs::read_dir(dir)? {
        let e = e?;
        if e.file_type()?.is_dir() {
            walk(&e.path(), out)?;
        } else {
            out.push(e.path());
        }
    }
    Ok(())
}

fn is_bundle_name(n: &str) -> bool {
    n.len() == 16 && n.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

fn hex16(h: u64) -> String {
    format!("{h:016x}")
}

/// What a file name from Nexus Mods tells: Nexus names downloads
/// `<file name> <mod id> <version> <upload time> <code>`.
#[derive(Debug, PartialEq)]
struct NexusFile {
    /// The file name without version tokens such as "V1.2".
    name: String,
    mod_id: u64,
    version: semver::Version,
}

impl NexusFile {
    /// The Nexus mod page and the file name: one page can hold several files that are separate
    /// mods, and every version of one file keeps the same id.
    fn id(&self) -> String {
        let slug = legacy_id(&self.name);
        legacy_id(&format!("nexus {} {}", self.mod_id, slug.trim_start_matches("legacy.")))
    }
}

fn nexus_file(stem: &str) -> Option<NexusFile> {
    let words: Vec<&str> = stem.split_whitespace().collect();
    let [head @ .., id, version, time, code] = words.as_slice() else { return None };
    let is_time = time.len() == 17 && time.as_bytes()[10] == b'T' && time.ends_with('Z') && time.bytes().filter(u8::is_ascii_digit).count() == 12;
    if head.is_empty() || !is_time || !code.bytes().all(|b| b.is_ascii_alphanumeric()) {
        return None;
    }
    let mod_id = id.parse().ok()?;
    let looks_like_version = |w: &&str| {
        let w = w.trim_start_matches(['v', 'V']);
        w.contains('.') && w.split('.').all(|p| !p.is_empty() && p.bytes().all(|b| b.is_ascii_digit()))
    };
    let name: Vec<&str> = head.iter().copied().filter(|w| !looks_like_version(w)).collect();
    Some(NexusFile { name: if name.is_empty() { head.join(" ") } else { name.join(" ") }, mod_id, version: lenient_version(version) })
}

/// "1.2" is 1.2.0, "1.0.4b" is 1.0.4; anything without a leading number is 0.0.0.
fn lenient_version(v: &str) -> semver::Version {
    let mut n = v.trim_start_matches(['v', 'V']).split('.').map(|p| p.chars().take_while(char::is_ascii_digit).collect::<String>().parse::<u64>().ok());
    let mut part = || n.next().flatten();
    match part() {
        Some(major) => semver::Version::new(major, part().unwrap_or(0), part().unwrap_or(0)),
        None => semver::Version::new(0, 0, 0),
    }
}

/// `legacy.` plus the name lowercased, with every run of other characters turned into one `-`.
fn legacy_id(stem: &str) -> String {
    let mut slug = String::new();
    for c in stem.to_lowercase().chars() {
        if c.is_ascii_lowercase() || c.is_ascii_digit() {
            slug.push(c);
        } else if !slug.ends_with('-') && !slug.is_empty() {
            slug.push('-');
        }
    }
    let mut id = format!("legacy.{}", slug.trim_end_matches('-'));
    id.truncate(64);
    id.trim_end_matches('-').to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nexus_file_names_give_a_stable_id_a_clean_name_and_the_version() {
        let tpc12 = nexus_file("ThirdPersonCamera V1.2 Manual 12 1.2 2026-10-28T10-41Z 6ZKn90ihp").unwrap();
        let tpc15 = nexus_file("ThirdPersonCamera V1.5 Manual 12 1.5 2026-10-29T20-32Z UQhsN6aoF").unwrap();
        assert_eq!((tpc12.name.as_str(), tpc12.mod_id, tpc12.version.to_string()), ("ThirdPersonCamera Manual", 12, "1.2.0".to_string()));
        assert_eq!((tpc15.name, tpc15.mod_id, tpc15.version.to_string()), (tpc12.name, 12, "1.5.0".to_string()));
        let rip = nexus_file("RIP THEM APART FOR SUPER EARTH 11 1 2026-10-28T18-46Z ym1oMPKH7").unwrap();
        assert_eq!((rip.name.as_str(), rip.mod_id, rip.version.to_string()), ("RIP THEM APART FOR SUPER EARTH", 11, "1.0.0".to_string()));
        assert_eq!(nexus_file("Odd 3 1.0.4b 2026-01-02T03-04Z abc").unwrap().version.to_string(), "1.0.4");
        // One Nexus page can hold several files that are separate mods; versions of one file share the id.
        let id = |n: &str| nexus_file(n).unwrap().id();
        assert_eq!(id("ThirdPersonCamera V1.2 Manual 12 1.2 2026-10-28T10-41Z 6ZKn90ihp"), "legacy.nexus-12-thirdpersoncamera-manual");
        assert_eq!(id("ThirdPersonCamera V1.5 Manual 12 1.5 2026-10-29T20-32Z UQhsN6aoF"), "legacy.nexus-12-thirdpersoncamera-manual");
        assert_eq!(id("Saber Unlock 14 2 2026-10-29T23-32Z E9DGIkWtE"), "legacy.nexus-14-saber-unlock");
        assert_eq!(id("Saber-Finish-enemys and xp 14 2 2026-10-29T23-34Z VqAWU7Nfb"), "legacy.nexus-14-saber-finish-enemys-and-xp");
    }

    #[test]
    fn other_file_names_are_not_nexus_files() {
        for n in ["My Mod (v2)", "HD2CAM", "Mod 12 1.2", "Mod x 1.2 2026-10-28T10-41Z code", "12 1.2 2026-10-28T10-41Z code"] {
            assert!(nexus_file(n).is_none(), "{n}");
        }
    }
    use crate::bundle::{Bundle, Variant};
    use crate::hash::hash_name;
    use crate::testutil::spaced_tempdir;

    const LUA: u64 = 0xa14e8dfa2cd117e2;

    fn e(type_hash: u64, name_hash: u64, flags: u32, data: &[u8]) -> Entry {
        Entry { type_hash, name_hash, flags, variants: vec![Variant { lang: 0, data: data.to_vec(), stream_size: 0 }] }
    }

    struct Fixture {
        _t: tempfile::TempDir,
        game: GameInstall,
        lib: Library,
        mod_dir: PathBuf,
    }

    /// Vanilla `00000000000000aa` holds lua/1 "old" and lua/2 "keep"; the mod changes 1, keeps 2, adds texture/3.
    fn fixture(mod_entries: Vec<Entry>) -> Fixture {
        let t = spaced_tempdir();
        let game = GameInstall { root: t.path().join("game"), saves_dir: t.path().join("saves"), cloud_saves: Vec::new() };
        std::fs::create_dir_all(game.contents()).unwrap();
        let vanilla = Bundle { props: [9; 256], entries: vec![e(LUA, 1, 0, b"old"), e(LUA, 2, 0, b"keep")] };
        bundle::write_file(&game.contents().join("00000000000000aa"), &vanilla).unwrap();
        let mod_dir = t.path().join("My Mod (v2)");
        std::fs::create_dir_all(mod_dir.join("contents")).unwrap();
        let m = Bundle { props: [9; 256], entries: mod_entries };
        bundle::write_file(&mod_dir.join("contents").join("00000000000000aa"), &m).unwrap();
        let lib = Library::open(&t.path().join("data")).unwrap();
        Fixture { _t: t, game, lib, mod_dir }
    }

    fn standard() -> Vec<Entry> {
        vec![e(LUA, 1, 0, b"new"), e(LUA, 2, 0, b"keep"), e(hash_name("texture"), 3, 7, b"add")]
    }

    #[test]
    fn legacy_bundle_becomes_resource_level_mod() {
        let f = fixture(standard());
        let r = import_path(&f.mod_dir, &f.game, &f.lib).unwrap();
        assert_eq!((r.id.as_str(), r.legacy, r.changed, r.added, r.removed_ignored), ("legacy.my-mod-v2", true, 1, 1, 0));
        assert_eq!(r.version, semver::Version::new(0, 0, 0));
        let m = &f.lib.list().unwrap()[0];
        assert_eq!(m.scope, Scope::Session);
        assert_eq!(m.resources.len(), 2);
        let tex = m.resources.iter().find(|r| r.flags == 7).unwrap();
        assert_eq!(tex.type_text, "texture");
        assert_eq!(std::fs::read(f.lib.mod_dir(&r.id).join(tex.data_path())).unwrap(), b"add");
    }

    #[test]
    fn legacy_build_date_information_becomes_entry() {
        let t = spaced_tempdir();
        let game = GameInstall { root: t.path().join("game"), saves_dir: t.path().join("saves"), cloud_saves: Vec::new() };
        let entry = hash_name(crate::loader::ENTRY);
        let mod_dir = t.path().join("HD2CAM");
        std::fs::create_dir_all(game.contents()).unwrap();
        std::fs::create_dir_all(&mod_dir).unwrap();
        let vanilla = Bundle { props: [9; 256], entries: vec![e(LUA, entry, 0, b"vanilla"), e(LUA, 5, 0, b"old")] };
        bundle::write_file(&game.contents().join(crate::loader::BUNDLE), &vanilla).unwrap();
        let modded = Bundle { props: [9; 256], entries: vec![e(LUA, entry, 0, b"camera"), e(LUA, 5, 0, b"new")] };
        bundle::write_file(&mod_dir.join(crate::loader::BUNDLE), &modded).unwrap();
        let lib = Library::open(&t.path().join("data")).unwrap();
        let r = import_path(&mod_dir, &game, &lib).unwrap();
        assert_eq!((r.changed, r.added), (2, 0));
        let m = &lib.list().unwrap()[0];
        let path = m.entry.clone().expect("entry");
        assert_eq!(std::fs::read(lib.mod_dir(&r.id).join(path)).unwrap(), b"camera");
        assert_eq!(m.resources.len(), 1);
        assert_eq!(m.resources[0].name_hash, 5);
    }

    #[test]
    fn missing_entry_is_counted_not_removed() {
        let f = fixture(vec![e(LUA, 1, 0, b"new")]);
        assert_eq!(import_path(&f.mod_dir, &f.game, &f.lib).unwrap().removed_ignored, 1);
    }

    #[test]
    fn zip_with_nested_folder_imports_the_same() {
        let f = fixture(standard());
        let zip_path = f.mod_dir.with_extension("zip");
        let mut z = zip::ZipWriter::new(std::fs::File::create(&zip_path).unwrap());
        z.start_file("pack/contents/00000000000000aa", zip::write::SimpleFileOptions::default()).unwrap();
        std::io::copy(&mut std::fs::File::open(f.mod_dir.join("contents/00000000000000aa")).unwrap(), &mut z).unwrap();
        z.finish().unwrap();
        let r = import_path(&zip_path, &f.game, &f.lib).unwrap();
        assert_eq!((r.changed, r.added), (1, 1));
    }

    #[test]
    fn obsidian_mod_folder_is_installed_as_is() {
        let f = fixture(standard());
        let k = f.mod_dir.join("kmod");
        crate::testutil::put(&k, "obsidian.json", br#"{"obsidian":1,"id":"me.kmod","version":"1.0.0","name":{"en":"K"}}"#);
        let r = import_path(&f.mod_dir, &f.game, &f.lib).unwrap();
        assert_eq!((r.id.as_str(), r.legacy, r.version.to_string()), ("me.kmod", false, "1.0.0".to_string()));
        assert_eq!(f.lib.import_info("me.kmod"), None);
    }

    #[test]
    fn legacy_import_writes_import_info() {
        let f = fixture(standard());
        let r = import_path(&f.mod_dir, &f.game, &f.lib).unwrap();
        let info = f.lib.import_info(&r.id).expect("import info");
        assert_eq!(info.file, f.mod_dir.file_name().unwrap().to_string_lossy());
        assert!(chrono::DateTime::parse_from_rfc3339(&info.date).is_ok(), "{}", info.date);
    }

    #[test]
    fn reimport_replaces_existing_mod() {
        let f = fixture(standard());
        import_path(&f.mod_dir, &f.game, &f.lib).unwrap();
        let again = import_path(&f.mod_dir, &f.game, &f.lib).unwrap();
        assert!(matches!(again.outcome, InstallOutcome::Replaced { .. }));
    }

    #[test]
    fn mod_identical_to_the_game_is_nothing_to_import() {
        let f = fixture(vec![e(LUA, 1, 0, b"old"), e(LUA, 2, 0, b"keep")]);
        assert!(matches!(import_path(&f.mod_dir, &f.game, &f.lib), Err(ObsidianError::NothingToImport(_))));
    }

    #[test]
    fn unknown_bundle_name_is_an_error() {
        let f = fixture(standard());
        std::fs::rename(f.mod_dir.join("contents/00000000000000aa"), f.mod_dir.join("contents/00000000000000bb")).unwrap();
        assert!(matches!(import_path(&f.mod_dir, &f.game, &f.lib), Err(ObsidianError::UnknownBundle(_))));
    }
}
