---
title: Obsidian Trainer
group: Getting started
summary: The in-game menu that changes almost anything.
---

Obsidian Trainer is an in-game menu for your character, weapons, stratagems, enemies and missions, and for the game's own numbers. It comes with Obsidian and starts off.

## Turning it on

Switch on **Obsidian Trainer** in the Mods list and deploy. Obsidian API, the mod it's built on, turns on with it. In the game, press **F6** to open the menu. You can change the key in the mod's Keys tab.

| Key | What it does |
|---|---|
| Arrows, or W A S D | Move, and change a value |
| Enter, or E | Select, or type a number |
| Shift with left or right | Change a number ten steps at a time |
| Tab | Filter the list |
| Esc, or Q | Go back, and close |

The menu also works with the mouse, using your normal system cursor.

| Mouse | What it does |
|---|---|
| Point at a row | Select it |
| Click a row | Use it |
| Click `<` or `>` | Change a value, and hold to keep changing it |
| Click a number | Type a value |
| Wheel, or the bar at the side | Scroll the list |
| Right click | Go back |
| Title bar | Drag to move the window |
| Bottom right corner | Drag to resize the window |

The window remembers its place and size.

The menu blocks your character while it's open, and it closes by itself when the game changes screens, such as at the start of a mission. A gamepad can move around the menu, but F6 opens it.

## What's in it

- **Player:** god mode, infinite sprint, speed, teleporting, respawning, and helmets, armor and capes you own.
- **Weapons:** infinite ammo, instant reload, refills, and giving yourself any weapon, backpack or perk you own, with the upgrades you choose.
- **Stratagems:** no cooldowns, unlimited uses, instant call-ins, ignoring no-stratagem zones, any stratagem dropped at the cursor, and real flares, Reinforce included.
- **Vehicles:** speed, turning, armor, no damage and endless exosuit rockets for the vehicle you're driving, plus repairs and refills.
- **Spawn:** ammunition, supply crates and pickups on the spot, and flares at the cursor.
- **Enemies:** stopping spawns, freezing, blinding or stunning enemies, killing them, spawning more, and setting how hard encounters and patrols push.
- **Mission:** the objective list, finishing objectives, protecting convoys and escorts, fast extraction, skipping waits, proving ground modifiers in any mission, who's in the lobby, research samples, and practice missions of any kind from the ship.
- **World:** game speed, camera, HUD, fog, time of day and gravity.
- **Editor:** the numbers of every weapon, grenade, backpack, stratagem, sentry, mine, strike, vehicle, enemy and status effect.
- **Progress:** samples and unlocks.
- **Console:** the developers' own commands.
- **Changes:** what's switched on, and the way back.

Actions that only the host can do say so when you choose them.

## What it won't do

- **It has no control for your XP or rank.** Your total XP goes up with your next ordinary mission results, even after a purge, so an edited number would reach the shared leaderboards. Real missions still pay XP, though. Ending one with **Win now**, **Fast extraction** or **Finish all objectives** adds the usual XP to your save, and your next clean mission uploads that total. Practice missions pay nothing.
- **It won't unlock paid DLC.** Lists show the items you own, and everything else stays as the game sells it.
- **It won't touch the shared war.** Commands that report to the Galactic War are refused, and results stay blocked ([The Galactic War](wiki:galactic-war)).

> [!WARNING]
> The game has an anti-tamper check that cuts you off from the network until you restart it. Obsidian Trainer changes guarded values only the way the game itself does, so it shouldn't trigger. Other tools and hand-made scripts can.

## Playing with others

The trainer is a session mod, so everyone in the lobby has to run the same mods or allow session mods ([Playing online](wiki:multiplayer)). If someone joins who hasn't, every change is undone and the menu stops until they leave. Then your changes come back.

Numbers from the Editor and the two damage rows are simulated on each player's own game, so they work best when everyone uses the same ones.

Two things need you to be alone in the lobby: giving yourself laser sight, because other players' games would run it with no setup, and the console's `spawn_enemy`, because it loads a package on your game only.

> [!NOTE]
> Steam achievements are held back while Obsidian API is on, so nothing you do with the trainer earns one.

## Keeping changes

Changes last until you close the game. In **Changes**, **Keep these edits for next time** saves your Editor edits, and they come back at each launch while the mod's **Keep saved edits** option is on.

Unlocks and samples go into your real save. Obsidian backs up your saves before every deploy, including the ones in Steam Cloud.
