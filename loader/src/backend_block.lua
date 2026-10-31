-- No Galactic War or leaderboard reporting while session content is deployed (spec 6.3, layer 3).
-- The hooks sit on the public CampaignManager entry points the game calls. The begin_* functions
-- behind them are reached through locals inside campaign_manager, so hooking those never fires.
-- A blocked call is never sent, and every table passed in is emptied: StateMenu saves the same
-- table back as the upload queue, so the results can't be sent later, not even after a purge.
local B = require("obsidian/loader/builtins")
local log = require("obsidian/loader/log")
local game_text = require("obsidian/loader/game_text")

-- Results wait in these save keys until the ship menu is online, so a mission finished in a session
-- and then a quit or an offline exit would leave them for the next run without session mods to send.
local COMMON_QUEUES = { "mission_stats", "mission_stats_to_upload", "completed_planets" }
local USER_QUEUES = { "leaderboard_stats", "leaderboard_stats_to_upload", "leaderboard_provinggrounds_stats", "leaderboard_provinggrounds_stats_to_upload" }

-- Two, because the game's change of tip loops until it draws a different one.
local TIPS = { "obsidian_forfeit_tip_1", "obsidian_forfeit_tip_2" }

local METHODS = {
	"upload_mission_stats", "upload_leaderboard_stats", "upload_leaderboard_provinggrounds_stats",
	"complete_planets", "complete_defend_event_mission", "complete_attack_event_mission",
}

local M = {}

-- A player with no session mods of their own, who lets others' in, is in a modded game too when
-- someone here runs a different set.
local function modded(core)
	if core.deploy.has_session then return true end
	if not core.consent() then return false end
	for _, m in B.ipairs(core.session.members or {}) do
		if m.obsidian and m.modset ~= core.deploy.modset then return true end
	end
	return false
end

local function empty(t)
	local keys = {}
	for k in B.pairs(t) do keys[#keys + 1] = k end
	for _, k in B.ipairs(keys) do t[k] = nil end
end

function M.setup(core, hooks)
	-- Every way the game pays a player, proving grounds and a quit included, ends in this one write.
	-- These are loader hooks, so a stranger joining late can't let it through.
	hooks.loader_hook("SaveManager", "user_set", function(original, self, key, ...)
		if core.session.holds(key) then return end
		return original(self, key, ...)
	end)
	hooks.loader_hook("UserManager", "unlock_trophy", function(original, self, ...)
		if core.session.forfeited then return end
		return original(self, ...)
	end)
	-- The loading screen's tip line is drawn even with hints off, and the player reads it before the
	-- drop, so this replaces the message that would come up in the mission.
	hooks.loader_hook("StateMissionStart", "on_enter", function(original, self, ...)
		original(self, ...)
		if not core.session.mission_held() then return end
		for _, tip in B.ipairs(TIPS) do game_text.replace(core, hooks, tip, "progress_forfeited") end
		self.loading_tips, self.selected_tip = TIPS, TIPS[1]
		core.session.warned = true
	end)
	-- A forfeit ends with the mission, or the Armory couldn't spend samples on the ship.
	hooks.loader_hook("StateGame", "on_enter", function(original, self, ...)
		local warned = core.session.warned
		core.session.end_forfeit()
		core.session.warned = warned
		return original(self, ...)
	end)
	hooks.loader_hook("StateMenu", "on_enter", function(original, self, ...)
		core.session.end_forfeit()
		return original(self, ...)
	end)
	for _, name in B.ipairs(METHODS) do
		hooks.loader_hook("CampaignManager", name, function(original, self, ...)
			if not modded(core) then return original(self, ...) end
			for i = 1, B.select("#", ...) do
				local v = (B.select(i, ...))
				if B.type(v) == "table" then empty(v) end
			end
			log.limited("upload " .. name, "blocked upload: " .. name)
		end)
	end
	hooks.loader_hook("SaveManager", "save", function(original, self, ...)
		core.session.restore_progress()
		if modded(core) then
			for _, key in B.ipairs(COMMON_QUEUES) do self:set(key, nil) end
		end
		return original(self, ...)
	end)
	hooks.loader_hook("SaveManager", "user_save", function(original, self, done, fail, subtitle, details, user, ...)
		core.session.restore_progress()
		if modded(core) then
			for _, key in B.ipairs(USER_QUEUES) do self:user_set(key, nil, user) end
		end
		return original(self, done, fail, subtitle, details, user, ...)
	end)
	if not core.deploy.has_session then return end
	-- The mission end screen picks one of these two for the Galactic Campaign line.
	game_text.replace(core, hooks, "mission_end_galactic_campaign_progress", "campaign_not_uploaded")
	game_text.replace(core, hooks, "mission_end_galactic_campaign_no_progress", "campaign_not_uploaded")
	log.line("galactic war reporting blocked: session content is deployed")
end

return M
