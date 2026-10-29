//! The LuaJIT 2.0 compiler that ships beside Obsidian: the game runs only LuaJIT 2.0 bytecode.

use std::path::PathBuf;
use std::process::Command;

use crate::lua::check_bytecode;
use crate::{ObsidianError, Result};

#[cfg(windows)]
const EXE: &str = "luajit.exe";
#[cfg(not(windows))]
const EXE: &str = "luajit";

/// `OBSIDIAN_LUAJIT`, then `luajit/` beside the running exe, then the workspace build in `target/luajit/`.
pub fn find_compiler() -> Result<PathBuf> {
    let mut candidates = Vec::new();
    if let Some(p) = std::env::var_os("OBSIDIAN_LUAJIT") {
        candidates.push(PathBuf::from(p));
    }
    if let Some(dir) = std::env::current_exe().ok().and_then(|e| e.parent().map(|p| p.to_path_buf())) {
        candidates.push(dir.join("luajit").join(EXE));
    }
    candidates.push(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../target/luajit").join(EXE));
    candidates
        .iter()
        .find(|p| p.is_file())
        .cloned()
        .ok_or_else(|| ObsidianError::CompilerUnavailable(candidates.iter().map(|p| p.display().to_string()).collect::<Vec<_>>().join(", ")))
}

/// Compiles Lua source to stripped LuaJIT 2.0 bytecode. Errors name `chunk` instead of the temp file.
pub fn compile(source: &[u8], chunk: &str) -> Result<Vec<u8>> {
    let luajit = find_compiler()?;
    let dir = tempfile::tempdir()?;
    let (src, out) = (dir.path().join("chunk.lua"), dir.path().join("chunk.ljbc"));
    std::fs::write(&src, source)?;
    let run = Command::new(&luajit).arg("-b").arg("-s").arg(&src).arg(&out).output()?;
    if !run.status.success() {
        let raw = String::from_utf8_lossy(&run.stderr);
        let message = raw.replace(&*src.to_string_lossy(), chunk).replace(&*luajit.to_string_lossy(), "luajit");
        return Err(ObsidianError::CompileFailed { chunk: chunk.to_string(), message: message.trim().to_string() });
    }
    let code = std::fs::read(&out)?;
    check_bytecode(&code)?;
    Ok(code)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn compile_produces_2_0_bytecode() {
        let code = compile(b"x = 1", "t").unwrap();
        assert_eq!(&code[..5], &[0x1b, 0x4c, 0x4a, 0x01, 0x02]);
    }

    #[test]
    fn syntax_error_names_the_chunk() {
        match compile(b"x = ", "mods/a/main") {
            Err(ObsidianError::CompileFailed { chunk, message }) => {
                assert_eq!(chunk, "mods/a/main");
                assert!(message.contains("mods/a/main"), "{message}");
                assert!(!message.contains("chunk.lua"), "{message}");
            }
            other => panic!("{other:?}"),
        }
    }
}
