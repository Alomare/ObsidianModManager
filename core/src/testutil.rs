//! Test helpers.

/// A temp folder whose name has a space and parentheses, like `Program Files (x86)`.
pub fn spaced_tempdir() -> tempfile::TempDir {
    tempfile::Builder::new().prefix("kepler test (x86) ").tempdir().unwrap()
}

/// Writes `data` to `root/rel`, creating parent folders.
pub fn put(root: &std::path::Path, rel: &str, data: &[u8]) {
    let p = root.join(rel);
    std::fs::create_dir_all(p.parent().unwrap()).unwrap();
    std::fs::write(p, data).unwrap();
}
