-- The trainer as a player meets it: every page opened, every row read and pressed.
local E = require "fake_engine"
local G = require "fake_game"
local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local IDS = { "obsidian.api", "obsidian.trainer" }

local function start(opts)
	local e, game, ui = G.start(IDS, opts)
	rawset(math, "create_weak_unique_identifier", function() return "id" end)
	game.state.active_screens = {}
	return e, game, ui, e.loaded["obsidian/loader/menu"]
end

local function raw_key(text)
	return type(text) == "string" and text:match("^[a-z]+_[a-z_0-9]+$") ~= nil
end

-- Reads every row of the page on top, then goes into each sub page.
local function walk(M, ui, seen, press, path)
	local frame = M.stack[#M.stack]
	local count = #frame.page.items
	for i = 1, count do
		local it = frame.page.items[i]
		if not it then break end
		if it.kind ~= "header" and it.kind ~= "label" then
			frame.selected = i
			ui.frame()
			local core = M.core
			local previous = core.current
			core.current = it.owner or frame.state
			local label = type(it.label) == "function" and it.label() or it.label
			core.current = previous
			seen[#seen + 1] = path .. " / " .. tostring(label)
			if it.kind == "page" then
				ui.tap("enter")
				if M.stack[#M.stack] ~= frame then
					walk(M, ui, seen, press, path .. "/" .. tostring(label))
					ui.tap("esc")
				end
			elseif press then
				ui.tap("enter")
				if M.field then
					ui.typed = { "enter" }
					ui.frame()
				end
				ui.tap("right")
				ui.tap("left")
				if not M.is_open then M.open() end
				if M.stack[#M.stack] ~= frame then return end
			end
		end
	end
end

local function assert_clean(e, game, ui)
	E.eq(#game.tampered, 0, "protected values written directly: " .. table.concat(game.tampered, ","))
	for _, log in ipairs({ e:log(), e:log("obsidianapi"), e:log("obsidiantrainer") }) do
		E.lacks(log, "attempt to", "a Lua error")
		E.lacks(log, "Unrecognized message", "a command the game would assert on")
		E.lacks(log, "doesn't own", "a command on a unit of another peer")
		E.lacks(log, "Undeclared global", "strict mode, as in the game")
	end
	for _, t in ipairs(rawget(_G, "TOASTS") or {}) do
		E.lacks(t, "attempt to", "an error shown to the player")
		E.lacks(t, "Undeclared global", "strict mode, as in the game")
	end
end

-- Keeps every toast, so an error shown for a moment is seen.
local function record_toasts(M)
	local all = {}
	rawset(_G, "TOASTS", all)
	local toast = M.toast
	M.toast = function(text, ...)
		all[#all + 1] = tostring(text)
		return toast(text, ...)
	end
end

test("the_fake_game_catches_a_direct_write", function()
	local e, game = start()
	game.me.master.health.hitpoints_real = 1
	E.eq(game.tampered[1], "hitpoints_real", "the harness has to be able to fail")
end)

test("the_menu_opens_on_every_page_with_the_key", function()
	local e, game, ui = start()
	ui.tap("f6")
	local menu = rawget(_G, "obsidian").menu
	E.eq(menu.is_open(), true, "F6 opens it")
	ui.frame()
	for _, name in ipairs({ "Player", "Weapons", "Stratagems", "Vehicles", "Spawn", "Enemies", "Mission", "World", "Editor", "Progress", "Console", "Changes" }) do
		E.eq(ui.shown(name), true, name)
	end
	ui.tap("f6")
	E.eq(menu.is_open(), false, "F6 closes it")
end)

test("every_page_opens_and_every_row_has_real_text", function()
	local e, game, ui, M = start()
	rawget(_G, "obsidian").menu.open()
	local seen = {}
	walk(M, ui, seen, false, "root")
	E.eq(#seen > 150, true, "rows reached: " .. #seen)
	for _, row in ipairs(seen) do
		local label = row:match("([^/]+)$"):gsub("^%s+", "")
		E.eq(raw_key(label), false, "a text key shown as is: " .. row)
	end
	assert_clean(e, game, ui)
end)

test("pressing_every_row_in_a_mission_breaks_nothing", function()
	local e, game, ui, M = start()
	record_toasts(M)
	rawget(_G, "obsidian").menu.open()
	walk(M, ui, {}, true, "root")
	for _ = 1, 90 do e:frames(1) end
	assert_clean(e, game, ui)
	E.eq(rawget(_G, "obsidian").menu.is_open() ~= nil, true)
end)

test("pressing_every_row_on_the_ship_breaks_nothing", function()
	local e, game, ui, M = start({ state = "menu" })
	record_toasts(M)
	rawget(_G, "obsidian").menu.open()
	walk(M, ui, {}, true, "root")
	for _ = 1, 30 do e:frames(1) end
	assert_clean(e, game, ui)
end)

test("pressing_every_row_as_a_client_breaks_nothing", function()
	local e, game, ui, M = start({ host = false })
	record_toasts(M)
	rawget(_G, "obsidian").menu.open()
	walk(M, ui, {}, true, "root")
	assert_clean(e, game, ui)
	E.eq(game.completed, nil, "host actions stayed with the host")
end)

test("the_mod_stays_on_through_all_of_it", function()
	local e, game, ui, M = start()
	rawget(_G, "obsidian").menu.open()
	walk(M, ui, {}, true, "root")
	E.eq(e:core().mods_by_id["obsidian.api"].off, false)
	E.eq(e:core().mods_by_id["obsidian.trainer"].off, false)
end)

test("editing_a_weapon_from_the_menu_reaches_the_game_and_can_be_undone", function()
	local e, game, ui = start()
	local api = rawget(_G, "obsidian").import("obsidian.api")
	local core = e:core()
	core.current = core.mods_by_id["obsidian.trainer"]
	E.eq(api.edits.set_unit("equipment/rifle", "weapon_info.power", 300), true)
	core.current = nil
	E.eq(api.edits.list()[1].owner, "obsidian.trainer", "the change names the mod that made it")
	E.eq(game.rifle_upgraded.weapon_info.power, 300)
	api.edits.revert_all()
	E.eq(game.rifle.weapon_info.power, 75)
end)

test("saved_edits_come_back_at_the_next_launch", function()
	local e, game = start()
	local api = rawget(_G, "obsidian").import("obsidian.api")
	local core = e:core()
	core.current = core.mods_by_id["obsidian.trainer"]
	api.edits.set_unit("equipment/rifle", "weapon_info.power", 300)
	local changes = e.loaded["obsidian/mods/obsidian.trainer/pages/changes"]
	E.eq(changes.save(), 1)
	api.edits.revert_all()
	E.eq(game.rifle.weapon_info.power, 75)
	E.eq(changes.load_saved(), true)
	E.eq(game.rifle.weapon_info.power, 300)
	core.current = nil
end)

test("kept_stratagem_and_status_edits_come_back_too", function()
	local e, game = start()
	local api = rawget(_G, "obsidian").import("obsidian.api")
	local core = e:core()
	core.current = core.mods_by_id["obsidian.trainer"]
	local s = api.catalog.stratagem("stratagem_resupply")
	E.eq(api.stratagems.edit("stratagem_resupply", "cooldown_time", 30), true)
	local burn = rawget(_G, "StatusTemplateSettings").heavy_burn
	E.eq(api.edits.set_table("heavy_burn", burn, "duration", 9, { keep = "status:heavy_burn" }), true)
	local changes = e.loaded["obsidian/mods/obsidian.trainer/pages/changes"]
	E.eq(changes.save(), 2)
	api.edits.revert_all()
	E.eq(s.cooldown_time, 120)
	E.eq(burn.duration, 3)
	E.eq(changes.load_saved(), true)
	E.eq(s.cooldown_time, 30)
	E.eq(s.upgrades[3].cooldown_time, 30, "through the runtime, so at every level")
	E.eq(burn.duration, 9)
	core.current = nil
end)

test("the_changes_page_shows_names_not_effect_ids", function()
	local e, game, ui, M = start()
	local api = rawget(_G, "obsidian").import("obsidian.api")
	api.effects.set("vehicle_god", true)
	rawget(_G, "obsidian").menu.open()
	local changes = e.loaded["obsidian/mods/obsidian.trainer/pages/changes"]
	local labels = {}
	local page = { header = function() end, label = function(_, text) labels[#labels + 1] = text end, action = function() end }
	e:core().current = e:core().mods_by_id["obsidian.trainer"]
	changes.build(page)
	E.has(table.concat(labels, ","), "Vehicle can't be damaged")
	E.lacks(table.concat(labels, ","), "vehicle_god")
end)

test("the_new_pages_list_what_the_runtime_offers", function()
	local e, game, ui, M = start()
	rawget(_G, "obsidian").menu.open()
	local seen = {}
	walk(M, ui, seen, false, "root")
	local all = table.concat(seen, "\n")
	for _, row in ipairs({ "root/Vehicles / Speed", "root/Spawn / Supply crates", "root/Spawn/Pickups / Jumppack", "root/Weapons/Backpack / Jumppack",
		"root/Stratagems / Ignore no-stratagem zones", "root/Enemies / Spawn a wave", "root/Enemies/Spawn a wave / Wave scouts",
		"root/Mission / Protect convoys and escorts", "root/Mission / Proving grounds modifier", "root/Mission / Players here",
		"root/Editor/Vehicles/Exosuit / Top speed", "root/Editor/Strikes/Airstrike / Bombs", "root/Editor/Mines/Minedrop / Mines per drop",
		"root/Editor/Mines/Explosive mine / Arming delay", "root/Editor/Sentries/Turret / Detection radius", "root/Editor/Grenades/Frag / Fuse time",
		"root/Editor/Backpacks/Jumppack / Most uses", "root/Editor/Helldiver / Dive time", "root/Editor/Status effects/Slow / Slow amount" }) do
		E.has(all, row)
	end
end)

test("every_new_row_changes_what_it_says", function()
	local e, game, ui, M = start()
	local api = rawget(_G, "obsidian").import("obsidian.api")
	e:core().current = e:core().mods_by_id["obsidian.trainer"]
	local function page_of(name) return e.loaded["obsidian/mods/obsidian.trainer/pages/" .. name] end
	local rows = {}
	local page = {}
	function page:header() end
	function page:label() end
	function page:action(label, fn) rows[label] = fn end
	function page:page(label, build) rows[label] = build end
	function page:number(label, opts) rows[label] = opts end
	function page:toggle(label, opts) rows[label] = opts end
	function page:choice(label, opts) rows[label] = opts end
	page_of("mission")(page)
	rows["Proving grounds modifier"].set("super_boots")
	E.eq(api.effects.get("mutator"), "super_boots")
	E.eq(rows["Proving grounds modifier"].choices[2].label, "Super boots", "the game's name, or a readable form of it")
	rows["Proving grounds modifier"].set(false)
	page_of("enemies")(page)
	rows["Encounter difficulty"].set(15)
	E.eq(api.effects.get("enemy_difficulty"), 15)
	rows["Encounter difficulty"].set(0)
	E.eq(api.effects.is_on("enemy_difficulty"), false)
	E.eq(rows["Enemy limit"].max, 32)
end)

test("saved_edits_wait_for_the_games_data", function()
	local e, game = start()
	local changes = e.loaded["obsidian/mods/obsidian.trainer/pages/changes"]
	rawget(_G, "LuaSettingsManager").unit_path_to_modified_settings = {}
	E.eq(changes.load_saved(), false)
end)

local function keys_of(lang)
	local raw = assert(E.read("bundled/obsidian.trainer/locales/" .. lang .. ".json"), lang)
	local out = {}
	for k, v in raw:gmatch('"([^"]+)": "(.-)",?\r?\n') do out[k] = v end
	return out
end

test("every_language_has_every_text_and_the_same_placeholders", function()
	local en = keys_of("en")
	local count = 0
	for _, lang in ipairs({ "pt-BR", "fr", "es" }) do
		local other = keys_of(lang)
		for k, v in pairs(en) do
			count = count + 1
			E.eq(other[k] ~= nil, true, lang .. " lacks " .. k)
			local _, a = v:gsub("%%s", "")
			local _, b = other[k]:gsub("%%s", "")
			E.eq(a, b, lang .. " placeholders of " .. k)
		end
		for k in pairs(other) do E.eq(en[k] ~= nil, true, "only " .. lang .. " has " .. k) end
	end
	E.eq(count > 500, true)
end)

test("every_text_a_page_asks_for_exists", function()
	local en = keys_of("en")
	local files = { "main.lua" }
	for _, p in ipairs({ "ui", "player", "weapons", "stratagems", "vehicles", "spawn", "enemies", "mission", "world", "editor", "progress", "console", "changes" }) do
		files[#files + 1] = "pages/" .. p .. ".lua"
	end
	local checked = 0
	for _, file in ipairs(files) do
		local src = assert(E.read("bundled/obsidian.trainer/" .. file))
		for _, pattern in ipairs({ '%f[%w_]t%("([%w_]+)"', 'U%.%a+%(page, "([%w_]+)"', 'U%.t%("([%w_]+)"', 'pick%(page, "([%w_]+)"', 'page%("([%w_]+)"', 'key = "([%w_]+)"' }) do
			for key in src:gmatch(pattern) do
				if key:sub(-1) ~= "_" then
					checked = checked + 1
					E.eq(en[key] ~= nil, true, file .. " asks for " .. key)
				end
			end
		end
	end
	E.eq(checked > 150, true, "keys checked: " .. checked)
end)

test("every_reason_the_runtime_gives_has_a_text", function()
	local en = keys_of("en")
	for _, name in ipairs({ "game", "edits", "console", "catalog", "world", "player", "gear", "stratagems", "enemies", "mission", "progress", "events", "combat", "vehicles", "lobby", "ui", "audio" }) do
		local src = assert(E.read("bundled/obsidian.api/lib/" .. name .. ".lua"))
		for reason in src:gmatch('return false, "([%w_]+)"') do
			E.eq(en["why_" .. reason] ~= nil, true, name .. " can answer " .. reason)
		end
	end
end)

test("the_texts_stay_inside_what_the_font_can_draw", function()
	for _, lang in ipairs({ "en", "pt-BR", "fr", "es" }) do
		for k, v in pairs(keys_of(lang)) do
			E.eq(v:find("[\196-\244]") == nil, true, lang .. " " .. k .. " has a character outside Latin-1")
		end
	end
end)

return T
