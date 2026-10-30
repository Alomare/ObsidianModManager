-- Weapons: ammunition, giving weapons and perks, backpacks and vehicles.
local U = obsidian.module("pages/ui")
local api, t = U.api, U.t
local gear, catalog = api.gear, api.catalog

local GRENADES = {
	{ id = "equipment/equipment_grenade_01", key = "grenade_frag" },
	{ id = "equipment/equipment_grenade_incendiary", key = "grenade_fire" },
	{ id = "equipment/equipment_grenade_stun", key = "grenade_stun" },
	{ id = "equipment/equipment_grenade_smoke", key = "grenade_smoke" },
}

local function give(slot, list)
	return function(page)
		for _, item in ipairs(list()) do
			page:action(catalog.text(item.name), U.act(gear.give_weapon, slot, item.unit_path))
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
	page:page(t("give_primary"), give("primary_weapon", catalog.primaries))
	page:page(t("give_sidearm"), give("sidearm_weapon", catalog.sidearms))
	page:page(t("give_support"), give("support_weapon", catalog.support_weapons))
	page:page(t("give_perk"), function(sub)
		for _, perk in ipairs(catalog.perks()) do
			sub:action(catalog.text(perk.name), U.act(gear.give_perk, perk.name))
		end
	end)
	page:page(t("grenade_type"), function(sub)
		for _, g in ipairs(GRENADES) do
			sub:action(t(g.key), U.act(gear.set_grenade, g.id))
		end
	end)

	page:header(t("vehicle"))
	U.action(page, "repair_vehicle", gear.repair_vehicle)
	U.action(page, "refill_vehicle", gear.refill_vehicle)
end
