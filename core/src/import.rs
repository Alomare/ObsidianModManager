//! Importing mods: Kepler mods as they are, legacy whole-bundle mods as resource-level changes.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use crate::bundle::{self, Entry};
use crate::game::GameInstall;
use crate::hash::{format_name, format_type};
use crate::library::{InstallOutcome, Library};
use crate::manifest::{self, Manifest, Payload, ResourceSpec, Scope, write_manifest};
use crate::{KeplerError, Result};

#[derive(Debug, Clone, PartialEq)]
pub struct ImportReport {
    pub id: String,
    pub legacy: bool,
    pub outcome: InstallOutcome,
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
        let mut z = zip::ZipArchive::new(std::fs::File::open(src)?).map_err(|e| KeplerError::UnsupportedArchive(e.to_string()))?;
        z.extract(extracted.path()).map_err(|e| KeplerError::UnsupportedArchive(e.to_string()))?;
        extracted.path()
    } else {
        return Err(KeplerError::UnsupportedArchive(src.display().to_string()));
    };
    let stem = src.file_stem().map(|s| s.to_string_lossy().to_string()).unwrap_or_default();

    let mut files = Vec::new();
    walk(root, &mut files)?;
    let shallowest_manifest = files
        .iter()
        .filter(|p| p.file_name().is_some_and(|n| n == manifest::FILE))
        .min_by_key(|p| p.components().count());
    if let Some(m) = shallowest_manifest {
        let dir = m.parent().unwrap();
        let outcome = lib.install(dir)?;
        let id = manifest::load_manifest(dir)?.id;
        return Ok(ImportReport { id, legacy: false, outcome, changed: 0, added: 0, removed_ignored: 0 });
    }

    let bundles: Vec<&PathBuf> = files.iter().filter(|p| p.file_name().is_some_and(|n| is_bundle_name(&n.to_string_lossy()))).collect();
    if bundles.is_empty() {
        return Err(KeplerError::NothingToImport(src.display().to_string()));
    }
    let staged = tempfile::tempdir()?;
    let (mut changed, mut added, mut removed_ignored) = (0, 0, 0);
    let mut resources = Vec::new();
    for path in bundles {
        let name = path.file_name().unwrap().to_string_lossy().to_string();
        let vanilla_path = game.contents().join(&name);
        if !vanilla_path.is_file() {
            return Err(KeplerError::UnknownBundle(name));
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
                _ => return Err(KeplerError::UnsupportedLegacyEntry { bundle: name.clone(), entry }),
            };
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
            });
        }
    }
    let m = Manifest {
        kepler: 1,
        id: legacy_id(&stem),
        version: semver::Version::new(0, 0, 0),
        name: [("en".to_string(), stem)].into(),
        description: None,
        authors: Vec::new(),
        scope: Scope::Session,
        entry: None,
        resources,
        options: Vec::new(),
        keybinds: Vec::new(),
        requires: Vec::new(),
        conflicts: Vec::new(),
        loader_api: 1,
        extra: [("legacy".to_string(), serde_json::Value::Bool(true))].into(),
    };
    write_manifest(staged.path(), &m)?;
    let outcome = lib.install(staged.path())?;
    Ok(ImportReport { id: m.id, legacy: true, outcome, changed, added, removed_ignored })
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
        let game = GameInstall { root: t.path().join("game"), saves_dir: t.path().join("saves") };
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
        let m = &f.lib.list().unwrap()[0];
        assert_eq!(m.scope, Scope::Session);
        assert_eq!(m.resources.len(), 2);
        let tex = m.resources.iter().find(|r| r.flags == 7).unwrap();
        assert_eq!(tex.type_text, "texture");
        assert_eq!(std::fs::read(f.lib.mod_dir(&r.id).join(tex.data_path())).unwrap(), b"add");
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
    fn kepler_mod_folder_is_installed_as_is() {
        let f = fixture(standard());
        let k = f.mod_dir.join("kmod");
        crate::testutil::put(&k, "kepler.json", br#"{"kepler":1,"id":"me.kmod","version":"1.0.0","name":{"en":"K"}}"#);
        let r = import_path(&f.mod_dir, &f.game, &f.lib).unwrap();
        assert_eq!((r.id.as_str(), r.legacy), ("me.kmod", false));
    }

    #[test]
    fn reimport_replaces_existing_mod() {
        let f = fixture(standard());
        import_path(&f.mod_dir, &f.game, &f.lib).unwrap();
        let again = import_path(&f.mod_dir, &f.game, &f.lib).unwrap();
        assert!(matches!(again.outcome, InstallOutcome::Replaced { .. }));
    }

    #[test]
    fn unknown_bundle_name_is_an_error() {
        let f = fixture(standard());
        std::fs::rename(f.mod_dir.join("contents/00000000000000aa"), f.mod_dir.join("contents/00000000000000bb")).unwrap();
        assert!(matches!(import_path(&f.mod_dir, &f.game, &f.lib), Err(KeplerError::UnknownBundle(_))));
    }
}
