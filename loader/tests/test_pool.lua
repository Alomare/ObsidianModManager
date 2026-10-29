local E = require "fake_engine"
local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local function game_hash()
	local _, hash = string.match(rawget(_G, "BUILD_REVISION_INFORMATION"), "parent: ([0-9]+):([0-9abcdef]+)")
	return hash
end

test("no_session_and_no_consent_keeps_vanilla_hash", function()
	E.new()
	require("kepler/loader/pool").apply(E.deploy({ has_session = false }), false)
	E.eq(game_hash(), "3bd83d77c8ae")
end)

test("session_without_consent_uses_identical_tag", function()
	E.new()
	require("kepler/loader/pool").apply(E.deploy({ has_session = true }), false)
	E.eq(game_hash(), "3bd83d77c8aeaaaaaaaaaaaa")
end)

test("consent_uses_consent_tag_even_without_session_mods", function()
	E.new()
	require("kepler/loader/pool").apply(E.deploy({ has_session = false }), true)
	E.eq(game_hash(), "3bd83d77c8aebbbbbbbbbbbb")
end)

test("rewritten_hash_matches_build_info_pattern", function()
	E.new()
	require("kepler/loader/pool").apply(E.deploy({ has_session = true }), true)
	local rev = rawget(_G, "BUILD_REVISION_INFORMATION")
	E.eq(string.match(rev, "parent: ([0-9]+):"), "32148")
	E.eq(game_hash(), "3bd83d77c8aebbbbbbbbbbbb")
	E.has(rev, " tip\n [code] ok", "rest of the revision string")
end)

test("bad_tag_leaves_the_hash_vanilla", function()
	E.new()
	require("kepler/loader/pool").apply(E.deploy({ has_session = true, hashes = { identical = "XYZ", consent = "" } }), false)
	E.eq(game_hash(), "3bd83d77c8ae")
end)

test("boot_applies_the_pool_before_mods_start", function()
	local e = E.new({
		deploy = E.deploy({ has_session = true, mods = { E.mod("a", { scope = "session" }) } }),
		mods = { ["kepler/mods/a/main"] = "SEEN = BUILD_REVISION_INFORMATION" },
	})
	e:boot()
	E.has(rawget(_G, "SEEN"), "3bd83d77c8aeaaaaaaaaaaaa")
	E.has(e:log(), "pool: identical aaaaaaaaaaaa")
end)

return T
