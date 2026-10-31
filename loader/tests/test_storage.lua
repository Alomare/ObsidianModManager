-- obsidian.storage: values a mod keeps between launches.
local E = require "fake_engine"
local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local function start(source, root)
	local e = E.new({
		deploy = E.deploy({ mods = { E.mod("a.b") } }),
		mods = { ["obsidian/mods/a.b/main"] = source },
	})
	e:boot()
	return e
end

test("values_keep_their_type_and_survive_a_reload", function()
	local e = start([[
		local s = obsidian.storage
		s.set("text", "line one\nwith\ttab and \\ slash")
		s.set("n", 1.5)
		s.set("yes", true)
		s.set("no", false)
		s.set("gone", 1)
		s.set("gone", nil)
	]])
	local storage = e.loaded["obsidian/loader/storage"]
	storage.loaded = {}
	local core = e:core()
	core.current = core.mods_by_id["a.b"]
	local s = rawget(_G, "obsidian").storage
	E.eq(s.get("text"), "line one\nwith\ttab and \\ slash")
	E.eq(s.get("n"), 1.5)
	E.eq(s.get("yes"), true)
	E.eq(s.get("no"), false, "false isn't the default")
	E.eq(s.get("gone"), nil)
	E.eq(s.get("missing", "fallback"), "fallback")
	E.eq(s.all().n, 1.5)
end)

test("a_crash_between_the_two_steps_of_a_write_loses_nothing", function()
	local e = start([[ obsidian.storage.set("kept", "yes") ]])
	local file = e.obsidian_dir .. "/logs/ab.store"
	E.eq(os.rename(file, file .. ".tmp"), true, "as the old file went and the new one hadn't taken its name")
	local storage = e.loaded["obsidian/loader/storage"]
	storage.loaded = {}
	local core = e:core()
	core.current = core.mods_by_id["a.b"]
	E.eq(rawget(_G, "obsidian").storage.get("kept"), "yes")
	rawget(_G, "obsidian").storage.set("kept", "again")
	E.eq(io.open(file .. ".tmp", "rb"), nil, "the next write takes its proper name")
	storage.loaded = {}
	E.eq(rawget(_G, "obsidian").storage.get("kept"), "again")
end)

test("a_bad_file_gives_no_values_rather_than_an_error", function()
	local e = start("VALUE = obsidian.storage.get('k', 'default')")
	E.eq(rawget(_G, "VALUE"), "default")
	local f = assert(io.open(e.obsidian_dir .. "/logs/ab.store", "wb"))
	f:write("garbage with no tabs\nk\tn\tnot a number\n")
	f:close()
	local storage = e.loaded["obsidian/loader/storage"]
	storage.loaded = {}
	local core = e:core()
	core.current = core.mods_by_id["a.b"]
	E.eq(rawget(_G, "obsidian").storage.get("k", "fine"), "fine")
end)

test("tables_are_refused", function()
	local e = start([[OK, ERR = pcall(obsidian.storage.set, "k", {})]])
	E.eq(rawget(_G, "OK"), false)
	E.has(rawget(_G, "ERR"), "strings, numbers and booleans")
end)

return T
