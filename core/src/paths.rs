//! Where Obsidian keeps the library, profile, backups and state.

use std::path::{Path, PathBuf};

/// The explicit folder, else `data` beside a portable copy (marked by `portable.txt`),
/// else the per-user app data folder.
pub fn data_dir(explicit: Option<&Path>) -> PathBuf {
    if let Some(p) = explicit {
        return p.to_path_buf();
    }
    if let Some(dir) = std::env::current_exe().ok().and_then(|e| e.parent().map(Path::to_path_buf))
        && dir.join("portable.txt").is_file()
    {
        return dir.join("data");
    }
    #[cfg(windows)]
    let base = std::env::var_os("LOCALAPPDATA").map(PathBuf::from);
    #[cfg(not(windows))]
    let base = std::env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".local/share")));
    base.unwrap_or_default().join(crate::settings::DIR)
}
