//! Needs the real game: set OBSIDIAN_GAME_DIR to the Helldivers folder and run with --ignored.

use obsidian_core::bundle;

#[test]
#[ignore]
fn every_vanilla_bundle_round_trips() {
    let game = std::env::var("OBSIDIAN_GAME_DIR").expect("OBSIDIAN_GAME_DIR");
    let contents = std::path::Path::new(&game).join("contents");
    let (mut bundles, mut entries) = (0, 0);
    for f in std::fs::read_dir(&contents).unwrap() {
        let path = f.unwrap().path();
        let name = path.file_name().unwrap().to_string_lossy().to_string();
        if name.len() != 16 || !name.bytes().all(|b| b.is_ascii_hexdigit()) {
            continue;
        }
        let payload = bundle::decompress(&std::fs::read(&path).unwrap()).unwrap();
        let parsed = bundle::parse_payload(&payload).unwrap();
        let again = bundle::serialize_payload(&parsed);
        assert_eq!(&payload[..again.len()], &again[..], "{name}");
        assert!(payload[again.len()..].iter().all(|&b| b == 0), "{name}");
        assert_eq!(bundle::read_index(&path).unwrap().len(), parsed.entries.len(), "{name}");
        bundles += 1;
        entries += parsed.entries.len();
    }
    println!("{bundles} bundles, {entries} entries");
    assert_eq!((bundles, entries), (84, 37459));
}
