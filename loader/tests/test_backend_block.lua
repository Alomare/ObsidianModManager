local E = require "fake_engine"
local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

-- The public entry points the game calls (StateMenu, mission end). The begin_* functions behind
-- them are reached through locals inside campaign_manager, so hooking those never fires.
local METHODS = {
	"upload_mission_stats", "upload_leaderboard_stats", "upload_leaderboard_provinggrounds_stats",
	"complete_planets", "complete_defend_event_mission", "complete_attack_event_mission",
}

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
	E.has(e:log(), "blocked upload: upload_mission_stats")
end)

test("uploads_blocked_even_in_a_cleared_session", function()
	local e = engine(true, { my_id = "me", members = { "me" }, data = {} })
	e:frames(31)
	E.eq(rawget(_G, "obsidian").session.cleared(), true)
	local cm = load_campaign_manager(e)
	cm:upload_mission_stats({})
	E.eq(#cm.sent, 0)
end)

test("uploads_untouched_without_session_content", function()
	local e = engine(false)
	local cm = load_campaign_manager(e)
	for _, m in ipairs(METHODS) do cm[m](cm) end
	E.eq(#cm.sent, #METHODS)
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
	for _ = 1, 20 do cm:upload_mission_stats({}) end
	E.eq(E.count(e:log(), "blocked upload: upload_mission_stats"), 3)
end)

-- StateMenu saves the same table back as the queue after the call, so an emptied table means the
-- results are never sent later, not even after a purge.
test("blocked_upload_empties_the_queue", function()
	local e = engine(true)
	local cm = load_campaign_manager(e)
	local stats = { { kills = 10 }, { kills = 3 } }
	local planets = { 4, 7 }
	cm:upload_mission_stats(stats)
	cm:complete_planets(planets)
	E.eq(next(stats), nil, "mission stats queue")
	E.eq(next(planets), nil, "planets queue")
end)

test("hook_install_is_logged", function()
	local e = engine(true)
	load_campaign_manager(e)
	E.has(e:log(), "hook installed: CampaignManager.upload_mission_stats")
end)

return T
