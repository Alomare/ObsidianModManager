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

-- One row per field the item really has. A boolean that's absent reads as off.
local function unit_field(page, settings_path, field, name)
	local value = edits.value(settings_path, field.path)
	if value == nil and not field.opt then return end
	if value == nil and field.type ~= "boolean" then return end
	local help = field.meaning and (field.apply and (field.meaning .. ". " .. t("applies_" .. field.apply)) or field.meaning) or nil
	local opts = { min = field.min, max = field.max, apply = field.apply, target = name, new = field.opt }
	if field.type == "boolean" then
		page:toggle(field.label, {
			help = help,
			get = function() return edits.value(settings_path, field.path) == true end,
			set = function(v) note(edits.set_unit(settings_path, field.path, v, opts)) end,
		})
	else
		page:number(field.label, {
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

local function enemies_list(page)
	for _, enemy in ipairs(catalog.enemies()) do
		page:page(enemy.name, unit_page(enemy.settings, enemy.name))
	end
end

local function table_fields(family, name, target)
	return function(page)
		for _, field in ipairs(catalog.fields(family)) do
			if edits.table_value(target, field.path) ~= nil or field.opt then
				page:number(field.label, {
					min = field.min, max = field.max, step = step_of(field),
					help = field.meaning and (field.meaning .. ". " .. t("applies_" .. field.apply)) or nil,
					get = function() return edits.table_value(target, field.path) or 0 end,
					set = function(v) note(edits.set_table(name, target, field.path, v, { min = field.min, max = field.max, apply = field.apply, new = field.opt })) end,
				})
			end
		end
	end
end

local function stratagems_list(page)
	for _, s in ipairs(catalog.stratagems()) do
		local name = catalog.text(s.name)
		page:page(name, table_fields("stratagem", name, s))
	end
end

local function statuses_list(page)
	local templates = game.global("StatusTemplateSettings")
	for _, name in ipairs(catalog.status_templates()) do
		page:page(name, table_fields("status", name, templates[name]))
	end
end

local function character_page(page)
	local name = t("edit_character")
	for _, field in ipairs(CHARACTER_FIELDS) do
		unit_field(page, HELLDIVER, { path = field.path, label = field.label, min = field.min, max = field.max, step = field.step, apply = field.apply, type = "number" }, name)
	end
end

M.build = function(page)
	page:page(t("edit_primaries"), weapons_list(catalog.primaries))
	page:page(t("edit_sidearms"), weapons_list(catalog.sidearms))
	page:page(t("edit_support"), weapons_list(catalog.support_weapons))
	page:page(t("edit_stratagems"), stratagems_list)
	page:page(t("edit_enemies"), enemies_list)
	page:page(t("edit_statuses"), statuses_list)
	page:page(t("edit_character"), character_page)
end

return M
