//! Turning the enabled mods of a profile into one resource set per game bundle.

use std::collections::BTreeMap;

use crate::library::{Library, Profile};
use crate::lua::{check_bytecode, wrap_resource};
use crate::luajit::compile;
use crate::manifest::{Payload, load_manifest};
use crate::{ObsidianError, Result};

#[derive(Debug, Clone, PartialEq)]
pub struct Planned {
    pub type_hash: u64,
    pub name_hash: u64,
    pub flags: u32,
    pub data: Vec<u8>,
    pub owner: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Conflict {
    pub bundle: String,
    pub type_hash: u64,
    pub name_hash: u64,
    pub winner: String,
    pub losers: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Composition {
    pub bundles: BTreeMap<String, Vec<Planned>>,
    pub conflicts: Vec<Conflict>,
}

pub fn compose(lib: &Library, profile: &Profile) -> Result<Composition> {
    // (bundle, type, name) -> (winning resource, earlier owners it replaced)
    let mut slots: BTreeMap<(String, u64, u64), (Planned, Vec<String>)> = BTreeMap::new();
    for entry in profile.mods.iter().filter(|m| m.enabled) {
        let dir = lib.mod_dir(&entry.id);
        if !dir.join(crate::manifest::FILE).is_file() {
            return Err(ObsidianError::ModMissing(entry.id.clone()));
        }
        let m = load_manifest(&dir)?;
        for r in &m.resources {
            let bundle = r.bundle.clone().ok_or_else(|| ObsidianError::BundleRequired { mod_id: m.id.clone() })?;
            let bytes = std::fs::read(dir.join(r.data_path()))?;
            let data = match &r.payload {
                Payload::Data(_) => bytes,
                Payload::Bytecode(_) => {
                    check_bytecode(&bytes)?;
                    wrap_resource(&bytes)
                }
                Payload::Source(p) => {
                    let chunk = format!("{}/{}", m.id, p.to_string_lossy().replace('\\', "/"));
                    wrap_resource(&compile(&bytes, &chunk)?)
                }
            };
            let planned = Planned { type_hash: r.type_hash, name_hash: r.name_hash, flags: r.flags, data, owner: m.id.clone() };
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
    }
    let mut out = Composition::default();
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
        Profile { mods: ids.iter().map(|(id, on)| ProfileEntry { id: id.to_string(), enabled: *on }).collect() }
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
    fn missing_mod_is_an_error() {
        let t = spaced_tempdir();
        let lib = Library::open(&t.path().join("data")).unwrap();
        assert!(matches!(compose(&lib, &profile(&[("ghost", true)])), Err(ObsidianError::ModMissing(_))));
    }
}
