-- Obsidian Quality of Life: small fixes for the game, each one an option.
local get = obsidian.settings.get

-- Changes a settings table as soon as the game defines it, and again if the game ever replaces the
-- table with a new one. The per-frame check is one lookup and one comparison.
local function when_defined(name, change)
	local last
	local function check()
		local t = rawget(_G, name)
		if type(t) == "table" and t ~= last then
			last = t
			change(t)
		end
	end
	check()
	obsidian.on_frame(check)
end

-- StateLogos and the intro cutscene skip when Boot.arguments.skip_splash is set. Boot.arguments is
-- built from ARGUMENTS after mods start, and the frame callback covers the case where it isn't.
if get("skip_intro") then
	local a = rawget(_G, "ARGUMENTS")
	if type(a) == "table" then a.skip_splash = true end
	obsidian.on_frame(function()
		local boot = rawget(_G, "Boot")
		if type(boot) == "table" and type(boot.arguments) == "table" then
			boot.arguments.skip_splash = true
			return true
		end
	end)
end

-- Two steps, the first visit to the main menu only, so quitting to the main menu works:
-- 1. The login click: the menu's own handle_input gets select from keyboard and mouse every frame
--    until the menu takes the input (showing_menu), so the game's own checks (logo done, fades)
--    still decide when. That also makes keyboard and mouse the main pad, as a click would.
-- 2. At the login step, the steps the menu takes for a Steam invite: ask for the ship with the
--    Steam backend. The menu finishes the online setup (backend, campaign) before it leaves.
-- ARGUMENTS.autohost would skip both but picks the LAN backend, which stays offline.
if get("skip_login") then
	local clicked, done = false, false
	local function click(self)
		local pad = rawget(_G, "KEYBOARD_MOUSE_PAD_NUMBER")
		if pad == nil or type(self.handle_input) ~= "function" then return end
		local input = { select = true }
		local ok, err = pcall(self.handle_input, self, input, { { pad_number = pad, input_data = input } })
		if not ok then
			clicked = true
			obsidian.log("skip login: click failed, left to the player:", err)
		elseif self.showing_menu then
			clicked = true
			obsidian.log("skip login: clicked for keyboard and mouse")
		end
	end
	local function after_update(self)
		if done or type(self) ~= "table" or self.wants_exit then return end
		if not self.showing_menu then
			if not clicked then click(self) end
			return
		end
		if self.network_setup_state == nil or self.network_setup_state ~= self.NETWORK_SETUP_LOGIN then return end
		done = true
		self.wants_exit = true
		self.wanted_state = "menu"
		self.exit_timer = 0
		self.backend_type = "STEAM"
		local sm = self.state_machine
		if type(sm) == "table" and not sm:is_prepared("menu") and not sm:is_preparing("menu") then
			if sm:is_any_preparing() then sm:unprepare() end
			sm:prepare("menu")
		end
		obsidian.log("skip login: going online to the ship")
	end
	obsidian.hook("StateMainMenu", "update", function(original, self, ...)
		local r = { original(self, ...) }
		-- Protected here, so an error never makes the hook run the game's update a second time.
		local ok, err = pcall(after_update, self)
		if not ok then
			done = true
			obsidian.log("skip login: stopped after an error:", err)
		end
		return unpack(r)
	end)
end

-- The war brief after a long absence is the campaign recap, opened by show_recap when the ship
-- loads. The war-end sequence (state_season_end) writes the save and is left alone.
if get("skip_war_briefs") then
	obsidian.hook("StateMenu", "on_enter", function(original, self, params, ...)
		if type(params) == "table" and params.show_recap then
			params.show_recap = false
			obsidian.log("skip war briefs: recap skipped")
		end
		return original(self, params, ...)
	end)
end

-- The planet discovery animation is a list of timed steps in CampaignSettings (about 6.75 s in
-- all). Each step keeps a tiny time instead of 0, so the screen never divides by zero.
if get("skip_planet_scanning") then
	when_defined("CampaignSettings", function(s)
		for _, step in ipairs(s.planet_scanning_states or {}) do
			if type(step) == "table" and type(step.time) == "number" then step.time = 0.01 end
		end
		obsidian.log("skip planet scanning: steps shortened")
	end)
end

-- Every game state limits the viewport to GameSettings.max_aspect_ratio (16:9), which letterboxes
-- wider screens. A high limit lets the viewport fill the screen.
if get("widescreen") then
	when_defined("GameSettings", function(s)
		if type(s.max_aspect_ratio) == "number" then
			s.max_aspect_ratio = 10
			obsidian.log("widescreen: aspect ratio limit lifted")
		end
	end)
end

-- The mission end screens are sub-states of StateMissionEnd: change_state(self, sub) calls
-- sub.on_enter(self), and the state's update hands sub.update(self, dt) the frame time. Waiting
-- for data writes the save and Done calls save_stats, so both always run at full length; the
-- screens between them only show results. Three screens wait until every player presses
-- continue, and this player's presses are made for them (other players still press their own).
-- Instant goes from waiting for data straight to Done, as the game's own debug skip does.
-- Faster runs each result screen in about a second: steps listed in sub_state_states are timed
-- to fit, and a screen still showing after that runs ever faster until it ends.
local expedite = get("expedite_mission_end")
if expedite == "faster" or expedite == "instant" then
	local SHOWN = {
		"MissionEndStateMissionResult", "MissionEndStateMissionScore", "MissionEndStateGenocideResults",
		"MissionEndStateExperienceDistribution", "MissionEndStateIndividualStats", "MissionEndStatePrePlanetPause",
		"MissionEndStatePlanetCompleted", "MissionEndStatePlanetCompletedScore", "MissionEndStatePlanetCompletedReward",
		"MissionEndStateEventCompletedScore", "MissionEndStateEventCompletedReward", "MissionEndStateProvinggroundsCompleted",
		"MissionEndOverlayLevelUp",
	}
	local READY = {
		MissionEndStateGenocideResults = "is_ready_genocide",
		MissionEndStatePrePlanetPause = "is_ready_planet",
		MissionEndStateDone = "is_ready",
	}
	local PHASE = 1
	local phase = { elapsed = 0, speed = 1, pressed = false }

	local function current(self)
		for name in pairs(READY) do
			if self.current_state ~= nil and self.current_state == rawget(_G, name) then return name end
		end
	end

	-- Instant presses for all three screens at once: a host still showing one of them waits for
	-- this player's press there.
	local function press(self)
		local name = current(self)
		if not name or phase.pressed then return end
		phase.pressed = true
		for _, p in ipairs(self.players or {}) do
			local go = p.player_go
			if go and go:owned() then
				if expedite == "instant" then
					for _, flag in pairs(READY) do go:set(flag, true) end
				else
					go:set(READY[name], true)
				end
			end
		end
	end

	obsidian.hook("StateMissionEnd", "change_state", function(original, self, sub, ...)
		local done = rawget(_G, "MissionEndStateDone")
		if expedite == "instant" and done and sub ~= nil and sub ~= done and sub ~= rawget(_G, "MissionEndStateWaitingForData") then
			sub = done
			obsidian.log("expedite mission end: results skipped")
		end
		local steps = self.sub_state_states
		local r = { original(self, sub, ...) }
		phase.elapsed, phase.pressed, phase.speed = 0, false, 2
		if self.sub_state_states ~= steps and type(self.sub_state_states) == "table" then
			local total = 0
			for _, step in ipairs(self.sub_state_states) do
				if type(step) == "table" and type(step.time) == "number" then total = total + step.time end
			end
			phase.speed = math.max(1, total / PHASE)
		end
		if expedite == "instant" then press(self) end
		return unpack(r)
	end)

	if expedite == "faster" then
		obsidian.hook("StateMissionEnd", "update", function(original, self, dt, ...)
			if type(dt) == "number" then
				phase.elapsed = phase.elapsed + dt
				if phase.elapsed > PHASE then
					phase.speed = math.min(phase.speed * 1.25, 1000)
					press(self)
				end
			end
			return original(self, dt, ...)
		end)
		for _, name in ipairs(SHOWN) do
			obsidian.hook(name, "update", function(original, self, dt, ...)
				if type(dt) == "number" then dt = dt * phase.speed end
				return original(self, dt, ...)
			end)
		end
	end
end
