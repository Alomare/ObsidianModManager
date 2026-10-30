-- The parts of the game the menu touches: the brightness world, Gui, the input stacks and an
-- edge-triggered keyboard. pressed() is true for the one frame a key goes down, as in the game.
local F = {}

local KEYS = { "up", "down", "left", "right", "enter", "esc", "tab", "e", "q", "w", "a", "s", "d", "left shift", "f6" }

function F.install(e, opts)
	opts = opts or {}
	local ui = { rects = {}, texts = {}, focus = {}, interfaces = {}, down = {}, tapped = {}, state = opts.state or "game", destroyed = 0, typed = {} }
	e.ui = ui

	rawset(_G, "Vector3", function(x, y, z) return { x = x, y = y, z = z } end)
	rawset(_G, "Vector2", function(x, y) return { x = x, y = y } end)
	rawset(_G, "Color", function(a, r, g, b) return { a, r, g, b } end)
	rawset(_G, "Gui", {
		rect = function(_, pos, size, color) ui.rects[#ui.rects + 1] = { pos = pos, size = size, color = color } end,
		text = function(_, text, font, size, material, pos, color)
			ui.texts[#ui.texts + 1] = { text = text, font = font, size = size, material = material, pos = pos, color = color }
		end,
	})
	rawset(_G, "World", {
		create_screen_gui = function(world, a, b, c)
			ui.gui_args = { world, a, b, c }
			return "gui"
		end,
		destroy_gui = function() ui.destroyed = ui.destroyed + 1 end,
	})
	local application = rawget(_G, "Application")
	application.resolution = function() return ui.width or 1920, ui.height or 1080 end
	rawset(_G, "Script", { temp_count = function() return 1, 2, 3 end, set_temp_count = function() end })
	rawset(_G, "ENGINE_DT", 0.016)
	rawset(_G, "KEYBOARD_MOUSE_USER_NAME", "keyboard_mouse")
	rawset(_G, "ControllerSettings", { pad = {} })

	local boot = rawget(_G, "Boot")
	boot.brightness_world = "brightness"
	boot.state_machine = {
		get_current_state_name = function() return ui.state end,
		get_current_state = function() return ui.state_object or {} end,
	}

	rawset(_G, "InputManager", {
		has_interface = function(_, user, name) return ui.interfaces[user .. "/" .. name] == true end,
		create_controller_interface = function(_, user, name) ui.interfaces[user .. "/" .. name] = true end,
		take_focus = function(_, user, name) ui.focus[user] = name end,
		release_focus = function(_, user) ui.focus[user] = nil end,
	})
	rawset(_G, "PadManager", {
		users = { { name = "user1" } },
		create_rebindable_interface = function(_, name) ui.interfaces["user1/" .. name] = true end,
		get_inputs = function() return ui.pad or {} end,
	})

	local keyboard = rawget(_G, "Keyboard")
	keyboard.button_index = function(name)
		for i, n in ipairs(KEYS) do
			if n == name then return i end
		end
		return nil
	end
	keyboard.pressed = function(i) return ui.tapped[KEYS[i]] == true end
	keyboard.button = function(i) return (ui.down[KEYS[i]] or ui.tapped[KEYS[i]]) and 1 or 0 end

	-- One frame with these keys going down.
	function ui.tap(...)
		for _, k in ipairs({ ... }) do ui.tapped[k] = true end
		ui.rects, ui.texts = {}, {}
		e:frames(1)
		ui.tapped = {}
	end

	function ui.frame()
		ui.rects, ui.texts = {}, {}
		e:frames(1)
	end

	function ui.shown(needle)
		for _, t in ipairs(ui.texts) do
			if string.find(t.text, needle, 1, true) then return true end
		end
		return false
	end

	-- A stand-in for the game's text field. Keys typed since the last frame arrive in ui.typed.
	rawset(_G, "GuiItems", {
		InputField = {
			do_input = function(text)
				local out, finished, cancelled = text, false, false
				for _, k in ipairs(ui.typed) do
					if k == "enter" then
						finished = true
					elseif k == "esc" then
						finished, cancelled = true, true
					else
						out = out .. k
					end
				end
				ui.typed = {}
				return out, out ~= text, finished, cancelled
			end,
		},
	})
	return ui
end

return F
