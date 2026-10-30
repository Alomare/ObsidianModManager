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

## Options in session mods

Every option value counts when Obsidian compares players' sets, unless you mark it `"scope": "client"`. Mark the options that only change what this player sees ([Options and keys](wiki:options-and-keys#personal-options-in-session-mods)).
