-- No Galactic War or leaderboard reporting while session content is deployed (spec 6.3, layer 3).
-- The hooks sit on the public CampaignManager entry points the game calls. The begin_* functions
-- behind them are reached through locals inside campaign_manager, so hooking those never fires.
-- A blocked call is never sent, and every table passed in is emptied: StateMenu saves the same
-- table back as the upload queue, so the results can't be sent later, not even after a purge.
local B = require("obsidian/loader/builtins")
local log = require("obsidian/loader/log")
local game_text = require("obsidian/loader/game_text")

local METHODS = {
	"upload_mission_stats", "upload_leaderboard_stats", "upload_leaderboard_provinggrounds_stats",
	"complete_planets", "complete_defend_event_mission", "complete_attack_event_mission",
}

local M = {}

local function empty(t)
	local keys = {}
	for k in B.pairs(t) do keys[#keys + 1] = k end
	for _, k in B.ipairs(keys) do t[k] = nil end
end

function M.setup(core, hooks)
	if not core.deploy.has_session then return end
	for _, name in B.ipairs(METHODS) do
		hooks.loader_hook("CampaignManager", name, function(_, _, ...)
			for i = 1, B.select("#", ...) do
				local v = (B.select(i, ...))
				if B.type(v) == "table" then empty(v) end
			end
			log.limited("upload " .. name, "blocked upload: " .. name)
		end)
	end
	-- The mission end screen picks one of these two for the Galactic Campaign line.
	game_text.replace(core, hooks, "mission_end_galactic_campaign_progress", "campaign_not_uploaded")
	game_text.replace(core, hooks, "mission_end_galactic_campaign_no_progress", "campaign_not_uploaded")
	log.line("galactic war reporting blocked: session content is deployed")
end

return M
