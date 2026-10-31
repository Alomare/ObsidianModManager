-- Obsidian Trainer: an in-game menu built only on the public Obsidian API.
local t = obsidian.text
local player = obsidian.module("pages/player")
local weapons = obsidian.module("pages/weapons")
local stratagems = obsidian.module("pages/stratagems")
local vehicles = obsidian.module("pages/vehicles")
local spawn = obsidian.module("pages/spawn")
local enemies = obsidian.module("pages/enemies")
local mission = obsidian.module("pages/mission")
local world = obsidian.module("pages/world")
local editor = obsidian.module("pages/editor")
local progress = obsidian.module("pages/progress")
local console = obsidian.module("pages/console")
local changes = obsidian.module("pages/changes")

-- The title is a function: at boot the game's language isn't known yet.
local function page(key, build, icon)
	obsidian.menu.add(function() return t(key) end, build, { icon = icon })
end

obsidian.after_startup(function()
	page("page_player", player, "player")
	page("page_weapons", weapons, "weapons")
	page("page_stratagems", stratagems, "stratagems")
	page("page_vehicles", vehicles, "vehicles")
	page("page_spawn", spawn, "spawn")
	page("page_enemies", enemies, "enemies")
	page("page_mission", mission, "mission")
	page("page_world", world, "world")
	page("page_editor", editor.build, "editor")
	page("page_progress", progress, "progress")
	page("page_console", console, "console")
	page("page_changes", changes.build, "changes")
end)

obsidian.keybind("open", function() obsidian.menu.toggle() end)

-- A session that stops being cleared switches everything off, and the player should hear why.
obsidian.on_session(function(on)
	if on then
		obsidian.toast(t("session_on"))
	else
		obsidian.toast(t("session_off"), 8)
	end
end)

if obsidian.settings.get("keep_edits") then
	obsidian.on_frame(function() return changes.load_saved() end)
end
