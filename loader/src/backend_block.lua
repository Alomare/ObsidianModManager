-- No Galactic War or leaderboard reporting while session content is deployed (spec 6.3, layer 3).
-- The game keeps unsent results in memory and retries on a timer, so a blocked upload is simply
-- never sent; the local save still updates as usual.
local log = require("obsidian/loader/log")

local METHODS = { "begin_upload_mission_stats", "begin_upload_leaderboard_stats", "begin_upload_leaderboard_provinggrounds_stats" }

local M = {}

function M.setup(core, hooks)
	if not core.deploy.has_session then return end
	for _, name in ipairs(METHODS) do
		hooks.loader_hook("CampaignManager", name, function()
			log.limited("upload " .. name, "blocked upload: " .. name)
		end)
	end
	log.line("galactic war reporting blocked: session content is deployed")
end

return M
