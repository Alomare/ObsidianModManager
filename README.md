# Obsidian

Obsidian is a mod manager for HELLDIVERS (2015), with an in-game runtime called Obsidian Loader.

Mods installed with Obsidian never overwrite a game file, so several mods can run side by side, and a purge brings the game back to vanilla. Mods that change the shared game run only with players who have the same mods or have agreed to play with modded players, so a vanilla player is never affected.

Obsidian is in early development. The design is in [docs/superpowers/specs](docs/superpowers/specs).

## Beta

The first beta is the `obsidian` command line for Windows. It handles the mods people already share, the ones that replace whole game files, and turns them into small patches the game loads on top of the originals. Obsidian Loader and the desktop app are not in this beta, so nothing yet stops a mod from changing the game for other players. Until the loader ships, play with these mods the way you would after installing them by hand: with friends who run the same mods.

## Command line

The `obsidian` command line works today; the desktop app comes later. Build it with `cargo build --release`, plus `toolsuild-luajit.cmd` once for the LuaJIT 2.0 compiler that turns mod scripts into code the game can run. Run it with the game closed:

```
obsidian import <mod folder or .zip>   add a mod to the library (old whole-file mods work too)
obsidian list                          mods in load order, on or off
obsidian enable <id> / disable <id>    choose what to play with
obsidian order <id>...                 put these mods first; later mods win conflicts
obsidian conflicts                     show which mods change the same thing
obsidian deploy                        put the enabled mods into the game
obsidian purge                         take them out again
obsidian status                        game build, what is deployed
obsidian feature <name> on|off         skip_intro, skip_login or skip_war_briefs
obsidian consent on|off                play session mods with other Obsidian users who allow them too
obsidian set <id> <option> <value>     change a mod option
```

Obsidian finds the game through Steam; `--game <folder>` points somewhere else. Your save folder is backed up before every deploy.

## License

Copyright (C) 2026 Alomare. Licensed under the [Apache License 2.0](LICENSE).

Only builds from this repository's GitHub releases are official Obsidian. The license gives no right to use the Obsidian name for other builds.
