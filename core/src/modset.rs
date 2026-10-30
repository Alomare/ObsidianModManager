//! The mod-set hash (spec 6.2) and the matchmaking pool tags derived from the hash (spec 6.3).

use sha2::{Digest, Sha256};

/// A session-scope mod as the hash sees the mod: id, version and option values.
#[derive(Debug, Clone, PartialEq)]
pub struct SessionMod {
    pub id: String,
    pub version: semver::Version,
    /// (option id, value, marked `"scope": "client"`)
    pub options: Vec<(String, serde_json::Value, bool)>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PoolTags {
    pub identical: String,
}

fn sha256_hex(text: &str) -> String {
    Sha256::digest(text.as_bytes()).iter().map(|b| format!("{b:02x}")).collect()
}

/// SHA-256 over the sorted `id@version` lines, each followed by the sorted `;option=value` pairs
/// of every option not marked client scope.
pub fn modset_hash(mods: &[SessionMod]) -> String {
    let mut lines: Vec<String> = mods
        .iter()
        .map(|m| {
            let mut opts: Vec<String> = m.options.iter().filter(|(_, _, client)| !client).map(|(id, v, _)| format!(";{id}={v}")).collect();
            opts.sort();
            format!("{}@{}{}", m.id, m.version, opts.concat())
        })
        .collect();
    lines.sort();
    sha256_hex(&lines.join("\n"))
}

/// The tag appended to the vanilla build hash for players with session content: 12 lowercase hex digits.
pub fn pool_tags(modset: &str) -> PoolTags {
    PoolTags { identical: sha256_hex(&format!("obsidian:{modset}"))[..12].to_string() }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn m(id: &str, options: Vec<(&str, serde_json::Value, bool)>) -> SessionMod {
        SessionMod {
            id: id.into(),
            version: semver::Version::new(1, 0, 0),
            options: options.into_iter().map(|(a, b, c)| (a.to_string(), b, c)).collect(),
        }
    }

    #[test]
    fn modset_hash_ignores_order() {
        let a = m("a", vec![("x", json!(1), false), ("y", json!(true), false)]);
        let b = m("b", vec![]);
        let a2 = m("a", vec![("y", json!(true), false), ("x", json!(1), false)]);
        assert_eq!(modset_hash(&[a, b.clone()]), modset_hash(&[b, a2]));
    }

    #[test]
    fn session_option_changes_the_hash() {
        assert_ne!(modset_hash(&[m("a", vec![("x", json!(1), false)])]), modset_hash(&[m("a", vec![("x", json!(2), false)])]));
    }

    #[test]
    fn client_option_does_not_change_the_hash() {
        assert_eq!(modset_hash(&[m("a", vec![("cam", json!(1), true)])]), modset_hash(&[m("a", vec![("cam", json!(9), true)])]));
    }

    #[test]
    fn tags_are_12_lowercase_hex() {
        let t = pool_tags(&modset_hash(&[m("a", vec![])]));
        assert_eq!(t.identical.len(), 12);
        assert!(t.identical.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b)));
        assert_ne!(t.identical, pool_tags("other").identical);
    }
}
