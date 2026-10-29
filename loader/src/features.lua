-- The built-in features: client scope, each switched on in the app.
local B = require("obsidian/loader/builtins")
local log = require("obsidian/loader/log")

local M = {}

local function arguments()
	local a = B.rawget(B.G, "ARGUMENTS")
	if B.type(a) == "table" then return a end
	return nil
end

-- StateLogos and the intro cutscene both skip when Boot.arguments.skip_splash is set. Boot.arguments
-- is built from ARGUMENTS after the loader runs, and the frame hook covers the case where it isn't.
local function skip_intro(hooks)
	local a = arguments()
	if a then a.skip_splash = true end
	local done = false
	hooks.on_frame(function()
		if done then return end
		local boot = B.rawget(B.G, "Boot")
		if B.type(boot) == "table" and B.type(boot.arguments) == "table" then
			boot.arguments.skip_splash = true
			done = true
		end
	end)
end

-- Takes the steps the main menu takes for a Steam invite: once the menu shows and network setup
-- reaches the login step, ask for the ship with the Steam backend. The menu then finishes the
-- online setup (backend, campaign) before it leaves, so the Galactic Campaign is online.
-- ARGUMENTS.autohost would also skip the login but picks the LAN backend, which stays offline.
-- Only the first visit to the main menu, so quitting to the main menu works.
local function skip_login(hooks)
	local done = false
	hooks.loader_hook("StateMainMenu", "update", function(original, self, ...)
		local r = { original(self, ...) }
		if done or B.type(self) ~= "table" or not self.showing_menu or self.wants_exit then return B.unpack(r) end
		if self.network_setup_state == nil or self.network_setup_state ~= self.NETWORK_SETUP_LOGIN then return B.unpack(r) end
		done = true
		self.wants_exit = true
		self.wanted_state = "menu"
		self.exit_timer = 0
		self.backend_type = "STEAM"
		local sm = self.state_machine
		if B.type(sm) == "table" and not sm:is_prepared("menu") and not sm:is_preparing("menu") then
			if sm:is_any_preparing() then sm:unprepare() end
			sm:prepare("menu")
		end
		log.line("skip login: going online to the ship")
		return B.unpack(r)
	end)
end

-- The war brief after a long absence is the campaign recap, opened by show_recap when the ship loads.
-- The war-end sequence (state_season_end) writes the save and is left alone.
local function skip_war_briefs(hooks)
	hooks.loader_hook("StateMenu", "on_enter", function(original, self, params, ...)
		if B.type(params) == "table" and params.show_recap then
			params.show_recap = false
			log.line("skip war briefs: recap skipped")
		end
		return original(self, params, ...)
	end)
end

local FEATURES = { skip_intro = skip_intro, skip_login = skip_login, skip_war_briefs = skip_war_briefs }

function M.setup(hooks, enabled)
	for _, name in B.ipairs(enabled) do
		local f = FEATURES[name]
		if f then
			f(hooks)
			log.line("feature on: " .. name)
		else
			log.line("unknown feature " .. B.tostring(name))
		end
	end
end

return M
