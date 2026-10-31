-- Progress: the player's own save. XP and rank aren't here on purpose: see lib/progress.lua in
-- Obsidian API.
local U = obsidian.module("pages/ui")
local api, t = U.api, U.t
local progress = api.progress

local function item_list(key, list)
	return function(page)
		for _, item in ipairs(list()) do
			page:action(api.catalog.text(item.name), U.act(progress.set_loadout, { [key] = item.name }))
		end
	end
end

local function stratagem_slot(slot)
	return U.stratagem_list(function(s) return U.result(progress.set_loadout({ stratagems = { [slot] = s.name } })) end)
end

local function loadout(page)
	page:page(t("loadout_primary"), item_list("primary_weapon", api.catalog.primaries))
	page:page(t("loadout_sidearm"), item_list("sidearm_weapon", api.catalog.sidearms))
	page:page(t("loadout_perk"), item_list("perk", api.catalog.perks))
	for slot = 1, 4 do page:page(t("loadout_slot", slot), stratagem_slot(slot)) end
end

local function upgrade_rows(page, list)
	for _, item in ipairs(list) do
		local limit = progress.upgrade_limit(item.name)
		if limit and limit > 0 then
			page:number(api.catalog.text(item.name), {
				min = 0, max = limit, step = 1,
				get = function() return progress.upgrades()[item.name] or 0 end,
				set = function(v)
					local ok, why = progress.set_upgrade(item.name, v)
					if not ok then obsidian.toast(U.why(why)) end
				end,
			})
		end
	end
end

local function upgrades(page)
	upgrade_rows(page, api.catalog.primaries())
	upgrade_rows(page, api.catalog.sidearms())
	upgrade_rows(page, api.catalog.stratagems())
end

return function(page)
	page:label(function()
		local rank, xp = progress.rank()
		if not rank then return t("no_rank") end
		return t("rank_info", api.catalog.text(rank.name or ""), tostring(xp))
	end)
	page:number(t("samples_owned"), {
		min = 0, max = progress.max_samples(), step = 10, help = U.help("samples_owned"),
		get = function() return progress.samples() end,
		set = function(v)
			local ok, why = progress.set_samples(v)
			if not ok then obsidian.toast(U.why(why)) end
		end,
	})
	U.action(page, "unlock_items", progress.unlock_items)
	U.action(page, "upgrade_all", progress.upgrade_all)
	page:page(t("loadout_page"), loadout, { help = U.help("loadout_page") })
	page:page(t("upgrades_page"), upgrades, { help = U.help("upgrades_page") })
end
