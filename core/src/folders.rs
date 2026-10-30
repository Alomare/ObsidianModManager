//! Folders in a profile: a name and a colour for a run of mods in the load order. The mods of a
//! folder always sit together, at the place of the first one; an empty folder has no place in the
//! load order and the app shows it last.

use serde::{Deserialize, Serialize};

use crate::library::Profile;

/// The folder that holds the bundled mods: always first, never renamed, moved or deleted, and only
/// bundled mods go in.
pub const LOCKED: &str = "obsidian";

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Folder {
    pub id: String,
    pub name: String,
    /// A CSS colour, such as `#e8b931`.
    pub color: String,
    #[serde(default)]
    pub collapsed: bool,
    /// A locked folder keeps the name, colour, place and mods it has until it is unlocked. The
    /// Obsidian folder is always locked.
    #[serde(default)]
    pub locked: bool,
}

impl Profile {
    /// Puts `bundled` first, in the locked folder (made when missing), and every other mod out of it.
    pub fn pin_bundled(&mut self, bundled: &[&str]) {
        self.folders.retain(|f| f.id != LOCKED || !bundled.is_empty());
        if !bundled.is_empty() && !self.folders.iter().any(|f| f.id == LOCKED) {
            self.folders.insert(0, Folder { id: LOCKED.into(), name: "Obsidian".into(), color: "#f0b429".into(), collapsed: false, locked: true });
        }
        for e in &mut self.mods {
            let pinned = bundled.contains(&e.id.as_str());
            if pinned {
                e.folder = Some(LOCKED.into());
            } else if e.folder.as_deref() == Some(LOCKED) {
                e.folder = None;
            }
        }
        // Stable: the bundled mods keep their order among themselves, and so do the others.
        self.mods.sort_by_key(|e| e.folder.as_deref() != Some(LOCKED));
        self.tidy_folders();
    }

    /// Puts the mods in `ids` order (as `set_order`), moves each `(mod, folder)` in `moves` into
    /// that folder (or out of any with `None`), then keeps every folder together.
    pub fn arrange(&mut self, ids: &[String], moves: &[(String, Option<String>)]) {
        self.set_order(ids);
        for (id, folder) in moves {
            if let Some(e) = self.mods.iter_mut().find(|m| &m.id == id) {
                e.folder = folder.clone();
            }
        }
        self.tidy_folders();
    }

    /// Drops folder marks that name no folder, then gathers each folder's mods at the place of
    /// the first one, keeping their order.
    pub fn tidy_folders(&mut self) {
        for e in &mut self.mods {
            if e.folder.as_ref().is_some_and(|f| !self.folders.iter().any(|x| &x.id == f)) {
                e.folder = None;
            }
        }
        let mut out = Vec::with_capacity(self.mods.len());
        let mut done: Vec<&str> = Vec::new();
        for e in &self.mods {
            match &e.folder {
                None => out.push(e.clone()),
                Some(f) if !done.contains(&f.as_str()) => {
                    done.push(f);
                    out.extend(self.mods.iter().filter(|m| m.folder.as_ref() == Some(f)).cloned());
                }
                Some(_) => {}
            }
        }
        self.mods = out;
    }

    /// A new folder holding `ids` (maybe none), at the place of the first of them. Returns the id.
    pub fn create_folder(&mut self, name: &str, color: &str, ids: &[String]) -> String {
        let n = self.folders.iter().filter_map(|f| f.id.strip_prefix('f')?.parse::<u32>().ok()).max().unwrap_or(0) + 1;
        let id = format!("f{n}");
        self.folders.push(Folder { id: id.clone(), name: name.to_string(), color: color.to_string(), collapsed: false, locked: false });
        for e in self.mods.iter_mut().filter(|m| ids.contains(&m.id)) {
            e.folder = Some(id.clone());
        }
        self.tidy_folders();
        id
    }

    /// Changes what is given; `None` keeps the current value. A locked folder takes only a new
    /// collapsed state, or being unlocked (never the Obsidian folder).
    pub fn edit_folder(&mut self, id: &str, name: Option<&str>, color: Option<&str>, collapsed: Option<bool>, locked: Option<bool>) -> crate::Result<()> {
        let f = self.folders.iter_mut().find(|f| f.id == id).ok_or_else(|| crate::ObsidianError::ModMissing(id.to_string()))?;
        if id == LOCKED && locked == Some(false) {
            return Err(crate::ObsidianError::LockedFolder);
        }
        if let Some(l) = locked {
            f.locked = l;
        }
        if f.locked && (name.is_some() || color.is_some()) {
            return Err(crate::ObsidianError::LockedFolder);
        }
        if let Some(n) = name {
            f.name = n.to_string();
        }
        if let Some(c) = color {
            f.color = c.to_string();
        }
        if let Some(c) = collapsed {
            f.collapsed = c;
        }
        Ok(())
    }

    /// Deletes a folder; the mods in it stay where they are, outside any folder. Returns their ids.
    /// A locked folder stays.
    pub fn delete_folder(&mut self, id: &str) -> Vec<String> {
        if self.folders.iter().any(|f| f.id == id && f.locked) {
            return Vec::new();
        }
        self.folders.retain(|f| f.id != id);
        let mut members = Vec::new();
        for e in self.mods.iter_mut().filter(|m| m.folder.as_deref() == Some(id)) {
            e.folder = None;
            members.push(e.id.clone());
        }
        members
    }
}

#[cfg(test)]
mod tests {
    use crate::library::{Profile, ProfileEntry};

    fn profile(ids: &[&str]) -> Profile {
        Profile { mods: ids.iter().map(|id| ProfileEntry { id: id.to_string(), enabled: true, folder: None }).collect(), ..Default::default() }
    }
    fn order(p: &Profile) -> Vec<&str> {
        p.mods.iter().map(|m| m.id.as_str()).collect()
    }
    fn s(ids: &[&str]) -> Vec<String> {
        ids.iter().map(|x| x.to_string()).collect()
    }

    #[test]
    fn a_folder_gathers_its_mods_at_the_first_one() {
        let mut p = profile(&["a", "b", "c", "d"]);
        let f = p.create_folder("Weapons", "#e8b931", &s(&["b", "d"]));
        assert_eq!(f, "f1");
        assert_eq!(order(&p), ["a", "b", "d", "c"]);
        assert_eq!(p.create_folder("Empty", "#fff", &[]), "f2");
    }

    #[test]
    fn arrange_moves_mods_in_and_out_and_keeps_folders_whole() {
        let mut p = profile(&["a", "b", "c", "d"]);
        p.create_folder("F", "#fff", &s(&["a", "b"]));
        // "d" dropped between "a" and "b", into the folder.
        p.arrange(&s(&["a", "d", "b", "c"]), &[("d".into(), Some("f1".into()))]);
        assert_eq!(order(&p), ["a", "d", "b", "c"]);
        assert!(p.mods.iter().take(3).all(|m| m.folder.as_deref() == Some("f1")));
        // "c" dragged into the middle of the folder without joining it ends up after the folder.
        p.arrange(&s(&["a", "c", "d", "b"]), &[]);
        assert_eq!(order(&p), ["a", "d", "b", "c"]);
        // "a" taken out.
        p.arrange(&s(&["d", "b", "a", "c"]), &[("a".into(), None)]);
        assert_eq!(order(&p), ["d", "b", "a", "c"]);
        assert_eq!(p.mods[2].folder, None);
    }

    #[test]
    fn deleting_a_folder_frees_the_mods_in_place() {
        let mut p = profile(&["a", "b", "c"]);
        p.create_folder("F", "#fff", &s(&["b", "c"]));
        p.edit_folder("f1", Some("G"), None, Some(true), None).unwrap();
        assert_eq!((p.folders[0].name.as_str(), p.folders[0].collapsed), ("G", true));
        p.edit_folder("f1", None, None, None, Some(true)).unwrap();
        assert!(p.edit_folder("f1", Some("H"), None, None, None).is_err(), "locked");
        assert!(p.delete_folder("f1").is_empty() && p.folders.len() == 1, "a locked folder stays");
        p.edit_folder("f1", None, None, None, Some(false)).unwrap();
        assert_eq!(p.delete_folder("f1"), s(&["b", "c"]));
        assert_eq!(order(&p), ["a", "b", "c"]);
        assert!(p.folders.is_empty() && p.mods.iter().all(|m| m.folder.is_none()));
    }

    #[test]
    fn bundled_mods_stay_first_in_the_locked_folder() {
        let mut p = profile(&["a", "qol", "b"]);
        p.mods[0].folder = Some(super::LOCKED.into());
        p.pin_bundled(&["qol"]);
        assert_eq!(order(&p), ["qol", "a", "b"]);
        assert_eq!(p.folders[0].id, super::LOCKED);
        assert_eq!(p.mods[1].folder, None, "only bundled mods go in");
        assert!(p.edit_folder(super::LOCKED, Some("Mine"), None, None, None).is_err());
        assert!(p.edit_folder(super::LOCKED, None, None, None, Some(false)).is_err(), "never unlocked");
        p.edit_folder(super::LOCKED, None, None, Some(true), None).unwrap();
        assert!(p.delete_folder(super::LOCKED).is_empty() && p.folders.len() == 1);
        p.arrange(&s(&["a", "qol", "b"]), &[]);
        p.pin_bundled(&["qol"]);
        assert_eq!(order(&p), ["qol", "a", "b"]);
        p.pin_bundled(&[]);
        assert!(p.folders.is_empty());
    }

    #[test]
    fn a_profile_without_folders_reads_as_before() {
        let p: Profile = serde_json::from_str(r#"{"mods":[{"id":"a","enabled":true}]}"#).unwrap();
        assert_eq!(p.mods[0].folder, None);
        assert!(!serde_json::to_string(&p).unwrap().contains("folder"));
    }
}
