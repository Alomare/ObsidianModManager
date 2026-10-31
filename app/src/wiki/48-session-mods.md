---
title: Writing session mods
group: Making mods
summary: How to change the shared game so the guardrails keep working for you.
---

A session mod changes something other players notice: damage, enemies, spawns, missions. The loader decides when such a mod may run ([Playing online](wiki:multiplayer)), and switches it on and off as players come and go. Your part is to make every change through the loader, so it can be switched off.

## Set the scope

```json
"scope": "session"
```

Leaving the field out has the same effect. Only use `client` when nothing the mod does reaches other players.

## Change the game through hooks

Hooks of a session mod call the original game code by themselves while the lobby isn't cleared. A mod built only from hooks needs no extra code to be safe:

```lua
-- Double the damage of every shot, in cleared lobbies only.
obsidian.hook("Damage", "apply", function(original, target, amount, ...)
  return original(target, amount * 2, ...)
end)
```

The same goes for `on_frame` functions and keys: in a lobby that isn't cleared, they don't run.

## Undo what stays behind

Some changes outlive the call that made them: a value written into a settings table, a unit you spawned. Listen for the switch and put things back:

```lua
local original_speed

obsidian.on_require("lua/settings/player_settings", function(settings)
  original_speed = settings.run_speed
end)

obsidian.on_session(function(on)
  local settings = rawget(_G, "PlayerSettings")
  if settings and original_speed then
    settings.run_speed = on and original_speed * 1.5 or original_speed
  end
end)
```

## Things to avoid

- **Replacing globals directly.** `SomeTable.func = mine` keeps running in every lobby, because the loader can't switch it off. The loader log lists such changes for every mod at startup.
- **Replacing game scripts with resources for gameplay changes.** A replaced script can't be switched off live either. Obsidian accepts it, but in a lobby with a player who didn't agree, the change stays in your game while the rest of your session mods switch off.
- **Sending your own network messages** to other players outside the game's own code.

> [!NOTE]
> Changing your own progress, such as XP or unlocks, is allowed. Obsidian backs up the save before every deploy and doesn't undo those changes.

## Writing a library {#libraries}

A mod that exists for other mods to build on can declare itself a library:

```json
"scope": "library"
```

On each deploy, Obsidian makes it a session mod if an enabled session mod requires it, directly or through another library. Otherwise it's a client mod. Anything it does as a session mod goes through the usual rules, and it joins the set players compare. A library that replaces game files with `resources` keeps them in both cases, so keep gameplay changes out of those.

Your code has to work both ways. `obsidian.scope()` says which one this deploy gave you, and `obsidian.session.guard` sorts the functions you hand to other mods. Name the ones that are safe for anyone: reading, undoing, and changes only this player sees or hears. Every other function answers `false, "needs_session"` when your library runs as a client mod, and `false, "not_cleared"` in a lobby that isn't cleared. A function you forget to list is refused.

```lua
local M = obsidian.module("lib/enemies")

-- The gameplay hooks wait for a session mod that needs them.
if obsidian.scope() == "session" then
  obsidian.hook("Damage", "apply", M.on_damage)
end

return {
  enemies = obsidian.session.guard(M, { "list", "count" }),
}
```

Your own code keeps the real table, so it can still undo its changes after the lobby stops being cleared.

## Options in session mods

Every option value counts when Obsidian compares players' sets, unless you mark it `"scope": "client"`. Mark the options that only change what this player sees ([Options and keys](wiki:options-and-keys#personal-options-in-session-mods)).
