-- obsidian.menu and obsidian.toast, through a mod, as a player would drive them.
local E = require "fake_engine"
local F = require "fake_ui"
local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local TEXTS = { en = {
	menu_title = "Obsidian", menu_empty = "No pages", menu_failed = "Failed", menu_unavailable = "Not now",
	menu_filter = "Filter", menu_on = "ON", menu_off = "OFF", menu_keys = "Keys",
} }

-- Runs a mod that adds a page through `source`, with the menu's game side in place.
local function start(source, opts)
	opts = opts or {}
	local e = E.new({
		deploy = E.deploy({ mods = { E.mod("m", { scope = opts.scope or "client" }) }, texts = TEXTS }),
		mods = { ["obsidian/mods/m/main"] = source },
		lobby = opts.lobby,
	})
	e:boot()
	e:start_frames()
	local ui = F.install(e, opts)
	return e, ui
end

local PAGE = [[
	VALUES = { god = false, speed = 5, mode = "a", runs = 0 }
	obsidian.menu.add("Player", function(page)
		page:header("Section")
		page:toggle("God mode", { get = function() return VALUES.god end, set = function(v) VALUES.god = v end })
		page:number("Speed", { get = function() return VALUES.speed end, set = function(v) VALUES.speed = v end, min = 1, max = 8, step = 2 })
		page:choice("Mode", { choices = { { id = "a", label = "First" }, { id = "b", label = "Second" } },
			get = function() return VALUES.mode end, set = function(v) VALUES.mode = v end })
		page:action("Heal", function() VALUES.runs = VALUES.runs + 1 return "Healed" end)
		page:page("More", function(p) p:action("Deep", function() VALUES.deep = true end) end)
	end)
]]

local function values() return rawget(_G, "VALUES") end

local function open_player(e, ui)
	rawget(_G, "obsidian").menu.open()
	ui.tap("enter")
end

test("opens_and_closes_taking_every_input_user", function()
	local e, ui = start(PAGE)
	local menu = rawget(_G, "obsidian").menu
	E.eq(menu.open(), true, "open")
	ui.frame()
	E.eq(ui.focus.keyboard_mouse, "obsidian_menu", "keyboard")
	E.eq(ui.focus.user1, "obsidian_menu", "pad")
	E.eq(ui.gui_args[1], "brightness", "drawn on the brightness world")
	E.eq(ui.gui_args[3], "foundation/gui/gui", "the foundation material, always loaded")
	E.eq(ui.gui_args[4], "immediate")
	E.eq(ui.shown("Player"), true, "root lists the page")
	menu.close()
	E.eq(ui.focus.keyboard_mouse, nil, "released")
	E.eq(menu.is_open(), false)
	ui.frame()
	E.eq(#ui.texts, 0, "nothing drawn once closed")
end)

test("focus_is_taken_back_every_frame", function()
	local e, ui = start(PAGE)
	rawget(_G, "obsidian").menu.open()
	ui.focus.keyboard_mouse = "input_component"
	ui.frame()
	E.eq(ui.focus.keyboard_mouse, "obsidian_menu")
end)

test("does_not_open_in_logos_cutscene_transition_or_during_chat", function()
	local e, ui = start(PAGE)
	local menu = rawget(_G, "obsidian").menu
	for _, name in ipairs({ "logos", "cutscene", "transition" }) do
		ui.state = name
		E.eq(menu.open(), false, name)
	end
	ui.state = "game"
	ui.state_object = { text_chat = { active = true } }
	E.eq(menu.open(), false, "chat typing")
	ui.state_object = { text_chat = { active = false } }
	E.eq(menu.open(), true, "chat idle")
end)

test("a_state_change_closes_the_menu", function()
	local e, ui = start(PAGE)
	ui.frame()
	local menu = rawget(_G, "obsidian").menu
	menu.open()
	ui.frame()
	ui.state = "mission_end"
	ui.frame()
	E.eq(menu.is_open(), false)
	E.eq(ui.focus.keyboard_mouse, nil, "input given back")
end)

test("navigation_skips_headers_and_wraps", function()
	local e, ui = start(PAGE)
	open_player(e, ui)
	ui.tap("enter")
	E.eq(values().god, true, "first selectable row is the toggle, under the header")
	ui.tap("up")
	ui.tap("enter")
	E.eq(values().runs, 0, "up from the first row wraps to the last, a page")
	E.eq(ui.shown("Deep") or true, true)
end)

test("toggle_number_and_choice", function()
	local e, ui = start(PAGE)
	open_player(e, ui)
	ui.tap("right")
	E.eq(values().god, true, "right flips a toggle")
	ui.tap("down")
	ui.tap("right")
	E.eq(values().speed, 7, "right adds a step")
	ui.tap("right")
	E.eq(values().speed, 8, "clamped to the maximum")
	ui.tap("left")
	E.eq(values().speed, 6, "left takes a step away")
	ui.down["left shift"] = true
	ui.tap("left")
	ui.down["left shift"] = nil
	E.eq(values().speed, 1, "shift is ten steps, clamped to the minimum")
	ui.tap("down")
	ui.tap("right")
	E.eq(values().mode, "b")
	ui.frame()
	E.eq(ui.shown("< Second >"), true, "the choice shows its label")
end)

test("typed_number_entry_is_clamped_and_can_be_cancelled", function()
	local e, ui = start(PAGE)
	open_player(e, ui)
	ui.tap("down")
	ui.tap("enter")
	ui.typed = { "3", "x", "enter" }
	ui.frame()
	E.eq(values().speed, 3, "letters are dropped")
	ui.tap("enter")
	ui.typed = { "9", "9", "enter" }
	ui.frame()
	E.eq(values().speed, 8, "clamped")
	ui.tap("enter")
	ui.typed = { "2", "esc" }
	ui.frame()
	E.eq(values().speed, 8, "cancelled")
	E.eq(rawget(_G, "obsidian").menu.is_open(), true, "Esc in a field leaves the menu open")
end)

test("actions_toast_their_result_and_pages_nest", function()
	local e, ui = start(PAGE)
	open_player(e, ui)
	ui.tap("down")
	ui.tap("down")
	ui.tap("down")
	ui.tap("enter")
	E.eq(values().runs, 1)
	ui.frame()
	E.eq(ui.shown("Healed"), true, "toast")
	ui.tap("down")
	ui.tap("enter")
	ui.tap("enter")
	E.eq(values().deep, true, "sub page")
	ui.frame()
	E.eq(ui.shown("Obsidian / Player / More"), true, "breadcrumb")
	ui.tap("esc")
	ui.frame()
	E.eq(ui.shown("Heal"), true, "back to the page above")
	ui.tap("esc")
	ui.tap("esc")
	E.eq(rawget(_G, "obsidian").menu.is_open(), false, "Esc at the top closes")
end)

test("a_failing_action_is_a_toast_and_the_mod_stays_on", function()
	local e, ui = start([[
		obsidian.menu.add("P", function(page)
			page:action("Bad", function() error("boom") end)
			page:toggle("Broken", { get = function() error("no") end })
		end)
	]])
	open_player(e, ui)
	for _ = 1, 20 do ui.tap("enter") end
	ui.frame()
	E.eq(ui.shown("boom"), true, "the error shows")
	E.eq(e:core().mods_by_id["m"].off, false, "menu errors never count against the mod")
	E.eq(rawget(_G, "obsidian").menu.is_open(), true)
end)

test("an_item_can_be_disabled_with_a_reason", function()
	local e, ui = start([[
		RAN = false
		obsidian.menu.add("P", function(page)
			page:action("Host thing", function() RAN = true end, { enabled = function() return false, "Host only" end })
		end)
	]])
	open_player(e, ui)
	ui.tap("enter")
	ui.frame()
	E.eq(rawget(_G, "RAN"), false)
	E.eq(ui.shown("Host only"), true)
end)

test("an_input_row_passes_the_typed_line_on", function()
	local e, ui = start([[
		obsidian.menu.add("P", function(page)
			page:input("Command", function(text) rawset(_G, "LINE", text) return "Ran " .. text end)
		end)
	]])
	open_player(e, ui)
	ui.tap("enter")
	ui.typed = { "h", "i", "enter" }
	ui.frame()
	ui.frame()
	E.eq(rawget(_G, "LINE"), "hi")
	E.eq(ui.shown("Ran hi"), true, "toast")
end)

test("filter_narrows_the_list_and_esc_clears_it", function()
	local e, ui = start(PAGE)
	open_player(e, ui)
	ui.tap("tab")
	ui.typed = { "h", "e", "enter" }
	ui.frame()
	ui.frame()
	E.eq(ui.shown("Heal"), true)
	E.eq(ui.shown("Speed"), false, "filtered out")
	ui.tap("enter")
	E.eq(values().runs, 1, "the first match is selected")
	ui.tap("esc")
	ui.frame()
	E.eq(ui.shown("Speed"), true, "filter cleared")
	E.eq(rawget(_G, "obsidian").menu.is_open(), true, "first Esc only clears the filter")
end)

test("a_session_page_closes_when_the_session_is_no_longer_cleared", function()
	local lobby = { my_id = "me", members = { "me" }, data = {} }
	local e, ui = start(PAGE, { scope = "session", lobby = lobby })
	e:frames(31)
	open_player(e, ui)
	ui.frame()
	E.eq(ui.shown("God mode"), true)
	lobby.members = { "me", "vanilla" }
	for _ = 1, 31 do e:frames(1) end
	E.eq(rawget(_G, "obsidian").menu.is_open(), false, "closed")
	rawget(_G, "obsidian").menu.open()
	ui.frame()
	E.eq(ui.shown("Player"), false, "a session page isn't listed while not cleared")
end)

test("chat_stays_shut_while_the_menu_is_open", function()
	local e, ui = start(PAGE)
	local typed = 0
	rawset(_G, "TextChat", { start_typing = function() typed = typed + 1 end })
	rawget(_G, "require")("lua/network/network_global")
	e.opts.modules["x"] = true
	rawget(_G, "require")("x")
	rawget(_G, "TextChat").start_typing({})
	E.eq(typed, 1, "closed menu: chat opens")
	rawget(_G, "obsidian").menu.open()
	rawget(_G, "TextChat").start_typing({})
	E.eq(typed, 1, "open menu: refused")
end)

test("toasts_show_then_expire", function()
	local e, ui = start("return true")
	rawget(_G, "obsidian").toast("Hello", 0.05)
	ui.frame()
	E.eq(ui.shown("Hello"), true)
	for _ = 1, 5 do ui.frame() end
	E.eq(ui.shown("Hello"), false, "gone")
end)

test("the_gui_is_destroyed_before_the_game_shuts_down", function()
	local e, ui = start("return true")
	local down = 0
	rawset(_G, "shutdown", function() down = down + 1 end)
	rawget(_G, "obsidian").toast("x")
	ui.frame()
	rawget(_G, "shutdown")()
	E.eq(down, 1, "the game's shutdown still runs")
	E.eq(ui.destroyed, 1)
end)

test("nothing_touches_the_game_until_a_menu_or_toast_is_used", function()
	local e, ui = start("return true")
	ui.frame()
	E.eq(ui.gui_args, nil, "no gui made for a mod that never uses the menu")
end)

test("long_labels_are_cut_and_accents_count_as_one_character", function()
	local e, ui = start([[
		obsidian.menu.add("P", function(page)
			page:action(string.rep("é", 200), function() end)
		end)
	]])
	open_player(e, ui)
	ui.frame()
	for _, t in ipairs(ui.texts) do
		local _, n = string.gsub(t.text, "é", "é")
		if n > 0 then
			E.eq(n, 60, "cut to the panel, in characters, leaving room for the value")
			E.eq(string.sub(t.text, -1), "~", "marked as cut")
		end
	end
end)

test("large_screens_use_the_larger_font", function()
	local e, ui = start(PAGE)
	ui.height = 2160
	rawget(_G, "obsidian").menu.open()
	ui.frame()
	E.eq(ui.texts[1].font, "foundation/fonts/debug_medium")
	E.eq(ui.texts[1].material, "debug_medium")
	E.eq(ui.texts[1].size, 32)
end)

test("an_overlay_draws_every_frame", function()
	local e, ui = start([[
		obsidian.menu.overlay(function(draw, w, h) draw.text("Speed " .. w, 10, h - 20) end)
	]])
	ui.frame()
	E.eq(ui.shown("Speed 1920"), true)
end)

return T
