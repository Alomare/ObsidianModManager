-- Player: staying alive, moving, getting around, looks.
local U = obsidian.module("pages/ui")
local api, t = U.api, U.t
local player, catalog = api.player, api.catalog

local function cosmetics(slot)
	return function(page)
		for _, item in ipairs(catalog.cosmetics(slot)) do
			page:action(catalog.text(item.name or tostring(item.index)), U.act(player.set_cosmetic, slot, item.index))
		end
	end
end

local OUTLINES = {
	{ id = false, key = "outline_own" },
	{ id = { 240, 180, 41 }, key = "color_gold" },
	{ id = { 92, 180, 196 }, key = "color_cyan" },
	{ id = { 183, 60, 60 }, key = "color_red" },
	{ id = { 96, 162, 93 }, key = "color_green" },
	{ id = { 165, 60, 211 }, key = "color_purple" },
}

local function outlines()
	local out = {}
	for i, c in ipairs(OUTLINES) do out[i] = { id = c.id, label = t(c.key) } end
	return out
end

return function(page)
	page:header(t("survival"))
	U.effect(page, "god", "god")
	U.effect(page, "no_status", "no_status")
	U.effect_number(page, "regen", "regen", { off = 0, min = 0, max = 100, step = 5 })
	U.effect_number(page, "shield", "shield", { off = 0, min = 0, max = 30000, step = 500 })
	U.effect_number(page, "damage_to_players", "damage_to_players", { off = 1, min = 0, max = 10, step = 0.25, format = "x%.2f" })
	U.effect_number(page, "armor_value", "armor", { off = 0, min = 0, max = 500, step = 5 })
	U.effect(page, "hidden", "hidden")
	U.action(page, "heal", player.heal)
	U.action(page, "revive", player.revive)
	U.action(page, "respawn", player.respawn)
	U.action(page, "heal_everyone", player.heal_everyone)
	U.action(page, "revive_everyone", player.revive_everyone)
	page:number(t("lives"), {
		min = 0, max = 20, step = 1, help = U.help("lives"),
		get = function() return player.lives() or 0 end,
		set = function(v) player.set_lives(v) end,
		enabled = U.in_mission,
	})

	page:header(t("movement"))
	U.effect_number(page, "speed", "speed", { off = 1, min = 0.25, max = 6, step = 0.25, format = "x%.2f" })
	U.effect(page, "infinite_stamina", "infinite_stamina")
	U.effect(page, "noclip", "noclip")
	U.effect(page, "ignore_slow", "ignore_slow")
	U.effect(page, "no_screen_leash", "no_screen_leash")
	U.effect_number(page, "throw_range", "throw_range", { off = 1, min = 0.5, max = 5, step = 0.25, format = "x%.2f" })
	U.action(page, "drop_carried", player.drop_carried)

	page:header(t("teleport"))
	U.action(page, "tp_cursor", player.teleport_cursor)
	U.action(page, "tp_ahead", player.teleport_ahead, 10)
	U.action(page, "tp_objective", player.teleport_objective)
	U.action(page, "tp_extraction", player.teleport_extraction)
	U.action(page, "tp_spawn", player.teleport_spawn)
	U.action(page, "unstick", player.unstick)

	page:header(t("looks"))
	page:page(t("helmet"), cosmetics("helmet"))
	page:page(t("armor"), cosmetics("body"))
	page:page(t("cape"), cosmetics("cape"))
	page:page(t("gender"), cosmetics("gender"))
	U.effect(page, "heavy_armor_look", "heavy_armor_look")
	U.effect(page, "hide_model", "hide_model")
	U.effect_choice(page, "outline_color", "outline_color", outlines())
	U.action(page, "taunt", player.taunt)
end
