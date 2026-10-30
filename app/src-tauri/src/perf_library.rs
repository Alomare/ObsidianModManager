//! A large made-up library for performance tests: many mods with options, keybinds and
//! resources, where neighbours in the load order change some of the same files. Used by the
//! snapshot timing test and by `cargo run --example perf_library` for the UI suite
//! (tools/perf.mjs).

use std::path::Path;

use obsidian_core::Result;
use obsidian_core::library::{Library, Profile};

/// Resources per mod; the first `SHARED` of them are also changed by the next mod in order.
const RESOURCES: usize = 12;
const SHARED: usize = 4;

/// Installs `count` mods into the data folder `data` and turns them all on.
pub fn build(data: &Path, count: usize) -> Result<()> {
    let lib = Library::open(data)?;
    let stage = data.join("perf-stage");
    for i in 0..count {
        let id = format!("perf.mod-{i:03}");
        let dir = stage.join(&id);
        std::fs::create_dir_all(&dir)?;
        let resources: Vec<String> = (0..RESOURCES)
            .map(|r| {
                // Mod i shares the first SHARED resources of mod i with mod i - 1.
                let n = if r < SHARED { i * 100 + SHARED + r } else { (i + 1) * 100 + r };
                format!(r##"{{"type":"#0000000000000001","name":"#{n:016x}","bundle":"00000000000aa000","data":"r{r}.bin"}}"##)
            })
            .collect();
        let scope = if i % 3 == 0 { "session" } else { "client" };
        let json = format!(
            r##"{{"obsidian":1,"id":"{id}","version":"1.{}.0","name":{{"en":"Performance test mod {i}"}},
               "description":{{"en":"A made-up mod with options, a keybind and {RESOURCES} files."}},
               "authors":["Obsidian"],"scope":"{scope}","entry":"main.lua",
               "options":[{{"id":"on","type":"toggle","default":true,"label":{{"en":"Enabled part"}}}},
                          {{"id":"amount","type":"number","default":5,"min":0,"max":10,"step":1,"label":{{"en":"Amount"}}}},
                          {{"id":"mode","type":"choice","default":"a","choices":["a","b","c"],"label":{{"en":"Mode"}}}}],
               "keybinds":[{{"id":"use","default":"f{}","label":{{"en":"Use"}}}}],
               "resources":[{}]}}"##,
            i % 10,
            1 + i % 12,
            resources.join(",")
        );
        std::fs::write(dir.join("obsidian.json"), json)?;
        std::fs::write(dir.join("main.lua"), "return true\n")?;
        for r in 0..RESOURCES {
            std::fs::write(dir.join(format!("r{r}.bin")), format!("{id} {r}"))?;
        }
        lib.install(&dir)?;
    }
    std::fs::remove_dir_all(&stage)?;
    let mut p = Profile::load(data)?;
    p.sync(&lib)?;
    for i in 0..count {
        p.set_enabled(&format!("perf.mod-{i:03}"), true)?;
    }
    p.save(data)
}
