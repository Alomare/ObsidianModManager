//! The game-side settings file the loader reads at boot: consent, option values
//! and keys. A change applies at the next game launch, with no redeploy.

use std::path::{Path, PathBuf};

use crate::Result;

pub const FILE: &str = "settings.txt";

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Settings {
    pub consent: bool,
    /// (mod id, option id, option type, value text)
    pub options: Vec<(String, String, String, String)>,
    /// (mod id, keybind id, key name)
    pub keys: Vec<(String, String, String)>,
}

/// `%APPDATA%\Arrowhead\Helldivers\obsidian`, beside the game's own save folder.
pub fn game_side_dir(saves_dir: &Path) -> PathBuf {
    saves_dir.parent().map(|p| p.join("obsidian")).unwrap_or_else(|| saves_dir.join("obsidian"))
}

pub fn render(s: &Settings) -> String {
    let mut out = String::from("# Written by Obsidian. Changes made here are replaced at the next deploy.\n");
    out.push_str(&format!("consent\t{}\n", if s.consent { 1 } else { 0 }));
    for (m, o, t, v) in &s.options {
        out.push_str(&format!("option\t{m}\t{o}\t{t}\t{v}\n"));
    }
    for (m, k, key) in &s.keys {
        out.push_str(&format!("key\t{m}\t{k}\t{key}\n"));
    }
    out
}

/// Lines that don't parse are skipped, as the loader does.
pub fn parse(text: &str) -> Settings {
    let mut s = Settings::default();
    for line in text.lines() {
        let f: Vec<&str> = line.split('\t').collect();
        match f.as_slice() {
            ["consent", v] => s.consent = *v == "1",
            ["option", m, o, t, v] => s.options.push((m.to_string(), o.to_string(), t.to_string(), v.to_string())),
            ["key", m, k, key] => s.keys.push((m.to_string(), k.to_string(), key.to_string())),
            _ => {}
        }
    }
    s
}

/// Writes the file atomically and makes sure the logs folder exists for the loader.
pub fn write(dir: &Path, s: &Settings) -> Result<()> {
    std::fs::create_dir_all(dir.join("logs"))?;
    let tmp = dir.join(format!("{FILE}.obsidian-tmp"));
    std::fs::write(&tmp, render(s))?;
    std::fs::rename(&tmp, dir.join(FILE))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn settings_file_round_trips() {
        let s = Settings {
            consent: true,
            options: vec![("a.b".into(), "d".into(), "number".into(), "2.5".into())],
            keys: vec![("a.b".into(), "toggle".into(), "f8".into())],
        };
        let t = crate::testutil::spaced_tempdir();
        write(t.path(), &s).unwrap();
        assert!(t.path().join("logs").is_dir());
        assert_eq!(parse(&std::fs::read_to_string(t.path().join(FILE)).unwrap()), s);
    }

    #[test]
    fn game_side_dir_is_beside_the_saves() {
        assert_eq!(game_side_dir(Path::new("C:/x/Arrowhead/Helldivers/saves")), Path::new("C:/x/Arrowhead/Helldivers/obsidian"));
    }
}
