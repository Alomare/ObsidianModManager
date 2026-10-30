---
title: Loader API
group: Making mods
summary: Every function of the obsidian table, version 1.
---

Obsidian Loader starts the `entry` script of each enabled mod in load order, once, when the game boots. Every script sees a global table named `obsidian`. Everything a mod registers through it runs protected: an error is logged and never stops the game.

## Hooks {#hooks}

### obsidian.hook(target, method, fn)

Wraps a function of the game. `target` is a table, or the name of a global table as a string. `fn` receives the original function first, then the arguments of the call:

```lua
obsidian.hook("PlayerUnitMovement", "update", function(original, self, dt)
  -- before the game code
  local result = original(self, dt)
  -- after the game code
  return result
end)
```

When the global doesn't exist yet, the hook waits and goes in as soon as the game defines it. If `fn` fails, the original runs instead.

In a session mod, the hook calls only the original while the lobby isn't cleared ([Writing session mods](wiki:session-mods)).

### obsidian.on_require(name, fn)

Calls `fn(module)` when the game loads the script `name`, such as `"lua/settings/perk_settings"`. Use it to change a settings table right after the game builds it.

### obsidian.on_frame(fn)

Calls `fn` once per frame. Return `true` to stop the calls. A session mod's frame functions only run in a cleared lobby.

### obsidian.after_startup(fn)

Calls `fn` once every mod has started, so mods can work together without depending on load order.

## Settings and keys

### obsidian.settings.get(id)

The value of option `id` of this mod: the one the player chose in the app, or the default ([Options and keys](wiki:options-and-keys)).

### obsidian.keybind(id, fn)

Calls `fn` each time the key bound to `id` goes down. The key comes from the app, or from the default in `obsidian.json`.

## Multiplayer

### obsidian.session.cleared()

`true` while this player's session mods may run. Client mods rarely need it.

### obsidian.session.members()

A list of the other players in the lobby. Each entry has `peer`, `obsidian` (whether that player runs Obsidian), `modset` and `consent`.

### obsidian.on_session(fn)

Calls `fn(on)` whenever the loader switches this mod on or off, so the mod can undo what other players would see.

## Text and logs

### obsidian.text(key, ...)

The text `key` from the `locales` folder of the mod, in the language of the game, with English as the fallback. Extra arguments fill `%s` and `%d` placeholders.

### obsidian.log(...)

Writes a line to the log of this mod, in `%APPDATA%\Arrowhead\Helldivers\ObsidianModManager\logs`.

## Version and features

`obsidian.version` is the API version, `1` today. A mod that needs a newer API sets `loader_api` in `obsidian.json`, and older loaders refuse to start it.

`obsidian.capabilities` is a read-only table of what the running loader supports, one entry per feature: `hook`, `on_require`, `on_frame`, `on_session`, `after_startup`, `settings`, `keybind`, `session`, `text`, `log`. Test a feature by name before using one that came later:

```lua
if obsidian.capabilities.on_frame then
  obsidian.on_frame(update)
end
```

## When a mod fails

- An error at startup switches the mod off for this session and writes the error to `loader.log`.
- Errors in hooks and callbacks are logged at most three times per place, so a broken frame function can't flood the log.
- A mod that keeps failing is switched off for the rest of the session.
- If the game crashes while a mod starts, the app names that mod at the next launch.
