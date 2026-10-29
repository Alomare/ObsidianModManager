-- API version 1 as mods see it: every key of obsidian, obsidian.session, obsidian.settings and
-- obsidian.capabilities with the type of each value, and the loader log lines at boot. A change
-- here is a change to the mod API, so contract.txt changes only on purpose.
local E = require "fake_engine"
local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local function keys(prefix, t, out)
	for k, v in pairs(t) do out[#out + 1] = prefix .. "." .. tostring(k) .. " " .. type(v) end
end

local function current()
	local e = E.new({
		deploy = E.deploy({ mods = { E.mod("a") } }),
		mods = { ["obsidian/mods/a/main"] = "return true" },
	})
	e:boot()
	local api = rawget(_G, "obsidian")
	local out = {}
	keys("obsidian", api, out)
	keys("obsidian.session", api.session, out)
	keys("obsidian.settings", api.settings, out)
	keys("obsidian.capabilities", e:core().capabilities, out)
	table.sort(out)
	for line in e:log():gmatch("[^\n]+") do out[#out + 1] = "log: " .. line:gsub("^%d%d:%d%d:%d%d ", "") end
	return out
end

test("api_matches_contract", function()
	local want = {}
	for line in (E.read("loader/tests/contract.txt") or ""):gmatch("[^\r\n]+") do want[#want + 1] = line end
	local got = current()
	local same = #want == #got
	for i = 1, math.max(#want, #got) do
		if want[i] ~= got[i] then same = false end
	end
	if not same then error("contract changed; the loader now gives:\n" .. table.concat(got, "\n")) end
end)

return T
