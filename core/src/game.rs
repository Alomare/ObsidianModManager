//! Finding the HELLDIVERS install and the player's save folder.

use std::path::{Path, PathBuf};

use crate::{ObsidianError, Result};

pub const STEAM_DIR: &str = "steamapps/common/Helldivers";

#[derive(Debug, Clone, PartialEq)]
pub struct GameInstall {
    pub root: PathBuf,
    pub saves_dir: PathBuf,
}

impl GameInstall {
    pub fn contents(&self) -> PathBuf {
        self.root.join("contents")
    }
    pub fn exe(&self) -> PathBuf {
        self.root.join("binaries").join("x64").join("helldivers.exe")
    }
}

/// The first library in `libraries` holding the game, else `GameNotFound` naming them all.
pub fn find_in_libraries(libraries: &[PathBuf]) -> Result<PathBuf> {
    libraries
        .iter()
        .map(|lib| lib.join(STEAM_DIR))
        .find(|root| root.join("binaries").join("x64").join("helldivers.exe").is_file())
        .ok_or_else(|| {
            let names: Vec<String> = libraries.iter().map(|l| l.display().to_string()).collect();
            ObsidianError::GameNotFound(if names.is_empty() { "(no Steam library found)".into() } else { names.join("; ") })
        })
}

/// The explicit folder when given, else the game found through Steam.
pub fn find_game(explicit: Option<&Path>) -> Result<GameInstall> {
    let root = match explicit {
        Some(p) => p.to_path_buf(),
        None => find_in_libraries(&steam_libraries())?,
    };
    Ok(GameInstall { root, saves_dir: appdata().join("Arrowhead").join("Helldivers").join("saves") })
}

/// `OBSIDIAN_APPDATA` (tests) or the Windows roaming app data folder.
fn appdata() -> PathBuf {
    std::env::var_os("OBSIDIAN_APPDATA").or_else(|| std::env::var_os("APPDATA")).map(PathBuf::from).unwrap_or_default()
}

fn steam_libraries() -> Vec<PathBuf> {
    let mut roots = Vec::new();
    #[cfg(windows)]
    {
        let key = winreg::RegKey::predef(winreg::enums::HKEY_CURRENT_USER).open_subkey(r"Software\Valve\Steam");
        if let Ok(path) = key.and_then(|k| k.get_value::<String, _>("SteamPath")) {
            roots.push(PathBuf::from(path));
        }
        roots.push(PathBuf::from(r"C:\Program Files (x86)\Steam"));
    }
    #[cfg(not(windows))]
    if let Some(home) = std::env::var_os("HOME").map(PathBuf::from) {
        roots.push(home.join(".steam/steam"));
        roots.push(home.join(".local/share/Steam"));
    }
    let mut libs = Vec::new();
    for root in roots {
        let vdf = root.join("steamapps").join("libraryfolders.vdf");
        let found = std::fs::read_to_string(&vdf).map(|t| crate::vdf::library_paths(&t)).unwrap_or_default();
        for lib in std::iter::once(root).chain(found) {
            if !libs.contains(&lib) {
                libs.push(lib);
            }
        }
    }
    libs
}

/// The game's process name.
pub const EXE: &str = "helldivers.exe";

/// Whether HELLDIVERS is running.
/// Deploy and purge rewrite game files, so they wait until the game is closed.
pub fn ensure_closed() -> Result<()> {
    if is_running() { Err(crate::ObsidianError::GameRunning) } else { Ok(()) }
}

pub fn is_running() -> bool {
    is_running_named(EXE)
}

/// Whether a process with this file name runs, ignoring case.
pub fn is_running_named(name: &str) -> bool {
    use sysinfo::{ProcessRefreshKind, ProcessesToUpdate, System};
    // A system that can't list processes counts as "not running", so deploys stay possible.
    let Ok(mut s) = System::new() else { return false };
    s.refresh_processes_specifics(ProcessesToUpdate::All, true, ProcessRefreshKind::nothing());
    s.processes().values().any(|p| p.name().to_string_lossy().eq_ignore_ascii_case(name))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testutil::{put, spaced_tempdir};

    #[test]
    fn finds_game_in_the_library_that_has_it() {
        let a = spaced_tempdir();
        let b = spaced_tempdir();
        put(b.path(), "steamapps/common/Helldivers/binaries/x64/helldivers.exe", b"exe");
        let libs = vec![a.path().to_path_buf(), b.path().to_path_buf()];
        assert_eq!(find_in_libraries(&libs).unwrap(), b.path().join(STEAM_DIR));
        assert!(find_in_libraries(&libs[..1]).is_err());
    }

    #[test]
    fn explicit_folder_is_used_as_is() {
        let g = spaced_tempdir();
        assert_eq!(find_game(Some(g.path())).unwrap().root, g.path());
    }
    #[test]
    fn running_process_is_found_by_name() {
        let me = std::env::current_exe().unwrap();
        let name = me.file_name().unwrap().to_string_lossy().to_uppercase();
        assert!(is_running_named(&name));
        assert!(!is_running_named("no-such-process-obsidian.exe"));
    }
}
