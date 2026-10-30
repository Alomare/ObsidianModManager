---
title: Adding and updating mods
group: Getting started
summary: Importing a mod from a .zip or a folder, updating one, and removing one.
---

## Importing

Drag a mod folder or a `.zip` file onto the mod list in the [Mods](app:mods) tab, or click the green **+** beside the search box and pick one. Several files can go in at once, and a notification says what happened to each one.

Obsidian copies the mod into the library, so you can delete the download afterwards. Importing changes nothing in the game until you deploy.

### Mods made for Obsidian

A mod made for Obsidian has an `obsidian.json` file at the top of the folder or archive. Obsidian reads the name, version, options and keys from that file, and the mod shows them in the panel on the right.

### Older mods

Most HD1 mods shared today replace whole game bundles, with files named like `9e13b2414b41b842`. Obsidian imports those as well. It compares each bundle in the mod with the one in your game and keeps only the resources the mod really changes, so two older mods that touch different things can now run together.

Older mods are imported with the **session** scope, because Obsidian can't tell what they change in a shared game ([Scopes](wiki:scopes)). They also can't be switched off in the middle of a mission.

> [!NOTE]
> To compare bundles, the game has to be the vanilla build Obsidian knows. Purge first if another tool has changed the game files.

## Updating

Import the new version the same way. A mod with the same id replaces the one in the library, and the notification shows the old and new version numbers. Your option values and keys stay, except for options the author changed the type of.

## Removing

Right-click a mod and choose **Remove**, or check several mods and use **Remove** in the bar above the list. The mods that come with Obsidian can't be removed; they sit in the locked Obsidian folder and stay off until you turn them on.

## Pictures

A mod can bring a square picture. To use your own, open the mod in the panel on the right and click the picture. Profiles take a picture the same way.
