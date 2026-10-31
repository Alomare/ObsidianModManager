-- Spawn: crates, ammunition and pickups on the spot, and real call-ins at the cursor. The lists come
-- from the stratagems this player can use, so paid content they don't own stays out.
local U = obsidian.module("pages/ui")
local api, t = U.api, U.t
local enemies, catalog, world = api.enemies, api.catalog, api.world

local AMMO_BOX = "gameobjects/pickup_ammunitionbox_01"

local where = "ahead"

local function position()
	if where == "cursor" then return world.cursor() end
	return world.ahead(3)
end

local function spawn(path)
	return function() return U.result(enemies.spawn_entity(path, position())) end
end

local function rows(list)
	return function(page)
		for _, item in ipairs(list()) do page:action(catalog.text(item.name), spawn(item.unit_path)) end
	end
end

return function(page)
	page:choice(t("spawn_where"), {
		choices = { { id = "ahead", label = t("where_ahead") }, { id = "cursor", label = t("where_cursor") } },
		get = function() return where end,
		set = function(v) where = v end,
	})
	page:action(t("spawn_ammo"), spawn(AMMO_BOX), { enabled = U.in_mission })
	page:page(t("spawn_crates"), rows(catalog.crates), { help = U.help("spawn_crates") })
	page:page(t("spawn_pickups"), rows(catalog.pickups))

	page:header(t("call_down"))
	U.call_rows(page)
end
