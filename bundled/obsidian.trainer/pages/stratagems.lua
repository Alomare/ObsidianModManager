-- Stratagems: cooldowns, uses, call-in time, and calling one down at will.
local U = obsidian.module("pages/ui")
local api, t = U.api, U.t
local stratagems, catalog, world = api.stratagems, api.catalog, api.world

local function list(run)
	return function(page)
		for _, s in ipairs(catalog.stratagems()) do
			page:action(catalog.text(s.name), function() return run(s) end)
		end
	end
end

local function result(ok, why)
	if ok then return t("done") end
	return U.why(why)
end

return function(page)
	U.effect(page, "no_cooldown", "no_cooldown")
	U.effect(page, "free_stratagems", "free_stratagems")
	U.effect(page, "instant_call_in", "instant_call_in")
	U.effect(page, "fast_pods", "fast_pods")
	U.action(page, "reset_cooldowns", stratagems.reset_cooldowns)
	U.action(page, "refill_uses", stratagems.refill_uses)

	page:header(t("call_down"))
	page:page(t("drop_cursor"), list(function(s) return result(stratagems.drop(s.name, world.cursor())) end), { help = U.help("drop_cursor") })
	page:page(t("give_stratagem"), list(function(s) return result(stratagems.give(s.name)) end), { help = U.help("give_stratagem") })

	page:header(t("any_arrow"))
	U.effect(page, "any_arrow_on", "any_arrow")
	page:page(t("any_arrow_pick"), list(function(s)
		stratagems.select(s.id)
		api.effects.set("any_arrow", true)
		return t("any_arrow_set", catalog.text(s.name))
	end))
end
