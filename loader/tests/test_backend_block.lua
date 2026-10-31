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

-- The game's save, which holds results until the ship menu is online.
local function load_save_manager(e)
	local save = { common = { mission_stats = {}, mission_stats_to_upload = { 1 }, completed_planets = { 1 }, volume_sfx = 5 },
		user = { leaderboard_stats = {}, leaderboard_stats_to_upload = { 1 }, player_xp = 100 }, saves = 0, user_saves = 0 }
	rawset(_G, "SaveManager", {
		set = function(_, k, v) save.common[k] = v end,
		user_set = function(_, k, v, id) save.user[k] = v; save.user_id = id end,
		save = function() save.saves = save.saves + 1 end,
		user_save = function(_, done, fail, subtitle, details, id) save.user_saves = save.user_saves + 1; save.saved_id = id end,
	})
	e.opts.modules["foundation/lua/managers/save_manager"] = true
	rawget(_G, "require")("foundation/lua/managers/save_manager")
	return save
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

test("consent_alone_blocks_uploads_only_beside_a_different_set", function()
	local other = "1;" .. string.rep("c", 64) .. ";1"
	local lobby = { my_id = "me", members = { "me", "p2" }, data = { p2 = other } }
	local e = E.new({ deploy = E.deploy({ has_session = false, modset = string.rep("a", 64) }), lobby = lobby })
	e:boot()
	e:start_frames()
	rawget(_G, "require")("obsidian/loader/core").consent = function() return true end
	e:frames(31)
	local cm = load_campaign_manager(e)
	cm:upload_mission_stats({})
	E.eq(#cm.sent, 0, "someone here runs other session mods")
	lobby.data.p2 = "1;" .. string.rep("a", 64) .. ";1"
	e:frames(31)
	cm:upload_mission_stats({})
	E.eq(#cm.sent, 1, "the same set again")
end)

test("a_forfeited_mission_keeps_the_old_xp_until_the_next_mission", function()
	local e = engine(true, { my_id = "me", members = { "me" }, data = {} })
	local save = load_save_manager(e)
	local sm = rawget(_G, "SaveManager")
	rawset(_G, "StateGame", { on_enter = function() end })
	e.opts.modules["lua/states/state_game"] = true
	rawget(_G, "require")("lua/states/state_game")
	sm:user_set("player_xp", 200, "user")
	E.eq(save.user.player_xp, 200, "an ordinary mission pays")

	local session = rawget(_G, "obsidian").session
	session.forfeit_xp()
	session.forfeit_xp()
	sm:user_set("player_xp", 900, "user")
	E.eq(save.user.player_xp, 200, "every way of paying ends in this write")
	sm:user_set("research_samples", 7, "user")
	E.eq(save.user.research_samples, 7, "other values still save")
	E.eq(E.count(e:log(), "this mission pays no XP"), 1, "told once")
	E.eq(#e:core().notices + #e:core().notices_shown, 1)

	rawget(_G, "StateGame").on_enter({})
	sm:user_set("player_xp", 300, "user")
	E.eq(save.user.player_xp, 300, "the next mission pays again")
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

-- The mission end screen reads one of two texts; with session content both say why nothing was sent.
local function localization()
	local lm = { string = function(_, key) return "game:" .. key end }
	rawset(_G, "LocalizationManager", lm)
	return lm
end

test("mission_end_says_why_progress_was_not_uploaded", function()
	local lm = localization()
	local texts = { en = { campaign_not_uploaded = "Progress was not uploaded to Galactic Campaign due to session mods" } }
	local e = E.new({ deploy = E.deploy({ has_session = true, modset = string.rep("a", 64), texts = texts }) })
	e:boot()
	e:start_frames()
	for _, key in ipairs({ "mission_end_galactic_campaign_progress", "mission_end_galactic_campaign_no_progress" }) do
		E.eq(lm:string(key), "Progress was not uploaded to Galactic Campaign due to session mods", key)
	end
	E.eq(lm:string("menu_play"), "game:menu_play", "other texts")
end)

test("mission_end_text_untouched_without_session_content", function()
	local lm = localization()
	local e = engine(false)
	E.eq(lm:string("mission_end_galactic_campaign_progress"), "game:mission_end_galactic_campaign_progress")
end)

test("results_in_the_save_dont_outlive_a_session", function()
	local e = engine(true)
	local save = load_save_manager(e)
	rawget(_G, "SaveManager"):save()
	E.eq(save.saves, 1, "the save still happens")
	E.eq(save.common.mission_stats_to_upload, nil)
	E.eq(save.common.completed_planets, nil)
	E.eq(save.common.volume_sfx, 5, "everything else stays")
	rawget(_G, "SaveManager"):user_save(nil, nil, nil, nil, "user1")
	E.eq(save.user_saves, 1)
	E.eq(save.saved_id, "user1", "the arguments reach the game")
	E.eq(save.user_id, "user1")
	E.eq(save.user.leaderboard_stats_to_upload, nil)
	E.eq(save.user.player_xp, 100)
end)

test("a_vanilla_setup_leaves_the_save_alone", function()
	local e = engine(false)
	local save = load_save_manager(e)
	rawget(_G, "SaveManager"):save()
	E.eq(#save.common.mission_stats_to_upload, 1)
end)

return T
