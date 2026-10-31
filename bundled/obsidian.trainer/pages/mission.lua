-- Mission: objectives, extraction, waits, samples, modifiers, and a practice drop from the ship.
local U = obsidian.module("pages/ui")
local api, t = U.api, U.t
local mission = api.mission

local practice = { time = 2, environment = 1, enemy = 1, kind = 1, difficulty = 5 }

local function choices(list)
	local out = {}
	for i, id in ipairs(list) do out[i] = { id = i, label = t("seed_" .. id) } end
	return out
end

local function pick(page, key, field, list)
	page:choice(t(key), { choices = choices(list), get = function() return practice[field] end, set = function(v) practice[field] = v end })
end

local function practice_page(page)
	pick(page, "seed_time", "time", mission.TIMES)
	pick(page, "seed_environment", "environment", mission.ENVIRONMENTS)
	pick(page, "seed_enemy", "enemy", mission.FACTIONS)
	pick(page, "seed_kind", "kind", mission.TYPES)
	page:number(t("seed_difficulty"), { min = 1, max = 15, step = 1, get = function() return practice.difficulty end, set = function(v) practice.difficulty = v end })
	page:action(t("practice_start"), U.act(mission.practice, practice), { help = U.help("practice_start") })
end

local function objective_page(page)
	local list = mission.objectives()
	if #list == 0 then page:label(t("no_mission")) end
	for _, o in ipairs(list) do
		local name = o.text
		if o.total and o.total > 1 then name = string.format("%s (%s/%s)", name, tostring(o.done), tostring(o.total)) end
		page:label(t("objective_row", name, t("objective_" .. tostring(o.state))))
	end
end

local function players_page(page)
	for _, p in ipairs(api.lobby.players()) do
		local name = p.name or t("player_joining")
		if p.host then name = t("player_host", name) end
		page:label(p.ping and t("player_ping", name, tostring(p.ping)) or name)
	end
end

local function modifier_choices()
	local out = { { id = false, label = t("mutator_off") } }
	for _, name in ipairs(mission.MUTATORS) do
		out[#out + 1] = { id = name, label = api.catalog.text("provinggrounds_" .. name) }
	end
	return out
end

return function(page)
	page:label(function()
		local params, seed = mission.params()
		if not params then return t("no_mission") end
		return t("mission_info", tostring(seed), tostring(params.difficulty or "?"), tostring(params.enemy or "?"))
	end)

	page:header(t("objectives"))
	page:page(t("objective_list"), objective_page)
	U.action(page, "finish_objectives", mission.finish_objectives)
	U.action(page, "restart_objectives", mission.restart_objectives)
	U.effect(page, "protect_objectives", "protect_objectives")
	U.effect(page, "fast_extract", "fast_extract")
	U.action(page, "win", mission.win)
	U.action(page, "abort", mission.abort)

	page:header(t("waits"))
	U.effect(page, "skip_waits", "skip_waits")
	U.effect(page, "fast_mission_start", "fast_mission_start")

	page:header(t("reinforcements"))
	U.effect(page, "infinite_respawns", "infinite_respawns")
	U.effect(page, "no_game_over", "no_game_over")

	page:header(t("modifiers"))
	U.effect_choice(page, "mutator", "mutator", modifier_choices())

	page:header(t("players_header"))
	page:page(t("players_here"), players_page)

	page:header(t("samples"))
	U.action(page, "spawn_samples", mission.spawn_samples)
	U.action(page, "collect_samples", mission.collect_samples)
	U.action(page, "reveal_map", mission.reveal_map)

	page:header(t("practice"))
	page:page(t("practice_setup"), practice_page, { help = U.help("practice_setup") })
end
