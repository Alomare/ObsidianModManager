//! `obsidian.json`: what a mod is and which game resources it changes.

use std::collections::BTreeMap;
use std::path::{Component, Path, PathBuf};

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::hash::parse_ref;
use crate::{ObsidianError, Result};

pub const FILE: &str = "obsidian.json";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Scope {
    Client,
    /// Anything that may change the shared game. Missing or unknown scopes count as session.
    #[default]
    Session,
}

impl Serialize for Scope {
    fn serialize<S: serde::Serializer>(&self, s: S) -> std::result::Result<S::Ok, S::Error> {
        s.serialize_str(match self {
            Scope::Client => "client",
            Scope::Session => "session",
        })
    }
}

impl<'de> Deserialize<'de> for Scope {
    fn deserialize<D: serde::Deserializer<'de>>(d: D) -> std::result::Result<Self, D::Error> {
        let v = Value::deserialize(d)?;
        Ok(if v.as_str() == Some("client") { Scope::Client } else { Scope::Session })
    }
}

pub type Localized = BTreeMap<String, String>;

#[derive(Debug, Clone, PartialEq)]
pub enum Payload {
    Source(PathBuf),
    Bytecode(PathBuf),
    Data(PathBuf),
}

impl Payload {
    pub fn path(&self) -> &Path {
        match self {
            Payload::Source(p) | Payload::Bytecode(p) | Payload::Data(p) => p,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(try_from = "RawResource", into = "RawResource")]
pub struct ResourceSpec {
    pub type_text: String,
    pub name_text: String,
    pub type_hash: u64,
    pub name_hash: u64,
    pub bundle: Option<String>,
    pub flags: u32,
    pub payload: Payload,
}

impl ResourceSpec {
    pub fn data_path(&self) -> &Path {
        self.payload.path()
    }
}

#[derive(Serialize, Deserialize)]
struct RawResource {
    #[serde(rename = "type")]
    type_: String,
    name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    bundle: Option<String>,
    #[serde(default, skip_serializing_if = "is_zero")]
    flags: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    source: Option<PathBuf>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    bytecode: Option<PathBuf>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    data: Option<PathBuf>,
}

fn is_zero(v: &u32) -> bool {
    *v == 0
}

impl TryFrom<RawResource> for ResourceSpec {
    type Error = String;
    fn try_from(r: RawResource) -> std::result::Result<Self, String> {
        let payload = match (r.source, r.bytecode, r.data) {
            (Some(p), None, None) => Payload::Source(p),
            (None, Some(p), None) => Payload::Bytecode(p),
            (None, None, Some(p)) => Payload::Data(p),
            _ => return Err("needs exactly one of source, bytecode or data".into()),
        };
        Ok(ResourceSpec {
            type_hash: parse_ref(&r.type_).map_err(|e| e.to_string())?,
            name_hash: parse_ref(&r.name).map_err(|e| e.to_string())?,
            type_text: r.type_,
            name_text: r.name,
            bundle: r.bundle,
            flags: r.flags,
            payload,
        })
    }
}

impl From<ResourceSpec> for RawResource {
    fn from(s: ResourceSpec) -> Self {
        let (mut source, mut bytecode, mut data) = (None, None, None);
        match s.payload {
            Payload::Source(p) => source = Some(p),
            Payload::Bytecode(p) => bytecode = Some(p),
            Payload::Data(p) => data = Some(p),
        }
        RawResource { type_: s.type_text, name: s.name_text, bundle: s.bundle, flags: s.flags, source, bytecode, data }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Manifest {
    pub obsidian: u32,
    pub id: String,
    pub version: semver::Version,
    pub name: Localized,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<Localized>,
    #[serde(default)]
    pub authors: Vec<String>,
    #[serde(default)]
    pub scope: Scope,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub entry: Option<PathBuf>,
    #[serde(default)]
    pub resources: Vec<ResourceSpec>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub options: Vec<Value>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub keybinds: Vec<Value>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub requires: Vec<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub conflicts: Vec<String>,
    #[serde(default = "one")]
    pub loader_api: u32,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

fn one() -> u32 {
    1
}

fn bad(field: impl Into<String>, reason: impl Into<String>) -> ObsidianError {
    ObsidianError::BadManifest { field: field.into(), reason: reason.into() }
}

fn is_hex16(s: &str) -> bool {
    s.len() == 16 && s.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

fn valid_id(id: &str) -> bool {
    let b = id.as_bytes();
    !b.is_empty()
        && b.len() <= 64
        && (b[0].is_ascii_lowercase() || b[0].is_ascii_digit())
        && b.iter().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || b"._-".contains(c))
}

/// A relative path that stays inside the mod folder and names an existing file.
fn check_path(mod_dir: &Path, p: &Path, field: &str) -> Result<()> {
    if !p.components().all(|c| matches!(c, Component::Normal(_) | Component::CurDir)) {
        return Err(bad(field, format!("{} must be a path inside the mod folder", p.display())));
    }
    if !mod_dir.join(p).is_file() {
        return Err(bad(field, format!("{} does not exist", p.display())));
    }
    Ok(())
}

impl Manifest {
    pub fn validate(&self, mod_dir: &Path) -> Result<()> {
        if self.obsidian != 1 {
            return Err(bad("obsidian", "only version 1 is supported"));
        }
        if !valid_id(&self.id) {
            return Err(bad("id", "use 1 to 64 of a-z, 0-9, '.', '_' or '-', starting with a letter or digit"));
        }
        if !self.name.contains_key("en") {
            return Err(bad("name.en", "an English name is required"));
        }
        if let Some(entry) = &self.entry {
            check_path(mod_dir, entry, "entry")?;
        }
        for (i, r) in self.resources.iter().enumerate() {
            let field = format!("resources[{i}]");
            if r.bundle.as_deref().is_some_and(|b| !is_hex16(b)) {
                return Err(bad(field, "bundle must be 16 lowercase hex digits"));
            }
            check_path(mod_dir, r.data_path(), &field)?;
        }
        Ok(())
    }
}

pub fn load_manifest(mod_dir: &Path) -> Result<Manifest> {
    let text = std::fs::read_to_string(mod_dir.join(FILE))?;
    let mut v: Value = serde_json::from_str(&text).map_err(|e| bad(FILE, e.to_string()))?;
    let raw = v.as_object_mut().ok_or_else(|| bad(FILE, "must be a JSON object"))?.remove("resources");
    let resources = match raw {
        None => Vec::new(),
        Some(Value::Array(items)) => items
            .into_iter()
            .enumerate()
            .map(|(i, r)| serde_json::from_value(r).map_err(|e| bad(format!("resources[{i}]"), e.to_string())))
            .collect::<Result<Vec<ResourceSpec>>>()?,
        Some(_) => return Err(bad("resources", "must be a list")),
    };
    let mut m: Manifest = serde_json::from_value(v).map_err(|e| bad(FILE, e.to_string()))?;
    m.resources = resources;
    m.validate(mod_dir)?;
    Ok(m)
}

pub fn write_manifest(mod_dir: &Path, m: &Manifest) -> Result<()> {
    std::fs::write(mod_dir.join(FILE), serde_json::to_string_pretty(m)? + "\n")?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testutil::{put, spaced_tempdir};

    const EXAMPLE: &str = r#"{
      "obsidian": 1, "id": "author.short-name", "version": "1.0.0",
      "name": { "en": "Example", "pt-BR": "Exemplo" }, "description": { "en": "x" },
      "authors": ["Author"], "scope": "client", "entry": "src/main.lua",
      "resources": [
        { "type": "lua", "name": "lua/settings/perk_settings", "source": "res/perk_settings.lua" },
        { "type": "texture", "name": "units/foo/bar", "bundle": "ebbaccd983625dde", "data": "res/bar.texture" }
      ],
      "options": [ { "id": "distance", "type": "number", "default": 5 } ],
      "keybinds": [ { "id": "toggle", "default": "f8" } ],
      "requires": [], "conflicts": [], "loader_api": 1, "homepage": "https://example.org"
    }"#;

    fn mod_with(json: &str) -> tempfile::TempDir {
        let d = spaced_tempdir();
        put(d.path(), FILE, json.as_bytes());
        for f in ["src/main.lua", "res/perk_settings.lua", "res/bar.texture"] {
            put(d.path(), f, b"x");
        }
        d
    }

    fn field_of(r: Result<Manifest>) -> String {
        match r {
            Err(ObsidianError::BadManifest { field, .. }) => field,
            other => panic!("expected BadManifest, got {other:?}"),
        }
    }

    #[test]
    fn spec_example_parses() {
        let m = load_manifest(mod_with(EXAMPLE).path()).unwrap();
        assert_eq!(m.scope, Scope::Client);
        assert_eq!(m.resources.len(), 2);
        assert_eq!(m.resources[0].type_hash, 0xa14e8dfa2cd117e2);
    }

    #[test]
    fn unknown_or_missing_scope_is_session() {
        let weird = EXAMPLE.replace(r#""scope": "client""#, r#""scope": "weird""#);
        assert_eq!(load_manifest(mod_with(&weird).path()).unwrap().scope, Scope::Session);
        let missing = EXAMPLE.replace(r#""scope": "client","#, "");
        assert_eq!(load_manifest(mod_with(&missing).path()).unwrap().scope, Scope::Session);
    }

    #[test]
    fn two_payloads_are_rejected() {
        let both = EXAMPLE.replace(r#""source": "res/perk_settings.lua""#, r#""source": "res/perk_settings.lua", "data": "res/bar.texture""#);
        assert_eq!(field_of(load_manifest(mod_with(&both).path())), "resources[0]");
    }

    #[test]
    fn english_name_is_required() {
        let no_en = EXAMPLE.replace(r#""en": "Example", "#, "");
        assert_eq!(field_of(load_manifest(mod_with(&no_en).path())), "name.en");
    }

    #[test]
    fn payload_outside_the_mod_is_rejected() {
        let out = EXAMPLE.replace("res/bar.texture", "../x");
        assert_eq!(field_of(load_manifest(mod_with(&out).path())), "resources[1]");
    }

    #[test]
    fn unknown_fields_survive_a_round_trip() {
        let d = mod_with(EXAMPLE);
        let m = load_manifest(d.path()).unwrap();
        write_manifest(d.path(), &m).unwrap();
        let again = load_manifest(d.path()).unwrap();
        assert_eq!(again.extra.get("homepage").and_then(Value::as_str), Some("https://example.org"));
        assert_eq!(again, m);
    }
}
