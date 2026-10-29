-- obsidian.hook and obsidian.on_require, the wrapped require, and the per-frame driver.
-- Hooks of session mods call the original whenever the session isn't cleared (spec 6.4).
local B = require("obsidian/loader/builtins")
local log = require("obsidian/loader/log")

local M = { pending = {}, requires = {}, fired = {}, frame_fns = {}, frame_installed = false }

function M.setup(core, session)
	M.core, M.session = core, session
end

local function pack(...)
	return { n = B.select("#", ...), ... }
end

local function install(h)
	local target = h.target
	if B.type(target) == "string" then target = B.rawget(B.G, target) end
	if B.type(target) ~= "table" then return false end
	local original = target[h.method]
	if B.type(original) ~= "function" then return false end
	local core, session, state, fn, site = M.core, M.session, h.state, h.fn, "hook " .. B.tostring(h.method)
	-- A missing or unknown scope counts as session. The loader's own hooks are never gated.
	local gated = not h.loader and not (state and state.mod.scope == "client")
	target[h.method] = function(...)
		if (state and state.off) or (gated and not session.cleared()) then return original(...) end
		local r = pack(core.call(state, site, fn, original, ...))
		if r[1] then return B.unpack(r, 2, r.n) end
		return original(...)
	end
	return true
end

function M.hook(target, method, fn)
	local h = { state = M.core.current, target = target, method = method, fn = fn }
	if not install(h) then B.insert(M.pending, h) end
end

-- A hook owned by the loader itself (guardrails, built-in features).
function M.loader_hook(target, method, fn)
	local h = { state = nil, loader = true, target = target, method = method, fn = fn }
	if not install(h) then B.insert(M.pending, h) end
end

function M.on_require(name, fn)
	local list = M.requires[name]
	if not list then
		list = {}
		M.requires[name] = list
	end
	B.insert(list, { state = M.core.current, fn = fn })
end

local function resolve_pending()
	if #M.pending == 0 then return end
	local still = {}
	for _, h in B.ipairs(M.pending) do
		if not install(h) then B.insert(still, h) end
	end
	M.pending = still
end

-- The engine calls the global update every frame. The boot script defines update after the loader
-- runs, so the wrapper goes in at the first require that happens once update exists.
local function install_frame()
	if M.frame_installed then return end
	local update = B.rawget(B.G, "update")
	if B.type(update) ~= "function" then return end
	M.frame_installed = true
	log.line("frame hook installed")
	local fns = M.frame_fns
	B.rawset(B.G, "update", function(...)
		local r = pack(update(...))
		for i = 1, #fns do B.pcall(fns[i]) end
		return B.unpack(r, 1, r.n)
	end)
end

function M.on_frame(fn)
	B.insert(M.frame_fns, fn)
end

function M.wrap_require()
	local original = B.require
	B.rawset(B.G, "require", function(name, ...)
		local r = pack(original(name, ...))
		local list = M.requires[name]
		if list and not M.fired[name] then
			M.fired[name] = true
			for _, cb in B.ipairs(list) do M.core.call(cb.state, "on_require " .. B.tostring(name), cb.fn, r[1]) end
		end
		resolve_pending()
		install_frame()
		return B.unpack(r, 1, r.n)
	end)
end

return M
