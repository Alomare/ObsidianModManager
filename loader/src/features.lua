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

-- StateMainMenu.on_enter goes straight to the ship (wanted_state "menu") when ARGUMENTS.autohost
-- is set. autohost also changes drop zones and mission start elsewhere, so the flag exists only
-- during that one call, and only the first time the game reaches the main menu.
local function skip_login(hooks)
	local done = false
	hooks.loader_hook("StateMainMenu", "on_enter", function(original, self, ...)
		local a = arguments()
		if done or not a then return original(self, ...) end
		done = true
		local was = a.autohost
		a.autohost = true
		local ok, err = B.pcall(original, self, ...)
		a.autohost = was
		log.line("skip login: main menu wants " .. B.tostring(self and self.wanted_state))
		if not ok then B.error(err, 0) end
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
