-- World: time, camera, HUD and the look of the mission.
local U = obsidian.module("pages/ui")
local api, t = U.api, U.t
local world = api.world

local blast = { power = 500, radius = 8 }

return function(page)
	page:header(t("time"))
	U.effect_number(page, "time_scale", "time_scale", { off = 1, min = 0.1, max = 4, step = 0.1, format = "x%.1f" })
	U.effect(page, "pause", "pause")

	page:header(t("camera"))
	U.effect_number(page, "camera_distance", "camera_distance", { off = 17, min = 5, max = 60, step = 1 })
	U.effect_number(page, "camera_angle", "camera_angle", { off = 65, min = 20, max = 90, step = 5 })
	U.effect(page, "free_camera_bounds", "free_camera_bounds")
	U.effect(page, "no_camera_shake", "no_camera_shake")

	page:header(t("screen"))
	U.effect(page, "hide_hud", "hide_hud")
	U.effect(page, "show_patrols", "show_patrols")
	U.effect(page, "test_info", "test_info")

	page:header(t("look"))
	U.effect(page, "no_fog", "no_fog")
	U.effect(page, "no_dof", "no_dof")
	U.effect_number(page, "exposure", "exposure", { off = 1, min = 0.2, max = 3, step = 0.1, format = "%.1f" })
	U.effect_choice(page, "time_of_day", "time_of_day", {
		{ id = false, label = t("time_of_day_auto") }, { id = "dawn", label = t("seed_dawn") }, { id = "day", label = t("seed_day") },
		{ id = "dusk", label = t("seed_dusk") }, { id = "night", label = t("seed_night") },
	})
	U.effect_number(page, "gravity", "gravity", { off = -18, min = -60, max = -1, step = 1 })
	U.effect(page, "mute_music", "mute_music")
	U.action(page, "clear_decals", world.clear_decals)

	page:header(t("blast"))
	page:number(t("blast_power"), { min = 10, max = 20000, step = 50, get = function() return blast.power end, set = function(v) blast.power = v end })
	page:number(t("blast_radius"), { min = 1, max = 30, step = 1, get = function() return blast.radius end, set = function(v) blast.radius = v end })
	page:action(t("blast_cursor"), function()
		local ok, why = world.explode(world.cursor(), blast.power, blast.radius)
		if ok then return t("done") end
		return U.why(why)
	end, { enabled = U.in_mission })
end
