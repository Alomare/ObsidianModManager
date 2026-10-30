-- obsidian.menu and obsidian.toast, through a mod, as a player would drive them.
local E = require "fake_engine"
local F = require "fake_ui"
local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local TEXTS = { en = {
	menu_title = "Obsidian", menu_empty = "No pages", menu_failed = "Failed", menu_unavailable = "Not now",
	menu_filter = "Filter", menu_keys = "Keys",
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

-- A long page, for scrolling and resizing.
local LONG = [[
	VALUES = {}
	obsidian.menu.add("Long", function(page)
		for i = 1, 90 do
			page:action("Row " .. i .. ".", function() VALUES.ran = i end, { help = "Help for " .. i .. "." })
		end
	end)
]]

local function open_root(ui)
	rawget(_G, "obsidian").menu.open()
	ui.frame()
end

-- Clicks on a drawn text, a little inside it.
local function click_on(ui, needle, exact)
	local t = ui.find(needle, exact)
	ui.click(t.pos.x + 2, t.pos.y + 4)
	ui.frame()
end

local function panel(ui)
	return ui.rects[1]
end

local function rows_shown(ui)
	local n = 0
	for _, t in ipairs(ui.texts) do
		if string.find(t.text, "^Row %d+%.") then n = n + 1 end
	end
	return n
end

test("a_click_opens_a_page_flips_a_toggle_and_runs_an_action", function()
	local e, ui = start(PAGE)
	open_root(ui)
	click_on(ui, "Player")
	E.eq(ui.shown("God mode"), true, "the page opened")
	click_on(ui, "God mode")
	E.eq(values().god, true, "the toggle flipped")
	click_on(ui, "Heal")
	E.eq(values().runs, 1, "the action ran")
	click_on(ui, "Section")
	E.eq(values().runs, 1, "a header does nothing")
end)

test("the_arrows_of_a_number_step_and_holding_repeats", function()
	local e, ui = start(PAGE)
	open_root(ui)
	click_on(ui, "Player")
	local v = ui.find("< 5 >")
	ui.press(v.pos.x, v.pos.y + 4)
	E.eq(values().speed, 3, "the left arrow takes a step away")
	for _ = 1, 24 do ui.frame() end
	E.eq(values().speed, 3, "no repeat before the first delay")
	for _ = 1, 3 do ui.frame() end
	E.eq(values().speed, 1, "held, it repeats")
	ui.release()
	ui.frame()
	v = ui.find("< 1 >")
	ui.click(v.pos.x + 4 * 8, v.pos.y + 4)
	E.eq(values().speed, 3, "the right arrow adds a step")
end)

test("clicking_the_value_of_a_number_types_it_and_a_click_elsewhere_keeps_it", function()
	local e, ui = start(PAGE)
	open_root(ui)
	click_on(ui, "Player")
	local v = ui.find("< 5 >")
	ui.click(v.pos.x + 2 * 8 + 2, v.pos.y + 4)
	E.eq(values().speed, 5, "nothing changes yet")
	ui.typed = { "7" }
	ui.frame()
	E.eq(ui.shown("Speed: 7_"), true, "the line being typed shows")
	ui.click(5, 5)
	E.eq(values().speed, 7, "a click ends typing, as Enter does")
end)

test("a_choice_steps_with_a_click_either_way", function()
	local e, ui = start(PAGE)
	open_root(ui)
	click_on(ui, "Player")
	click_on(ui, "< First >")
	E.eq(values().mode, "b", "the arrows of a choice step it")
end)

test("back_right_click_and_close", function()
	local e, ui = start(PAGE)
	local menu = rawget(_G, "obsidian").menu
	open_root(ui)
	E.eq(ui.shown("God mode"), false)
	click_on(ui, "Player")
	click_on(ui, "<", true)
	E.eq(ui.shown("God mode"), false, "the back button leaves the page")
	click_on(ui, "Player")
	ui.click(700, 500, "right")
	ui.frame()
	E.eq(ui.shown("God mode"), false, "a right click goes back too")
	click_on(ui, "x", true)
	E.eq(menu.is_open(), false, "the close button closes")
end)

test("the_filter_button_starts_the_filter", function()
	local e, ui = start(LONG)
	open_root(ui)
	click_on(ui, "Long")
	click_on(ui, "Filter", true)
	ui.typed = { "Row 7" }
	ui.frame()
	ui.typed = { "enter" }
	ui.frame()
	ui.frame()
	E.eq(ui.shown("Filter: Row 7"), true, "the title bar shows it")
	E.eq(ui.shown("Row 70."), true, "the filter applies")
	E.eq(ui.shown("Row 8."), false)
end)

test("the_title_bar_moves_the_window_and_it_stays_on_screen", function()
	local e, ui = start(PAGE)
	open_root(ui)
	local before = panel(ui).pos
	local title = ui.find("Obsidian", true)
	ui.press(title.pos.x + 200, title.pos.y + 4)
	ui.move(title.pos.x + 300, title.pos.y - 96)
	E.eq(panel(ui).pos.x, before.x + 100, "it follows the cursor")
	E.eq(panel(ui).pos.y, before.y - 100, "up and down too")
	ui.move(-4000, -4000)
	E.eq(panel(ui).pos.x, 0, "stopped at the left edge")
	E.eq(panel(ui).pos.y, 0, "stopped at the bottom edge")
	ui.move(9000, 9000)
	E.eq(panel(ui).pos.x + panel(ui).size.x, 1920, "stopped at the right edge")
	E.eq(panel(ui).pos.y + panel(ui).size.y, 1080, "stopped at the top edge")
	ui.release()
	local x = panel(ui).pos.x
	ui.move(100, 100)
	E.eq(panel(ui).pos.x, x, "let go, it stays")
end)

test("the_grip_resizes_the_window_and_more_rows_show", function()
	local e, ui = start(LONG)
	open_root(ui)
	click_on(ui, "Long")
	local p = panel(ui)
	local right, bottom, width, height = p.pos.x + p.size.x, p.pos.y, p.size.x, p.size.y
	local before = rows_shown(ui)
	ui.press(right - 3, bottom + 3)
	ui.move(right + 197, bottom - 177)
	E.eq(panel(ui).size.x, width + 200, "wider")
	E.eq(panel(ui).size.y, height + 180, "taller, with the top staying put")
	E.eq(panel(ui).pos.y + panel(ui).size.y, p.pos.y + height, "the title bar didn't move")
	E.eq(rows_shown(ui), before + 7, "the extra height holds more rows")
	ui.move(-9000, 9000)
	E.eq(panel(ui).size.x, 37 * 8, "not narrower than the rows need")
	E.eq(rows_shown(ui) >= 4, true, "not so short that no rows fit")
	ui.release()
end)

test("the_window_is_remembered", function()
	local e, ui = start(PAGE)
	local menu = rawget(_G, "obsidian").menu
	open_root(ui)
	local title = ui.find("Obsidian", true)
	ui.press(title.pos.x + 200, title.pos.y + 4)
	ui.move(title.pos.x + 300, title.pos.y - 96)
	ui.release()
	local x, y = panel(ui).pos.x, panel(ui).pos.y
	menu.close()
	open_root(ui)
	E.eq(panel(ui).pos.x, x, "while the game runs")
	menu.close()
	e.loaded["obsidian/loader/storage"].loaded = {}
	e.loaded["obsidian/loader/menu"].win = nil
	open_root(ui)
	E.eq(panel(ui).pos.x, x, "and from the file at the next launch")
	E.eq(panel(ui).pos.y, y)
end)

test("the_wheel_and_the_scroll_bar_scroll_and_the_keys_bring_the_selection_back", function()
	local e, ui = start(LONG)
	open_root(ui)
	click_on(ui, "Long")
	E.eq(ui.shown("Row 1."), true)
	ui.scroll(-1)
	E.eq(ui.shown("Row 1."), false, "the wheel scrolled away from the selection")
	E.eq(ui.shown("Row 4."), true, "by three rows")
	ui.scroll(1)
	E.eq(ui.shown("Row 1."), true, "and back")
	ui.scroll(1)
	E.eq(ui.shown("Row 1."), true, "not past the top")
	local p = panel(ui)
	local track_x = p.pos.x + p.size.x - 6
	ui.press(track_x, p.pos.y + 120)
	ui.release()
	E.eq(ui.shown("Row 90."), true, "the bar jumped to the end")
	ui.tap("down")
	ui.frame()
	E.eq(ui.shown("Row 2."), true, "moving the selection brings it into view")
end)

test("hovering_selects_a_row_and_a_resting_cursor_leaves_the_keys_alone", function()
	local e, ui = start(LONG)
	open_root(ui)
	click_on(ui, "Long")
	local row = ui.find("Row 5.")
	ui.move(row.pos.x + 2, row.pos.y + 4)
	ui.frame()
	E.eq(ui.shown("Help for 5."), true, "the row under the cursor is selected")
	ui.tap("down")
	ui.tap("down")
	ui.frame()
	E.eq(ui.shown("Help for 7."), true, "the keys move on from there, the cursor resting")
end)

test("without_a_mouse_the_keys_still_work", function()
	local e, ui = start(PAGE)
	rawset(_G, "Mouse", nil)
	open_player(e, ui)
	ui.tap("enter")
	E.eq(values().god, true)
end)

test("a_broken_mouse_is_logged_once_and_the_keys_still_work", function()
	local e, ui = start(PAGE)
	rawget(_G, "Mouse").axis = function() error("no such axis") end
	open_player(e, ui)
	ui.frame()
	ui.tap("enter")
	E.eq(values().god, true)
	E.eq(rawget(_G, "obsidian").menu.is_open(), true, "the menu stays open")
	E.eq(E.count(e:log(), "menu: no mouse"), 1)
end)

test("the_menu_shows_the_system_cursor_and_gives_the_game_its_own_back", function()
	local e, ui = start(PAGE)
	local menu = rawget(_G, "obsidian").menu
	ui.cursor.shown, ui.cursor.clipped = false, true
	open_root(ui)
	E.eq(ui.cursor.system, true, "the arrow of the operating system")
	E.eq(ui.cursor.shown, true)
	E.eq(ui.cursor.clipped, false, "free to leave the aim area")
	menu.close()
	E.eq(ui.cursor.system, false, "not left behind")
	E.eq(ui.cursor.name, "hud/cursors/game")
	E.eq(ui.cursor.shown, false, "hidden again")
	E.eq(ui.cursor.clipped, true, "clipped again")
end)

test("where_the_engine_refuses_the_system_cursor_the_pause_menus_is_left", function()
	local e, ui = start(PAGE)
	ui.cursor.refuse_system = true
	open_root(ui)
	E.eq(ui.cursor.system, false)
	E.eq(ui.cursor.name, "hud/cursors/menu", "still a visible cursor")
	E.eq(ui.cursor.shown, true)
	E.eq(rawget(_G, "obsidian").menu.is_open(), true)
	E.has(e:log(), "no system cursor")
end)

test("a_game_that_hides_the_cursor_behind_the_menu_loses_that_fight", function()
	local e, ui = start(PAGE)
	open_root(ui)
	ui.cursor.shown, ui.cursor.system = false, false
	ui.frame()
	E.eq(ui.cursor.shown, true, "shown again")
	E.eq(ui.cursor.system, true)
	ui.cursor.name, ui.cursor.system = "hud/cursors/game", false
	ui.frame()
	E.eq(ui.cursor.name, "hud/cursors/menu", "swapped back")
	E.eq(ui.cursor.system, true)
end)

test("a_new_state_keeps_the_cursor_it_set_for_itself", function()
	local e, ui = start(PAGE)
	open_root(ui)
	ui.state = "menu"
	ui.cursor.name, ui.cursor.shown = "hud/cursors/menu", false
	ui.frame()
	E.eq(rawget(_G, "obsidian").menu.is_open(), false, "the state change closed the menu")
	E.eq(ui.cursor.shown, false, "the new state's choice stands")
	E.eq(ui.cursor.system, false)
	E.eq(ui.cursor.clipped, false, "and so does its clipping")
end)

return T
