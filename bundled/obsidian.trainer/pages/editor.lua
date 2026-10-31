-- Editor: game data, by item and field. Every change goes through the runtime's checked edits, and
-- the Changes page lists and undoes them.
local U = obsidian.module("pages/ui")
local api, t = U.api, U.t
local catalog, edits, gear, game = api.catalog, api.edits, api.gear, api.game

local M = {}

local HELLDIVER = "characters/helldiver_private_01/helldiver_private_01"

local CHARACTER_FIELDS = {
	{ path = "character_info.move_speed_jog", label = "Jog speed", min = 0.5, max = 20, step = 0.5, apply = "use" },
	{ path = "character_info.move_speed_sprint_max", label = "Sprint speed", min = 0.5, max = 30, step = 0.5, apply = "live" },
	{ path = "character_info.move_speed_sprint_min", label = "Tired sprint speed", min = 0.5, max = 30, step = 0.5, apply = "live" },
	{ path = "character_info.move_speed_aim", label = "Aiming speed", min = 0.1, max = 10, step = 0.1, apply = "use" },
	{ path = "character_info.move_speed_crawl", label = "Crawl speed", min = 0.1, max = 10, step = 0.1, apply = "use" },
	{ path = "character_info.move_speed_dive", label = "Dive speed", min = 1, max = 40, step = 1, apply = "use" },
	{ path = "character_info.dive_duration", label = "Dive time", min = 0.2, max = 3, step = 0.1, apply = "use" },
	{ path = "character_info.get_up_presses_needed", label = "Presses to get up", min = 1, max = 100, step = 1, apply = "spawn" },
	{ path = "character_info.sprint_stamina", label = "Stamina seconds", min = 1, max = 120, step = 1, apply = "live" },
	{ path = "character_info.spawn_time", label = "Landing time", min = 0.5, max = 10, step = 0.5, apply = "spawn" },
	{ path = "health_info.health", label = "Health", min = 1, max = 32767, step = 25, apply = "spawn" },
	{ path = "health_info.armor_max", label = "Armor", min = 0, max = 3000, step = 5, apply = "spawn" },
}

local function step_of(field)
	if field.step then return field.step end
	local span = (field.max or 100) - (field.min or 0)
	if span <= 2 then return 0.05 end
	if span <= 20 then return 0.5 end
	if span <= 200 then return 5 end
	return 25
end

local function note(result_ok, why)
	if not result_ok then obsidian.toast(U.why(why)) end
end

-- The text key of a field, when it has one. Older rows keep the English in the data, with its note.
local function field_key(field)
	local key = "field_" .. tostring(field.family) .. "_" .. string.match(field.path, "([^.]+)$")
	if obsidian.text(key) ~= key then return key end
	return nil
end

local function label_of(field)
	local key = field_key(field)
	return key and t(key) or field.label
end

local function help_of(field)
	local applies = field.apply and t("applies_" .. field.apply)
	local key = field_key(field)
	if key then
		local help = U.help(key)
		return help and applies and (help .. " " .. applies) or help or applies
	end
	if not field.meaning then return nil end
	return applies and (field.meaning .. ". " .. applies) or field.meaning
end

-- One row per field the item really has. A boolean that's absent reads as off.
local function unit_field(page, settings_path, field, name)
	local value = edits.value(settings_path, field.path)
	if value == nil and not field.opt then return end
	if value == nil and field.type ~= "boolean" then return end
	local help = help_of(field)
	local opts = { min = field.min, max = field.max, apply = field.apply, target = name, new = field.opt }
	if field.type == "boolean" then
		page:toggle(label_of(field), {
			help = help,
			get = function() return edits.value(settings_path, field.path) == true end,
			set = function(v) note(edits.set_unit(settings_path, field.path, v, opts)) end,
		})
	else
		page:number(label_of(field), {
			help = help, min = field.min, max = field.max, step = step_of(field),
			get = function() return edits.value(settings_path, field.path) end,
			set = function(v) note(edits.set_unit(settings_path, field.path, v, opts)) end,
		})
	end
end

local function settings_of(unit_path)
	local lsm = game.global("LuaSettingsManager")
	if not lsm then return nil end
	return lsm:get_settings_path_by_unit_path(unit_path), lsm:get_settings_by_unit_path(unit_path)
end

local function unit_page(unit_path, name)
	return function(page)
		local settings_path, settings = settings_of(unit_path)
		if not settings then
			page:label(t("why_not_loaded"))
			return
		end
		for _, family in ipairs(catalog.families_of(settings)) do
			page:header(t("family_" .. family))
			for _, field in ipairs(catalog.fields(family)) do unit_field(page, settings_path, field, name) end
		end
		page:header(t("apply"))
		U.action(page, "apply_now", gear.refresh)
	end
end

local function weapons_list(list)
	return function(page)
		for _, item in ipairs(list()) do
			local name = catalog.text(item.name)
			page:page(name, unit_page(item.unit_path, name))
		end
	end
end

-- Things with a name of their own in the game: pickups and stratagems.
local function named_units(list)
	return function(page)
		for _, item in ipairs(list()) do
			local name = catalog.text(item.name)
			page:page(name, unit_page(item.unit_path, name))
		end
	end
end

local function by_subtype(subtype, extra)
	return function()
		local out = catalog.by_subtype(subtype)
		for _, item in ipairs(extra or {}) do out[#out + 1] = item end
		return out
	end
end

local function grenades_list(page)
	for _, g in ipairs(U.GRENADES) do
		page:page(t(g.key), unit_page(g.id, t(g.key)))
	end
end

-- The drop has the number of mines, and each mine its own arming delay.
local function mines_list(page)
	named_units(by_subtype("mine"))(page)
	page:page(t("edit_mine"), unit_page("gameobjects/mine_01", t("edit_mine")))
	page:page(t("edit_mine_stun"), unit_page("gameobjects/mine_stun", t("edit_mine_stun")))
end

local function enemies_list(page)
	for _, enemy in ipairs(catalog.enemies()) do
		page:page(enemy.name, unit_page(enemy.settings, enemy.name))
	end
end

-- write(field, value) makes the change, since a stratagem has more to it than one table.
local function table_fields(family, target, write)
	return function(page)
		for _, field in ipairs(catalog.fields(family)) do
			if edits.table_value(target, field.path) ~= nil or field.opt then
				page:number(field.label, {
					min = field.min, max = field.max, step = step_of(field),
					help = field.meaning and (field.meaning .. ". " .. t("applies_" .. field.apply)) or nil,
					get = function() return edits.table_value(target, field.path) or 0 end,
					set = function(v) note(write(field, v)) end,
				})
			end
		end
	end
end

local function stratagems_list(page)
	for _, s in ipairs(catalog.stratagems()) do
		local name = catalog.text(s.name)
		page:page(name, table_fields("stratagem", s, function(field, v) return api.stratagems.edit(s.name, field.path, v) end))
	end
end

local function statuses_list(page)
	local templates = game.global("StatusTemplateSettings")
	for _, name in ipairs(catalog.status_templates()) do
		local target = templates[name]
		page:page(catalog.text(name), table_fields("status", target, function(field, v)
			return edits.set_table(name, target, field.path, v, { min = field.min, max = field.max, apply = field.apply, new = field.opt, keep = "status:" .. name })
		end))
	end
end

local function character_page(page)
	local name = t("edit_character")
	for _, field in ipairs(CHARACTER_FIELDS) do
		unit_field(page, HELLDIVER, { family = "character", path = field.path, label = field.label, min = field.min, max = field.max, step = field.step, apply = field.apply, type = "number" }, name)
	end
end

M.build = function(page)
	page:page(t("edit_primaries"), weapons_list(catalog.primaries))
	page:page(t("edit_sidearms"), weapons_list(catalog.sidearms))
	page:page(t("edit_support"), weapons_list(catalog.support_weapons))
	page:page(t("edit_grenades"), grenades_list)
	page:page(t("edit_backpacks"), named_units(catalog.backpacks))
	page:page(t("edit_stratagems"), stratagems_list)
	page:page(t("edit_sentries"), named_units(by_subtype("turret")))
	page:page(t("edit_mines"), mines_list)
	page:page(t("edit_strikes"), named_units(by_subtype("strike")))
	page:page(t("edit_vehicles"), named_units(catalog.vehicles))
	page:page(t("edit_enemies"), enemies_list)
	page:page(t("edit_statuses"), statuses_list)
	page:page(t("edit_character"), character_page)
end

return M
