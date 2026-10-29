-- The bundled Obsidian Quality of Life mod, run from bundled/obsidian.qol/main.lua as a client mod.
local E = require "fake_engine"
local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local IDS = { "skip_intro", "skip_login", "skip_war_briefs", "skip_planet_scanning", "widescreen" }

-- off: option ids switched off in settings.txt; every other option keeps the default (on).
local function engine(off)
	local options, lines = {}, {}
	for _, id in ipairs(IDS) do options[#options + 1] = { id = id, type = "toggle", default = true } end
	for _, id in ipairs(off or {}) do lines[#lines + 1] = "option\tobsidian.qol\t" .. id .. "\ttoggle\t0\n" end
	local e = E.new({
		deploy = E.deploy({ mods = { E.mod("obsidian.qol", { options = options }) } }),
		mods = { ["obsidian/mods/obsidian.qol/main"] = E.read("bundled/obsidian.qol/main.lua") },
		settings = table.concat(lines),
	})
	e:boot()
	e:start_frames()
	return e
end

local function load_states(e)
	local seen = {}
	rawset(_G, "StateMainMenu", {
		NETWORK_SETUP_LOGIN = 3,
		update = function(self, dt) seen.updates = (seen.updates or 0) + 1 end,
	})
	rawset(_G, "StateMenu", { on_enter = function(self, params) seen.recap = params and params.show_recap end })
	e.opts.modules["lua/states/state_main_menu"] = true
	rawget(_G, "require")("lua/states/state_main_menu")
	return seen
end

local function main_menu(showing, step)
	local sm = { prepared = nil }
	function sm:is_prepared(name) return self.prepared == name end
	function sm:is_preparing() return false end
	function sm:is_any_preparing() return false end
	function sm:unprepare() self.prepared = nil end
	function sm:prepare(name) self.prepared = name end
	return setmetatable({ showing_menu = showing, network_setup_state = step, state_machine = sm }, { __index = rawget(_G, "StateMainMenu") })
end

-- The login click lands once the menu takes input (ready), as a player's click would.
local function clicking_menu(ready)
	rawset(_G, "KEYBOARD_MOUSE_PAD_NUMBER", 7)
	local menu = main_menu(false, 1)
	menu.ready = ready
	function menu:handle_input(input, inputs)
		self.inputs_seen = (self.inputs_seen or 0) + 1
		if self.ready and input.select then
			self.showing_menu = true
			self.main_pad = inputs[1].pad_number
		end
	end
	return menu
end

local function update(menu) rawget(_G, "StateMainMenu").update(menu, 0.016) end

test("skip_intro_sets_skip_splash", function()
	local e = engine()
	E.eq(rawget(_G, "ARGUMENTS").skip_splash, true, "ARGUMENTS")
	rawset(_G, "Boot", { arguments = {} })
	e:frames(1)
	E.eq(rawget(_G, "Boot").arguments.skip_splash, true, "Boot.arguments")
end)

test("skip_login_clicks_then_goes_online_once", function()
	local e = engine()
	local seen = load_states(e)
	local menu = clicking_menu(false)
	update(menu)
	E.eq(menu.showing_menu, false, "logo still showing")
	menu.ready = true
	update(menu)
	E.eq(menu.showing_menu, true, "menu took the click")
	E.eq(menu.main_pad, 7, "keyboard and mouse")
	local count = menu.inputs_seen
	update(menu)
	E.eq(menu.inputs_seen, count, "no more clicks once the menu shows")
	menu.network_setup_state = 3
	update(menu)
	E.eq(seen.updates, 4, "original update once per frame")
	E.eq(menu.wants_exit, true, "wants_exit")
	E.eq(menu.wanted_state, "menu", "wanted_state")
	E.eq(menu.backend_type, "STEAM", "backend_type")
	E.eq(menu.state_machine.prepared, "menu", "prepared state")
	E.eq(rawget(_G, "ARGUMENTS").autohost, nil, "autohost never set")
	local again = main_menu(true, 3)
	update(again)
	E.eq(again.wants_exit, nil, "second visit to the main menu")
	E.has(e:log("obsidianqol"), "skip login: going online to the ship")
end)

test("skip_login_waits_for_the_login_step", function()
	local e = engine()
	load_states(e)
	local early = main_menu(true, 1)
	update(early)
	E.eq(early.wants_exit, nil, "before the login step")
	early.network_setup_state = 3
	update(early)
	E.eq(early.backend_type, "STEAM", "once the login step comes")
end)

test("skip_login_error_is_logged_and_left_to_the_player", function()
	local e = engine()
	local seen = load_states(e)
	local menu = clicking_menu(true)
	function menu:handle_input() error("boom") end
	update(menu)
	update(menu)
	E.eq(seen.updates, 2, "original update once per frame")
	E.eq(E.count(e:log("obsidianqol"), "skip login: click failed"), 1, "logged once")
end)

test("skip_war_briefs_skips_the_recap", function()
	local e = engine()
	local seen = load_states(e)
	rawget(_G, "StateMenu").on_enter({}, { show_recap = true })
	E.eq(seen.recap, false)
end)

test("skip_planet_scanning_shortens_every_step", function()
	local e = engine()
	rawset(_G, "CampaignSettings", { planet_scanning_states = { { name = "wait", time = 1 }, { name = "first_scan", time = 0.75 } } })
	e:frames(1)
	for _, step in ipairs(rawget(_G, "CampaignSettings").planet_scanning_states) do E.eq(step.time, 0.01, step.name) end
	rawset(_G, "CampaignSettings", { planet_scanning_states = { { name = "wait", time = 1 } } })
	e:frames(1)
	E.eq(rawget(_G, "CampaignSettings").planet_scanning_states[1].time, 0.01, "a replaced table")
end)

test("widescreen_lifts_the_aspect_ratio_limit", function()
	rawset(_G, "GameSettings", { max_aspect_ratio = 16 / 9 })
	engine()
	E.eq(rawget(_G, "GameSettings").max_aspect_ratio, 10)
end)

test("options_off_change_nothing", function()
	rawset(_G, "GameSettings", { max_aspect_ratio = 16 / 9 })
	local e = engine(IDS)
	local seen = load_states(e)
	rawset(_G, "CampaignSettings", { planet_scanning_states = { { name = "wait", time = 1 } } })
	e:frames(1)
	E.eq(rawget(_G, "ARGUMENTS").skip_splash, nil, "intro")
	local menu = clicking_menu(true)
	update(menu)
	E.eq(menu.showing_menu, false, "login")
	rawget(_G, "StateMenu").on_enter({}, { show_recap = true })
	E.eq(seen.recap, true, "war briefs")
	E.eq(rawget(_G, "CampaignSettings").planet_scanning_states[1].time, 1, "planet scanning")
	E.eq(rawget(_G, "GameSettings").max_aspect_ratio, 16 / 9, "widescreen")
end)

return T
