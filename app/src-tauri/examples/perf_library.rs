//! Builds a large made-up library for the UI performance suite:
//!   cargo run -p obsidian-app --example perf_library -- <data dir> [mods, default 200]
//! then start the app with OBSIDIAN_DATA_DIR=<data dir> and run tools/perf.mjs.

fn main() {
    let mut args = std::env::args().skip(1);
    let dir = std::path::PathBuf::from(args.next().expect("usage: perf_library <data dir> [mods]"));
    let count = args.next().map_or(200, |n| n.parse().expect("mods is a number"));
    if dir.exists() {
        std::fs::remove_dir_all(&dir).expect("clear the old library");
    }
    obsidian_app_lib::perf_library::build(&dir, count).expect("build the library");
    println!("{count} mods in {}", dir.display());
}
