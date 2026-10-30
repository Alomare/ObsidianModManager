-- obsidian.menu and obsidian.toast: an overlay any mod can add pages to, and short messages.
-- Everything draws on one immediate gui on the brightness world: the world exists in every game
-- state, survives state changes and renders after everything else. The debug fonts live in the
-- foundation package, loaded before any mod runs, so text can never ask for a font that isn't
-- loaded, and they cover Latin-1. They are monospaced, so widths need no engine call.
-- Gui, World and Color are read through _G each frame: the engine defines them, and the game's
-- strict mode forbids touching undeclared globals by name from here.
local B = require("obsidian/loader/builtins")
local log = require("obsidian/loader/log")

local IFACE = "obsidian_menu"
local MATERIAL = "foundation/gui/gui"
local LAYER_BACK, LAYER_MARK, LAYER_TEXT, LAYER_TOAST = 880, 884, 888, 896
local FIRST_REPEAT, NEXT_REPEAT = 0.4, 0.08
local CLOSED_STATES = { logos = true, cutscene = true, transition = true }

local NAV_KEYS = {
	up = { "up", "w" }, down = { "down", "s" }, left = { "left", "a" }, right = { "right", "d" },
	select = { "enter", "e" }, back = { "esc", "q" }, filter = { "tab" },
}
local REPEATS = { up = true, down = true, left = true, right = true }

local YELLOW, WHITE, GREY, GREEN, RED, DARK = { 255, 220, 100 }, { 235, 235, 235 }, { 150, 150, 150 }, { 120, 230, 120 }, { 255, 110, 100 }, { 12, 14, 16 }

local M = { is_open = false, roots = {}, stack = {}, toasts = {}, overlays = {}, keys = nil, gui = nil, field = nil, state_name = nil }

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
	local frame = { title = title, build = the_build, state = state, selected = 1, top = 1 }
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

function M.close()
	if not M.is_open then return end
	M.is_open = false
	M.field = nil
	M.stack = {}
	local ok, err = B.pcall(drop_focus)
	if not ok then log.limited("menu focus", "menu: could not release input: " .. B.tostring(err)) end
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
			frame.selected, frame.top = 1, 1
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
			frame.selected = i
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

local function handle(ev)
	local frame = M.stack[#M.stack]
	local list = rows(frame)
	settle(frame, list)
	local it = list[frame.selected]
	if ev.back then
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

local function value_text(frame, it)
	if it.kind == "action" then return ">", GREY end
	if it.kind == "input" then return "_", GREY end
	if it.kind == "page" then return ">>", YELLOW end
	if it.kind == "label" or it.kind == "header" then return nil end
	local ok, value = run(frame.state, "get", it.get)
	if not ok then return "?", RED end
	if it.kind == "toggle" then
		if value then return M.core.text("menu_on"), GREEN end
		return M.core.text("menu_off"), GREY
	elseif it.kind == "number" then
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

local function draw_menu(w, h)
	local _, size, _, advance, line = font()
	local frame = M.stack[#M.stack]
	local list = rows(frame)
	settle(frame, list)
	local columns = B.min(64, B.floor((w - 80) / advance))
	local panel_w = (columns + 2) * advance
	local shown = B.max(4, B.floor((h * 0.72) / line) - 5)
	if frame.selected < frame.top then frame.top = frame.selected end
	if frame.selected >= frame.top + shown then frame.top = frame.selected - shown + 1 end
	if frame.top > 1 and frame.top + shown - 1 > #list then frame.top = B.max(1, #list - shown + 1) end

	local x = 40
	local inner = x + advance
	local top = h - 60
	local count = B.min(shown, #list)
	local help = {}
	local selected = list[frame.selected]
	if selected and selected.help then help = wrap(text_of(frame.state, selected.help, "help"), columns) end
	local panel_h = line * (count + 4 + #help)
	rect(x, top - panel_h, panel_w, panel_h, LAYER_BACK, DARK, 232)
	rect(x, top - 2, panel_w, 2, LAYER_MARK, YELLOW)

	local y = top - line + B.floor((line - size) / 2)
	local titles = {}
	for i, f in B.ipairs(M.stack) do titles[i] = f.title end
	text(cut(B.concat(titles, " / "), columns), inner, y, LAYER_TEXT, YELLOW)
	y = y - line
	if frame.filter and frame.filter ~= "" then
		text(cut(M.core.text("menu_filter") .. ": " .. frame.filter, columns), inner, y, LAYER_TEXT, GREY)
	end
	y = y - line

	for i = frame.top, frame.top + count - 1 do
		local it = list[i]
		local active = i == frame.selected
		local value, value_color = value_text(frame, it)
		if active then rect(x, y - 4, panel_w, line, LAYER_MARK, YELLOW) end
		local label = text_of(it.owner or frame.state, it.label, "label")
		local c = it.kind == "header" and YELLOW or (it.kind == "label" and GREY or WHITE)
		if active then c = DARK end
		local room = columns - (value and length(value) + 2 or 0)
		text(cut(label, room), inner, y, LAYER_TEXT, c)
		if value then
			text(value, inner + (columns - length(value)) * advance, y, LAYER_TEXT, active and DARK or value_color)
		end
		y = y - line
	end

	y = y - line
	for _, l in B.ipairs(help) do
		text(l, inner, y, LAYER_TEXT, GREY)
		y = y - line
	end
	if M.field then
		text(cut(M.field.prompt .. ": " .. M.field.text .. "_", columns), inner, y, LAYER_TEXT, YELLOW)
	else
		local more = #list > shown and B.format(" (%d/%d)", frame.selected, #list) or ""
		text(cut(M.core.text("menu_keys") .. more, columns), inner, y, LAYER_TEXT, GREY)
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
		rect(15, y - 4, (length(s) + 1) * advance, line, LAYER_TOAST, DARK, alpha * 0.8)
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
			if M.field then
				read_field()
			else
				local ev = read_nav(dt)
				handle(ev)
			end
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
