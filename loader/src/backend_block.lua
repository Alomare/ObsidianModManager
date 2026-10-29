-- No Galactic War or leaderboard reporting while session content is deployed (spec 6.3, layer 3).
-- The hooks sit on the public CampaignManager entry points the game calls. The begin_* functions
-- behind them are reached through locals inside campaign_manager, so hooking those never fires.
-- A blocked call is never sent, and every table passed in is emptied: StateMenu saves the same
-- table back as the upload queue, so the results can't be sent later, not even after a purge.
local B = require("obsidian/loader/builtins")
local log = require("obsidian/loader/log")

local METHODS = {
	"upload_mission_stats", "upload_leaderboard_stats", "upload_leaderboard_provinggrounds_stats",
	"complete_planets", "complete_defend_event_mission", "complete_attack_event_mission",
}

-- The two texts the mission end screen picks between for the Galactic Campaign line.
local CAMPAIGN_TEXTS = { mission_end_galactic_campaign_progress = true, mission_end_galactic_campaign_no_progress = true }

local M = {}

-- LocalizationManager.string runs for every text on screen, every frame, so this wrapper stays
-- lean instead of going through the protected hook path.
local function wrap_campaign_text(core)
	local lm = B.rawget(B.G, "LocalizationManager")
	if B.type(lm) ~= "table" or B.type(lm.string) ~= "function" then return false end
	local original = lm.string
	lm.string = function(self, key, ...)
		if CAMPAIGN_TEXTS[key] then return core.text("campaign_not_uploaded") end
		return original(self, key, ...)
	end
	log.line("hook installed: LocalizationManager.string")
	return true
end

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
	if not wrap_campaign_text(core) then
		local done = false
		hooks.on_frame(function()
			if not done then done = wrap_campaign_text(core) end
		end)
	end
	log.line("galactic war reporting blocked: session content is deployed")
end

return M
