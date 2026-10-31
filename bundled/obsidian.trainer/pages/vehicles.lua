-- Vehicles: the one under the player. Driving makes a vehicle this player's a moment after getting
-- in, and the runtime waits for that, so these can be set before a vehicle is around.
local U = obsidian.module("pages/ui")
local api, t = U.api, U.t
local gear, vehicles = api.gear, api.vehicles

return function(page)
	page:label(function()
		if not vehicles.current() then return t("vehicle_none") end
		if vehicles.driving() then return t("vehicle_driving") end
		return t("vehicle_riding")
	end)

	page:header(t("vehicle"))
	U.effect_number(page, "vehicle_speed", "vehicle_speed", { off = 1, min = 0.25, max = 6, step = 0.25, format = "x%.2f" })
	U.effect_number(page, "vehicle_turn", "vehicle_turn", { off = 1, min = 0.25, max = 4, step = 0.25, format = "x%.2f" })
	U.effect_number(page, "vehicle_armor", "vehicle_armor", { off = 0, min = 0, max = 5000, step = 100 })
	U.effect(page, "vehicle_god", "vehicle_god")
	U.effect(page, "vehicle_rockets", "vehicle_rockets")
	U.action(page, "repair_vehicle", gear.repair_vehicle)
	U.action(page, "refill_vehicle", gear.refill_vehicle)
end
