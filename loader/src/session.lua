-- When a session is cleared for session mods (spec 6.2), and the lobby handshake (spec 6.3, layer 2).
-- Every Obsidian player publishes lobby member data "obsidian" = "1;<mod-set hash>;<consent 0|1>".
local B = require("obsidian/loader/builtins")
local log = require("obsidian/loader/log")

local EVERY = 30

local M = { state = true, members = {}, listeners = {}, published = nil, published_lobby = nil, warned = nil }

function M.setup(core)
	M.core = core
end

-- Anything but exactly version 1, 64 lowercase hex digits and 0 or 1 counts as not a Obsidian player.
function M.parse(value)
	if B.type(value) ~= "string" then return nil end
	local version, hash, consent = B.match(value, "^(%d+);([0-9a-f]+);([01])$")
	if version ~= "1" or #hash ~= 64 then return nil end
	return { modset = hash, consent = consent == "1" }
end

local function lobby()
	local network = B.rawget(B.G, "NetworkGlobal")
	if B.type(network) == "table" then return network.lobby end
	return nil
end

local function set_cleared(on)
	if on == M.state then return end
	M.state = on
	log.line("session: " .. (on and "cleared" or "not cleared"))
	for _, l in B.ipairs(M.listeners) do M.core.call(l.state, "on_session", l.fn, on) end
end

function M.evaluate()
	local core, deploy = M.core, M.core.deploy
	local own_consent = core.consent()
	local l = lobby()
	if not l then
		M.members = {}
		set_cleared(true)
		return
	end
	local value = "1;" .. B.tostring(deploy.modset) .. ";" .. (own_consent and "1" or "0")
	if M.published ~= value or M.published_lobby ~= l then
		l:set_member_data("obsidian", value)
		log.line("session: published member data " .. value)
		M.published, M.published_lobby = value, l
	end
	local me, list, signature = l.my_id, {}, {}
	-- My session mods run when every other player runs the same set or allows other players' mods.
	-- My own consent is about their mods in my game, so it plays no part here.
	local allowed = true
	for _, peer in B.ipairs(l:members() or {}) do
		if peer ~= me then
			local d = M.parse(l:member_data(peer, "obsidian"))
			B.insert(list, { peer = peer, obsidian = d ~= nil, modset = d and d.modset, consent = d and d.consent or false })
			B.insert(signature, B.tostring(peer))
			if not (d and (d.modset == deploy.modset or d.consent)) then allowed = false end
		end
	end
	M.members = list
	local on = allowed
	set_cleared(on)
	-- Data overrides and legacy mods can't be switched off live, so everyone running Obsidian gets told.
	if not on and deploy.has_static_session then
		B.sort(signature)
		local key = B.concat(signature, ",")
		if M.warned ~= key then
			M.warned = key
			core.notice("session_not_cleared")
		end
	elseif on then
		M.warned = nil
	end
end

function M.tick()
	local n = M.core.frame_count
	if n % EVERY == 0 then
		local ok, err = B.pcall(M.evaluate)
		if not ok then
			log.limited("session", "session check failed: " .. B.tostring(err))
			-- Not knowing who's here can't count as cleared.
			set_cleared(false)
		end
	end
end

function M.cleared()
	return M.state
end

function M.on_session(fn)
	B.insert(M.listeners, { state = M.core.current, fn = fn })
end

function M.api()
	return {
		cleared = M.cleared,
		members = function()
			local copy = {}
			for i, m in B.ipairs(M.members) do
				copy[i] = { peer = m.peer, obsidian = m.obsidian, modset = m.modset, consent = m.consent }
			end
			return copy
		end,
	}
end

return M
