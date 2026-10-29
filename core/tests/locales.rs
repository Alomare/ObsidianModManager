//! Every catalog in `locales/` has the keys of `en.json`, with the same `%s` placeholders.

use std::collections::BTreeMap;
use std::path::PathBuf;

const LANGUAGES: [&str; 4] = ["en", "fr", "es", "pt-BR"];
const LOADER_KEYS: [&str; 4] = ["mod_failed", "build_unknown", "session_not_cleared", "uploads_blocked"];

fn catalog(lang: &str) -> BTreeMap<String, String> {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../locales").join(format!("{lang}.json"));
    let text = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
    serde_json::from_str(&text).unwrap_or_else(|e| panic!("{}: {e}", path.display()))
}

#[test]
fn catalogs_have_the_same_keys_and_placeholders() {
    let en = catalog("en");
    for key in LOADER_KEYS {
        assert!(en.contains_key(key), "en lacks {key}");
    }
    for lang in LANGUAGES {
        let other = catalog(lang);
        assert_eq!(other.keys().collect::<Vec<_>>(), en.keys().collect::<Vec<_>>(), "{lang} keys");
        for (key, text) in &en {
            assert_eq!(other[key].matches("%s").count(), text.matches("%s").count(), "{lang} {key} placeholders");
        }
    }
}
