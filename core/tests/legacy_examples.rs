//! Needs KEPLER_GAME_DIR (the Helldivers folder) and KEPLER_EXAMPLES_DIR (internal/_examples); run with --ignored.

use std::collections::{BTreeMap, BTreeSet};
use std::path::PathBuf;

use kepler_core::game::find_game;
use kepler_core::import::import_path;
use kepler_core::library::Library;

fn zip_in(folder: &str) -> PathBuf {
    let dir = PathBuf::from(std::env::var("KEPLER_EXAMPLES_DIR").expect("KEPLER_EXAMPLES_DIR")).join("FROM NEXUS").join(folder);
    std::fs::read_dir(&dir).unwrap().map(|e| e.unwrap().path()).find(|p| p.extension().is_some_and(|x| x == "zip")).unwrap()
}

#[test]
#[ignore]
fn rework_and_tpc_import_to_their_resource_lists() {
    let game = find_game(Some(std::env::var("KEPLER_GAME_DIR").expect("KEPLER_GAME_DIR").as_ref())).unwrap();
    let data = tempfile::tempdir().unwrap();
    let lib = Library::open(data.path()).unwrap();
    let mut seen = Vec::new();
    for (folder, expected) in [
        ("Rework and more enemys", vec![("9e13b2414b41b842", 49)]),
        ("Third Person Camera HD2 Style", vec![("1a9c33dcd0301dfd", 1), ("9cf71054ea26dddf", 2), ("9e13b2414b41b842", 27), ("ebbaccd983625dde", 294)]),
    ] {
        let r = import_path(&zip_in(folder), &game, &lib).unwrap();
        let m = lib.list().unwrap().into_iter().find(|m| m.id == r.id).unwrap();
        let mut per_bundle: BTreeMap<String, usize> = BTreeMap::new();
        for res in &m.resources {
            *per_bundle.entry(res.bundle.clone().unwrap()).or_default() += 1;
        }
        let expected: BTreeMap<String, usize> = expected.into_iter().map(|(b, n)| (b.to_string(), n)).collect();
        assert_eq!(per_bundle, expected, "{folder}");
        if folder.starts_with("Third") {
            assert!(m.resources.iter().filter(|r| r.bundle.as_deref() == Some("ebbaccd983625dde")).all(|r| r.flags == 531101911));
        }
        seen.push(m.resources.iter().map(|r| (r.type_hash, r.name_hash)).collect::<BTreeSet<_>>());
    }
    assert!(seen[0].is_disjoint(&seen[1]), "Rework and TPC share a resource");
}
