local E = require "fake_engine"
local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local METHODS = { "begin_upload_mission_stats", "begin_upload_leaderboard_stats", "begin_upload_leaderboard_provinggrounds_stats" }

-- The campaign manager class appears when the game requires the script, after the loader boots.
local function load_campaign_manager(e)
	local cm = { sent = {} }
	for _, m in ipairs(METHODS) do
		cm[m] = function(self) self.sent[#self.sent + 1] = m end
	end
	cm.begin_update_status = function(self) self.sent[#self.sent + 1] = "status" end
	rawset(_G, "CampaignManager", cm)
	e.opts.modules["lua/managers/campaign_manager"] = true
	rawget(_G, "require")("lua/managers/campaign_manager")
	return cm
end

local function engine(has_session, lobby)
	local e = E.new({ deploy = E.deploy({ has_session = has_session, modset = string.rep("a", 64) }), lobby = lobby })
	e:boot()
	e:start_frames()
	return e
end

test("uploads_blocked_with_session_content", function()
	local e = engine(true)
	local cm = load_campaign_manager(e)
	for _, m in ipairs(METHODS) do cm[m](cm) end
	E.eq(#cm.sent, 0, "uploads sent")
	E.has(e:log(), "blocked upload: begin_upload_mission_stats")
end)

test("uploads_blocked_even_in_a_cleared_session", function()
	local e = engine(true, { my_id = "me", members = { "me" }, data = {} })
	e:frames(31)
	E.eq(rawget(_G, "kepler").session.cleared(), true)
	local cm = load_campaign_manager(e)
	cm:begin_upload_mission_stats()
	E.eq(#cm.sent, 0)
end)

test("uploads_untouched_without_session_content", function()
	local e = engine(false)
	local cm = load_campaign_manager(e)
	for _, m in ipairs(METHODS) do cm[m](cm) end
	E.eq(#cm.sent, 3)
	E.lacks(e:log(), "blocked upload")
end)

test("reading_war_status_still_works", function()
	local e = engine(true)
	local cm = load_campaign_manager(e)
	cm:begin_update_status()
	E.eq(cm.sent[1], "status")
end)

test("repeated_retries_log_three_times", function()
	local e = engine(true)
	local cm = load_campaign_manager(e)
	for _ = 1, 20 do cm:begin_upload_mission_stats() end
	E.eq(E.count(e:log(), "blocked upload: begin_upload_mission_stats"), 3)
end)

return T
