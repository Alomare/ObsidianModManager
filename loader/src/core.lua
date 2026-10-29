-- Kepler Loader core: the boot sequence, starting mods, error isolation and the `kepler` API.
local B = require("kepler/loader/builtins")
local log = require("kepler/loader/log")

local API_VERSION = 1
local MAX_ERRORS = 10
local STDLIB = { "string", "table", "math", "io", "os", "coroutine", "debug", "package", "bit", "jit" }

local M = { mods = {}, mods_by_id = {}, notices = {}, after = {}, current = nil, deploy = nil }

local capabilities = { after_startup = true, log = true }
local api = {
	version = API_VERSION,
	capabilities = B.setmetatable({}, {
		__index = capabilities,
		__newindex = function() B.error("kepler.capabilities is read-only", 2) end,
		__metatable = false,
	}),
}
M.api = api
M.capabilities = capabilities

function M.notice(key, ...)
	B.insert(M.notices, { key = key, args = { ... } })
end

local function traceback(err)
	if B.traceback then return B.traceback(B.tostring(err), 2) end
	return B.tostring(err)
end

-- Runs fn for a mod, protected. Errors are logged at most 3 times per site, and a mod that keeps
-- erroring is switched off for the rest of the session.
function M.call(state, site, fn, ...)
	if state and state.off then return false end
	local previous = M.current
	M.current = state
	local args, n = { ... }, B.select("#", ...)
	local result = { B.xpcall(function() return fn(B.unpack(args, 1, n)) end, traceback) }
	M.current = previous
	if not result[1] and state then
		state.errors = state.errors + 1
		log.limited(state.id .. "\0" .. site, "error " .. state.id .. " " .. site .. ": " .. B.tostring(result[2]))
		if state.errors >= MAX_ERRORS then
			state.off = true
			log.line("switched off " .. state.id .. " after " .. MAX_ERRORS .. " errors")
			M.notice("mod_failed", state.id)
		end
	end
	return B.unpack(result)
end

local function snapshot()
	local s = { globals = {}, stdlib = {}, loaded = {} }
	for k, v in B.pairs(B.G) do s.globals[k] = v end
	for _, lib in B.ipairs(STDLIB) do
		local t = B.rawget(B.G, lib)
		if B.type(t) == "table" then
			for k, v in B.pairs(t) do s.stdlib[lib .. "." .. B.tostring(k)] = v end
		end
	end
	local package = B.rawget(B.G, "package")
	if B.type(package) == "table" and B.type(package.loaded) == "table" then
		for k in B.pairs(package.loaded) do s.loaded[k] = true end
	end
	return s
end

local function diff(label, before, after, out)
	local added, replaced = {}, {}
	for k, v in B.pairs(after) do
		if before[k] == nil then
			B.insert(added, B.tostring(k))
		elseif not B.rawequal(before[k], v) then
			B.insert(replaced, B.tostring(k))
		end
	end
	for k in B.pairs(before) do
		if after[k] == nil then B.insert(replaced, B.tostring(k)) end
	end
	B.sort(added)
	B.sort(replaced)
	if #added > 0 then B.insert(out, label .. "+=" .. B.concat(added, ",")) end
	if #replaced > 0 then B.insert(out, label .. "~=" .. B.concat(replaced, ",")) end
end

-- One line per mod naming the globals, standard library members and modules the mod added or replaced.
local function changes(before, after)
	local out = {}
	diff("globals", before.globals, after.globals, out)
	diff("stdlib", before.stdlib, after.stdlib, out)
	diff("loaded", before.loaded, after.loaded, out)
	if #out == 0 then return "none" end
	return B.concat(out, " ")
end

function api.log(...)
	local state = M.current
	if state then log.mod(state.id, ...) else log.line("mod (unknown):", ...) end
end

function api.after_startup(fn)
	B.insert(M.after, { state = M.current, fn = fn })
end

local function start(mod)
	local state = { id = B.tostring(mod.id), mod = mod, errors = 0, off = false }
	B.insert(M.mods, state)
	M.mods_by_id[state.id] = state
	local needs = B.tonumber(mod.loader_api) or 1
	if needs > API_VERSION then
		state.off = true
		log.line("refused " .. state.id .. ": needs loader API " .. needs)
		M.notice("mod_failed", state.id)
		return
	end
	log.line("loading " .. state.id)
	local before = snapshot()
	local ok, err = M.call(state, "start", B.require, mod.entry)
	if ok then
		log.line("started " .. state.id)
	else
		state.off = true
		log.line("failed " .. state.id .. ": " .. B.tostring(err))
		M.notice("mod_failed", state.id)
	end
	log.line("changes: " .. state.id .. " " .. changes(before, snapshot()))
end

function M.boot()
	local jit = B.rawget(B.G, "jit")
	local jit_was_on = false
	if B.type(jit) == "table" then
		-- The game and every mod share one machine-code cache; LuaJIT 2.0 defaults are 512 KB and 1000 traces.
		if B.type(jit.opt) == "table" then B.pcall(jit.opt.start, "maxmcode=4096", "maxtrace=4000") end
		if jit.status then jit_was_on = (jit.status()) == true end
		-- One-time loader code leaves no traces behind.
		if jit_was_on then B.pcall(jit.off) end
	end

	local appdata = B.getenv("APPDATA")
	if appdata then log.setup(appdata .. "/Arrowhead/Helldivers/kepler/logs") end
	log.line("Kepler Loader, API " .. API_VERSION .. ", jit " .. (B.type(jit) == "table" and "available" or "missing"))

	local ok, deploy = B.pcall(B.require, "kepler/deploy")
	if not ok or B.type(deploy) ~= "table" then
		log.line("no deploy table, no mod started: " .. B.tostring(deploy))
		return
	end
	M.deploy = deploy

	local revision = B.rawget(B.G, "BUILD_REVISION_INFORMATION")
	local expected = B.tostring(deploy.revision)
	if B.type(revision) ~= "string" or B.sub(revision, 1, #expected) ~= expected then
		log.line("build unknown, no mod started (expected " .. expected .. ")")
		M.notice("build_unknown")
		if jit_was_on then B.pcall(jit.on) end
		return
	end

	B.rawset(B.G, "kepler", api)
	for _, mod in B.ipairs(deploy.mods or {}) do
		start(mod)
	end
	for _, cb in B.ipairs(M.after) do
		M.call(cb.state, "after_startup", cb.fn)
	end
	if jit_was_on then B.pcall(jit.on) end
	log.line("boot done")
end

return M
