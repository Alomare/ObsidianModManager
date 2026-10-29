//! Save backups taken before every deploy.

use std::path::{Path, PathBuf};

use crate::Result;

/// Copies `saves_dir` to `backups_dir/YYYYMMDD-HHMMSS` (adding `-2`, `-3`... on a clash) and keeps the newest `keep`.
pub fn backup_saves(saves_dir: &Path, backups_dir: &Path, keep: usize) -> Result<Option<PathBuf>> {
    if !saves_dir.is_dir() {
        return Ok(None);
    }
    std::fs::create_dir_all(backups_dir)?;
    let stamp = chrono::Local::now().format("%Y%m%d-%H%M%S").to_string();
    // Number above every existing backup of this second: reusing a pruned name would sort the new copy as the oldest.
    let highest = std::fs::read_dir(backups_dir)?
        .filter_map(|e| e.ok().and_then(|e| order_key(&e.path())))
        .filter(|(s, _)| *s == stamp)
        .map(|(_, n)| n)
        .max();
    let target = match highest {
        None => backups_dir.join(&stamp),
        Some(n) => backups_dir.join(format!("{stamp}-{}", n + 1)),
    };
    crate::library::copy_dir(saves_dir, &target)?;
    let mut all: Vec<(String, u32, PathBuf)> = std::fs::read_dir(backups_dir)?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.is_dir())
        .filter_map(|p| order_key(&p).map(|(s, n)| (s, n, p)))
        .collect();
    // Sort by stamp, then by the numeric suffix, so "-10" comes after "-9".
    all.sort();
    let excess = all.len().saturating_sub(keep);
    for (_, _, old) in all.into_iter().take(excess) {
        std::fs::remove_dir_all(old)?;
    }
    Ok(Some(target))
}

/// (`YYYYMMDD-HHMMSS`, suffix) for a backup folder name, or None for anything else.
fn order_key(p: &Path) -> Option<(String, u32)> {
    let name = p.file_name()?.to_str()?;
    let (stamp, rest) = name.split_at_checked(15)?;
    let n = match rest {
        "" => 1,
        r => r.strip_prefix('-')?.parse().ok()?,
    };
    Some((stamp.to_string(), n))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testutil::{put, spaced_tempdir};

    #[test]
    fn backups_keep_the_newest_ten() {
        let t = spaced_tempdir();
        let saves = t.path().join("saves");
        put(&saves, "profile.sav", b"save");
        let backups = t.path().join("backups");
        let made: Vec<PathBuf> = (0..12).map(|_| backup_saves(&saves, &backups, 10).unwrap().unwrap()).collect();
        let left: Vec<PathBuf> = std::fs::read_dir(&backups).unwrap().map(|e| e.unwrap().path()).collect();
        assert_eq!(left.len(), 10);
        assert!(!made[0].exists() && !made[1].exists() && made[11].exists(), "made {made:?} left {left:?}");
        assert_eq!(std::fs::read(made[11].join("profile.sav")).unwrap(), b"save");
    }

    #[test]
    fn no_saves_folder_means_no_backup() {
        let t = spaced_tempdir();
        assert_eq!(backup_saves(&t.path().join("none"), &t.path().join("b"), 10).unwrap(), None);
    }
}
