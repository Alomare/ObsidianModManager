local E = require "fake_engine"
local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local OWN = string.rep("a", 64)
local OTHER = string.rep("c", 64)

local function engine(lobby, deploy_over, mods)
	local d = { has_session = true, modset = OWN, mods = {} }
	for k, v in pairs(deploy_over or {}) do d[k] = v end
	local e = E.new({ deploy = E.deploy(d), lobby = lobby, mods = mods })
	e:boot()
	e:start_frames()
	return e
end

local function cleared()
	return rawget(_G, "kepler").session.cleared()
end

test("solo_is_cleared", function()
	engine({ my_id = "me", members = { "me" }, data = {} })
	E.eq(cleared(), true)
end)

test("no_lobby_is_cleared", function()
	local e = engine(nil)
	e:frames(31)
	E.eq(cleared(), true)
end)

test("identical_hashes_are_cleared", function()
	local e = engine({ my_id = "me", members = { "me", "p2" }, data = { p2 = "1;" .. OWN .. ";0" } })
	e:frames(31)
	E.eq(cleared(), true)
end)

test("one_different_hash_is_not_cleared", function()
	local e = engine({ my_id = "me", members = { "me", "p2", "p3" }, data = { p2 = "1;" .. OWN .. ";0", p3 = "1;" .. OTHER .. ";0" } })
	e:frames(31)
	E.eq(cleared(), false)
end)

test("all_consenting_is_cleared", function()
	local e = engine({ my_id = "me", members = { "me", "p2" }, data = { p2 = "1;" .. OTHER .. ";1" } })
	e:core().consent_on = true
	e:frames(31)
	E.eq(cleared(), true)
end)

test("consent_needs_every_member", function()
	local e = engine({ my_id = "me", members = { "me", "p2" }, data = { p2 = "1;" .. OTHER .. ";1" } })
	e:frames(31)
	E.eq(cleared(), false, "own consent off")
end)

test("one_vanilla_member_is_not_cleared", function()
	local e = engine({ my_id = "me", members = { "me", "p2" }, data = {} })
	e:frames(31)
	E.eq(cleared(), false)
end)

test("malformed_member_data_is_not_cleared", function()
	for _, bad in ipairs({ "1;zz;0", "2;" .. OWN .. ";0", "", "1;" .. OWN .. ";2", "1;" .. OWN }) do
		local e = engine({ my_id = "me", members = { "me", "p2" }, data = { p2 = bad } })
		e:frames(31)
		E.eq(cleared(), false, "data " .. bad)
	end
end)

test("own_member_data_is_published", function()
	local lobby = { my_id = "me", members = { "me" }, data = {} }
	local e = engine(lobby)
	e:frames(31)
	E.eq(lobby.published.kepler, "1;" .. OWN .. ";0")
end)

local HOOK_MODS = {
	["kepler/mods/s/main"] = "kepler.hook('Target', 'run', function(original, self, x) return 'session ' .. x end)",
	["kepler/mods/c/main"] = "kepler.hook(Target, 'look', function(original, self) return 'client' end)",
}

local function hook_engine(data)
	rawset(_G, "Target", { run = function(self, x) return "vanilla " .. x end, look = function() return "vanilla" end })
	return engine({ my_id = "me", members = { "me", "p2" }, data = data },
		{ mods = { E.mod("s", { scope = "session" }), E.mod("c", { scope = "client" }) } }, HOOK_MODS)
end

test("session_hook_calls_original_when_not_cleared", function()
	local e = hook_engine({ p2 = "1;" .. OTHER .. ";0" })
	e:frames(31)
	E.has(e:log(), "started s")
	E.eq(rawget(_G, "Target"):run(1), "vanilla 1")
end)

test("session_hook_runs_when_cleared", function()
	local e = hook_engine({ p2 = "1;" .. OWN .. ";0" })
	e:frames(31)
	E.eq(rawget(_G, "Target"):run(1), "session 1")
end)

test("client_hook_always_runs", function()
	local e = hook_engine({})
	e:frames(31)
	E.eq(rawget(_G, "Target"):look(), "client")
end)

test("hook_on_undeclared_scope_is_gated", function()
	rawset(_G, "Target", { run = function() return "vanilla" end })
	local undeclared = E.mod("u")
	undeclared.scope = nil
	local e = engine({ my_id = "me", members = { "me", "p2" }, data = {} },
		{ mods = { undeclared } },
		{ ["kepler/mods/u/main"] = "kepler.hook(Target, 'run', function() return 'modded' end)" })
	e:frames(31)
	E.has(e:log(), "started u")
	E.eq(rawget(_G, "Target"):run(), "vanilla")
end)

test("hook_by_global_name_resolves_later", function()
	local e = engine(nil, { mods = { E.mod("c") } },
		{ ["kepler/mods/c/main"] = "kepler.hook('LaterClass', 'go', function() return 'hooked' end)" })
	rawset(_G, "LaterClass", { go = function() return "vanilla" end })
	e.opts.modules["lua/later"] = true
	rawget(_G, "require")("lua/later")
	E.eq(rawget(_G, "LaterClass").go(), "hooked")
end)

test("on_require_fires_after_module_loads", function()
	local e = engine(nil, { mods = { E.mod("c") } },
		{ ["kepler/mods/c/main"] = "kepler.on_require('lua/thing', function(v) rawset(_G, 'GOT', v) end)" })
	e.opts.modules["lua/thing"] = "value"
	rawget(_G, "require")("lua/thing")
	E.eq(rawget(_G, "GOT"), "value")
end)

test("on_session_fires_on_change_only", function()
	local lobby = { my_id = "me", members = { "me" }, data = {} }
	local e = engine(lobby, { mods = { E.mod("s", { scope = "session" }) } },
		{ ["kepler/mods/s/main"] = "CALLS = ''; kepler.on_session(function(on) rawset(_G, 'CALLS', CALLS .. tostring(on) .. ',') end)" })
	e:frames(31)
	lobby.members = { "me", "p2" }
	e:frames(60)
	lobby.members = { "me" }
	e:frames(30)
	E.eq(rawget(_G, "CALLS"), "false,true,")
end)

test("static_session_content_warns_once", function()
	local lobby = { my_id = "me", members = { "me", "p2" }, data = {} }
	local e = engine(lobby, { has_static_session = true })
	e:frames(90)
	local n = 0
	for _, x in ipairs(e:core().notices_shown) do
		if x.key == "session_not_cleared" then n = n + 1 end
	end
	E.eq(n, 1)
	E.has(e:log(), "notice: session_not_cleared")
end)

test("frame_hook_runs_after_the_game_update", function()
	local e = engine(nil)
	e:frames(5)
	E.eq(rawget(_G, "FRAMES"), 5)
	E.eq(e:core().frame_count, 5)
end)

return T
