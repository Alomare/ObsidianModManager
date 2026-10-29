//! Obsidian Loader as patch resources: the loader modules, every mod entry and the deploy table,
//! all compiled for the boot bundle, plus the settings file the loader reads at launch.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use serde_json::{Map, Value, json};

use crate::compose::{Composition, Planned};
use crate::hash::hash_name;
use crate::library::{Library, Profile};
use crate::lua::{check_bytecode, unwrap_resource, wrap_resource};
use crate::luajit::compile;
use crate::manifest::{Scope, load_manifest};
use crate::modset::{SessionMod, modset_hash, pool_tags};
use crate::options::{effective_values, value_text};
use crate::settings::Settings;
use crate::{ObsidianError, Result};

/// The boot bundle, which holds `foundation/lua/build_date_information`.
pub const BUNDLE: &str = "9cf71054ea26dddf";
/// The vanilla chunk the game requires at boot; the loader takes the chunk's place.
pub const ENTRY: &str = "foundation/lua/build_date_information";
/// The start of `BUILD_REVISION_INFORMATION` on the supported build.
pub const REVISION: &str = "parent: 32148:3bd83d77c8ae";
const LANGUAGES: [&str; 4] = ["en", "fr", "es", "pt-BR"];

/// `rel` beside the exe, then in this workspace.
fn candidates(rel: &str) -> Vec<PathBuf> {
    let mut out = Vec::new();
    if let Some(dir) = std::env::current_exe().ok().and_then(|e| e.parent().map(Path::to_path_buf)) {
        out.push(dir.join(rel));
    }
    out.push(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("..").join(rel));
    out
}

/// The bundled mods folder (`bundled/` beside the exe, then in this workspace), if there is one.
pub fn find_bundled_dir() -> Option<PathBuf> {
    candidates("bundled").into_iter().find(|d| d.is_dir())
}

/// `loader/src` beside the exe, then the one in this workspace.
pub fn find_loader_dir() -> Result<PathBuf> {
    let candidates = candidates("loader/src");
    candidates.iter().find(|d| d.join("boot.lua").is_file()).cloned().ok_or_else(|| {
        ObsidianError::LoaderMissing(candidates.iter().map(|d| d.display().to_string()).collect::<Vec<_>>().join(", "))
    })
}

/// The loader goes into the game whenever a mod is on or consent is on.
pub fn needed(comp: &Composition, profile: &Profile) -> bool {
    !comp.mods.is_empty() || profile.consent
}

/// The resource name a mod entry runs from. Ids are already limited to `[a-z0-9._-]`.
pub fn entry_name(id: &str) -> String {
    let safe: String = id.chars().map(|c| if c.is_ascii_alphanumeric() || "._-".contains(c) { c } else { '_' }).collect();
    format!("obsidian/mods/{safe}/main")
}

fn lua_resource(name: &str, bytecode: &[u8]) -> Planned {
    Planned { type_hash: hash_name("lua"), name_hash: hash_name(name), flags: 0, data: wrap_resource(bytecode), owner: "obsidian".into() }
}

/// An entry file is bytecode when the file starts with the LuaJIT header or the resource envelope,
/// and source otherwise.
fn entry_bytecode(bytes: &[u8], chunk: &str) -> Result<Vec<u8>> {
    if bytes.starts_with(&[0x1b, 0x4c, 0x4a]) {
        check_bytecode(bytes)?;
        return Ok(bytes.to_vec());
    }
    if let Ok(inner) = unwrap_resource(bytes) {
        check_bytecode(inner)?;
        return Ok(inner.to_vec());
    }
    compile(bytes, chunk)
}

/// Every `<lang>.json` found in `dir`, as `{ lang: { key: text } }`.
fn read_texts(dir: &Path) -> Result<Value> {
    let mut out = Map::new();
    for lang in LANGUAGES {
        let path = dir.join(format!("{lang}.json"));
        if !path.is_file() {
            continue;
        }
        let mut v: Value = serde_json::from_str(&std::fs::read_to_string(&path)?)
            .map_err(|e| ObsidianError::BadManifest { field: path.display().to_string(), reason: e.to_string() })?;
        // The shared catalog also holds the app's texts, which the game never shows.
        if let Value::Object(m) = &mut v {
            m.retain(|k, _| !k.starts_with("app."));
        }
        out.insert(lang.to_string(), v);
    }
    Ok(Value::Object(out))
}

fn scope_text(s: &Scope) -> &'static str {
    if *s == Scope::Client { "client" } else { "session" }
}

/// The deploy table as JSON: version, revision, pool hashes, shared texts and the mods
/// with an entry, in load order.
pub fn deploy_table(comp: &Composition, texts: Value) -> Result<Value> {
    let mut session = Vec::new();
    let mut mods = Vec::new();
    let (mut has_session, mut has_static_session) = (false, false);
    for c in &comp.mods {
        let m = &c.manifest;
        let specs = m.option_specs()?;
        if m.scope == Scope::Session {
            has_session = true;
            has_static_session |= c.resources > 0;
            session.push(SessionMod {
                id: m.id.clone(),
                version: m.version.clone(),
                options: specs.iter().map(|s| (s.id.clone(), c.values[&s.id].clone(), s.client)).collect(),
            });
        }
        if m.entry.is_none() {
            continue;
        }
        let options: Vec<Value> = specs
            .iter()
            .map(|s| {
                let mut o = json!({ "id": s.id, "type": s.kind.name(), "default": s.default, "client": s.client });
                match &s.kind {
                    crate::options::OptionKind::Number { min, max, step } => {
                        for (k, v) in [("min", min), ("max", max), ("step", step)] {
                            if let Some(v) = v {
                                o[k] = json!(v);
                            }
                        }
                    }
                    crate::options::OptionKind::Choice(ids) => o["choices"] = json!(ids),
                    _ => {}
                }
                o
            })
            .collect();
        let keybinds: Vec<Value> =
            crate::options::parse_keybinds(&m.keybinds)?.into_iter().map(|k| json!({ "id": k.id, "default": k.default })).collect();
        mods.push(json!({
            "id": m.id,
            "version": m.version.to_string(),
            "scope": scope_text(&m.scope),
            "entry": entry_name(&m.id),
            "loader_api": m.loader_api,
            "options": options,
            "keybinds": keybinds,
            "texts": read_texts(&c.dir.join("locales"))?,
        }));
    }
    let modset = modset_hash(&session);
    let tags = pool_tags(&modset);
    Ok(json!({
        "version": 1,
        "revision": REVISION,
        "modset": modset,
        "hashes": { "identical": tags.identical, "consent": tags.consent },
        "has_session": has_session,
        "has_static_session": has_static_session,
        "texts": texts,
        "mods": mods,
    }))
}

/// A Lua literal for a JSON value. Strings escape every byte outside printable ASCII as `\ddd`.
pub fn to_lua(v: &Value) -> String {
    match v {
        Value::Null => "nil".into(),
        Value::Bool(b) => b.to_string(),
        Value::Number(n) => n.to_string(),
        Value::String(s) => {
            let mut out = String::from("\"");
            for b in s.bytes() {
                match b {
                    b'\\' => out.push_str("\\\\"),
                    b'"' => out.push_str("\\\""),
                    0x20..=0x7e => out.push(b as char),
                    _ => out.push_str(&format!("\\{b:03}")),
                }
            }
            out.push('"');
            out
        }
        Value::Array(items) => format!("{{{}}}", items.iter().map(to_lua).collect::<Vec<_>>().join(", ")),
        Value::Object(map) => {
            format!("{{{}}}", map.iter().map(|(k, v)| format!("[{}] = {}", to_lua(&Value::String(k.clone())), to_lua(v))).collect::<Vec<_>>().join(", "))
        }
    }
}

/// Every loader module (`boot.lua` as the boot entry), every mod entry and `obsidian/deploy`.
pub fn build(loader_dir: &Path, comp: &Composition) -> Result<Vec<Planned>> {
    let mut files: Vec<PathBuf> =
        std::fs::read_dir(loader_dir)?.filter_map(|e| e.ok().map(|e| e.path())).filter(|p| p.extension().is_some_and(|x| x == "lua")).collect();
    files.sort();
    if !files.iter().any(|p| p.file_stem().is_some_and(|s| s == "boot")) {
        return Err(ObsidianError::LoaderMissing(loader_dir.display().to_string()));
    }
    let mut out = Vec::new();
    for p in files {
        let stem = p.file_stem().unwrap().to_string_lossy().to_string();
        let module = format!("obsidian/loader/{stem}");
        let code = compile(&std::fs::read(&p)?, &module)?;
        out.push(lua_resource(if stem == "boot" { ENTRY } else { &module }, &code));
    }
    for c in &comp.mods {
        if let Some(entry) = &c.manifest.entry {
            let name = entry_name(&c.manifest.id);
            out.push(lua_resource(&name, &entry_bytecode(&std::fs::read(c.dir.join(entry))?, &name)?));
        }
    }
    let texts = read_texts(&loader_dir.join("..").join("..").join("locales"))?;
    let source = format!("return {}\n", to_lua(&deploy_table(comp, texts)?));
    out.push(lua_resource("obsidian/deploy", &compile(source.as_bytes(), "obsidian/deploy")?));
    Ok(out)
}

/// What `build` compiles, uncompiled: the loader sources, each mod entry and the deploy table.
/// Equal inputs build equal resources, so this stands in for `build` where nothing is written.
pub fn build_inputs(loader_dir: &Path, comp: &Composition) -> Result<Vec<u8>> {
    let mut files: Vec<PathBuf> =
        std::fs::read_dir(loader_dir)?.filter_map(|e| e.ok().map(|e| e.path())).filter(|p| p.extension().is_some_and(|x| x == "lua")).collect();
    files.sort();
    let mut out = Vec::new();
    for p in files {
        out.extend(p.file_name().unwrap().to_string_lossy().as_bytes());
        out.extend(std::fs::read(&p)?);
    }
    for c in &comp.mods {
        if let Some(entry) = &c.manifest.entry {
            out.extend(c.manifest.id.as_bytes());
            out.extend(std::fs::read(c.dir.join(entry))?);
        }
    }
    let texts = read_texts(&loader_dir.join("..").join("..").join("locales"))?;
    out.extend(deploy_table(comp, texts)?.to_string().as_bytes());
    Ok(out)
}

/// The settings file for this profile: consent and the value of every option of each
/// enabled mod with an entry. Reads manifests only, so nothing is compiled.
pub fn settings_for(lib: &Library, profile: &Profile) -> Result<Settings> {
    let mut s = Settings { consent: profile.consent, ..Default::default() };
    for entry in profile.mods.iter().filter(|m| m.enabled) {
        let dir = lib.mod_dir(&entry.id);
        if !dir.join(crate::manifest::FILE).is_file() {
            continue;
        }
        let m = load_manifest(&dir)?;
        if m.entry.is_none() {
            continue;
        }
        let specs = m.option_specs()?;
        let values: BTreeMap<String, Value> = effective_values(&specs, profile.options.get(&m.id));
        for spec in &specs {
            s.options.push((m.id.clone(), spec.id.clone(), spec.kind.name().to_string(), value_text(&values[&spec.id])));
        }
        // Only keybinds the manifest still declares, so a key set for an older version is dropped.
        let set = profile.keys.get(&m.id);
        for k in crate::options::parse_keybinds(&m.keybinds)? {
            if let Some(key) = set.and_then(|s| s.get(&k.id)) {
                s.keys.push((m.id.clone(), k.id, key.clone()));
            }
        }
    }
    Ok(s)
}

/// The mod named by a `loading` line that no `started`, `failed` or `refused` line followed: the
/// mod that was starting when the game last closed or crashed.
pub fn crash_culprit(log: &str) -> Option<String> {
    let mut pending: Option<String> = None;
    for line in log.lines() {
        let text = line.split_once(' ').map_or(line, |(_, rest)| rest);
        if let Some(id) = text.strip_prefix("loading ") {
            pending = Some(id.trim().to_string());
        } else if let Some(rest) = ["started ", "failed ", "refused "].iter().find_map(|p| text.strip_prefix(p)) {
            let id = rest.split(':').next().unwrap_or("").trim();
            if pending.as_deref() == Some(id) {
                pending = None;
            }
        }
    }
    pending
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::compose::compose;
    use crate::library::ProfileEntry;
    use crate::testutil::{put, spaced_tempdir};

    fn add(t: &Path, lib: &Library, id: &str, scope: &str) {
        let d = t.join(format!("stage-{id}"));
        let json = format!(r#"{{"obsidian":1,"id":"{id}","version":"1.0.0","name":{{"en":"{id}"}},"scope":"{scope}","entry":"main.lua"}}"#);
        put(&d, "obsidian.json", json.as_bytes());
        put(&d, "main.lua", b"return true\n");
        lib.install(&d).unwrap();
    }

    #[test]
    fn deploy_table_lists_mods_in_load_order() {
        let t = spaced_tempdir();
        let lib = Library::open(&t.path().join("data")).unwrap();
        add(t.path(), &lib, "a", "client");
        add(t.path(), &lib, "b", "session");
        let entry = |id: &str| ProfileEntry { id: id.into(), enabled: true };
        let profile = Profile { mods: vec![entry("b"), entry("a")], ..Default::default() };
        let comp = compose(&lib, &profile).unwrap();
        let table = deploy_table(&comp, json!({})).unwrap();
        let ids: Vec<&str> = table["mods"].as_array().unwrap().iter().map(|m| m["id"].as_str().unwrap()).collect();
        assert_eq!(ids, ["b", "a"]);
        assert_eq!(table["mods"][0]["entry"], "obsidian/mods/b/main");
        assert_eq!(table["has_session"], true);
        assert_eq!(table["has_static_session"], false, "an entry can stop when the session isn't cleared");
        assert_eq!(table["modset"].as_str().unwrap().len(), 64);
        let planned = build(&find_loader_dir().unwrap(), &comp).unwrap();
        for name in [ENTRY, "obsidian/loader/core", "obsidian/mods/a/main", "obsidian/mods/b/main", "obsidian/deploy"] {
            assert!(planned.iter().any(|p| p.name_hash == hash_name(name)), "{name}");
        }
    }

    #[test]
    fn settings_for_writes_keys_of_enabled_mods() {
        let t = spaced_tempdir();
        let lib = Library::open(&t.path().join("data")).unwrap();
        for id in ["k1", "k2"] {
            let d = t.path().join(format!("stage-{id}"));
            let json = format!(r#"{{"obsidian":1,"id":"{id}","version":"1.0.0","name":{{"en":"{id}"}},"entry":"main.lua","keybinds":[{{"id":"toggle","default":"f8"}}]}}"#);
            put(&d, "obsidian.json", json.as_bytes());
            put(&d, "main.lua", b"return true\n");
            lib.install(&d).unwrap();
        }
        let mut profile = Profile {
            mods: vec![ProfileEntry { id: "k1".into(), enabled: true }, ProfileEntry { id: "k2".into(), enabled: false }],
            ..Default::default()
        };
        for id in ["k1", "k2"] {
            profile.keys.entry(id.into()).or_default().insert("toggle".into(), "f9".into());
        }
        profile.keys.get_mut("k1").unwrap().insert("gone".into(), "f10".into());
        let s = settings_for(&lib, &profile).unwrap();
        assert_eq!(s.keys, vec![("k1".to_string(), "toggle".to_string(), "f9".to_string())]);
    }

    #[test]
    fn shared_texts_leave_out_app_keys() {
        let texts = read_texts(&find_loader_dir().unwrap().join("..").join("..").join("locales")).unwrap();
        let en = texts["en"].as_object().unwrap();
        assert!(en.contains_key("mod_failed"));
        assert!(en.keys().all(|k| !k.starts_with("app.")), "{:?}", en.keys().collect::<Vec<_>>());
    }

    #[test]
    fn lua_strings_escape_every_byte_outside_ascii() {
        assert_eq!(to_lua(&json!("a\"b\\c\né1")), r#""a\"b\\c\010\195\1691""#);
        assert_eq!(to_lua(&json!({"k": [1, true]})), r#"{["k"] = {1, true}}"#);
    }

    #[test]
    fn crash_culprit_is_the_last_unfinished_loading_line() {
        assert_eq!(crash_culprit("1 loading a\n2 started a\n3 loading b\n"), Some("b".into()));
        assert_eq!(crash_culprit("1 loading a\n2 failed a: boom\n3 boot done\n"), None);
        assert_eq!(crash_culprit(""), None);
    }
}
