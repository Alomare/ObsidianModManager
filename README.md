# Kepler

Kepler is a mod manager for HELLDIVERS (2015), with an in-game runtime called Kepler Loader.

Mods installed with Kepler never overwrite a game file, so several mods can run side by side, and a purge brings the game back to vanilla. Mods that change the shared game run only with players who have the same mods or have agreed to play with modded players, so a vanilla player is never affected.

Kepler is in early development. The design is in [docs/superpowers/specs](docs/superpowers/specs).

## Command line

The `kepler` command line works today; the desktop app comes later. Build it with `cargo build --release` and run it with the game closed:

```
kepler import <mod folder or .zip>   add a mod to the library (old whole-file mods work too)
kepler list                          mods in load order, on or off
kepler enable <id> / disable <id>    choose what to play with
kepler order <id>...                 put these mods first; later mods win conflicts
kepler conflicts                     show which mods change the same thing
kepler deploy                        put the enabled mods into the game
kepler purge                         take them out again
kepler status                        game build, what is deployed
```

Kepler finds the game through Steam; `--game <folder>` points somewhere else. Your save folder is backed up before every deploy.

## License

Copyright (C) 2026 Alomare. Licensed under the [Apache License 2.0](LICENSE).

Only builds from this repository's GitHub releases are official Kepler. The license gives no right to use the Kepler name for other builds.
