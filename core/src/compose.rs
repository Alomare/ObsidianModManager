//! Turning the enabled mods of a profile into one resource set per game bundle.

use std::collections::BTreeMap;
use std::path::PathBuf;

use serde_json::Value;

use crate::library::{Library, Profile};
use crate::lua::{check_bytecode, wrap_resource};
use crate::luajit::compile;
use crate::hash::hash_name;
use crate::manifest::{Manifest, Payload, load_manifest};
use crate::options::{effective_values, when_matches};
use crate::{ObsidianError, Result};

#[derive(Debug, Clone, PartialEq)]
pub struct Planned {
    pub type_hash: u64,
    pub name_hash: u64,
    pub flags: u32,
    /// Empty in a composition from `plan`, which keeps only the digest.
    pub data: Vec<u8>,
    /// SHA-256 of the data the game gets.
    pub digest: [u8; 32],
    pub owner: String,
}

impl Planned {
    pub fn new(type_hash: u64, name_hash: u64, flags: u32, data: Vec<u8>, owner: String) -> Planned {
        let digest = sha256(&data);
        Planned { type_hash, name_hash, flags, data, digest, owner }
    }
}

fn sha256(data: &[u8]) -> [u8; 32] {
    use sha2::{Digest, Sha256};
    Sha256::digest(data).into()
}

/// Digests of resource files by path, kept while the file is unchanged, so `plan` reads (and
/// compiles) a file only once.
type DigestCache = std::sync::Mutex<std::collections::HashMap<PathBuf, ((std::time::SystemTime, u64), [u8; 32])>>;

fn digests() -> &'static DigestCache {
    static CACHE: std::sync::OnceLock<DigestCache> = std::sync::OnceLock::new();
    CACHE.get_or_init(Default::default)
}

#[derive(Debug, Clone, PartialEq)]
pub struct Conflict {
    pub bundle: String,
    pub type_hash: u64,
    pub name_hash: u64,
    pub winner: String,
    pub losers: Vec<String>,
}

/// An enabled mod, in load order, with the option values in force and how many resources joined.
#[derive(Debug, Clone, PartialEq)]
pub struct ComposedMod {
    pub manifest: Manifest,
    pub dir: PathBuf,
    pub values: BTreeMap<String, Value>,
    pub resources: usize,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Composition {
    pub bundles: BTreeMap<String, Vec<Planned>>,
    pub conflicts: Vec<Conflict>,
    pub mods: Vec<ComposedMod>,
}

/// Everything the game would get, with the data, for a deploy.
pub fn compose(lib: &Library, profile: &Profile) -> Result<Composition> {
    compose_with(lib, profile, true)
}

/// `compose` without the data: the conflicts and a digest per resource, enough to tell whether a
/// deploy is waiting. Unchanged files are not read again, which keeps the window quick with a
/// large library.
pub fn plan(lib: &Library, profile: &Profile) -> Result<Composition> {
    compose_with(lib, profile, false)
}

/// When each file under a folder last changed and how big the file is, from the folder listings: on Windows
/// a listing carries both, where asking file by file costs a call each.
fn file_stamps(dir: &std::path::Path) -> std::collections::HashMap<PathBuf, (std::time::SystemTime, u64)> {
    let mut out = std::collections::HashMap::new();
    let mut todo = vec![dir.to_path_buf()];
    while let Some(d) = todo.pop() {
        let Ok(entries) = std::fs::read_dir(&d) else { continue };
        for e in entries.flatten() {
            let Ok(meta) = e.metadata() else { continue };
            if meta.is_dir() {
                todo.push(e.path());
            } else if let Ok(t) = meta.modified() {
                out.insert(e.path(), (t, meta.len()));
            }
        }
    }
    out
}

fn compose_with(lib: &Library, profile: &Profile, with_data: bool) -> Result<Composition> {
    // (bundle, type, name) -> (winning resource, earlier owners it replaced)
    let mut slots: BTreeMap<(String, u64, u64), (Planned, Vec<String>)> = BTreeMap::new();
    let mut mods = Vec::new();
    let reserved = (hash_name("lua"), hash_name(crate::loader::ENTRY));
    for entry in profile.mods.iter().filter(|m| m.enabled) {
        let dir = lib.mod_dir(&entry.id);
        if !dir.join(crate::manifest::FILE).is_file() {
            return Err(ObsidianError::ModMissing(entry.id.clone()));
        }
        let m = load_manifest(&dir)?;
        let values = effective_values(&m.option_specs()?, profile.options.get(&m.id));
        if m.resources.iter().any(|r| (r.type_hash, r.name_hash) == reserved) {
            return Err(ObsidianError::ReservedResource { mod_id: m.id.clone(), name: crate::loader::ENTRY.into() });
        }
        let chosen: Vec<_> = m.resources.iter().filter(|r| when_matches(&r.when, &values)).collect();
        let stamps = if with_data { Default::default() } else { file_stamps(&dir) };
        for r in &chosen {
            let bundle = r.bundle.clone().ok_or_else(|| ObsidianError::BundleRequired { mod_id: m.id.clone() })?;
            let path = dir.join(r.data_path());
            let game_data = || -> Result<Vec<u8>> {
                let bytes = std::fs::read(&path)?;
                Ok(match &r.payload {
                    Payload::Data(_) => bytes,
                    Payload::Bytecode(_) => {
                        check_bytecode(&bytes)?;
                        wrap_resource(&bytes)
                    }
                    Payload::Source(p) => {
                        let chunk = format!("{}/{}", m.id, p.to_string_lossy().replace('\\', "/"));
                        wrap_resource(&compile(&bytes, &chunk)?)
                    }
                })
            };
            let planned = if with_data {
                Planned::new(r.type_hash, r.name_hash, r.flags, game_data()?, m.id.clone())
            } else {
                let stamp = match stamps.get(&path) {
                    Some(s) => *s,
                    None => {
                        let meta = std::fs::metadata(&path)?;
                        (meta.modified()?, meta.len())
                    }
                };
                let cached = digests().lock().unwrap().get(&path).filter(|(s, _)| *s == stamp).map(|(_, d)| *d);
                let digest = match cached {
                    Some(d) => d,
                    None => {
                        let d = sha256(&game_data()?);
                        digests().lock().unwrap().insert(path.clone(), (stamp, d));
                        d
                    }
                };
                Planned { type_hash: r.type_hash, name_hash: r.name_hash, flags: r.flags, data: Vec::new(), digest, owner: m.id.clone() }
            };
            let key = (bundle, r.type_hash, r.name_hash);
            let losers = match slots.remove(&key) {
                Some((old, mut losers)) => {
                    losers.push(old.owner);
                    losers
                }
                None => Vec::new(),
            };
            slots.insert(key, (planned, losers));
        }
        let resources = chosen.len();
        mods.push(ComposedMod { manifest: m, dir, values, resources });
    }
    let mut out = Composition { mods, ..Default::default() };
    for ((bundle, type_hash, name_hash), (planned, losers)) in slots {
        if !losers.is_empty() {
            out.conflicts.push(Conflict { bundle: bundle.clone(), type_hash, name_hash, winner: planned.owner.clone(), losers });
        }
        out.bundles.entry(bundle).or_default().push(planned);
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::library::ProfileEntry;
    use crate::testutil::{put, spaced_tempdir};

    const VANILLA_BODY_HEX: &str = "1b4c4a0102450200020003000434000000250102003a0101004700010018323032302d31322d32322030393a33333a31341b4255494c445f444154455f494e464f524d4154494f4e075f4700";

    /// Installs a mod whose one resource is `lua/#..01` in bundle `..aa`, from `kind` = data/bytecode/source.
    fn add_mod(t: &std::path::Path, lib: &Library, id: &str, kind: &str, bytes: &[u8]) {
        let d = t.join(format!("stage-{id}"));
        let json = format!(
            r##"{{"obsidian":1,"id":"{id}","version":"1.0.0","name":{{"en":"{id}"}},
               "resources":[{{"type":"lua","name":"#0000000000000001","bundle":"00000000000000aa","{kind}":"r.bin"}}]}}"##
        );
        put(&d, "obsidian.json", json.as_bytes());
        put(&d, "r.bin", bytes);
        lib.install(&d).unwrap();
    }

    fn profile(ids: &[(&str, bool)]) -> Profile {
        Profile { mods: ids.iter().map(|(id, on)| ProfileEntry { id: id.to_string(), enabled: *on, folder: None }).collect(), ..Default::default() }
    }

    fn hex(s: &str) -> Vec<u8> {
        (0..s.len()).step_by(2).map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap()).collect()
    }

    #[test]
    fn later_mod_wins_and_conflict_is_recorded() {
        let t = spaced_tempdir();
        let lib = Library::open(&t.path().join("data")).unwrap();
        add_mod(t.path(), &lib, "first", "data", b"one");
        add_mod(t.path(), &lib, "second", "data", b"two");
        let c = compose(&lib, &profile(&[("first", true), ("second", true)])).unwrap();
        assert_eq!(c.bundles["00000000000000aa"][0].data, b"two");
        assert_eq!(c.conflicts.len(), 1);
        assert_eq!((c.conflicts[0].winner.as_str(), c.conflicts[0].losers.clone()), ("second", vec!["first".to_string()]));
    }

    #[test]
    fn disabled_mods_contribute_nothing() {
        let t = spaced_tempdir();
        let lib = Library::open(&t.path().join("data")).unwrap();
        add_mod(t.path(), &lib, "first", "data", b"one");
        assert!(compose(&lib, &profile(&[("first", false)])).unwrap().bundles.is_empty());
    }

    #[test]
    fn bytecode_is_wrapped_and_checked() {
        let t = spaced_tempdir();
        let lib = Library::open(&t.path().join("data")).unwrap();
        add_mod(t.path(), &lib, "bc", "bytecode", &hex(VANILLA_BODY_HEX));
        add_mod(t.path(), &lib, "bad", "bytecode", &[0x1b, 0x4c, 0x4a, 0x02, 0x02]);
        let c = compose(&lib, &profile(&[("bc", true)])).unwrap();
        assert_eq!(&c.bundles["00000000000000aa"][0].data[..8], &[76, 0, 0, 0, 2, 0, 0, 0]);
        assert!(matches!(compose(&lib, &profile(&[("bad", true)])), Err(ObsidianError::InvalidBytecode(_))));
    }

    #[test]
    fn source_resource_is_compiled_and_wrapped() {
        let t = spaced_tempdir();
        let lib = Library::open(&t.path().join("data")).unwrap();
        add_mod(t.path(), &lib, "src", "source", b"return 1");
        let c = compose(&lib, &profile(&[("src", true)])).unwrap();
        let res = &c.bundles["00000000000000aa"][0].data;
        crate::lua::check_bytecode(crate::lua::unwrap_resource(res).unwrap()).unwrap();
    }

    #[test]
    fn source_error_names_the_mod_and_file() {
        let t = spaced_tempdir();
        let lib = Library::open(&t.path().join("data")).unwrap();
        add_mod(t.path(), &lib, "src", "source", b"return (");
        match compose(&lib, &profile(&[("src", true)])) {
            Err(ObsidianError::CompileFailed { chunk, .. }) => assert_eq!(chunk, "src/r.bin"),
            other => panic!("{other:?}"),
        }
    }

    #[test]
    fn deploy_options_filter_resources() {
        let t = spaced_tempdir();
        let lib = Library::open(&t.path().join("data")).unwrap();
        let d = t.path().join("stage");
        put(&d, "obsidian.json", br##"{"obsidian":1,"id":"opt","version":"1.0.0","name":{"en":"o"},
            "options":[{"id":"sky","type":"choice","default":"day","choices":["day","night"]}],
            "resources":[
              {"type":"lua","name":"#0000000000000001","bundle":"00000000000000aa","data":"day.bin","when":{"sky":"day"}},
              {"type":"lua","name":"#0000000000000001","bundle":"00000000000000aa","data":"night.bin","when":{"sky":"night"}}]}"##);
        put(&d, "day.bin", b"day");
        put(&d, "night.bin", b"night");
        lib.install(&d).unwrap();
        let mut p = profile(&[("opt", true)]);
        let c = compose(&lib, &p).unwrap();
        assert_eq!(c.bundles["00000000000000aa"].iter().map(|r| r.data.as_slice()).collect::<Vec<_>>(), vec![b"day".as_slice()]);
        assert!(c.conflicts.is_empty(), "an option switched off never reports a conflict");
        p.options.insert("opt".into(), [("sky".to_string(), serde_json::json!("night"))].into());
        assert_eq!(compose(&lib, &p).unwrap().bundles["00000000000000aa"][0].data, b"night");
    }

    #[test]
    fn reserved_resource_is_refused() {
        let t = spaced_tempdir();
        let lib = Library::open(&t.path().join("data")).unwrap();
        let d = t.path().join("stage");
        put(&d, "obsidian.json", br##"{"obsidian":1,"id":"grab","version":"1.0.0","name":{"en":"g"},
            "resources":[{"type":"lua","name":"foundation/lua/build_date_information","bundle":"9cf71054ea26dddf","data":"r.bin"}]}"##);
        put(&d, "r.bin", b"x");
        lib.install(&d).unwrap();
        let e = compose(&lib, &profile(&[("grab", true)])).unwrap_err();
        assert!(matches!(e, ObsidianError::ReservedResource { ref mod_id, .. } if mod_id == "grab"), "{e}");
    }

    #[test]
    fn missing_mod_is_an_error() {
        let t = spaced_tempdir();
        let lib = Library::open(&t.path().join("data")).unwrap();
        assert!(matches!(compose(&lib, &profile(&[("ghost", true)])), Err(ObsidianError::ModMissing(_))));
    }
}
