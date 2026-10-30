-- A small mission of the game, for testing Obsidian API and the trainer. It copies the behaviour
-- that makes mistakes costly: an unknown queued command asserts, a command on a unit this peer
-- doesn't own asserts, and a protected value changed outside set_protected is recorded as
-- tampering, which is what the game's check would catch.
local E = require "fake_engine"
local F = require "fake_ui"

local G = {}

local PROTECTED = {
	hitpoints_real = true, armor_min = true, armor_max = true, rounds = true, num_mags = true, reload_time = true,
	magazine_capacity = true, num_grenades = true, cooldown_timer = true, uses_left = true, wanted_move_speed = true,
	defend_timer = true, enemies_killed = true, enemies_to_kill = true, current_wave = true, extra_lives = true,
}

-- Commands the game's components accept. Anything else is the game's assert("Unrecognized message").
local KNOWN = {}
for component, list in pairs({
	health = "reset do_heal set_hitpoints armor set_invincible set_ignore_death_plane set_health_decay do_damage",
	status = "remove_all remove_status remove_statuses_by_element add_immunity_status add_immunity_element",
	shield = "set_shieldpoints set_shield_activated set_shield_info reset_shield_info",
	character = "infinite_stamina move_speed_sprint_max do_knockdown drop_carry exit_interact_objective set_throw_range_multiplier",
	mover = "position position_teleport move_speed acceleration deceleration ignore_slow keep_inside_screen destroy enable",
	inventory = "ammo_pickup set_grenades set_grenade_path set_stratagem_info broadcast_stratagem_cooldown set_stratagem_cooldown_multiplier receive_stratagem set_weapon set_perk set_item_upgrades",
	customization = "set_customization communication_event",
	enemy_target = "enable disable",
	enemy = "remove_from_group",
	research_sample_pickup = "interact",
	show_on_map = "show",
}) do
	KNOWN[component] = {}
	for word in list:gmatch("%S+") do KNOWN[component][word] = true end
end

local function guarded(game, real)
	return setmetatable({}, {
		__index = real,
		__newindex = function(_, k, v)
			if PROTECTED[k] and not game.in_setter then game.tampered[#game.tampered + 1] = k end
			real[k] = v
		end,
		__len = function() return #real end,
	})
end

local function unit(game, parts)
	local u = { alive = true, master = {}, slave = {}, owned = parts.owned ~= false, pos = parts.pos or { x = 0, y = 0, z = 0 } }
	for name, state in pairs(parts.components or {}) do
		u.master[name] = guarded(game, state)
		u.slave[name] = guarded(game, state)
	end
	return u
end

local function component(game, name, plugin)
	return {
		name = name,
		set_protected = function(_, state, key, value)
			game.in_setter = true
			state[key] = value
			game.in_setter = false
			game.protected[#game.protected + 1] = key
		end,
		setup_console_plugin = plugin and function() return plugin end or nil,
	}
end

-- Starts the engine with the bundled mods given, then a mission. opts: lobby, state, host, dlc.
function G.start(ids, opts)
	opts = opts or {}
	local mods, deploy_mods = {}, {}
	for _, id in ipairs(ids) do
		local manifest = E.read("bundled/" .. id .. "/obsidian.json")
		mods["obsidian/mods/" .. id .. "/main"] = E.read("bundled/" .. id .. "/main.lua")
		local list = manifest:match('"modules":%s*%[(.-)%]') or ""
		for path in list:gmatch('"([^"]+)%.lua"') do
			mods["obsidian/mods/" .. id .. "/" .. path] = assert(E.read("bundled/" .. id .. "/" .. path .. ".lua"), path)
		end
		local texts = {}
		for _, lang in ipairs({ "en", "fr", "es", "pt-BR" }) do
			local raw = E.read("bundled/" .. id .. "/locales/" .. lang .. ".json")
			if raw then
				texts[lang] = {}
				for k, v in raw:gmatch('"([^"]+)": "(.-)",?\r?\n') do texts[lang][k] = v end
			end
		end
		deploy_mods[#deploy_mods + 1] = E.mod(id, { scope = "session", texts = texts,
			requires = id == "obsidian.trainer" and { "obsidian.api" } or nil,
			options = { { id = "keep_edits", type = "toggle", default = false } },
			keybinds = { { id = "open", default = "f6" } } })
	end
	local e = E.new({ deploy = E.deploy({ mods = deploy_mods, has_session = true, texts = { en = {
		menu_title = "Obsidian", menu_empty = "No pages", menu_failed = "Page failed", menu_unavailable = "Not now",
		menu_filter = "Filter", menu_on = "ON", menu_off = "OFF", menu_keys = "Keys",
	} } }), mods = mods, lobby = opts.lobby })

	-- string and table helpers the game adds, then the rest of the game.
	local game = { commands = {}, tampered = {}, protected = {}, sent = {}, rpc = {}, spawned = {}, saved = 0 }
	e.game = game
	rawset(string, "split_command", nil)

	e:boot()
	e:start_frames()
	local ui = F.install(e, { state = opts.state or "game" })
	game.ui = ui

	rawset(_G, "Unit", {
		alive = function(u) return u ~= nil and u.alive ~= false end,
		world_position = function(u) return u.pos end,
		local_rotation = function() return "rotation" end,
		mover = function(u) return u.master.mover ~= nil end,
		mover_fits_at = function() return true end,
		get_data = function() return nil end,
	})
	local v3 = setmetatable({
		normalize = function(v) return v end,
		distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end,
		forward = function() return { x = 0, y = 1, z = 0 } end,
	}, { __call = function(_, x, y, z) return setmetatable({ x = x, y = y, z = z }, G.vector) end })
	rawset(_G, "Vector3", v3)
	rawset(_G, "Quaternion", { forward = function() return v3(0, 1, 0) end, identity = function() return "identity" end })
	rawset(_G, "Vector3Aux", {
		box = function(t, v) t.x, t.y, t.z = v.x, v.y, v.z return t end,
		unbox = function(t) return v3(t.x, t.y, t.z) end,
	})
	rawset(_G, "Mouse", { axis_index = function() return 1 end, axis = function() return v3(10, 10, 0) end })
	rawset(_G, "Camera", { world_position = function() return v3(0, 0, 20) end })
	rawset(_G, "PhysicsWorld", {
		immediate_raycast = function() return true, v3(5, 5, 0) end,
		set_gravity = function(_, g) game.gravity = g end,
	})
	rawset(_G, "Timpani", { set_bus_volume = function(bus, v) game.bus = { bus, v } end })
	rawset(_G, "Network", { peer_id = function() return "me" end })
	rawset(_G, "NetworkGlobal", rawget(_G, "NetworkGlobal") or { lobby = { is_host = function() return opts.host ~= false end,
		members = function() return { "me" } end, member_data = function() end, set_member_data = function() end, my_id = "me" } })
	local lobby = rawget(_G, "NetworkGlobal").lobby
	lobby.is_host = function() return opts.host ~= false end

	local dlc_items = opts.dlc or { weapon_dlc = true, stratagem_dlc = true, cus_helmet_dlc = true }
	rawset(_G, "DlcSettings", {
		is_item_dlc = function(name) return dlc_items[name] == true end,
		can_use = function() return false end,
	})
	rawset(_G, "LocalizationManager", { current_language = opts.language or "en", string = function(_, key)
		if key == "weapon_rifle" then return "Rifle" end
		return "LOC:" .. key
	end })
	rawset(_G, "GameSettings", { get_main_pad_number = function() return 0 end, MAX_NUM_ALLOWED_ENEMIES = 16, MAX_NUM_RESEARCH_SAMPLES = 3168 })
	rawset(_G, "CameraManager", { change_settings = function(_, ...) game.camera = { ... } end, set_ignore_level_bounds = function() end,
		add_shake = function() game.shakes = (game.shakes or 0) + 1 end })
	rawset(_G, "UserManager", { get_user_id = function() return "user" end, get_name = function() return "Tester" end,
		unlock_trophy = function(_, name) game.trophy = name end })

	local save = { user = { player_xp = 1000, research_samples = 50, item_unlocks = { "owned_item" }, new_unlocks = {}, item_upgrades = { a = 1 } }, common = {} }
	game.save = save
	rawset(_G, "SaveManager", {
		get = function(_, k) return save.common[k] end,
		set = function(_, k, v) save.common[k] = v end,
		user_get = function(_, k) return save.user[k] end,
		user_set = function(_, k, v) save.user[k] = v end,
		save = function() game.saved = game.saved + 1 end,
		user_save = function() game.saved = game.saved + 1 end,
	})
	rawset(_G, "SaveDataHelper", { save_all = function() game.saved = game.saved + 1 end })
	rawset(_G, "PlanetRewardSettings", { planet_rewards = { bugs = { xp_boost = { { name = "boost" } }, weapon = { { name = "reward_item" }, { name = "weapon_dlc" } } } } })
	rawset(_G, "ProgressionSettings", { ranks = { { unlocks = { weapon = { "rank_item" } } } }, get_rank = function() return { name = "rank_private" } end })
	rawset(_G, "CustomizationSettings", { helmet = { { name = "cus_helmet_a" }, { name = "cus_helmet_dlc" } }, body = { { name = "cus_body_a" } }, cape = { { name = "cus_cape_tutorial" } }, gender = { { name = "x" } } })
	rawset(_G, "LoadoutSettings", {
		primary_weapon = { { name = "weapon_rifle", unit_path = "equipment/rifle" }, { name = "weapon_dlc", unit_path = "equipment/dlc" } },
		sidearm_weapon = { { name = "weapon_pistol", unit_path = "equipment/pistol" } },
		perks = { { name = "perk_cardio" } },
		stratagems = {
			{ id = 1, name = "stratagem_resupply", cooldown_time = 120, activation_time = 5, stratagem_subtypes = {} },
			{ id = 2, name = "stratagem_machinegun", cooldown_time = 0, activation_time = 3, stratagem_subtypes = { "support_weapon" }, unit = "gameobjects/crate" },
			{ id = 3, name = "stratagem_dlc", cooldown_time = 0, activation_time = 3 },
			{ id = 4, name = "stratagem_reinforce", cooldown_time = 0, activation_time = 3 },
		},
		find_stratagem = function() return "from the arrows" end,
		upgrade_all = function(t) t.all = 7 end,
	})
	rawset(_G, "StatusTemplateSettings", { heavy_burn = { power = 5, duration = 3 } })
	rawset(_G, "EnemyGroupSettings", { bug_scout_x2 = { units = { { unit_path = "characters/bug_scout/bug_scout", amount = 2 } } } })

	-- Settings files: one weapon with an upgrade clone, the way the game builds them.
	local rifle = { weapon_info = { power = 75, firerate = 650, magazine_capacity = 30, magazines = 6, magazines_max = 12, reload_duration = 2.5, reload_duration_fast = 1.25,
		attributes = {} }, melee_info = { power = 50, radius = 1, center_distance = 1, duration = 0.5 },
		upgrade_info = { type = "bitmask", { weapon_info = { magazine_capacity = 45 } } } }
	local rifle_upgraded = { weapon_info = { power = 75, firerate = 650, magazine_capacity = 45, magazines = 6, magazines_max = 12, reload_duration = 2.5, reload_duration_fast = 1.25,
		attributes = {} }, melee_info = { power = 50, radius = 1, center_distance = 1, duration = 0.5 },
		upgrade_info = { type = "bitmask", { weapon_info = { magazine_capacity = 45 } } } }
	game.rifle, game.rifle_upgraded = rifle, rifle_upgraded
	local helldiver = { character_info = { move_speed_jog = 4, move_speed_sprint_max = 7, sprint_stamina = 5 }, health_info = { health = 100, armor_max = 35 } }
	local scout = { enemy_info = { movement_speed = 4, threat_calculation = function() return 1 end, aggro_range = 80 }, health_info = { health = 30, armor_min = 15, armor_max = 25 } }
	local crate = { supply_crate_info = { content = { { unit_path = "equipment/mg_pickup" } } } }
	local by_settings = {
		["equipment/rifle"] = rifle, ["characters/helldiver_private_01/helldiver_private_01"] = helldiver,
		["characters/bug_scout/bug_scout"] = scout, ["gameobjects/crate"] = crate, ["equipment/mg"] = { weapon_info = { power = 40, magazine_capacity = 100, magazines = 3, magazines_max = 6, reload_duration = 5, reload_duration_fast = 4 } },
	}
	local unit_to_settings = { ["equipment/rifle"] = "equipment/rifle", ["equipment/mg_pickup"] = "equipment/mg", ["gameobjects/crate"] = "gameobjects/crate",
		["characters/helldiver_private_01/helldiver_private_01"] = "characters/helldiver_private_01/helldiver_private_01", ["characters/bug_scout/bug_scout"] = "characters/bug_scout/bug_scout" }
	rawset(_G, "LuaSettingsManager", {
		unit_path_to_modified_settings = { ["equipment/rifle"] = { [1] = rifle_upgraded } },
		get_settings_by_settings_path = function(_, p) return by_settings[p] end,
		get_settings_by_unit_path = function(_, p) return by_settings[unit_to_settings[p]] end,
		get_settings_path_by_unit_path = function(_, p) return unit_to_settings[p] end,
		get_settings_by_unit = function() return helldiver end,
		unit_path_to_settings_path_iterator = function() return pairs(unit_to_settings) end,
		all_settings_iterator = function() return pairs(by_settings) end,
	})
	local function clone(t)
		local out = {}
		for k, v in pairs(t) do out[k] = type(v) == "table" and clone(v) or v end
		return out
	end
	rawset(table, "clone", clone)
	local function override(t, o)
		for k, v in pairs(o) do
			if type(v) == "table" and type(t[k]) == "table" then override(t[k], v) else t[k] = v end
		end
	end
	rawset(_G, "SettingsAux", { recursive_override = override })

	-- The mission.
	local inventory = { stratagems = {
		guarded(game, { id = 1, cooldown_timer = 30, uses_left = 1, loadout_info = { num_uses = 4 } }),
	}, num_grenades = 1 }
	local weapon = unit(game, { components = { firearm = { rounds = 3, num_mags = 2, is_reloading = true, reload_time = 2 } } })
	inventory.current_weapon, inventory.primary_weapon = weapon, weapon
	local me = unit(game, { pos = { x = 1, y = 1, z = 0 }, components = {
		health = { hitpoints = 100, is_downed = false, is_dead = false, hitpoints_real = 100 }, status = {}, shield = {},
		character = { sprint_stamina = 0, input = {} }, mover = { position = { x = 1, y = 1, z = 0 } },
		inventory = inventory, customization = {}, enemy_target = {},
	} })
	game.me = me
	game.weapon = weapon
	local function enemy(owned, x)
		return unit(game, { owned = owned, pos = { x = x, y = 0, z = 0 }, components = { enemy = {}, health = { is_dead = false, constitution = -10 } } })
	end
	game.enemies = { enemy(true, 3), enemy(false, 100) }

	local comps = { health = component(game, "health"), status = component(game, "status"), inventory = component(game, "inventory"),
		firearm = component(game, "firearm"), stratagem = component(game, "stratagem"), launcher = component(game, "launcher"),
		flameweapon = component(game, "flameweapon"), beamweapon = component(game, "beamweapon"), throwable_weapon = component(game, "throwable_weapon") }
	comps.stratagem.spawn_stratagem_hellpod = function(_, ...) game.pods = { ... } end
	comps.stratagem.trigger_rpc_event = function() end
	comps.inventory.setup_console_plugin = function()
		return { give_stratagem = function(args) game.given = args[2] end }
	end
	game.objective_runs = {}
	for _, name in ipairs({ "objective_destroy_object", "objective_interact_object" }) do
		comps[name] = component(game, name, {
			complete_objectives = function() game.objective_runs[#game.objective_runs + 1] = name end,
			restart_objectives = function() game.objective_runs[#game.objective_runs + 1] = "restart " .. name end,
		})
	end
	comps.objective_destroy_object.setup_console_plugin = function()
		return { complete_objectives = function() error("one objective failed") end }
	end
	game.components = comps

	local masters = { enemy = {}, objective_destroy_object = { { state = {} } }, objective_interact_object = { { state = {} } } }
	local slaves = { enemy = {}, objective_extract_lz = {} }
	for _, u in ipairs(game.enemies) do
		slaves.enemy[u] = { state = u.slave.health }
		if u.owned then masters.enemy[u] = { state = u.master.health } end
	end
	game.masters = masters

	rawset(_G, "EntityAux", {
		get_component = function(name) return comps[name] end,
		has_component_master = function(u, c) return u.master[c] ~= nil end,
		has_component = function(u, c) return u.master[c] ~= nil end,
		has_interface = function(u, i) return i == "weapon" and u.master.firearm ~= nil end,
		state_master = function(u, c) return u.master[c] end,
		state_master_interface = function() return nil end,
		state = function(u, c) return u.slave[c] end,
		owned = function(u) return u.owned end,
		owner = function() return "peer2" end,
		queue_command_master = function(u, c, cmd, data)
			assert(u.owned, "command on a unit this peer doesn't own")
			assert(KNOWN[c] and KNOWN[c][cmd], "Unrecognized message " .. tostring(c) .. " " .. tostring(cmd))
			game.commands[#game.commands + 1] = { unit = u, component = c, command = cmd, data = data }
		end,
		queue_command_master_interface = function(u, i, cmd, data)
			game.commands[#game.commands + 1] = { unit = u, interface = i, command = cmd, data = data }
		end,
	})

	local player_go = { avatar_unit = me, research_samples = 0 }
	function player_go:owned() return true end
	function player_go:exists() return true end
	function player_go:get(k) return self[k] end
	function player_go:set(k, v) self[k] = v end
	function player_go:has(k) return self[k] ~= nil end
	local record = { player_go = player_go, pad_number = 0, extra_lives = 1 }
	game.record = record
	local mission_manager = { get_objectives = function()
		return { { name = "objective_a", state = "pending", position = { { x = 9, y = 9, z = 0 } } },
			{ name = "mission_objective_extract", state = "pending", position = { { x = 7, y = 7, z = 0 } } } }
	end, set_mission_completed = function() game.completed = true end, set_extraction_done = function() game.extraction_done = true end }
	local state = {
		players = { record }, mission_manager = mission_manager, mission_seed = 12345,
		respawn_position = { x = 2, y = 2, z = 0 },
		entity_manager = { get_master_entities = function(_, n) return masters[n] or {} end, get_slave_entities = function(_, n) return slaves[n] or {} end },
		network_router = { transmit_to = function(_, ...) game.rpc[#game.rpc + 1] = { ... } end },
		encounter_manager = {
			spawn_enemy = function(_, path) game.spawned[#game.spawned + 1] = path end,
			spawn_group = function(_, _, g) game.spawned[#game.spawned + 1] = g.units[1].amount end,
			set_disabled = function(_, v) game.encounters_off = v end,
			start_encounter = function() game.alarm = true end,
		},
		patrol_manager = { set_disabled = function(_, v) game.patrols_off = v end, add_patrol_on_spawner = function() game.patrol = true end },
		entity_spawner = { spawn_entity = function(_, p) game.spawned[#game.spawned + 1] = p end, despawn_entity = function() end },
		component_manager = { component_name_to_index = { navmesh_mover = 1, enemy = 2 }, active_components = { 1, 2 },
			pause_component = function(_, n) game.paused_component = n end, resume_component = function() end },
		explosion_manager = { do_explosion = function() game.boom = true end },
		viewport = { set_shading_environment_variable = function(_, n) game.shading = n end, remove_shading_environment_variable = function() end,
			set_shading_environment_settings = function() end, get_camera = function() return "camera" end,
			screen_to_world = function() return rawget(_G, "Vector3")(1, 1, -1) end },
		world_proxy = { get_physics_world = function() return "physics" end },
		hud = {},
		generated_level = { get_closest_position_on_level = function() return rawget(_G, "Vector3")(0, 0, 0) end },
		set_extra_lives = function(_, _, n) game.lives = n end,
		do_abort_mission = function() game.aborted = true end,
		spawn_research_samples_on_all_markers = function() game.samples = true end,
		get_active_players = function() return { 1 } end,
		state_machine = { change_state = function(_, name, params) game.changed = { name, params } end },
	}
	game.state = state
	ui.state_object = state
	rawget(_G, "Boot").package_manager = { is_package_online = function(_, name) return name == "resource_packages/race_bugs" end }
	rawset(_G, "DifficultySettings", { get_lookup_mission_params = function() return { difficulty = 5, enemy = "bugs" } end,
		modulate_seed = function(...) game.seed_parts = { ... } return 777 end })

	return e, game, ui
end

G.vector = {
	__add = function(a, b) return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, G.vector) end,
	__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, G.vector) end,
	__mul = function(a, n) return setmetatable({ x = a.x * n, y = a.y * n, z = a.z * n }, G.vector) end,
}

function G.command(game, component, command)
	for _, c in ipairs(game.commands) do
		if c.component == component and c.command == command then return c end
	end
	return nil
end

return G
