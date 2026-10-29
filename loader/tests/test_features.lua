local E = require "fake_engine"
local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local function engine(features)
	local e = E.new({ deploy = E.deploy({ features = features }) })
	e:boot()
	e:start_frames()
	return e
end

local function load_states(e)
	local seen = {}
	rawset(_G, "StateMainMenu", {
		NETWORK_SETUP_LOGIN = 3,
		on_enter = function(self, params)
			seen.autohost_during = rawget(_G, "ARGUMENTS").autohost
			if rawget(_G, "ARGUMENTS").autohost then self.wanted_state = "menu" end
		end,
		update = function(self, dt) seen.updates = (seen.updates or 0) + 1 end,
	})
	rawset(_G, "StateMenu", { on_enter = function(self, params) seen.recap = params and params.show_recap end })
	e.opts.modules["lua/states/state_main_menu"] = true
	rawget(_G, "require")("lua/states/state_main_menu")
	return seen
end

test("skip_intro_sets_skip_splash", function()
	local e = engine({ "skip_intro" })
	E.eq(rawget(_G, "ARGUMENTS").skip_splash, true, "ARGUMENTS")
	rawset(_G, "Boot", { arguments = {} })
	e:frames(1)
	E.eq(rawget(_G, "Boot").arguments.skip_splash, true, "Boot.arguments")
end)

-- A main menu instance at a given network setup step, with the state machine the menu prepares.
local function main_menu(showing, step)
	local sm = { prepared = nil }
	function sm:is_prepared(name) return self.prepared == name end
	function sm:is_preparing() return false end
	function sm:is_any_preparing() return false end
	function sm:unprepare() self.prepared = nil end
	function sm:prepare(name) self.prepared = name end
	return setmetatable({ showing_menu = showing, network_setup_state = step, state_machine = sm }, { __index = rawget(_G, "StateMainMenu") })
end

-- The same steps the game takes for a Steam invite: the online backend, so the campaign goes online.
test("skip_login_goes_online_to_the_ship_once", function()
	local e = engine({ "skip_login" })
	local seen = load_states(e)
	local menu = main_menu(true, 3)
	rawget(_G, "StateMainMenu").update(menu, 0.016)
	E.eq(seen.updates, 1, "original update")
	E.eq(menu.wants_exit, true, "wants_exit")
	E.eq(menu.wanted_state, "menu", "wanted_state")
	E.eq(menu.backend_type, "STEAM", "backend_type")
	E.eq(menu.state_machine.prepared, "menu", "prepared state")
	E.eq(rawget(_G, "ARGUMENTS").autohost, nil, "autohost never set")
	local again = main_menu(true, 3)
	rawget(_G, "StateMainMenu").update(again, 0.016)
	E.eq(again.wants_exit, nil, "second visit to the main menu")
end)

test("skip_login_waits_for_the_login_step", function()
	local e = engine({ "skip_login" })
	load_states(e)
	local early = main_menu(true, 1)
	rawget(_G, "StateMainMenu").update(early, 0.016)
	E.eq(early.wants_exit, nil, "before the login step")
	local hidden = main_menu(false, 3)
	rawget(_G, "StateMainMenu").update(hidden, 0.016)
	E.eq(hidden.wants_exit, nil, "menu not showing yet")
	rawget(_G, "StateMainMenu").update(early, 0.016)
	early.network_setup_state = 3
	rawget(_G, "StateMainMenu").update(early, 0.016)
	E.eq(early.backend_type, "STEAM", "once the login step comes")
end)

test("skip_war_briefs_skips_the_recap", function()
	local e = engine({ "skip_war_briefs" })
	local seen = load_states(e)
	rawget(_G, "StateMenu").on_enter({}, { show_recap = true })
	E.eq(seen.recap, false)
end)

test("features_off_change_nothing", function()
	local e = engine({})
	local seen = load_states(e)
	E.eq(rawget(_G, "ARGUMENTS").skip_splash, nil)
	local menu = {}
	rawget(_G, "StateMainMenu").on_enter(menu, {})
	E.eq(menu.wanted_state, nil)
	rawget(_G, "StateMenu").on_enter({}, { show_recap = true })
	E.eq(seen.recap, true)
end)

test("unknown_feature_is_logged_and_ignored", function()
	local e = engine({ "fly" })
	E.has(e:log(), "unknown feature fly")
end)

return T
