//! Square images for mods and profiles. A mod can name one in its manifest (`"image": "image.png"`,
//! inside the mod folder); the player can set their own for any mod or profile, kept in
//! `<data>/images/mods/<id>.<ext>` and `<data>/images/profiles/<name>.<ext>`. The player's image
//! comes first.

use std::path::{Path, PathBuf};

use crate::library::Library;
use crate::manifest::Manifest;
use crate::{ObsidianError, Result};

pub const TYPES: [&str; 4] = ["png", "jpg", "jpeg", "webp"];
pub const MAX_BYTES: u64 = 4 * 1024 * 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Owner {
    Mod,
    Profile,
}

fn dir(data: &Path, owner: Owner) -> PathBuf {
    data.join("images").join(match owner {
        Owner::Mod => "mods",
        Owner::Profile => "profiles",
    })
}

fn allowed(p: &Path) -> bool {
    p.extension().and_then(|e| e.to_str()).is_some_and(|e| TYPES.contains(&e.to_ascii_lowercase().as_str()))
}

/// The player's image for a mod or profile, if they set one.
pub fn custom(data: &Path, owner: Owner, key: &str) -> Option<PathBuf> {
    TYPES.iter().map(|ext| dir(data, owner).join(format!("{key}.{ext}"))).find(|p| p.is_file())
}

/// Every player image of one kind, by mod id or profile name, from one folder listing.
pub fn all_custom(data: &Path, owner: Owner) -> std::collections::HashMap<String, PathBuf> {
    let mut out = std::collections::HashMap::new();
    for e in std::fs::read_dir(dir(data, owner)).into_iter().flatten().flatten() {
        let p = e.path();
        if allowed(&p)
            && let Some(key) = p.file_stem().and_then(|s| s.to_str())
        {
            out.insert(key.to_string(), p);
        }
    }
    out
}

/// The image a mod's manifest names, if that file is an image inside the mod folder.
pub fn from_manifest(lib: &Library, m: &Manifest) -> Option<PathBuf> {
    let name = m.extra.get("image")?.as_str()?;
    let root = std::fs::canonicalize(lib.mod_dir(&m.id)).ok()?;
    let p = std::fs::canonicalize(root.join(name)).ok()?;
    (p.starts_with(&root) && p.is_file() && allowed(&p)).then_some(p)
}

/// The image a mod shows: the player's, else the one its manifest names.
pub fn for_mod(data: &Path, lib: &Library, m: &Manifest) -> Option<PathBuf> {
    custom(data, Owner::Mod, &m.id).or_else(|| from_manifest(lib, m))
}

/// Sets the player's image from `from` (a copy is kept), or removes it with `None`.
pub fn set(data: &Path, owner: Owner, key: &str, from: Option<&Path>) -> Result<()> {
    if let Some(src) = from {
        let size = std::fs::metadata(src)?.len();
        if !allowed(src) || size > MAX_BYTES {
            return Err(ObsidianError::BadImage(src.display().to_string()));
        }
    }
    remove(data, owner, key)?;
    if let Some(src) = from {
        let ext = src.extension().and_then(|e| e.to_str()).unwrap_or("png").to_ascii_lowercase();
        std::fs::create_dir_all(dir(data, owner))?;
        std::fs::copy(src, dir(data, owner).join(format!("{key}.{ext}")))?;
    }
    Ok(())
}

pub fn remove(data: &Path, owner: Owner, key: &str) -> Result<()> {
    while let Some(p) = custom(data, owner, key) {
        std::fs::remove_file(p)?;
    }
    Ok(())
}

/// Keeps a profile's image when the profile is renamed.
pub fn rename(data: &Path, owner: Owner, from: &str, to: &str) -> Result<()> {
    if let Some(p) = custom(data, owner, from) {
        let ext = p.extension().map(|e| e.to_string_lossy().into_owned()).unwrap_or_default();
        std::fs::rename(&p, dir(data, owner).join(format!("{to}.{ext}")))?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testutil::{put, spaced_tempdir};

    #[test]
    fn player_images_are_copied_replaced_renamed_and_removed() {
        let t = spaced_tempdir();
        let data = t.path().join("data");
        put(t.path(), "a.PNG", b"png");
        put(t.path(), "b.webp", b"webp");
        set(&data, Owner::Profile, "Main", Some(&t.path().join("a.PNG"))).unwrap();
        assert_eq!(custom(&data, Owner::Profile, "Main"), Some(data.join("images/profiles/Main.png")));
        set(&data, Owner::Profile, "Main", Some(&t.path().join("b.webp"))).unwrap();
        assert_eq!(custom(&data, Owner::Profile, "Main"), Some(data.join("images/profiles/Main.webp")), "one image per owner");
        rename(&data, Owner::Profile, "Main", "Other").unwrap();
        assert_eq!(custom(&data, Owner::Profile, "Main"), None);
        assert!(custom(&data, Owner::Profile, "Other").is_some());
        set(&data, Owner::Profile, "Other", None).unwrap();
        assert_eq!(custom(&data, Owner::Profile, "Other"), None);
    }

    #[test]
    fn other_files_are_refused() {
        let t = spaced_tempdir();
        put(t.path(), "a.exe", b"x");
        assert!(matches!(set(t.path(), Owner::Mod, "m", Some(&t.path().join("a.exe"))), Err(ObsidianError::BadImage(_))));
        let big = t.path().join("big.png");
        std::fs::File::create(&big).unwrap().set_len(MAX_BYTES + 1).unwrap();
        assert!(matches!(set(t.path(), Owner::Mod, "m", Some(&big)), Err(ObsidianError::BadImage(_))));
    }

    #[test]
    fn a_mod_shows_the_player_image_then_its_own_inside_its_folder() {
        let t = spaced_tempdir();
        let data = t.path().join("data");
        let lib = Library::open(&data).unwrap();
        let json = |image: &str| format!(r#"{{"obsidian":1,"id":"a.b","version":"1.0.0","name":{{"en":"a"}},"image":"{image}"}}"#);
        let mut m: Manifest = serde_json::from_str(&json("art/icon.png")).unwrap();
        assert_eq!(for_mod(&data, &lib, &m), None, "the file is missing");
        put(&lib.mod_dir("a.b").join("art"), "icon.png", b"png");
        assert!(for_mod(&data, &lib, &m).unwrap().ends_with("icon.png"));
        put(&data, "secret.png", b"png");
        m = serde_json::from_str(&json("../../secret.png")).unwrap();
        assert_eq!(for_mod(&data, &lib, &m), None, "outside the mod folder");
        put(t.path(), "mine.jpg", b"jpg");
        set(&data, Owner::Mod, "a.b", Some(&t.path().join("mine.jpg"))).unwrap();
        assert!(for_mod(&data, &lib, &m).unwrap().ends_with("a.b.jpg"));
    }
}
