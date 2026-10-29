//! The mod library (`<data>/mods/<id>/`) and the load-order profile (`<data>/profile.json`).

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::manifest::{Manifest, load_manifest};
use crate::{ObsidianError, Result};

const PROFILE: &str = "profile.json";

pub struct Library {
    root: PathBuf,
}

#[derive(Debug, Clone, PartialEq)]
pub enum InstallOutcome {
    Added,
    Replaced { old_version: semver::Version },
}

/// Copies a folder tree.
pub(crate) fn copy_dir(from: &Path, to: &Path) -> Result<()> {
    std::fs::create_dir_all(to)?;
    for e in std::fs::read_dir(from)? {
        let e = e?;
        let target = to.join(e.file_name());
        if e.file_type()?.is_dir() {
            copy_dir(&e.path(), &target)?;
        } else {
            std::fs::copy(e.path(), target)?;
        }
    }
    Ok(())
}

impl Library {
    pub fn open(data_dir: &Path) -> Result<Library> {
        let root = data_dir.join("mods");
        std::fs::create_dir_all(&root)?;
        Ok(Library { root })
    }
    pub fn mod_dir(&self, id: &str) -> PathBuf {
        self.root.join(id)
    }
    /// Copies a staged folder holding `obsidian.json` into `mods/<id>`, replacing an older copy.
    pub fn install(&self, staged: &Path) -> Result<InstallOutcome> {
        let m = load_manifest(staged)?;
        let target = self.mod_dir(&m.id);
        let tmp = self.root.join(format!("{}.obsidian-tmp", m.id));
        if tmp.exists() {
            std::fs::remove_dir_all(&tmp)?;
        }
        copy_dir(staged, &tmp)?;
        let outcome = match load_manifest(&target) {
            Ok(old) => InstallOutcome::Replaced { old_version: old.version },
            Err(_) => InstallOutcome::Added,
        };
        if target.exists() {
            std::fs::remove_dir_all(&target)?;
        }
        std::fs::rename(&tmp, &target)?;
        Ok(outcome)
    }
    pub fn list(&self) -> Result<Vec<Manifest>> {
        let mut out = Vec::new();
        for e in std::fs::read_dir(&self.root)? {
            let p = e?.path();
            let tmp = p.extension().is_some_and(|x| x == "obsidian-tmp");
            if !tmp && p.is_dir() && p.join(crate::manifest::FILE).is_file() {
                out.push(load_manifest(&p)?);
            }
        }
        out.sort_by(|a, b| a.id.cmp(&b.id));
        Ok(out)
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProfileEntry {
    pub id: String,
    pub enabled: bool,
}

/// Load order: the list order, where the last enabled mod wins a conflict.
#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
pub struct Profile {
    pub mods: Vec<ProfileEntry>,
    /// Built-in features switched on (skip_intro, skip_login, skip_war_briefs).
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub features: Vec<String>,
    /// "Allow session mods from other Obsidian users".
    #[serde(default)]
    pub consent: bool,
    /// Option values per mod id, as set by the player.
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub options: BTreeMap<String, BTreeMap<String, serde_json::Value>>,
}

impl Profile {
    pub fn load(data_dir: &Path) -> Result<Profile> {
        match std::fs::read_to_string(data_dir.join(PROFILE)) {
            Ok(text) => Ok(serde_json::from_str(&text)?),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Profile::default()),
            Err(e) => Err(e.into()),
        }
    }
    pub fn save(&self, data_dir: &Path) -> Result<()> {
        std::fs::create_dir_all(data_dir)?;
        std::fs::write(data_dir.join(PROFILE), serde_json::to_string_pretty(self)? + "\n")?;
        Ok(())
    }
    /// Puts `ids` first, in that order; mods not named keep their order after them.
    pub fn set_order(&mut self, ids: &[String]) {
        let mut first: Vec<ProfileEntry> = ids.iter().filter_map(|id| self.mods.iter().find(|m| &m.id == id).cloned()).collect();
        first.extend(self.mods.iter().filter(|m| !ids.contains(&m.id)).cloned());
        self.mods = first;
    }
    pub fn set_enabled(&mut self, id: &str, on: bool) -> Result<()> {
        let entry = self.mods.iter_mut().find(|m| m.id == id).ok_or_else(|| ObsidianError::ModMissing(id.to_string()))?;
        entry.enabled = on;
        Ok(())
    }
    /// Appends newly installed mods as disabled and drops entries whose mod is gone.
    pub fn sync(&mut self, lib: &Library) -> Result<()> {
        let installed: Vec<String> = lib.list()?.into_iter().map(|m| m.id).collect();
        self.mods.retain(|m| installed.contains(&m.id));
        for id in installed {
            if !self.mods.iter().any(|m| m.id == id) {
                self.mods.push(ProfileEntry { id, enabled: false });
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testutil::{put, spaced_tempdir};

    fn staged(root: &Path, id: &str, version: &str) -> PathBuf {
        let d = root.join(format!("stage-{id}-{version}"));
        let json = format!(r#"{{"obsidian":1,"id":"{id}","version":"{version}","name":{{"en":"{id}"}}}}"#);
        put(&d, "obsidian.json", json.as_bytes());
        d
    }

    #[test]
    fn install_then_list_and_replace() {
        let t = spaced_tempdir();
        let lib = Library::open(&t.path().join("data")).unwrap();
        assert_eq!(lib.install(&staged(t.path(), "a", "1.0.0")).unwrap(), InstallOutcome::Added);
        assert_eq!(lib.list().unwrap()[0].id, "a");
        let again = lib.install(&staged(t.path(), "a", "2.0.0")).unwrap();
        assert_eq!(again, InstallOutcome::Replaced { old_version: semver::Version::new(1, 0, 0) });
        assert_eq!(lib.list().unwrap()[0].version, semver::Version::new(2, 0, 0));
    }

    #[test]
    fn profile_syncs_orders_and_persists() {
        let t = spaced_tempdir();
        let data = t.path().join("data");
        let lib = Library::open(&data).unwrap();
        for id in ["a", "b", "c"] {
            lib.install(&staged(t.path(), id, "1.0.0")).unwrap();
        }
        let mut p = Profile::load(&data).unwrap();
        p.sync(&lib).unwrap();
        assert_eq!(p.mods.iter().map(|m| (m.id.as_str(), m.enabled)).collect::<Vec<_>>(), [("a", false), ("b", false), ("c", false)]);
        p.set_order(&["c".into(), "a".into()]);
        p.set_enabled("a", true).unwrap();
        assert_eq!(p.mods.iter().map(|m| m.id.as_str()).collect::<Vec<_>>(), ["c", "a", "b"]);
        p.save(&data).unwrap();
        assert_eq!(Profile::load(&data).unwrap(), p);
        assert!(p.set_enabled("zzz", true).is_err());
    }

    #[test]
    fn data_dir_prefers_the_explicit_path() {
        let t = spaced_tempdir();
        assert_eq!(crate::paths::data_dir(Some(t.path())), t.path());
    }
}
