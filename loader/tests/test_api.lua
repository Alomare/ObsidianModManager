-- Obsidian API against a fake game that fails the way the real one does.
local E = require "fake_engine"
local G = require "fake_game"
local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local function start(opts)
	local e, game, ui = G.start({ "obsidian.api" }, opts)
	e:core().current = e:core().mods_by_id["obsidian.api"]
	return rawget(_G, "obsidian").import("obsidian.api"), game, e, ui
end

local function no_tampering(game)
	E.eq(#game.tampered, 0, "protected values written directly: " .. table.concat(game.tampered, ","))
end

test("every_module_loads_and_the_api_is_exported", function()
	local api = start()
	for _, name in ipairs({ "game", "effects", "edits", "console", "catalog", "world", "player", "gear", "stratagems", "enemies", "mission", "progress" }) do
		E.eq(type(api[name]), "table", name)
	end
end)

test("local_player_is_found_by_ownership_not_position", function()
	local api, game = start()
	E.eq(api.game.my_unit(), game.me)
	E.eq(api.game.is_host(), true)
end)

test("a_command_outside_the_known_list_is_refused_before_the_game_can_assert", function()
	local api, game = start()
	E.eq(api.game.command(game.me, "health", "not_a_command"), false)
	E.eq(api.game.command(game.me, "nonsense", "reset"), false)
	E.eq(#game.commands, 0)
end)

test("a_command_on_a_unit_without_the_component_is_refused", function()
	local api, game = start()
	E.eq(api.game.command(game.weapon, "health", "reset"), false)
end)

test("god_mode_uses_the_games_flags_and_comes_back_after_a_respawn", function()
	local api, game, e = start()
	api.effects.set("god", true)
	E.eq(game.components.health.player_invincibility, true)
	E.eq(game.components.status.status_immune, true)
	E.eq(G.command(game, "health", "set_invincible").data, true)
	game.commands = {}
	game.state.players[1].player_go.avatar_unit = game.enemies[1]
	game.enemies[1].master.health = game.enemies[1].master.health
	e:frames(1)
	game.state.players[1].player_go.avatar_unit = game.me
	e:frames(1)
	E.eq(G.command(game, "health", "set_invincible").data, true, "applied to the new avatar")
	api.effects.set("god", false)
	E.eq(game.components.health.player_invincibility, false)
	no_tampering(game)
end)

test("god_mode_gets_a_downed_player_up", function()
	local api, game, e = start()
	api.effects.set("god", true)
	game.commands = {}
	game.me.slave.health.is_downed = true
	e:frames(1)
	E.eq(G.command(game, "health", "reset") ~= nil, true)
end)

test("no_status_and_god_share_a_flag_without_clearing_each_other", function()
	local api, game = start()
	api.effects.set("god", true)
	api.effects.set("no_status", true)
	api.effects.set("god", false)
	E.eq(game.components.status.status_immune, true, "no_status still on")
	api.effects.set("no_status", false)
	E.eq(game.components.status.status_immune, false)
end)

test("a_session_that_stops_being_cleared_takes_every_change_away_and_gives_it_back", function()
	local lobby = { my_id = "me", members = { "me" }, data = {} }
	local api, game, e = start({ lobby = lobby })
	api.effects.set("infinite_ammo", true)
	E.eq(api.edits.set_unit("equipment/rifle", "weapon_info.power", 500), true)
	e:frames(31)
	lobby.members = { "me", "stranger" }
	e:frames(31)
	E.eq(game.components.firearm.infinite_ammo, false, "effect off")
	E.eq(game.rifle.weapon_info.power, 75, "edit undone")
	local ok, why = api.edits.set_unit("equipment/rifle", "weapon_info.power", 900)
	E.eq(ok, false, "nothing new while not cleared")
	E.eq(why, "not_cleared")
	E.eq(api.console.run("anything"), false)
	lobby.members = { "me" }
	e:frames(31)
	e:frames(2)
	E.eq(game.components.firearm.infinite_ammo, true, "effect back")
	E.eq(game.rifle.weapon_info.power, 500, "edit back")
end)

test("an_edit_reaches_upgraded_weapons_and_undoes_exactly", function()
	local api, game = start()
	local base, upgraded = game.rifle.weapon_info, game.rifle_upgraded.weapon_info
	E.eq(api.edits.set_unit("equipment/rifle", "weapon_info.power", 200), true)
	E.eq(base.power, 200)
	E.eq(upgraded.power, 200, "the upgrade's own clone")
	E.eq(upgraded.magazine_capacity, 45, "what the upgrade sets stays")
	E.eq(game.rifle.weapon_info, base, "same table: live entities hold it")
	E.eq(game.rifle_upgraded.weapon_info, upgraded)
	E.eq(api.edits.count(), 1)
	api.edits.revert_all()
	E.eq(base.power, 75)
	E.eq(upgraded.power, 75)
	E.eq(api.edits.count(), 0)
end)

test("an_edit_is_recorded_with_the_mod_that_made_it", function()
	local api = start()
	api.edits.set_unit("equipment/rifle", "weapon_info.power", 200, { target = "Rifle" })
	local list = api.edits.list()
	E.eq(list[1].owner, "obsidian.api")
	E.eq(list[1].target, "Rifle")
end)

test("changing_a_field_twice_keeps_one_record_and_the_first_original", function()
	local api, game = start()
	api.edits.set_unit("equipment/rifle", "weapon_info.power", 200)
	api.edits.set_unit("equipment/rifle", "weapon_info.power", 300)
	E.eq(api.edits.count(), 1)
	api.edits.revert_all()
	E.eq(game.rifle.weapon_info.power, 75)
end)

test("reverting_one_edit_leaves_the_others", function()
	local api, game = start()
	api.edits.set_unit("equipment/rifle", "weapon_info.power", 200)
	api.edits.set_unit("equipment/rifle", "weapon_info.firerate", 900)
	api.edits.revert_where("equipment/rifle", "weapon_info.power")
	E.eq(game.rifle.weapon_info.power, 75)
	E.eq(game.rifle.weapon_info.firerate, 900)
end)

test("edits_are_checked", function()
	local api = start()
	local set = function(...) return select(2, api.edits.set_unit("equipment/rifle", ...)) end
	E.eq(set("weapon_info.power", "strong"), "bad_type")
	E.eq(set("weapon_info.power", 0 / 0), "bad_value")
	E.eq(set("weapon_info.power", 1 / 0), "bad_value")
	E.eq(set("weapon_info.power", 99999, { max = 20000 }), "out_of_range")
	E.eq(set("weapon_info.nothing", 1), "no_field")
	E.eq(set("missing.table.field", 1), "no_field")
	E.eq(api.edits.count(), 0)
end)

test("protected_keys_cant_be_edited_whatever_table_they_are_in", function()
	local api = start()
	for _, key in ipairs({ "hitpoints_real", "rounds", "num_mags", "cooldown_timer", "uses_left", "num_grenades", "defend_timer", "extra_lives" }) do
		local t = { [key] = 1 }
		local ok, why = api.edits.set_table("t", t, key, 2)
		E.eq(ok, false, key)
		E.eq(why, "protected", key)
		E.eq(t[key], 1, key)
	end
end)

test("paid_content_switches_cant_be_edited", function()
	local api = start()
	local dlc = rawget(_G, "DlcSettings")
	dlc.unlock_all = false
	local ok, why = api.edits.set_table("t", dlc, "unlock_all", true)
	E.eq(ok, false)
	E.eq(why, "protected")
	local progression = rawget(_G, "ProgressionSettings")
	progression.unlock_all = false
	E.eq(api.edits.set_table("t", progression, "unlock_all", true), false)
end)

test("the_console_collects_what_the_game_registers_and_refuses_what_it_must", function()
	local api, game = start()
	local debug_table = { console = "the dummy" }
	rawset(_G, "Debug", debug_table)
	rawget(_G, "Application").build = function() return "release" end
	api.console.installed = false
	E.eq(api.console.install(), true)
	debug_table.console:register_plugin("state_game", {
		time_scale = function(args) rawset(_G, "SCALE", args[2]) return { error = false, message = "ok" } end,
		push_planet = function() rawset(_G, "PUSHED", true) end,
		boom = function() error("broken") end,
	})
	E.eq(api.console.run("time_scale 2"), true)
	E.eq(rawget(_G, "SCALE"), "2")
	local ok, why = api.console.run("push_planet 0 1")
	E.eq(ok, false)
	E.eq(why, "denied")
	E.eq(rawget(_G, "PUSHED"), nil, "a command that reaches the backend never runs")
	E.eq(api.console.run("no_such_command"), false)
	E.eq(api.console.run("boom"), false, "a failing command is an answer, not a crash")
	local names = table.concat(api.console.commands(), " ")
	E.has(names, "time_scale")
	E.lacks(names, "push_planet")
	debug_table.console:clear()
	E.eq(#api.console.commands(), 0, "a new state starts clean")
	debug_table.console:do_multiple_commands_string("x,y")
	E.eq(debug_table.console:no_such_method(), nil, "the rest of the console stays a dummy")
end)

test("the_console_leaves_a_real_debug_module_alone", function()
	local api = start()
	local debug_table = { console = "real" }
	rawset(_G, "Debug", debug_table)
	rawget(_G, "Application").build = function() return "dev" end
	api.console.installed = false
	api.console.install()
	E.eq(debug_table.console, "real")
end)

test("every_command_that_reaches_the_backend_or_wipes_a_save_is_denied", function()
	local api = start()
	for _, name in ipairs({ "push_planet", "push_defend_event", "push_attack_event", "push_bogus_statistics", "clear_save_and_tus",
		"clear_achievemenets", "unlock_all", "unlock_dlc", "season_end", "upgrade_all", "console_command" }) do
		E.eq(api.console.denied(name), true, name)
	end
end)

test("paid_items_a_player_doesnt_own_are_left_out_of_every_list", function()
	local api = start()
	for _, item in ipairs(api.catalog.primaries()) do E.eq(item.name ~= "weapon_dlc", true) end
	for _, item in ipairs(api.catalog.stratagems()) do E.eq(item.name ~= "stratagem_dlc", true) end
	E.eq(api.catalog.stratagem("stratagem_dlc"), nil)
	for _, item in ipairs(api.catalog.cosmetics("helmet")) do E.eq(item.name ~= "cus_helmet_dlc", true) end
end)

test("support_weapons_are_found_through_their_crate", function()
	local api = start()
	local list = api.catalog.support_weapons()
	E.eq(#list, 1)
	E.eq(list[1].unit_path, "equipment/mg")
end)

test("a_display_name_falls_back_to_something_readable", function()
	local api = start()
	E.eq(api.catalog.text("weapon_rifle"), "Rifle")
	E.eq(api.catalog.text("weapon_pulse_laser"), "Pulse laser", "a missing key")
end)

test("names_the_font_cant_draw_fall_back_too", function()
	local api = start()
	rawget(_G, "LocalizationManager").string = function() return "\208\159\209\131\208\187\209\143" end
	E.eq(api.catalog.text("weapon_rifle"), "Rifle", "cyrillic isn't in the font")
end)

test("refill_treats_beam_weapons_as_heat", function()
	local api, game = start()
	E.eq(api.gear.refill(), true)
	E.eq(game.commands[1].command, "set_ammo")
	E.eq(game.commands[1].data.num_mags, 1000000)
	no_tampering(game)
end)

test("instant_reload_goes_through_the_games_setter", function()
	local api, game, e = start()
	api.effects.set("instant_reload", true)
	e:frames(1)
	E.eq(game.weapon.master.firearm.reload_time, 0.01)
	E.eq(game.protected[1], "reload_time")
	no_tampering(game)
end)

test("stratagem_uses_are_restored_through_the_games_setter", function()
	local api, game = start()
	E.eq(api.stratagems.refill_uses(), true)
	E.eq(game.me.master.inventory.stratagems[1].uses_left, 4)
	no_tampering(game)
end)

test("cooldowns_are_reset_by_command_never_by_a_write", function()
	local api, game = start()
	E.eq(api.stratagems.reset_cooldowns(), true)
	E.eq(G.command(game, "inventory", "set_stratagem_info").data.cooldown_timer, 0)
	E.eq(G.command(game, "inventory", "broadcast_stratagem_cooldown") ~= nil, true)
	E.eq(game.me.master.inventory.stratagems[1].cooldown_timer, 30)
	no_tampering(game)
end)

test("any_arrow_calls_the_chosen_stratagem_only_when_on", function()
	local api = start()
	local find = rawget(_G, "LoadoutSettings").find_stratagem
	rawget(_G, "require")("lua/network/network_global")
	E.eq(api.stratagems.find(find, { "up" }), "from the arrows", "off")
	api.stratagems.select(2)
	api.effects.set("any_arrow", true)
	E.eq(api.stratagems.find(find, { "up" }), 2)
	E.eq(api.stratagems.find(find, {}), "from the arrows", "no arrow yet")
end)

test("a_stratagem_drops_with_no_flare_except_reinforce", function()
	local api, game = start()
	E.eq(api.stratagems.drop("stratagem_resupply", api.world.cursor()), true)
	E.eq(game.pods ~= nil, true)
	local ok, why = api.stratagems.drop("stratagem_reinforce", api.world.cursor())
	E.eq(ok, false)
	E.eq(why, "needs_flare")
	local ok2, why2 = api.stratagems.drop("stratagem_dlc", api.world.cursor())
	E.eq(ok2, false, "paid content")
	E.eq(why2, "not_available")
end)

test("lives_change_only_through_the_games_setter", function()
	local api, game = start()
	api.player.set_lives(5)
	E.eq(game.lives, 5)
	E.eq(game.record.extra_lives, 1, "the value itself is the game's to write")
	no_tampering(game)
end)

test("respawn_needs_a_dead_player", function()
	local api, game = start()
	local ok, why = api.player.respawn()
	E.eq(ok, false)
	E.eq(why, "alive")
	game.me.slave.health.is_dead = true
	E.eq(api.player.respawn(), true)
	E.eq(game.record.spawn_timer, 0.01, "never zero")
end)

test("helping_a_teammate_goes_to_its_owner", function()
	local api, game = start()
	local other = game.enemies[2]
	local go = { avatar_unit = other }
	function go:owned() return false end
	function go:exists() return true end
	function go:get(k) return self[k] end
	function go:has(k) return self[k] ~= nil end
	game.state.players[2] = { player_go = go, pad_number = 1 }
	E.eq(api.player.heal_everyone(), true)
	E.eq(game.rpc[1][2], "rpc_heal_request")
	E.eq(G.command(game, "health", "reset").unit, game.me, "this player is healed by command")
end)

test("teleport_finds_the_objective_and_the_extraction", function()
	local api, game = start()
	E.eq(api.player.teleport_objective(), true)
	E.eq(G.command(game, "mover", "position_teleport").data.x, 9)
	game.commands = {}
	E.eq(api.player.teleport_extraction(), true)
	E.eq(G.command(game, "mover", "position_teleport").data.x, 7)
end)

test("teleport_refuses_in_a_seat", function()
	local api, game = start()
	game.me.master.mover = nil
	local ok, why = api.player.teleport_cursor()
	E.eq(ok, false)
	E.eq(why, "seated")
end)

test("an_enemy_whose_package_isnt_loaded_never_spawns", function()
	local api, game = start()
	E.eq(api.enemies.spawn("bug_scout", 1), true, "bugs are loaded")
	E.eq(game.spawned[1], "characters/bug_scout/bug_scout")
	local ok, why = api.enemies.spawn("cyborg_soldier", 1)
	E.eq(ok, false)
	E.eq(why, "not_loaded")
	E.eq(#game.spawned, 1)
end)

test("large_spawns_go_in_batches_the_spawner_can_place", function()
	local api, game = start()
	E.eq(api.enemies.spawn("bug_scout", 23), true)
	E.eq(table.concat(game.spawned, ","), "10,10,3")
end)

test("groups_are_for_the_host", function()
	local api = start({ host = false })
	local ok, why = api.enemies.spawn("bug_scout", 5)
	E.eq(ok, false)
	E.eq(why, "host_only")
	E.eq(api.enemies.spawn("bug_scout", 1), true, "a single spawn is a request to the host")
end)

test("a_kill_goes_to_the_owner_and_credits_the_player", function()
	local api, game = start()
	E.eq(api.enemies.kill_all(), true)
	local kill = G.command(game, "health", "set_hitpoints")
	E.eq(kill.data.new_hitpoints, -10, "the unit's own constitution")
	E.eq(kill.data.owner_unit, game.me)
	E.eq(game.rpc[1][2], "rpc_set_hitpoints_request", "the other peer's enemy")
end)

test("no_spawns_holds_and_lets_go", function()
	local api, game, e = start()
	api.effects.set("no_spawns", true)
	E.eq(game.encounters_off, true)
	E.eq(game.patrols_off, true)
	game.encounters_off = false
	for _ = 1, 70 do e:frames(1) end
	E.eq(game.encounters_off, true, "held against the game turning it back on")
	api.effects.set("no_spawns", false)
	E.eq(game.encounters_off, false)
end)

test("blind_enemies_get_their_settings_back", function()
	local api = start()
	local scout = rawget(_G, "LuaSettingsManager"):get_settings_by_settings_path("characters/bug_scout/bug_scout")
	local threat = scout.enemy_info.threat_calculation
	api.effects.set("blind", true)
	E.eq(scout.enemy_info.threat_calculation(), -2)
	E.eq(scout.enemy_info.aggro_range, 1, "never 0: it is a divisor")
	api.effects.set("blind", false)
	E.eq(scout.enemy_info.threat_calculation, threat)
	E.eq(scout.enemy_info.aggro_range, 80)
end)

test("one_failing_objective_doesnt_stop_the_others", function()
	local api, game = start()
	E.eq(api.mission.finish_objectives(), true)
	E.eq(game.objective_runs[1], "objective_interact_object")
end)

test("objectives_and_the_end_of_a_mission_are_the_hosts", function()
	local api, game = start({ host = false })
	for _, fn in ipairs({ "finish_objectives", "win", "abort", "spawn_samples" }) do
		local ok, why = api.mission[fn]()
		E.eq(ok, false, fn)
		E.eq(why, "host_only", fn)
	end
	E.eq(game.completed, nil)
end)

test("winning_marks_the_player_extracted_first", function()
	local api, game = start()
	E.eq(api.mission.win(), true)
	E.eq(game.completed, true)
	E.eq(game.extraction_done, true)
	E.eq(game.record.player_go.has_extracted, true)
end)

test("practice_starts_only_from_the_ship_and_pays_nothing", function()
	local api, game, e, ui = start()
	local ok, why = api.mission.practice({ time = 1, environment = 1, enemy = 1, kind = 1, difficulty = 5 })
	E.eq(ok, false)
	E.eq(why, "not_on_ship")
	ui.state = "menu"
	rawset(math, "create_weak_unique_identifier", function() return "id" end)
	E.eq(api.mission.practice({ time = 2, environment = 3, enemy = 2, kind = 1, difficulty = 7 }), true)
	E.eq(game.changed[2].is_training, true)
	E.eq(game.changed[2].mission_seed, 777)
	E.eq(game.seed_parts[1], 1, "time, zero based")
	E.eq(game.seed_parts[3], 2, "environment")
	E.eq(game.seed_parts[7], 7, "difficulty")
end)

test("there_is_no_way_to_change_xp", function()
	local api, game = start()
	for name in pairs(api.progress) do E.lacks(string.lower(name), "xp", "progress." .. name) end
	api.progress.rank()
	E.eq(game.save.user.player_xp, 1000)
end)

test("unlocking_items_merges_and_skips_paid_content", function()
	local api, game, e, ui = start()
	ui.state = "menu"
	game.state.active_screens = {}
	E.eq(api.progress.unlock_items(), true)
	local all = " " .. table.concat(game.save.user.item_unlocks, " ") .. " "
	E.has(all, " owned_item ", "kept what was there")
	E.has(all, " reward_item ")
	E.has(all, " rank_item ")
	E.has(all, " cus_helmet_a ")
	E.lacks(all, "weapon_dlc")
	E.lacks(all, "cus_helmet_dlc")
	E.lacks(all, " boost ", "a repeatable reward, not an item")
	E.lacks(all, "cus_cape_tutorial")
	E.eq(game.save.user.player_xp, 1000, "XP untouched")
	E.eq(game.saved > 0, true, "saved")
end)

test("save_edits_wait_for_the_ships_screens_to_close", function()
	local api, game, e, ui = start()
	ui.state = "menu"
	game.state.active_screens = { { name = "menu_screen_armory" } }
	local ok, why = api.progress.set_samples(100)
	E.eq(ok, false)
	E.eq(why, "close_screen")
	E.eq(game.save.user.research_samples, 50)
	local ok2, why2 = api.progress.upgrade_all()
	E.eq(ok2, false)
	E.eq(why2, "close_screen")
end)

test("samples_stop_at_the_games_cap", function()
	local api, game, e, ui = start()
	ui.state = "menu"
	game.state.active_screens = {}
	api.progress.set_samples(999999)
	E.eq(game.save.user.research_samples, 3168)
end)

test("steam_achievements_are_held_back", function()
	local api, game, e = start()
	e.opts.modules["x"] = true
	rawget(_G, "require")("x")
	rawget(_G, "UserManager").unlock_trophy(rawget(_G, "UserManager"), "trophy_gold_all_upgrades")
	E.eq(game.trophy, nil)
end)

test("a_shake_is_dropped_only_when_asked", function()
	local api, game, e = start()
	e.opts.modules["x"] = true
	rawget(_G, "require")("x")
	rawget(_G, "CameraManager").add_shake(rawget(_G, "CameraManager"))
	E.eq(game.shakes, 1)
	api.effects.set("no_camera_shake", true)
	rawget(_G, "CameraManager").add_shake(rawget(_G, "CameraManager"))
	E.eq(game.shakes, 1)
end)

return T
