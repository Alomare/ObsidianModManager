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
		on_enter = function(self, params)
			seen.autohost_during = rawget(_G, "ARGUMENTS").autohost
			if rawget(_G, "ARGUMENTS").autohost then self.wanted_state = "menu" end
		end,
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

test("skip_login_moves_main_menu_to_the_ship_once", function()
	local e = engine({ "skip_login" })
	local seen = load_states(e)
	local menu = {}
	rawget(_G, "StateMainMenu").on_enter(menu, {})
	E.eq(seen.autohost_during, true, "autohost during on_enter")
	E.eq(menu.wanted_state, "menu")
	E.eq(rawget(_G, "ARGUMENTS").autohost, nil, "autohost after on_enter")
	local again = {}
	rawget(_G, "StateMainMenu").on_enter(again, {})
	E.eq(again.wanted_state, nil, "second visit to the main menu")
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
