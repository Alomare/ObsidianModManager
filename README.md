# Obsidian

Obsidian is a mod manager for HELLDIVERS (2015), with an in-game runtime called Obsidian Loader.

Mods installed with Obsidian never overwrite a game file, so several mods can run side by side, and a purge brings the game back to vanilla. Mods that change the shared game run only with players who have the same mods or have agreed to play with modded players, so a vanilla player is never affected.

Obsidian comes as a desktop app and the `obsidian` command line, which work on the same data. There is no public release yet. The design is in [docs/superpowers/specs](docs/superpowers/specs).

## Desktop app

The app handles your mods, load order, folders, conflicts, options, keys and named profiles, with Deploy, Play and Purge one click away. Its Wiki tab has guides for players and mod authors. It runs in English, Brazilian Portuguese and Simplified Chinese, and comes as an installer that updates itself or as a portable ZIP.

Mods that replace whole game files work too: Obsidian imports them and turns them into small patches the game loads on top of the originals.

[CONTRIBUTING.md](CONTRIBUTING.md) has what you need to build it.

## Command line

The `obsidian` command line does the same work from a terminal. Build it with `cargo build --release`, plus `tools\build-luajit.cmd` once for the LuaJIT 2.0 compiler that turns mod scripts into code the game can run. Run it with the game closed:

```
obsidian import <mod folder or .zip>   add a mod to the library (old whole-file mods work too)
obsidian list                          mods in load order, on or off
obsidian enable <id> / disable <id>    choose what to play with
obsidian order <id>...                 put these mods first; later mods win conflicts
obsidian conflicts                     show which mods change the same thing
obsidian deploy                        put the enabled mods into the game
obsidian purge                         take them out again
obsidian status                        game build, what is deployed
obsidian consent on|off                play session mods with other Obsidian users who allow them too
obsidian set <id> <option> <value>     change a mod option
obsidian remove <id>                   delete a mod from the library
obsidian key <id> <keybind> <key>      change a mod key
obsidian updates                       ask GitHub for new versions of the mods that name a repository
obsidian update [<id>...]              install new versions from GitHub
obsidian profile list|use|new <name>   switch between named sets of mods and settings
```

Obsidian comes with Obsidian Quality of Life, a mod that is off until you enable it (`obsidian enable obsidian.qol`). It skips the intro, the login screen, war briefs and planet scanning, removes the black bars on screens wider than 16:9, and can speed up or skip the results screens after a mission. Each fix is an option. All are on by default except the mission end one, which starts off: `obsidian set obsidian.qol skip_login false` turns one off.

Obsidian finds the game through Steam; `--game <folder>` points somewhere else. Your save folder is backed up before every deploy.

## License

Copyright (C) 2026 Alomare. Licensed under the [Apache License 2.0](LICENSE).

Only builds from this repository's GitHub releases are official Obsidian. The license gives no right to use the Obsidian name for other builds.
