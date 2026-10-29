# Contributing to Obsidian

Thanks for helping. Obsidian is a small project, so a short note before a large change saves both of us time: open an issue first and describe what you want to do.

## Branches

Work happens on `dev`. Open pull requests against `dev`. `main` only moves when a release is published.

## Building and testing

You need Rust (stable, MSVC toolchain on Windows) and the Visual Studio Build Tools.

1. Build the LuaJIT 2.0 compiler once: `tools\build-luajit.cmd`
2. Run the core tests: `cargo test`
3. Run the loader tests: `tools\test-loader.cmd`

Some tests read your own game files and are skipped unless you point them at the game with `OBSIDIAN_GAME_DIR`. Game files are never committed.

## Changes that need care

- Anything in the loader that decides when session mods run (spec section 6) needs a test for every case it touches, and a note in the pull request on how it was tested in game.
- Obsidian never writes a vanilla game file. A change that does will not be merged.
- Mods that change the game for other players must stay `session` scope. Pull requests that weaken the guardrails will not be merged.

## Bug reports

Include the output of `obsidian status`, the file `%APPDATA%\Arrowhead\Helldivers\obsidian\logs\loader.log` if one exists, and the mods you had enabled.

## License

By contributing, you agree that your contribution is licensed under the [Apache License 2.0](LICENSE), the same as the rest of Obsidian.
