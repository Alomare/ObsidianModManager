//! The mod library (`<data>/mods/<id>/`) and the load-order profile (the active one in `<data>/profiles/`).

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::manifest::{Manifest, load_manifest};
use crate::{ObsidianError, Result};

pub struct Library {
    root: PathBuf,
}

/// Where a legacy mod came from, kept as `import.json` in the mod folder.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ImportInfo {
    /// RFC 3339.
    pub date: String,
    /// The folder or file name the mod was imported from.
    pub file: String,
}

pub const IMPORT_INFO: &str = "import.json";

#[derive(Debug, Clone, PartialEq)]
pub enum InstallOutcome {
    Added,
    Replaced { old_version: semver::Version },
}

/// Copies a folder tree.
/// True when every file in `a` exists in `b` with the same bytes.
fn same_files(a: &Path, b: &Path) -> Result<bool> {
    if !b.is_dir() {
        return Ok(false);
    }
    for e in std::fs::read_dir(a)? {
        let e = e?;
        let other = b.join(e.file_name());
        let same = if e.file_type()?.is_dir() { same_files(&e.path(), &other)? } else { other.is_file() && std::fs::read(e.path())? == std::fs::read(&other)? };
        if !same {
            return Ok(false);
        }
    }
    Ok(true)
}

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
    /// Installs every bundled mod (a subfolder of `dir` with `obsidian.json`) that is missing or
    /// differs from the copy in the library. A new mod joins the profile switched off at sync.
    pub fn install_bundled(&self, dir: &Path) -> Result<()> {
        if !dir.is_dir() {
            return Ok(());
        }
        for e in std::fs::read_dir(dir)? {
            let src = e?.path();
            if !src.join(crate::manifest::FILE).is_file() {
                continue;
            }
            let id = crate::manifest::load_manifest(&src)?.id;
            if !same_files(&src, &self.mod_dir(&id))? {
                self.install(&src)?;
            }
        }
        Ok(())
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
        crate::manifest::forget(&target);
        Ok(outcome)
    }
    pub fn import_info(&self, id: &str) -> Option<ImportInfo> {
        let text = std::fs::read_to_string(self.mod_dir(id).join(IMPORT_INFO)).ok()?;
        serde_json::from_str(&text).ok()
    }
    /// Deletes a mod from the library. Profiles drop it at their next sync.
    pub fn remove(&self, id: &str) -> Result<()> {
        let dir = self.mod_dir(id);
        let m = load_manifest(&dir).map_err(|_| ObsidianError::ModMissing(id.to_string()))?;
        if m.is_bundled() {
            return Err(ObsidianError::BundledMod(id.to_string()));
        }
        crate::manifest::forget(&dir);
        std::fs::remove_dir_all(dir)?;
        Ok(())
    }
    pub fn list(&self) -> Result<Vec<Manifest>> {
        let mut out = Vec::new();
        for e in std::fs::read_dir(&self.root)? {
            let e = e?;
            let p = e.path();
            let tmp = p.extension().is_some_and(|x| x == "obsidian-tmp");
            if tmp || !e.file_type()?.is_dir() {
                continue;
            }
            match load_manifest(&p) {
                // A folder without a manifest is not a mod.
                Err(crate::ObsidianError::Io(e)) if e.kind() == std::io::ErrorKind::NotFound => {}
                m => out.push(m?),
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
    /// The folder the mod sits in, by folder id (`crate::folders`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub folder: Option<String>,
}

/// Load order: the list order, where the last enabled mod wins a conflict.
#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
pub struct Profile {
    pub mods: Vec<ProfileEntry>,
    /// "Allow session mods from other Obsidian users".
    #[serde(default)]
    pub consent: bool,
    /// Option values per mod id, as set by the player.
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub options: BTreeMap<String, BTreeMap<String, serde_json::Value>>,
    /// Keys per mod id and keybind id, as set by the player.
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub keys: BTreeMap<String, BTreeMap<String, String>>,
    /// Folders the player sorts mods into. They change nothing in the game.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub folders: Vec<crate::folders::Folder>,
}

impl Profile {
    /// The active profile.
    pub fn load(data_dir: &Path) -> Result<Profile> {
        Profile::load_named(data_dir, &crate::profiles::active(data_dir)?)
    }
    pub fn load_named(data_dir: &Path, name: &str) -> Result<Profile> {
        match std::fs::read_to_string(crate::profiles::path(data_dir, name)) {
            Ok(text) => Ok(serde_json::from_str(&text)?),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Profile::default()),
            Err(e) => Err(e.into()),
        }
    }
    /// Saves as the active profile.
    pub fn save(&self, data_dir: &Path) -> Result<()> {
        let path = crate::profiles::path(data_dir, &crate::profiles::active(data_dir)?);
        std::fs::create_dir_all(path.parent().expect("profiles folder"))?;
        std::fs::write(path, serde_json::to_string_pretty(self)? + "\n")?;
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
                self.mods.push(ProfileEntry { id, enabled: false, folder: None });
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
    fn remove_deletes_the_folder() {
        let t = spaced_tempdir();
        let lib = Library::open(&t.path().join("data")).unwrap();
        lib.install(&staged(t.path(), "a", "1.0.0")).unwrap();
        lib.remove("a").unwrap();
        assert!(lib.list().unwrap().is_empty());
        assert!(!lib.mod_dir("a").exists());
        assert!(matches!(lib.remove("a"), Err(ObsidianError::ModMissing(_))));
    }

    #[test]
    fn remove_refuses_bundled() {
        let t = spaced_tempdir();
        let lib = Library::open(&t.path().join("data")).unwrap();
        let d = t.path().join("stage-b");
        put(&d, "obsidian.json", br#"{"obsidian":1,"id":"b","version":"1.0.0","name":{"en":"b"},"bundled":true}"#);
        lib.install(&d).unwrap();
        assert!(matches!(lib.remove("b"), Err(ObsidianError::BundledMod(_))));
        assert!(lib.mod_dir("b").exists());
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
