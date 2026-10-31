-- Weapons: ammunition, and giving weapons, packs and perks.
local U = obsidian.module("pages/ui")
local api, t = U.api, U.t
local gear, catalog = api.gear, api.catalog

local upgrades = "own"

-- nil lets the runtime use what the player owns for that item.
local function upgrade_of(path)
	if upgrades == "none" then return 0 end
	if upgrades == "all" then return catalog.max_upgrade(path) end
	return nil
end

local function give(slot, list)
	return function(page)
		for _, item in ipairs(list()) do
			page:action(catalog.text(item.name), function() return U.result(gear.give_weapon(slot, item.unit_path, upgrade_of(item.unit_path))) end)
		end
	end
end

return function(page)
	page:header(t("ammunition"))
	U.effect(page, "infinite_ammo", "infinite_ammo")
	U.effect(page, "instant_reload", "instant_reload")
	U.action(page, "refill", gear.refill)
	U.action(page, "refill_grenades", gear.refill_grenades)
	U.action(page, "refill_backpack", gear.refill_backpack)

	page:header(t("give"))
	page:choice(t("give_upgrades"), {
		help = U.help("give_upgrades"), default = "own",
		choices = { { id = "own", label = t("upgrades_own") }, { id = "none", label = t("upgrades_none") }, { id = "all", label = t("upgrades_all") } },
		get = function() return upgrades end,
		set = function(v) upgrades = v end,
	})
	page:page(t("give_primary"), give("primary_weapon", catalog.primaries))
	page:page(t("give_sidearm"), give("sidearm_weapon", catalog.sidearms))
	page:page(t("give_support"), give("support_weapon", catalog.support_weapons))
	page:page(t("give_backpack"), function(sub)
		for _, item in ipairs(catalog.backpacks()) do
			sub:action(catalog.text(item.name), function() return U.result(gear.give_backpack(item.unit_path, upgrade_of(item.unit_path))) end)
		end
	end, { help = U.help("give_backpack") })
	page:page(t("give_perk"), function(sub)
		for _, perk in ipairs(catalog.perks()) do
			sub:action(catalog.text(perk.name), U.act(gear.give_perk, perk.name))
		end
	end)
	U.action(page, "remove_perk", gear.remove_perk)
	page:page(t("grenade_type"), function(sub)
		for _, g in ipairs(U.GRENADES) do
			sub:action(t(g.key), U.act(gear.set_grenade, g.id))
		end
	end)
end
