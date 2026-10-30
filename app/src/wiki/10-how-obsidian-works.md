---
title: How Obsidian works
group: Getting started
summary: What Obsidian does to the game, what stays untouched, and what each tab is for.
---

Obsidian is a mod manager for HELLDIVERS (2015). You keep your mods in a library, choose which ones to play with, and Obsidian puts them into the game. Your game files are never edited, so several mods can run side by side and the game can always go back to vanilla.

## Patches instead of replaced files

The game keeps the content in bundles, in the `contents` folder of the install. Next to each bundle, the engine also loads files named `<bundle>.patch_0`, `.patch_1` and so on, and a resource in a patch takes the place of the one in the bundle.

Mods made by hand usually replace whole bundles. Two such mods overwrite each other, even when they change different things. Obsidian reads every enabled mod, finds the resources each one really changes, and writes them into one patch per bundle. The vanilla bundles stay as they were.

> [!NOTE]
> Deploy writes the patches, and [Purge](wiki:deploy-and-purge#purge) deletes them. After a purge the install is byte for byte the vanilla game.

## Obsidian Loader

Mods that run code, such as a camera mod, need a way to start inside the game. Obsidian adds one small script to the game at every deploy: Obsidian Loader. When the game boots, the loader reads the list of deployed mods, starts each one, and keeps an eye on what they are allowed to do.

The loader also handles the multiplayer rules. Mods that change the shared game only run with players who agreed to it, and modded missions are kept out of the Galactic War. [Scopes: client and session](wiki:scopes) explains how.

## The tabs

| Tab | What it is for |
|---|---|
| Home | Links to the community and the source code |
| [Mods](app:mods) | Your library: turn mods on and off, set the load order, change options and keys |
| Wiki | These guides |
| [Settings](app:settings) | Language, theme, game folder, updates |

The bar at the top holds the multiplayer switch and three buttons:

- **Purge** takes every Obsidian patch out of the game.
- **Deploy** puts the enabled mods into the game. It turns green when your changes have not been deployed yet.
- **Play** starts the game through Steam.

The status bar at the bottom shows what Obsidian is doing, the version, your notifications and the About box.

## Where your files are

| What | Where |
|---|---|
| Mod library, profiles, app settings | `%LOCALAPPDATA%\ObsidianModManager`, or `data\` beside the app in a portable copy |
| Options and keys the game reads, logs | `%APPDATA%\Arrowhead\Helldivers\ObsidianModManager` |
| Save backups | the `backups` folder in the app data folder |
