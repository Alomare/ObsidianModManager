-- obsidian.menu and obsidian.toast: an overlay any mod can add pages to, and short messages.
-- Everything draws on one immediate gui on the brightness world: the world exists in every game
-- state, survives state changes and renders after everything else. The debug fonts live in the
-- foundation package, loaded before any mod runs, so text can never ask for a font that isn't
-- loaded, and they cover Latin-1. They are monospaced, so widths need no engine call.
-- Gui, World and Color are read through _G each frame: the engine defines them, and the game's
-- strict mode forbids touching undeclared globals by name from here.
-- The mouse is read raw, as the keyboard is. Its cursor axis shares the gui's origin, the bottom left
-- of the screen: the game's menus test the raw cursor against what they draw, with no flip.
local B = require("obsidian/loader/builtins")
local log = require("obsidian/loader/log")
local storage = require("obsidian/loader/storage")

local IFACE = "obsidian_menu"
local MATERIAL = "foundation/gui/gui"
local LAYER_BACK, LAYER_MARK, LAYER_TEXT, LAYER_TOAST = 880, 884, 888, 896
local FIRST_REPEAT, NEXT_REPEAT = 0.4, 0.08
local CLOSED_STATES = { logos = true, cutscene = true, transition = true }
local MENU_CURSOR = "hud/cursors/menu"
local MIN_COLUMNS, MIN_ROWS, WHEEL_ROWS, TRACK_W = 34, 4, 3, 6
local WINDOW_KEYS = { "x", "top", "w", "h" }

local NAV_KEYS = {
	up = { "up", "w" }, down = { "down", "s" }, left = { "left", "a" }, right = { "right", "d" },
	select = { "enter", "e" }, back = { "esc", "q" }, filter = { "tab" },
}
local REPEATS = { up = true, down = true, left = true, right = true }

-- Obsidian's default theme.
local GOLD, WHITE, GREY, RED, DARK = { 240, 180, 41 }, { 236, 235, 231 }, { 180, 181, 178 }, { 255, 155, 94 }, { 15, 17, 19 }
local PANEL, HEADER, LINE = { 33, 35, 39 }, { 48, 51, 56 }, { 255, 255, 255 }

local M = { is_open = false, roots = {}, stack = {}, toasts = {}, overlays = {}, keys = nil, gui = nil, field = nil, state_name = nil, hits = nil, win = nil, drag = nil, hold = nil, cursor = nil }

local function global(name)
	return B.rawget(B.G, name)
end

local function color(c, alpha)
	return global("Color")(alpha or 255, c[1], c[2], c[3])
end

-- Calls a mod's function as that mod. Errors become a toast and a log line: a failing menu entry
-- mustn't count against the mod the way a failing hook does.
local function run(state, what, fn, ...)
	local core, previous = M.core, M.core.current
	core.current = state
	local r = { B.pcall(fn, ...) }
	core.current = previous
	if not r[1] then
		log.limited("menu " .. what, "menu error (" .. (state and state.id or "loader") .. ", " .. what .. "): " .. B.tostring(r[2]))
		return false, r[2]
	end
	return B.unpack(r)
end

local function gated(state)
	return not (state and state.mod.scope == "client")
end

local function allowed(state)
	return not gated(state) or M.session.cleared()
end

-- Length and cut in characters, not bytes: text is UTF-8, and the font is monospaced.
local function length(s)
	local _, n = B.gsub(s, "[^\128-\191]", "")
	return n
end

local function cut(s, n)
	if length(s) <= n then return s end
	local out, count = {}, 0
	for ch in B.gmatch(s, "[%z\1-\127\192-\255][\128-\191]*") do
		count = count + 1
		if count >= n then break end
		out[count] = ch
	end
	return B.concat(out) .. "~"
end

-- Text for a label that may be a function, so a mod can show live values.
local function text_of(state, value, what)
	if B.type(value) == "function" then
		local ok, s = run(state, what, value)
		return ok and B.tostring(s) or "?"
	end
	return B.tostring(value)
end

local Page = {}
Page.__index = Page

local function add(page, kind, label, opts)
	local it = opts or {}
	it.kind, it.label = kind, label
	B.insert(page.items, it)
	return it
end

function Page:header(label) return add(self, "header", label) end
function Page:label(label, opts) return add(self, "label", label, opts) end
function Page:toggle(label, opts) return add(self, "toggle", label, opts) end
function Page:number(label, opts) return add(self, "number", label, opts) end
function Page:choice(label, opts) return add(self, "choice", label, opts) end

function Page:action(label, fn, opts)
	local it = add(self, "action", label, opts)
	it.run = fn
	return it
end

-- A row that asks for a line of text, then calls fn(text). A string it returns becomes a toast.
function Page:input(label, fn, opts)
	local it = add(self, "input", label, opts)
	it.run = fn
	return it
end

function Page:page(label, build, opts)
	local it = add(self, "page", label, opts)
	it.build = build
	return it
end

-- Asks for the page to be built again after the current action, as an action can change what it lists.
function Page:refresh()
	self.dirty = true
end

local function selectable(it)
	return it.kind ~= "header" and it.kind ~= "label"
end

local function rows(frame)
	if not frame.filter or frame.filter == "" then return frame.page.items end
	local want, out = B.lower(frame.filter), {}
	for _, it in B.ipairs(frame.page.items) do
		if selectable(it) and B.find(B.lower(text_of(it.owner or frame.state, it.label, "label")), want, 1, true) then
			B.insert(out, it)
		end
	end
	return out
end

local function settle(frame, list)
	if #list == 0 then
		frame.selected = 1
		return
	end
	frame.selected = B.max(1, B.min(frame.selected or 1, #list))
	if selectable(list[frame.selected]) then return end
	for i = frame.selected, #list do
		if selectable(list[i]) then
			frame.selected = i
			return
		end
	end
	for i = frame.selected, 1, -1 do
		if selectable(list[i]) then
			frame.selected = i
			return
		end
	end
end

local function build(frame)
	frame.page = B.setmetatable({ items = {}, dirty = false }, Page)
	local ok, err = run(frame.state, "build", frame.build, frame.page)
	if not ok then
		frame.page.items = {}
		B.insert(frame.page.items, { kind = "label", label = M.core.text("menu_failed") })
		log.limited("menu build", "menu page failed: " .. B.tostring(err))
	end
	settle(frame, rows(frame))
end

local function push(title, the_build, state)
	local frame = { title = title, build = the_build, state = state, selected = 1, top = 1, follow = true }
	build(frame)
	B.insert(M.stack, frame)
end

local function root_build(page)
	for _, root in B.ipairs(M.roots) do
		if allowed(root.state) then
			page:page(root.title, root.build, { owner = root.state })
		end
	end
	if #page.items == 0 then page:label(M.core.text("menu_empty")) end
end

local function users()
	local out = { global("KEYBOARD_MOUSE_USER_NAME") }
	local pads = global("PadManager")
	for _, u in B.ipairs(pads and pads.users or {}) do B.insert(out, u.name) end
	return out
end

local function ensure_interfaces()
	local im, pads = global("InputManager"), global("PadManager")
	local keyboard = global("KEYBOARD_MOUSE_USER_NAME")
	if im:has_interface(keyboard, IFACE) then return end
	im:create_controller_interface(keyboard, IFACE, {}, {})
	pads:create_rebindable_interface(IFACE, global("ControllerSettings").pad)
end

-- Every frame while open: nothing can hold focus by priority, and the game takes focus itself.
local function hold_focus()
	local im = global("InputManager")
	for _, u in B.ipairs(users()) do im:take_focus(u, IFACE) end
end

local function drop_focus()
	local im = global("InputManager")
	for _, u in B.ipairs(users()) do
		if im:has_interface(u, IFACE) then im:release_focus(u, IFACE) end
	end
end

local function state_name()
	local boot = global("Boot")
	local sm = B.type(boot) == "table" and boot.state_machine
	if not sm then return nil end
	local ok, name = B.pcall(sm.get_current_state_name, sm)
	return ok and name or nil
end

local function can_open()
	local name = state_name()
	if not name or CLOSED_STATES[name] then return false end
	local ok, st = B.pcall(global("Boot").state_machine.get_current_state, global("Boot").state_machine)
	return not (ok and B.type(st) == "table" and st.text_chat and st.text_chat.active)
end

-- The game's cursors nearly vanish away from the aim, so the menu asks for the system arrow: no path
-- gives it, where the engine allows that. The pause menu's cursor stays set for when it doesn't.
local function show_cursor()
	local cursors = global("CursorManager")
	cursors:set_cursor(MENU_CURSOR)
	cursors:set_show_cursor(true)
	cursors:set_clip_cursor(false)
	local ok, err = B.pcall(global("Window").set_cursor)
	if not ok then log.limited("menu cursor", "menu: no system cursor: " .. B.tostring(err)) end
end

local function open_cursor()
	local cursors = global("CursorManager")
	M.cursor = { name = cursors:get_current_cursor(), shown = cursors:is_shown(), state = state_name() }
	show_cursor()
end

-- Every frame while open: the game may hide or swap the cursor behind the menu.
local function hold_cursor()
	local cursors = global("CursorManager")
	if not cursors:is_shown() or cursors:get_current_cursor() ~= MENU_CURSOR then show_cursor() end
end

-- Puts back what the state had. A state that came up meanwhile set its own cursor, so only the
-- system arrow has to go.
local function close_cursor()
	local c, cursors = M.cursor, global("CursorManager")
	M.cursor = nil
	if not c then return end
	local same = c.state == state_name()
	local name, shown = c.name, c.shown
	if not same then name, shown = cursors:get_current_cursor(), cursors:is_shown() end
	cursors:set_cursor(name)
	cursors:set_show_cursor(shown)
	if same then cursors:set_clip_cursor(name ~= MENU_CURSOR) end
end

function M.close()
	if not M.is_open then return end
	M.is_open = false
	M.field, M.drag, M.hold, M.hits = nil, nil, nil, nil
	M.mouse_x, M.mouse_y = nil, nil
	M.stack = {}
	local ok, err = B.pcall(drop_focus)
	if not ok then log.limited("menu focus", "menu: could not release input: " .. B.tostring(err)) end
	ok, err = B.pcall(close_cursor)
	if not ok then log.limited("menu cursor", "menu: could not restore the cursor: " .. B.tostring(err)) end
end

function M.open()
	if M.is_open then return true end
	if not can_open() then return false end
	local ok, err = B.pcall(function()
		ensure_interfaces()
		hold_focus()
	end)
	if not ok then
		log.limited("menu open", "menu: could not take input: " .. B.tostring(err))
		B.pcall(drop_focus)
		return false
	end
	ok, err = B.pcall(open_cursor)
	if not ok then
		M.cursor = nil
		log.limited("menu cursor", "menu: could not show the cursor: " .. B.tostring(err))
	end
	M.is_open = true
	M.state_name = state_name()
	M.stack = {}
	push(M.core.text("menu_title"), root_build, nil)
	return true
end

function M.toggle()
	if M.is_open then M.close() else M.open() end
end

function M.toast(text, seconds)
	B.insert(M.toasts, { text = B.tostring(text), left = seconds or 4 })
end

local function shift_held()
	local kb = global("Keyboard")
	local ok, i = B.pcall(kb.button_index, "left shift")
	if not ok or not i then return false end
	local ok2, v = B.pcall(kb.button, i)
	return ok2 and B.type(v) == "number" and v > 0.5
end

local function write(frame, it, value)
	if it.set then
		local ok, err = run(frame.state, "set", it.set, value)
		if not ok then M.toast(B.tostring(err)) end
	end
end

local function step_number(frame, it, direction)
	local ok, value = run(frame.state, "get", it.get)
	if not ok or B.type(value) ~= "number" then return end
	local step = (it.step or 1) * (shift_held() and 10 or 1)
	local n = value + step * direction
	if it.min and n < it.min then n = it.min end
	if it.max and n > it.max then n = it.max end
	write(frame, it, n)
end

local function step_choice(frame, it, direction)
	local choices = it.choices or {}
	if #choices == 0 then return end
	local ok, value = run(frame.state, "get", it.get)
	local at = 1
	for i, c in B.ipairs(choices) do
		if ok and c.id == value then at = i end
	end
	write(frame, it, choices[(at - 1 + direction) % #choices + 1].id)
end

local function check_enabled(frame, it)
	if not it.enabled then return true end
	local ok, on, why = run(frame.state, "enabled", it.enabled)
	if ok and on then return true end
	M.toast(why or M.core.text("menu_unavailable"))
	return false
end

local function begin_number_entry(frame, it)
	if not global("GuiItems") then return end
	M.field = { text = "", state = {}, max = 16, prompt = text_of(frame.state, it.label, "label"), numeric = true,
		done = function(text)
			local n = B.tonumber(text)
			if not n then return end
			if it.min and n < it.min then n = it.min end
			if it.max and n > it.max then n = it.max end
			write(frame, it, n)
		end }
end

local function begin_text_entry(frame, it)
	if not global("GuiItems") then return end
	M.field = { text = "", state = {}, max = 48, prompt = text_of(frame.state, it.label, "label"),
		done = function(text)
			local ok, result = run(frame.state, "input", it.run, text)
			if not ok then
				M.toast(B.tostring(result))
			elseif B.type(result) == "string" then
				M.toast(result)
			end
		end }
end

local function begin_filter(frame)
	if not global("GuiItems") then return end
	M.field = { text = frame.filter or "", state = {}, max = 24, prompt = M.core.text("menu_filter"),
		change = function(text)
			frame.filter = text
			frame.selected, frame.top, frame.follow = 1, 1, true
			settle(frame, rows(frame))
		end,
		done = function() end }
end

local function activate(frame, it)
	if not check_enabled(frame, it) then return end
	if it.kind == "toggle" then
		local ok, value = run(frame.state, "get", it.get)
		if ok then write(frame, it, not value) end
	elseif it.kind == "number" then
		begin_number_entry(frame, it)
	elseif it.kind == "input" then
		begin_text_entry(frame, it)
	elseif it.kind == "choice" then
		step_choice(frame, it, 1)
	elseif it.kind == "action" then
		local ok, result = run(frame.state, "action", it.run)
		if not ok then
			M.toast(B.tostring(result))
		elseif B.type(result) == "string" then
			M.toast(result)
		end
	elseif it.kind == "page" then
		push(text_of(it.owner or frame.state, it.label, "label"), it.build, it.owner or frame.state)
		return
	end
	if frame.page.dirty then build(frame) end
end

local function adjust(frame, it, direction)
	if not check_enabled(frame, it) then return end
	if it.kind == "number" then
		step_number(frame, it, direction)
	elseif it.kind == "choice" then
		step_choice(frame, it, direction)
	elseif it.kind == "toggle" then
		activate(frame, it)
	end
end

local function move(frame, list, direction)
	if #list == 0 then return end
	local i = frame.selected
	for _ = 1, #list do
		i = (i - 1 + direction) % #list + 1
		if selectable(list[i]) then
			frame.selected, frame.follow = i, true
			return
		end
	end
end

local function read_key(name, dt)
	local st = M.keys[name]
	if not st then
		st = { index = {}, wait = 0 }
		local kb = global("Keyboard")
		for _, key in B.ipairs(NAV_KEYS[name]) do
			local ok, i = B.pcall(kb.button_index, key)
			if ok and i then B.insert(st.index, i) end
		end
		M.keys[name] = st
	end
	local kb = global("Keyboard")
	local pressed, held = false, false
	for _, i in B.ipairs(st.index) do
		pressed = pressed or kb.pressed(i) == true
		local level = kb.button(i)
		held = held or (B.type(level) == "number" and level > 0.5)
	end
	if pressed then
		st.wait = FIRST_REPEAT
		return true
	end
	if held and REPEATS[name] then
		st.wait = st.wait - dt
		if st.wait <= 0 then
			st.wait = NEXT_REPEAT
			return true
		end
	end
	return false
end

local function read_nav(dt)
	local ev = {}
	for name in B.pairs(NAV_KEYS) do ev[name] = read_key(name, dt) end
	local pads = global("PadManager")
	for i = 1, #(pads and pads.users or {}) do
		local ok, d = B.pcall(pads.get_inputs, pads, IFACE, i)
		if ok and B.type(d) == "table" then
			for name in B.pairs(NAV_KEYS) do
				if d[name] then ev[name] = true end
			end
		end
	end
	return ev
end

local function read_field()
	local f = M.field
	local input = global("GuiItems").InputField
	local before = f.text
	local text, _, finished, cancelled = input.do_input(f.text, f.state, f.max)
	f.text = text
	if f.numeric then
		f.text = B.gsub(f.text, "[^%d%.%-]", "")
		if B.type(f.state.marker) == "number" and f.state.marker > #f.text then f.state.marker = #f.text end
	end
	if f.change and f.text ~= before then f.change(f.text) end
	if finished then
		M.field = nil
		if not cancelled then f.done(f.text) end
	end
end

local function go_back(frame)
	if frame.filter and frame.filter ~= "" then
		frame.filter = nil
		settle(frame, rows(frame))
	elseif #M.stack > 1 then
		B.remove(M.stack)
		local back = M.stack[#M.stack]
		build(back)
	else
		M.close()
	end
end

local function handle(ev)
	local frame = M.stack[#M.stack]
	local list = rows(frame)
	settle(frame, list)
	local it = list[frame.selected]
	if ev.back then
		go_back(frame)
	elseif ev.up then
		move(frame, list, -1)
	elseif ev.down then
		move(frame, list, 1)
	elseif ev.filter then
		begin_filter(frame)
	elseif it and selectable(it) then
		if ev.select then
			activate(frame, it)
		elseif ev.left then
			adjust(frame, it, -1)
		elseif ev.right then
			adjust(frame, it, 1)
		end
	end
end

-- A row's value as text and its color, or as the third result for a toggle, which draws a switch.
local function value_text(frame, it)
	if it.kind == "action" then return ">", GREY end
	if it.kind == "input" then return "_", GREY end
	if it.kind == "page" then return ">", GOLD end
	if it.kind == "label" or it.kind == "header" then return nil end
	local ok, value = run(frame.state, "get", it.get)
	if not ok then return "?", RED end
	if it.kind == "toggle" then return nil, nil, value and true or false end
	if it.kind == "number" then
		if B.type(value) ~= "number" then return "-", GREY end
		return "< " .. B.format(it.format or "%g", value) .. " >", WHITE
	end
	for _, c in B.ipairs(it.choices or {}) do
		if c.id == value then return "< " .. B.tostring(c.label) .. " >", WHITE end
	end
	return "< " .. B.tostring(value) .. " >", WHITE
end

local function wrap(text, width)
	local lines, line = {}, ""
	for word in B.gmatch(text, "%S+") do
		if line == "" then
			line = word
		elseif length(line) + 1 + length(word) <= width then
			line = line .. " " .. word
		else
			B.insert(lines, line)
			line = word
		end
	end
	if line ~= "" then B.insert(lines, line) end
	return lines
end

local function font()
	local _, h = global("Application").resolution()
	if h >= 1400 then return "foundation/fonts/debug_medium", 32, "debug_medium", 15, 36 end
	return "foundation/fonts/debug_small", 16, "debug_small", 8, 20
end

local function rect(x, y, w, h, layer, c, alpha)
	global("Gui").rect(M.gui, global("Vector3")(x, y, layer), global("Vector2")(w, h), color(c, alpha))
end

local function text(s, x, y, layer, c, alpha)
	local path, size, material = font()
	global("Gui").text(M.gui, s, path, size, material, global("Vector3")(x, y, layer), color(c, alpha))
end

local function inside(area, x, y)
	return area ~= nil and x >= area.x and x < area.x + area.w and y >= area.y and y < area.y + area.h
end

-- The window as the player left it, or near the top left corner on first use. Always on screen.
local function place_window(sw, sh, min_h)
	local _, _, _, advance = font()
	local win = M.win
	if not win then
		local saved = storage.own("obsidian.menu")
		win = { x = saved.get("x") or 40, top = saved.get("top") or sh - 60, w = saved.get("w") or 67 * advance, h = saved.get("h") or B.floor(sh * 0.72) }
		M.win = win
	end
	win.w = B.max((MIN_COLUMNS + 3) * advance, B.min(win.w, sw))
	win.h = B.max(min_h, B.min(win.h, sh))
	win.x = B.max(0, B.min(win.x, sw - win.w))
	win.top = B.max(win.h, B.min(win.top, sh))
	return win
end

local function draw_switch(right, y, h, on)
	local _, _, _, advance = font()
	local w, inset = advance * 4, 3
	local knob = B.floor(w / 2) - inset
	rect(right - w, y, w, h, LAYER_MARK, on and GOLD or DARK, on and 255 or 170)
	rect(on and right - inset - knob or right - w + inset, y + inset, knob, h - inset * 2, LAYER_MARK + 1, on and DARK or GREY)
end

local function draw_menu(sw, sh)
	local _, _, _, advance, line = font()
	local row_h, bar_h = line + 4, line + 10
	local win = place_window(sw, sh, bar_h + line * 4 + 10 + MIN_ROWS * row_h)
	local frame = M.stack[#M.stack]
	local list = rows(frame)
	settle(frame, list)
	local x, top, w, h = win.x, win.top, win.w, win.h
	local bottom, pad = top - h, advance
	local columns = B.floor((w - pad * 2 - TRACK_W) / advance)
	local help_room = columns >= 44 and 2 or 3
	local foot_h = line * (help_room + 1) + 10
	local shown = B.max(1, B.floor((h - bar_h - foot_h) / row_h))
	if frame.follow then
		if frame.selected < frame.top then frame.top = frame.selected end
		if frame.selected >= frame.top + shown then frame.top = frame.selected - shown + 1 end
		frame.follow = false
	end
	frame.top = B.max(1, B.min(frame.top, #list - shown + 1))
	local mx, my = M.mouse_x or -1, M.mouse_y or -1
	local hits = { rows = {} }
	M.hits = hits

	rect(x, bottom, w, h, LAYER_BACK, PANEL, 245)
	local bar_y = top - bar_h
	rect(x, bar_y, w, bar_h, LAYER_BACK + 1, HEADER)
	rect(x, top - 2, w, 2, LAYER_MARK, GOLD)

	-- The title bar: back, the path, the filter and close. The rest of it moves the window.
	local bar_text = bar_y + B.floor((bar_h - line) / 2) + 4
	local function button(area_x, area_w, label)
		local area = { x = area_x, y = bar_y, w = area_w, h = bar_h }
		local over = inside(area, mx, my)
		if over then rect(area_x, bar_y, area_w, bar_h, LAYER_MARK, LINE, 20) end
		text(label, area_x + B.floor((area_w - length(label) * advance) / 2), bar_text, LAYER_TEXT, over and GOLD or GREY)
		return area
	end
	hits.title = { x = x, y = bar_y, w = w, h = bar_h }
	hits.close = button(x + w - bar_h, bar_h, "x")
	local filter = M.core.text("menu_filter")
	if frame.filter and frame.filter ~= "" then filter = cut(filter .. ": " .. frame.filter, 22) end
	local filter_w = (length(filter) + 2) * advance
	hits.filter = button(x + w - bar_h - filter_w, filter_w, filter)
	local title_x = x + pad
	if #M.stack > 1 then
		hits.back = button(x, bar_h, "<")
		title_x = x + bar_h
	end
	local titles = {}
	for i, f in B.ipairs(M.stack) do titles[i] = f.title end
	local room = B.max(4, B.floor((x + w - bar_h - filter_w - title_x) / advance) - 1)
	text(cut(B.concat(titles, " / "), room), title_x, bar_text, LAYER_TEXT, GOLD)

	-- The rows.
	local right = x + w - pad - TRACK_W
	local y = bar_y
	for i = frame.top, B.min(#list, frame.top + shown - 1) do
		y = y - row_h
		local it = list[i]
		local row = { x = x, y = y, w = w - TRACK_W - 2, h = row_h, it = it, index = i }
		B.insert(hits.rows, row)
		if i == frame.selected and selectable(it) then
			rect(x, y, row.w, row_h, LAYER_BACK + 2, LINE, 18)
			rect(x, y, 3, row_h, LAYER_MARK, GOLD)
		end
		local baseline = y + B.floor((row_h - line) / 2) + 4
		local value, value_color, switch = value_text(frame, it)
		local label = text_of(it.owner or frame.state, it.label, "label")
		local used = switch ~= nil and 6 or (value and length(value) + 2 or 0)
		local c = it.kind == "header" and GOLD or (it.kind == "label" and GREY or WHITE)
		text(cut(label, columns - used), x + pad, baseline, LAYER_TEXT, c)
		if switch ~= nil then
			draw_switch(right, y + 4, row_h - 8, switch)
		elseif value then
			local value_x = right - length(value) * advance
			text(value, value_x, baseline, LAYER_TEXT, value_color)
			if it.kind == "number" or it.kind == "choice" then
				row.minus = { x = value_x - advance, y = y, w = advance * 3, h = row_h }
				row.plus = { x = right - advance * 2, y = y, w = advance * 3, h = row_h }
			end
		end
	end

	-- The scroll bar, only when the rows don't fit.
	if #list > shown then
		local track_h = shown * row_h
		local track_x, track_y = x + w - TRACK_W - 3, bar_y - track_h
		local thumb = B.max(line, B.floor(track_h * shown / #list))
		local span = #list - shown
		local thumb_y = track_y + track_h - thumb - B.floor((track_h - thumb) * (frame.top - 1) / span)
		hits.track = { x = track_x - 3, y = track_y, w = TRACK_W + 6, h = track_h, thumb = thumb, span = span }
		local lit = inside(hits.track, mx, my) or (M.drag and M.drag.kind == "scroll")
		rect(track_x, track_y, TRACK_W, track_h, LAYER_BACK + 2, LINE, 14)
		rect(track_x, thumb_y, TRACK_W, thumb, LAYER_MARK, lit and GOLD or GREY)
	end

	-- The footer: help for the selected row, then the keys or the line being typed.
	local foot_y = bottom + foot_h
	rect(x, foot_y, w, 1, LAYER_BACK + 2, LINE, 26)
	local selected = list[frame.selected]
	if selected and selected.help then
		local lines = wrap(text_of(frame.state, selected.help, "help"), columns)
		if #lines > help_room then lines[help_room] = cut(lines[help_room], columns - 1) .. "~" end
		local help_y = foot_y - line
		for i = 1, B.min(help_room, #lines) do
			text(lines[i], x + pad, help_y, LAYER_TEXT, GREY)
			help_y = help_y - line
		end
	end
	if M.field then
		text(cut(M.field.prompt .. ": " .. M.field.text .. "_", columns - 2), x + pad, bottom + 8, LAYER_TEXT, GOLD)
	else
		local more = #list > shown and B.format(" (%d/%d)", frame.selected, #list) or ""
		text(cut(M.core.text("menu_keys") .. more, columns - 2), x + pad, bottom + 8, LAYER_TEXT, GREY)
	end

	-- The grip that resizes the window: a corner of dots.
	hits.grip = { x = x + w - line, y = bottom, w = line, h = line }
	local grip = (inside(hits.grip, mx, my) or (M.drag and M.drag.kind == "size")) and GOLD or GREY
	for row_at = 0, 2 do
		for dot = 0, 2 - row_at do
			rect(x + w - 5 - dot * 5, bottom + 3 + row_at * 5, 2, 2, LAYER_MARK, grip)
		end
	end
end

local function draw_toasts(w, h, dt)
	for i = #M.toasts, 1, -1 do
		local t = M.toasts[i]
		t.left = t.left - dt
		if t.left <= 0 then B.remove(M.toasts, i) end
	end
	local _, _, _, advance, line = font()
	local y = 40
	for _, t in B.ipairs(M.toasts) do
		local alpha = B.min(t.left * 2, 1) * 255
		local s = cut(t.text, B.floor((w - 60) / advance))
		rect(15, y - 4, (length(s) + 1) * advance, line, LAYER_TOAST, PANEL, alpha * 0.9)
		text(s, 19, y, LAYER_TOAST + 1, WHITE, alpha)
		y = y + line
	end
end

local function ensure_gui()
	if M.gui then return true end
	local boot = global("Boot")
	local world = B.type(boot) == "table" and boot.brightness_world
	if not world then return false end
	M.world = world
	M.gui = global("World").create_screen_gui(world, "material", MATERIAL, "immediate")
	-- The gui lives on a world the game releases at shutdown, so it goes first.
	local shutdown = global("shutdown")
	if B.type(shutdown) == "function" then
		B.rawset(B.G, "shutdown", function(...)
			if M.gui then B.pcall(global("World").destroy_gui, M.world, M.gui) end
			M.gui = nil
			return shutdown(...)
		end)
	end
	return true
end

-- Hooks may run later than the frame function, so a chat opened with the menu's select key is
-- refused here rather than noticed afterwards.
local function setup_chat(hooks)
	hooks.loader_hook("TextChat", "start_typing", function(original, self, ...)
		if M.is_open then return end
		return original(self, ...)
	end)
end

-- The mouse this frame, or nil where the engine has none: the menu then runs on the keyboard alone.
local function read_mouse()
	local mouse = global("Mouse")
	if not mouse or M.no_mouse then return nil end
	local ok, m = B.pcall(function()
		local ids = M.mouse_ids
		if not ids then
			ids = { cursor = mouse.axis_index("cursor"), wheel = mouse.axis_index("wheel"), left = mouse.button_index("left"), right = mouse.button_index("right") }
			M.mouse_ids = ids
		end
		local at, wheel = mouse.axis(ids.cursor), mouse.axis(ids.wheel)
		return { x = at.x, y = at.y, wheel = wheel.y, held = mouse.button(ids.left) > 0.5, left = mouse.pressed(ids.left) == true, right = mouse.pressed(ids.right) == true }
	end)
	if ok then return m end
	M.no_mouse = true
	log.limited("menu mouse", "menu: no mouse: " .. B.tostring(m))
	return nil
end

local function save_window()
	local values = {}
	for _, key in B.ipairs(WINDOW_KEYS) do values[key] = M.win[key] end
	storage.own("obsidian.menu").put(values)
end

local function scroll_to(frame, y)
	local track = M.hits.track
	local room = track.h - track.thumb
	if room <= 0 then return end
	local at = (track.y + track.h - track.thumb / 2 - y) / room
	frame.top = 1 + B.floor(B.max(0, B.min(at, 1)) * track.span + 0.5)
end

local function click_row(frame, row, x, y)
	local it = row.it
	if not selectable(it) then return end
	frame.selected = row.index
	local direction = inside(row.minus, x, y) and -1 or (inside(row.plus, x, y) and 1 or nil)
	if direction then
		adjust(frame, it, direction)
		M.hold = { it = it, direction = direction, wait = FIRST_REPEAT }
	else
		activate(frame, it)
	end
end

local function press(frame, x, y)
	local hits = M.hits
	if inside(hits.close, x, y) then
		M.close()
	elseif inside(hits.back, x, y) then
		go_back(frame)
	elseif inside(hits.filter, x, y) then
		begin_filter(frame)
	elseif inside(hits.grip, x, y) then
		M.drag = { kind = "size", x = x - M.win.w, y = y + M.win.h }
	elseif inside(hits.track, x, y) then
		M.drag = { kind = "scroll" }
		scroll_to(frame, y)
	elseif inside(hits.title, x, y) then
		M.drag = { kind = "move", x = x - M.win.x, y = y - M.win.top }
	else
		for _, row in B.ipairs(hits.rows) do
			if inside(row, x, y) then return click_row(frame, row, x, y) end
		end
	end
end

local function follow_drag(frame, drag, m)
	if not m.held then
		M.drag = nil
		if drag.kind ~= "scroll" then save_window() end
	elseif drag.kind == "move" then
		M.win.x, M.win.top = m.x - drag.x, m.y - drag.y
	elseif drag.kind == "size" then
		M.win.w, M.win.h = m.x - drag.x, drag.y - m.y
	else
		scroll_to(frame, m.y)
	end
end

local function mouse_input(dt)
	local m = read_mouse()
	if not m then return end
	local moved = M.mouse_x ~= nil and (m.x ~= M.mouse_x or m.y ~= M.mouse_y)
	M.mouse_x, M.mouse_y = m.x, m.y
	-- A click elsewhere ends typing, as Enter does.
	if M.field then
		if m.left then
			local field = M.field
			M.field = nil
			field.done(field.text)
		end
		return
	end
	local frame = M.stack[#M.stack]
	if M.drag then return follow_drag(frame, M.drag, m) end
	if M.hold then
		if not m.held then
			M.hold = nil
			return
		end
		M.hold.wait = M.hold.wait - dt
		if M.hold.wait <= 0 then
			M.hold.wait = NEXT_REPEAT
			adjust(frame, M.hold.it, M.hold.direction)
		end
		return
	end
	if not M.hits then return end
	if m.wheel > 0 then
		frame.top = frame.top - WHEEL_ROWS
	elseif m.wheel < 0 then
		frame.top = frame.top + WHEEL_ROWS
	end
	-- Only a moving mouse selects, so a resting cursor doesn't fight the keys.
	if moved then
		for _, row in B.ipairs(M.hits.rows) do
			if selectable(row.it) and inside(row, m.x, m.y) then frame.selected = row.index end
		end
	end
	if m.right then
		go_back(frame)
	elseif m.left then
		press(frame, m.x, m.y)
	end
end

function M.frame()
	if M.is_open then
		local name = state_name()
		if name ~= M.state_name then M.close() end
		M.state_name = name
	else
		M.state_name = state_name()
	end
	if not M.is_open and #M.toasts == 0 and #M.overlays == 0 then return end
	local script = global("Script")
	local vectors, quaternions, matrices = script.temp_count()
	if ensure_gui() then
		local w, h = global("Application").resolution()
		local dt = global("ENGINE_DT") or 0
		if M.is_open then
			hold_focus()
			if M.cursor then B.pcall(hold_cursor) end
			if M.field then
				read_field()
			else
				local ev = read_nav(dt)
				handle(ev)
			end
			if M.is_open then mouse_input(dt) end
		end
		if M.is_open then
			local frame = M.stack[#M.stack]
			if gated(frame.state) and not M.session.cleared() then
				M.close()
			else
				draw_menu(w, h)
			end
		end
		draw_toasts(w, h, dt)
		for _, o in B.ipairs(M.overlays) do
			if allowed(o.state) then run(o.state, "overlay", o.fn, M.draw_api, w, h) end
		end
	end
	script.set_temp_count(vectors, quaternions, matrices)
end

-- A failing overlay or a bad engine call must never reach the frame hook again and again.
local function protected_frame()
	local ok, err = B.pcall(M.frame)
	if not ok then
		log.limited("menu frame", "menu: " .. B.tostring(err))
		if M.is_open then M.close() end
	end
end

M.draw_api = {
	text = function(s, x, y, c) text(B.tostring(s), x, y, LAYER_BACK - 2, c or WHITE) end,
	rect = function(x, y, w, h, c, alpha) rect(x, y, w, h, LAYER_BACK - 4, c or DARK, alpha or 180) end,
	char_width = function()
		local _, _, _, advance = font()
		return advance
	end,
	line_height = function()
		local _, _, _, _, line = font()
		return line
	end,
}

function M.setup(core, hooks, session)
	M.core, M.session = core, session
	M.keys = {}
	setup_chat(hooks)
	hooks.on_frame(protected_frame)
end

function M.api()
	return {
		-- A page in the top level of the menu. build(page) runs each time the page opens.
		add = function(title, the_build)
			if B.type(the_build) == "function" then
				B.insert(M.roots, { title = title, build = the_build, state = M.core.current })
			end
		end,
		open = M.open,
		close = M.close,
		toggle = M.toggle,
		is_open = function() return M.is_open end,
		-- fn(draw, width, height) runs every frame, under the same rules as on_frame. Origin is the
		-- bottom left of the screen, in pixels.
		overlay = function(fn)
			if B.type(fn) == "function" then B.insert(M.overlays, { state = M.core.current, fn = fn }) end
		end,
	}
end

return M
