-- When a session is cleared for session mods (spec 6.2), and the lobby handshake (spec 6.3, layer 2).
-- Every Obsidian player publishes lobby member data "obsidian" = "1;<mod-set hash>;<consent 0|1>".
local B = require("obsidian/loader/builtins")
local log = require("obsidian/loader/log")

local EVERY = 30
local FORFEIT_KEY = "obsidian_forfeit"

-- What a mission can add to a player's save.
local PROGRESS = { "player_xp", "research_samples", "item_unlocks", "new_unlocks", "item_upgrades", "boss_influence", "lifetime_stats", "trophy_unlock_progress", "seen_enemies" }
local HELD = {}
for _, key in B.ipairs(PROGRESS) do HELD[key] = true end

local M = { state = true, members = {}, listeners = {}, published = nil, published_lobby = nil, warned = nil, forfeited = false, kept = nil, restoring = false, holders = {}, peer_holds = false, tip_shown = false }

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

local function in_mission()
	local boot = B.rawget(B.G, "Boot")
	local machine = B.type(boot) == "table" and boot.state_machine
	if not machine then return false end
	local name = machine:get_current_state_name()
	return name == "game" or name == "mission_end"
end

-- A mod that holds every mission does so while it runs.
local function holding()
	if not M.state then return false end
	for _, mod in B.ipairs(M.holders) do
		if not mod.off then return true end
	end
	return false
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
		M.members, M.peer_holds = {}, false
		set_cleared(true)
		return
	end
	local value = "1;" .. B.tostring(deploy.modset) .. ";" .. (own_consent and "1" or "0")
	if M.published ~= value or M.published_lobby ~= l then
		l:set_member_data("obsidian", value)
		log.line("session: published member data " .. value)
		M.published, M.published_lobby = value, l
	end
	local forfeit = (M.forfeited or holding()) and "1" or "0"
	if M.published_forfeit ~= forfeit or M.forfeit_lobby ~= l then
		l:set_member_data(FORFEIT_KEY, forfeit)
		M.published_forfeit, M.forfeit_lobby = forfeit, l
	end
	local me, list, signature, peer_holds = l.my_id, {}, {}, false
	-- My session mods run when every other player runs the same set or allows other players' mods.
	-- My own consent is about their mods in my game, so it plays no part here.
	local allowed = true
	for _, peer in B.ipairs(l:members() or {}) do
		if peer ~= me then
			local d = M.parse(l:member_data(peer, "obsidian"))
			B.insert(list, { peer = peer, obsidian = d ~= nil, modset = d and d.modset, consent = d and d.consent or false })
			B.insert(signature, B.tostring(peer))
			if not (d and (d.modset == deploy.modset or d.consent)) then allowed = false end
			-- What one player's mod does to a mission, it does to everyone in it.
			if l:member_data(peer, FORFEIT_KEY) == "1" then peer_holds = true end
		end
	end
	M.members, M.peer_holds = list, peer_holds
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
		if M.mission_held() and in_mission() then M.forfeit_progress() end
	end
end

function M.cleared()
	return M.state
end

function M.on_session(fn)
	B.insert(M.listeners, { state = M.core.current, fn = fn })
end

local function copy(value)
	if B.type(value) ~= "table" then return value end
	local out = {}
	for k, v in B.pairs(value) do out[k] = copy(v) end
	return out
end

-- The save hands out its live tables and the game fills them in place, so holding back the writes
-- isn't enough: these values go back before anything reaches the disk.
local function keep()
	local save, users = B.rawget(B.G, "SaveManager"), B.rawget(B.G, "UserManager")
	if B.type(save) ~= "table" or B.type(users) ~= "table" then return end
	local user = users:get_user_id()
	local values = {}
	for _, key in B.ipairs(PROGRESS) do values[key] = copy(save:user_get(key, user)) end
	M.kept = { save = save, user = user, values = values }
end

-- The mission under way adds nothing to the save, until it's over. For a mod that changes how a mission
-- plays out: what it earns would stay in the save, and a later clean mission would upload the total.
function M.forfeit_progress()
	if M.forfeited then return end
	M.forfeited = true
	local ok, err = B.pcall(keep)
	if not ok then log.limited("session keep", "session: could not keep the save's values: " .. B.tostring(err)) end
	log.line("session: this mission adds nothing to the save")
	if not M.tip_shown then M.core.notice("progress_forfeited") end
end

-- Every mission adds nothing to the save, for as long as the calling mod runs.
function M.hold_progress()
	B.insert(M.holders, M.core.current)
end

-- True when a mission starting now won't add to the save.
function M.mission_held()
	return holding() or M.peer_holds
end

function M.holds(key)
	return M.forfeited and not M.restoring and HELD[key] == true
end

function M.restore_progress()
	local kept = M.kept
	if not kept then return end
	M.restoring = true
	local ok, err = B.pcall(function()
		for _, key in B.ipairs(PROGRESS) do kept.save:user_set(key, copy(kept.values[key]), kept.user) end
	end)
	M.restoring = false
	if not ok then log.limited("session restore", "session: could not restore the save's values: " .. B.tostring(err)) end
end

function M.end_forfeit()
	M.tip_shown = false
	if not M.forfeited then return end
	M.restore_progress()
	M.forfeited, M.kept = false, nil
end

-- A view of a mod's table for other mods to call. Every function not named in `free` answers
-- false and a reason when the calling mod's scope or the lobby doesn't allow it, so a function
-- nobody sorted is refused rather than let through. The mod's own code keeps using the real table,
-- because undoing a change has to work after the session stops being cleared.
function M.guard(t, free)
	local state = M.core.current
	if not state then B.error("obsidian.session.guard needs a running mod", 2) end
	local open, wrapped = {}, {}
	for _, name in B.ipairs(free or {}) do
		open[name] = true
		if t[name] == nil then log.line("guard: " .. state.id .. " lists " .. B.tostring(name) .. ", which doesn't exist") end
	end
	return B.setmetatable({}, {
		__index = function(_, k)
			local v = t[k]
			if B.type(v) ~= "function" or open[k] then return v end
			if not wrapped[v] then
				wrapped[v] = function(...)
					if state.mod.scope == "client" then return false, "needs_session" end
					if not M.state then return false, "not_cleared" end
					return v(...)
				end
			end
			return wrapped[v]
		end,
		__newindex = t,
	})
end

function M.api()
	return {
		guard = M.guard,
		cleared = M.cleared,
		forfeit_progress = M.forfeit_progress,
		hold_progress = M.hold_progress,
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
