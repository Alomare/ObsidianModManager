-- Changes: what's switched on and what's been edited, and the way back. Edits can be kept for the
-- next launch: they're stored as text and applied once the game's data has loaded.
local U = obsidian.module("pages/ui")
local api, t = U.api, U.t
local edits, effects, game = api.edits, api.effects, api.game

local M = {}

local PREFIX = "edit."

local function encode(e)
	return table.concat({ e.settings_path, e.path, type(e.value), tostring(e.value) }, "|")
end

local function decode(text)
	local settings_path, path, kind, value = string.match(text, "^([^|]+)|([^|]+)|([^|]+)|(.*)$")
	if not settings_path then return nil end
	if kind == "number" then
		value = tonumber(value)
	elseif kind == "boolean" then
		value = value == "true"
	end
	return settings_path, path, value
end

function M.save()
	for key in pairs(obsidian.storage.all()) do
		if string.sub(key, 1, #PREFIX) == PREFIX then obsidian.storage.set(key, nil) end
	end
	local n = 0
	for _, e in ipairs(edits.list()) do
		if e.settings_path then
			n = n + 1
			obsidian.storage.set(PREFIX .. n, encode(e))
		end
	end
	return n
end

-- Weapon data is complete once the game has made its upgrade tables.
local function data_ready()
	local lsm = game.global("LuaSettingsManager")
	return lsm and next(lsm.unit_path_to_modified_settings or {}) ~= nil
end

function M.load_saved()
	if not data_ready() then return false end
	for key, text in pairs(obsidian.storage.all()) do
		if string.sub(key, 1, #PREFIX) == PREFIX then
			local settings_path, path, value = decode(text)
			if settings_path then
				local ok, why = edits.set_unit(settings_path, path, value, { target = settings_path })
				if not ok then obsidian.log("saved edit not applied (" .. tostring(why) .. "): " .. path) end
			end
		end
	end
	return true
end

M.build = function(page)
	page:header(t("changes_on"))
	local active = effects.active()
	if #active == 0 then page:label(t("changes_none")) end
	for _, id in ipairs(active) do page:label(id) end
	if #active > 0 then
		page:action(t("changes_effects_off"), function()
			effects.clear()
			page:refresh()
			return t("done")
		end)
	end

	page:header(t("changes_edits"))
	local list = edits.list()
	if #list == 0 then page:label(t("changes_none")) end
	for _, e in ipairs(list) do
		page:action(string.format("%s: %s = %s", tostring(e.target), e.path, tostring(e.value)), function()
			edits.revert(e.id)
			page:refresh()
			return t("done")
		end, { help = t("changes_edit_help", tostring(e.owner)) })
	end
	if #list > 0 then
		page:action(t("changes_edits_off"), function()
			edits.revert_all()
			page:refresh()
			return t("done")
		end)
		page:action(t("changes_keep"), function() return t("changes_kept", M.save()) end, { help = U.help("changes_keep") })
	end
end

return M
