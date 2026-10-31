//! Obsidian Loader as patch resources: the loader modules, every mod entry and the deploy table,
//! all compiled for the boot bundle, plus the settings file the loader reads at launch.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use serde_json::{Map, Value, json};

use crate::compose::{ComposedMod, Composition, Planned};
use crate::hash::hash_name;
use crate::library::{Library, Profile};
use crate::lua::{check_bytecode, unwrap_resource, wrap_resource};
use crate::luajit::compile_all;
use crate::manifest::{Scope, load_manifest};
use crate::modset::{SessionMod, modset_hash, open_pool_tag};
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

/// `rel` in the app's resources, beside the exe, then in this workspace. Debug builds look in the
/// workspace first: the copy beside a dev exe is only refreshed when the Rust side rebuilds, so it
/// goes stale after a change to a starter mod or the loader alone.
fn candidates(rel: &str) -> Vec<PathBuf> {
    let mut out: Vec<PathBuf> = crate::paths::resource_dir().map(|d| d.join(rel)).into_iter().collect();
    if let Some(dir) = std::env::current_exe().ok().and_then(|e| e.parent().map(Path::to_path_buf)) {
        out.push(dir.join(rel));
    }
    let workspace = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("..").join(rel);
    if cfg!(debug_assertions) {
        out.insert(0, workspace);
    } else {
        out.push(workspace);
    }
    out
}

/// The folder of the starter pack (`bundled/` beside the exe, then in this workspace), if there is one.
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

/// The folder of a mod's resources. Ids are already limited to `[a-z0-9._-]`.
fn mod_root(id: &str) -> String {
    let safe: String = id.chars().map(|c| if c.is_ascii_alphanumeric() || "._-".contains(c) { c } else { '_' }).collect();
    format!("obsidian/mods/{safe}")
}

/// The resource name a mod entry runs from.
pub fn entry_name(id: &str) -> String {
    format!("{}/main", mod_root(id))
}

/// The resource name of a script in `modules`: its path in the mod, without `.lua`.
pub fn module_name(id: &str, path: &Path) -> String {
    let parts: Vec<String> = path.with_extension("").components().map(|c| c.as_os_str().to_string_lossy().into_owned()).filter(|c| c != ".").collect();
    format!("{}/{}", mod_root(id), parts.join("/"))
}

fn lua_resource(name: &str, bytecode: &[u8]) -> Planned {
    Planned::new(hash_name("lua"), hash_name(name), 0, wrap_resource(bytecode), "obsidian".into())
}

/// One script of a loader build: bytecode already, or source for the compiler with its chunk name.
enum Script {
    Bytecode(Vec<u8>),
    Source(Vec<u8>, String),
}

/// An entry file is bytecode when the file starts with the LuaJIT header or the resource envelope,
/// and source otherwise.
fn entry_script(bytes: Vec<u8>, chunk: &str) -> Result<Script> {
    if bytes.starts_with(&[0x1b, 0x4c, 0x4a]) {
        check_bytecode(&bytes)?;
        return Ok(Script::Bytecode(bytes));
    }
    if let Ok(inner) = unwrap_resource(&bytes) {
        check_bytecode(inner)?;
        return Ok(Script::Bytecode(inner.to_vec()));
    }
    Ok(Script::Source(bytes, chunk.to_string()))
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

/// Load order, with each mod moved just far enough to start after the mods it requires.
fn start_order(mods: &[ComposedMod]) -> Vec<&ComposedMod> {
    fn visit<'a>(i: usize, mods: &'a [ComposedMod], seen: &mut [bool], out: &mut Vec<&'a ComposedMod>) {
        if std::mem::replace(&mut seen[i], true) {
            return;
        }
        for id in &mods[i].manifest.requires {
            if let Some(j) = mods.iter().position(|m| m.manifest.id == *id) {
                visit(j, mods, seen, out);
            }
        }
        out.push(&mods[i]);
    }
    let (mut seen, mut out) = (vec![false; mods.len()], Vec::with_capacity(mods.len()));
    for i in 0..mods.len() {
        visit(i, mods, &mut seen, &mut out);
    }
    out
}

/// The deploy table as JSON: version, revision, pool hashes, shared texts and the mods
/// with an entry, in the order they start.
pub fn deploy_table(comp: &Composition, texts: Value) -> Result<Value> {
    let mut session = Vec::new();
    let mut mods = Vec::new();
    let (mut has_session, mut has_static_session) = (false, false);
    for c in start_order(&comp.mods) {
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
            "requires": m.requires,
            "options": options,
            "keybinds": keybinds,
            "texts": read_texts(&c.dir.join("locales"))?,
        }));
    }
    let modset = modset_hash(&session);
    Ok(json!({
        "version": 1,
        "revision": REVISION,
        "modset": modset,
        "hashes": { "open": open_pool_tag() },
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
    let mut scripts = Vec::new();
    for p in files {
        let stem = p.file_stem().unwrap().to_string_lossy().to_string();
        let module = format!("obsidian/loader/{stem}");
        let name = if stem == "boot" { ENTRY.to_string() } else { module.clone() };
        scripts.push((name, Script::Source(std::fs::read(&p)?, module)));
    }
    for c in &comp.mods {
        if let Some(entry) = &c.manifest.entry {
            let name = entry_name(&c.manifest.id);
            let script = entry_script(std::fs::read(c.dir.join(entry))?, &name)?;
            scripts.push((name, script));
            for p in &c.manifest.modules {
                let name = module_name(&c.manifest.id, p);
                let script = entry_script(std::fs::read(c.dir.join(p))?, &name)?;
                scripts.push((name, script));
            }
        }
    }
    let texts = read_texts(&loader_dir.join("..").join("..").join("locales"))?;
    let source = format!("return {}\n", to_lua(&deploy_table(comp, texts)?));
    scripts.push(("obsidian/deploy".to_string(), Script::Source(source.into_bytes(), "obsidian/deploy".to_string())));

    let sources: Vec<(&[u8], &str)> = scripts
        .iter()
        .filter_map(|(_, s)| match s {
            Script::Source(source, chunk) => Some((source.as_slice(), chunk.as_str())),
            Script::Bytecode(_) => None,
        })
        .collect();
    let mut compiled = compile_all(&sources)?.into_iter();
    Ok(scripts
        .iter()
        .map(|(name, s)| match s {
            Script::Bytecode(code) => lua_resource(name, code),
            Script::Source(..) => lua_resource(name, &compiled.next().unwrap()),
        })
        .collect())
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
            for p in &c.manifest.modules {
                out.extend(std::fs::read(c.dir.join(p))?);
            }
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
        // A mod that can't be read stays out, as it does in a deploy.
        let Ok(m) = load_manifest(&lib.mod_dir(&entry.id)) else { continue };
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

/// The loader's lines that tell a normal exit from a crash, the first written once it can tell.
const WATCHING: &str = "watching for the game to close";
const CLOSED: &str = "game closed";

/// The last line of a log whose game stopped without closing: a crash, or the process being killed.
/// A log from before the loader could tell says nothing.
pub fn unclean_end(log: &str) -> Option<String> {
    let text = |line: &'_ str| line.split_once(' ').map_or(line, |(_, rest)| rest).trim().to_string();
    let lines: Vec<&str> = log.lines().filter(|l| !l.trim().is_empty()).collect();
    if !lines.iter().any(|l| text(l) == WATCHING) {
        return None;
    }
    lines.last().map(|l| text(l)).filter(|last| last != CLOSED)
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
        let entry = |id: &str| ProfileEntry { id: id.into(), enabled: true, folder: None };
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
    fn modules_become_resources_and_required_mods_start_first() {
        let t = spaced_tempdir();
        let lib = Library::open(&t.path().join("data")).unwrap();
        add(t.path(), &lib, "base", "session");
        let d = t.path().join("stage-user");
        let json = r#"{"obsidian":1,"id":"user","version":"1.0.0","name":{"en":"user"},"entry":"main.lua",
                       "modules":["lib/parts.lua"],"requires":["base"]}"#;
        put(&d, "obsidian.json", json.as_bytes());
        put(&d, "main.lua", b"return true\n");
        put(&d, "lib/parts.lua", b"return {}\n");
        lib.install(&d).unwrap();
        let entry = |id: &str| ProfileEntry { id: id.into(), enabled: true, folder: None };
        let profile = Profile { mods: vec![entry("user"), entry("base")], ..Default::default() };
        let comp = compose(&lib, &profile).unwrap();
        let table = deploy_table(&comp, json!({})).unwrap();
        let ids: Vec<&str> = table["mods"].as_array().unwrap().iter().map(|m| m["id"].as_str().unwrap()).collect();
        assert_eq!(ids, ["base", "user"]);
        assert_eq!(table["mods"][1]["requires"], json!(["base"]));
        let planned = build(&find_loader_dir().unwrap(), &comp).unwrap();
        assert!(planned.iter().any(|p| p.name_hash == hash_name("obsidian/mods/user/lib/parts")));
    }

    #[test]
    fn the_starter_mods_compile_and_the_trainer_brings_the_api() {
        let t = spaced_tempdir();
        let lib = Library::open(&t.path().join("data")).unwrap();
        let mut profile = Profile::default();
        crate::starter::restore(&lib, &mut profile).unwrap();
        assert_eq!(profile.switch(&lib, "obsidian.trainer", true).unwrap(), ["obsidian.api"]);
        let comp = compose(&lib, &profile).unwrap();
        let table = deploy_table(&comp, json!({})).unwrap();
        let ids: Vec<&str> = table["mods"].as_array().unwrap().iter().map(|m| m["id"].as_str().unwrap()).collect();
        assert_eq!(ids, ["obsidian.api", "obsidian.trainer", "obsidian.qol"]);
        assert_eq!(table["has_session"], true, "session mods, so the shared war stays out of it");
        assert_eq!(table["has_static_session"], false, "both can switch off live");
        assert_eq!(table["mods"][1]["keybinds"][0]["default"], "f6");
        assert!(table["mods"][1]["texts"]["pt-BR"]["god"].is_string());
        let planned = build(&find_loader_dir().unwrap(), &comp).unwrap();
        for name in ["obsidian/loader/menu", "obsidian/loader/storage", "obsidian/mods/obsidian.api/lib/game", "obsidian/mods/obsidian.api/lib/data", "obsidian/mods/obsidian.trainer/pages/player"] {
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
            mods: vec![ProfileEntry { id: "k1".into(), enabled: true, folder: None }, ProfileEntry { id: "k2".into(), enabled: false, folder: None }],
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
    fn a_log_that_never_says_the_game_closed_ended_badly() {
        assert_eq!(unclean_end("1 boot done\n2 watching for the game to close\n3 session: x\n"), Some("session: x".into()));
        assert_eq!(unclean_end("1 watching for the game to close\n2 game closed\n"), None);
        assert_eq!(unclean_end("1 watching for the game to close\n2 game closed\n\n"), None, "a blank end");
        assert_eq!(unclean_end("1 boot done\n2 session: x\n"), None, "an older loader can't tell");
        assert_eq!(unclean_end(""), None);
    }

    #[test]
    fn crash_culprit_is_the_last_unfinished_loading_line() {
        assert_eq!(crash_culprit("1 loading a\n2 started a\n3 loading b\n"), Some("b".into()));
        assert_eq!(crash_culprit("1 loading a\n2 failed a: boom\n3 boot done\n"), None);
        assert_eq!(crash_culprit(""), None);
    }
}
