-- Enemies: stopping them, getting rid of them, bringing more.
local U = obsidian.module("pages/ui")
local api, t = U.api, U.t
local enemies, catalog = api.enemies, api.catalog

local amount, where = 1, "ahead"

local FACTIONS = { { id = "bugs", key = "faction_bugs" }, { id = "cyborgs", key = "faction_cyborgs" }, { id = "illuminates", key = "faction_illuminates" } }

-- A map packed far past what the game ever puts on it can take the mission down, so spawning stops
-- short of that.
local function if_room(run)
	return function()
		if enemies.room() < 1 then return U.why("map_full") end
		return run()
	end
end

local function spawn_list(faction)
	return function(page)
		page:choice(t("spawn_where"), {
			choices = { { id = "ahead", label = t("where_ahead") }, { id = "cursor", label = t("where_cursor") } },
			default = "ahead",
			get = function() return where end,
			set = function(v) where = v end,
		})
		page:number(t("spawn_amount"), { min = 1, max = 30, step = 1, default = 1, get = function() return amount end, set = function(v) amount = v end })
		for _, enemy in ipairs(catalog.enemies(faction)) do
			if not enemy.boss and enemies.available(enemy) then
				page:action(enemy.name, if_room(function()
					local room = enemies.room()
					local ok, why = enemies.spawn(enemy.key, math.min(amount, room), where ~= "ahead" and where or nil)
					if not ok then return U.why(why) end
					if amount > room then return t("spawned_some", room) end
					return t("done")
				end))
			end
		end
	end
end

local function group_list(page)
	for _, key in ipairs(catalog.enemy_groups()) do
		page:action(catalog.text(key), if_room(U.act(enemies.spawn_group, key)), { enabled = U.host_only })
	end
end

local function wave_list(page)
	local names = enemies.waves()
	if #names == 0 then page:label(t("no_waves")) end
	for _, name in ipairs(names) do
		page:action(catalog.text(name), if_room(U.act(enemies.force_wave, name)), { enabled = U.host_only })
	end
end

return function(page)
	page:label(function() return t("enemy_count", enemies.count()) end)
	page:header(t("control"))
	page:toggle(t("no_spawns"), {
		help = U.help("no_spawns"), enabled = U.host_only, default = false,
		get = function() return api.effects.is_on("no_spawns") end,
		set = function(v) api.effects.set("no_spawns", v) end,
	})
	U.effect(page, "freeze", "freeze")
	U.effect(page, "blind", "blind")
	U.effect(page, "host_owns_enemies", "host_owns_enemies")
	U.action(page, "stun_near", enemies.stun_near, 20)
	U.effect_number(page, "damage_to_enemies", "damage_to_enemies", { off = 1, min = 0, max = 10, step = 0.25, format = "x%.2f" })

	page:header(t("pressure"))
	U.effect_number(page, "max_enemies", "enemy_cap", { off = 16, min = 1, max = enemies.MAX_CAP, step = 1, enabled = U.host_only })
	U.effect_number(page, "enemy_difficulty", "enemy_difficulty", { off = 0, min = 0, max = 15, step = 1, enabled = U.host_only })
	U.effect_number(page, "patrol_count", "patrol_count", { off = 0, min = 0, max = 60, step = 2, enabled = U.host_only })
	U.effect_number(page, "patrol_interval", "patrol_interval", { off = 0, min = 0, max = 120, step = 1, enabled = U.host_only })

	page:header(t("remove"))
	U.action(page, "kill_all", enemies.kill_all)
	U.action(page, "kill_near", enemies.kill_near, 20)
	U.action(page, "despawn_all", enemies.despawn_all)

	page:header(t("bring"))
	for _, f in ipairs(FACTIONS) do
		page:page(t("spawn_faction", t(f.key)), spawn_list(f.id))
	end
	page:page(t("spawn_group"), group_list)
	page:page(t("spawn_wave"), wave_list, { help = U.help("spawn_wave") })
	U.action(page, "call_encounter", enemies.call_encounter)
	U.action(page, "add_patrol", enemies.add_patrol)
end
