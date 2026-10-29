//! End-to-end checks of the `kepler` binary on throwaway folders.

use assert_cmd::Command;
use kepler_core::bundle::{self, Bundle, Entry, Variant};

fn spaced() -> tempfile::TempDir {
    tempfile::Builder::new().prefix("kepler cli (x86) ").tempdir().unwrap()
}

fn kepler(game: &std::path::Path, data: &std::path::Path) -> Command {
    let mut c = Command::cargo_bin("kepler").unwrap();
    c.arg("--game").arg(game).arg("--data-dir").arg(data);
    c
}

fn bundle_with(data: &[u8]) -> Bundle {
    let v = Variant { lang: 0, data: data.to_vec(), stream_size: 0 };
    Bundle { props: [9; 256], entries: vec![Entry { type_hash: 1, name_hash: 1, flags: 0, variants: vec![v] }] }
}

#[test]
fn help_lists_every_command() {
    let out = Command::cargo_bin("kepler").unwrap().arg("--help").assert().success().get_output().stdout.clone();
    let text = String::from_utf8(out).unwrap();
    for cmd in ["game", "import", "list", "order", "enable", "disable", "conflicts", "deploy", "purge", "status"] {
        assert!(text.contains(cmd), "missing {cmd}");
    }
}

#[test]
fn unknown_build_is_reported_and_blocks_deploy() {
    let t = spaced();
    let game = t.path().join("game");
    std::fs::create_dir_all(game.join("binaries/x64")).unwrap();
    std::fs::write(game.join("binaries/x64/helldivers.exe"), b"not the real game").unwrap();
    let data = t.path().join("data");
    let out = kepler(&game, &data).arg("status").assert().success().get_output().stdout.clone();
    assert!(String::from_utf8(out).unwrap().contains("Game build: not recognised"));
    kepler(&game, &data).arg("deploy").assert().code(2);
}

#[test]
fn purge_works_with_a_broken_mod_in_the_library() {
    let t = spaced();
    let game = t.path().join("game");
    std::fs::create_dir_all(game.join("contents")).unwrap();
    let data = t.path().join("data");
    std::fs::create_dir_all(data.join("mods/broken")).unwrap();
    std::fs::write(data.join("mods/broken/kepler.json"), b"{ not json").unwrap();
    kepler(&game, &data).arg("purge").assert().success();
}

#[test]
fn legacy_folder_imports_and_lists() {
    let t = spaced();
    let game = t.path().join("game");
    std::fs::create_dir_all(game.join("contents")).unwrap();
    bundle::write_file(&game.join("contents/00000000000000aa"), &bundle_with(b"old")).unwrap();
    let m = t.path().join("My Mod (v2)");
    std::fs::create_dir_all(&m).unwrap();
    bundle::write_file(&m.join("00000000000000aa"), &bundle_with(b"new")).unwrap();
    let data = t.path().join("data");
    kepler(&game, &data).arg("import").arg(&m).assert().success();
    let out = kepler(&game, &data).arg("list").assert().success().get_output().stdout.clone();
    assert!(String::from_utf8(out).unwrap().contains("legacy.my-mod-v2"));
}
