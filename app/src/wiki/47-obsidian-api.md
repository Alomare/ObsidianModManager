---
title: Obsidian API
group: Making mods
summary: The runtime for mods: the game's data by name, checked changes, and ready actions.
---

Obsidian API is a mod other mods build on. It knows where things are in the game, makes changes in ways the game accepts, and undoes them when it has to. It's how Obsidian Trainer works, and the trainer uses nothing you can't use.

## Using it

List it in `requires`, and Obsidian switches it on with your mod and starts it first:

```json
"scope": "session",
"entry": "main.lua",
"requires": ["obsidian.api"]
```

Then ask for it:

```lua
local api = obsidian.import("obsidian.api")

obsidian.keybind("panic", function()
  api.player.heal()
  api.enemies.kill_near(20)
end)
```

Actions answer `true`, or `false` and a short reason such as `"host_only"`, `"no_avatar"` or `"not_in_mission"`.

## Changing game data {#edits}

`api.edits` changes settings tables and keeps a record of what changed, who changed it and what it was before.

```lua
-- Double the assault rifle's damage, upgrades included.
local ok, why = api.edits.set_unit("equipment/wep_assaultrifle_01", "weapon_info.power", 150)

-- A value in any table the game reads.
local s = api.catalog.stratagem("stratagem_resupply")
api.edits.set_table("Resupply", s, "cooldown_time", 30)
```

- Types and ranges are checked, and `opts` can give `min` and `max`.
- Tables stay the same tables, because live units hold references to them.
- A weapon has a copy of its settings for each upgrade, and an edit reaches them all.
- `api.edits.list()`, `revert(id)` and `revert_all()` show and undo changes.
- When the lobby stops being cleared, every edit is undone. When it clears again, they return.

Fields a player can edit, with ranges and when each takes effect, are in `api.catalog.fields(family)`. Some numbers apply at once and some at the next spawn. `api.gear.refresh()` pushes the cached ones into weapons in play.

## Effects {#effects}

An effect stays on across respawns and missions. The game rebuilds much of its state then, so the runtime applies active effects again.

```lua
api.effects.set("god", true)
api.effects.set("speed", 2)     -- a value, false to switch off
api.effects.is_on("god")
```

Your own:

```lua
api.effects.define({
  id = "mymod.low_gravity",
  apply = function(ctx, value) end,            -- on, and again after a respawn or new mission
  frame = function(ctx, value, dt) end,        -- every frame while on
  remove = function(ctx, value) end,           -- off
})
```

`ctx` has `state`, `name`, `record` and `unit`. All of them can be nil.

## What's in the API {#contents}

| Table | For |
|---|---|
| `api.game` | The current state, the local player, `is_host()`, and safe writes |
| `api.catalog` | Weapons, stratagems, perks, enemies and groups by name, without paid items the player doesn't own |
| `api.player` | `heal`, `respawn`, `teleport`, `set_cosmetic`, and more |
| `api.gear` | `refill`, `give_weapon`, `give_perk`, `refresh` |
| `api.stratagems` | `reset_cooldowns`, `refill_uses`, `give`, `drop` |
| `api.enemies` | `spawn`, `spawn_group`, `kill_all`, `list` |
| `api.mission` | `finish_objectives`, `win`, `abort`, `practice` |
| `api.world` | `cursor`, `ahead`, `explode` |
| `api.progress` | `set_samples`, `unlock_items`, `upgrade_all` |
| `api.console` | `run(line)`, `commands()` |

## Rules worth knowing {#rules}

> [!WARNING]
> The game keeps hashed copies of guarded values such as `hitpoints_real`, `rounds`, `cooldown_timer`, `uses_left`, `num_grenades` and `extra_lives`. Writing one directly trips its anti-tamper check, which cuts the player off from the network until they restart. Use `api.game.protected` or a queued command. `api.edits` refuses those keys.

- `api.game.command(unit, component, command, data)` queues a command on a unit this player owns, from a list of known ones. Queuing an unknown command straight into the game stops it with an error no script can catch.
- A timer that the game runs while above zero, such as a hellpod's `drop_time`, never finishes at 0. Use 0.01.
- Spawning a unit whose package isn't loaded stops the game. `api.enemies.available(enemy)` checks.
- `api.console.run` refuses commands that reach the shared backend, wipe saves or unlock paid content.
- Only change XP if you've read why the trainer doesn't: the total goes up with the next ordinary results, after any purge.
