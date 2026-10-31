-- What every trainer page shares: texts, and rows bound to the runtime.
local api = obsidian.import("obsidian.api")
local effects = api.effects

local U = { api = api }

function U.t(key, ...)
	return obsidian.text(key, ...)
end

-- Text for an action that couldn't run. The runtime answers with a short reason, or the game's own
-- message when it has one.
function U.why(reason)
	local key = "why_" .. tostring(reason)
	local text = obsidian.text(key)
	if text ~= key then return text end
	return tostring(reason)
end

-- A row action: runs fn(...) and returns the toast.
function U.act(fn, ...)
	local args, n = { ... }, select("#", ...)
	return function()
		local ok, why = fn(unpack(args, 1, n))
		if ok then return U.t("done") end
		return U.why(why)
	end
end

-- The toast for what the runtime answered.
function U.result(ok, why)
	if ok then return U.t("done") end
	return U.why(why)
end

function U.action(page, key, fn, ...)
	return page:action(U.t(key), U.act(fn, ...), { help = U.help(key) })
end

-- The help text of a key, when it has one.
function U.help(key)
	local help = obsidian.text(key .. "_help")
	if help ~= key .. "_help" then return help end
	return nil
end

function U.effect(page, key, id)
	return page:toggle(U.t(key), {
		default = false,
		get = function() return effects.is_on(id) end,
		set = function(on) effects.set(id, on) end,
		help = U.help(key),
	})
end

-- A number that is an effect: the off value switches the effect off.
function U.effect_number(page, key, id, opts)
	local off = opts.off
	return page:number(U.t(key), {
		min = opts.min, max = opts.max, step = opts.step, format = opts.format, help = U.help(key), enabled = opts.enabled, default = off,
		get = function()
			local v = effects.get(id)
			if v == false then return off end
			return v
		end,
		set = function(v)
			if v == off then effects.set(id, false) else effects.set(id, v) end
		end,
	})
end

function U.effect_choice(page, key, id, choices)
	return page:choice(U.t(key), {
		choices = choices, help = U.help(key), default = false,
		get = function() return effects.get(id) end,
		set = function(v) effects.set(id, v) end,
	})
end

U.GRENADES = {
	{ id = "equipment/equipment_grenade_01", key = "grenade_frag" },
	{ id = "equipment/equipment_grenade_incendiary", key = "grenade_fire" },
	{ id = "equipment/equipment_grenade_stun", key = "grenade_stun" },
	{ id = "equipment/equipment_grenade_smoke", key = "grenade_smoke" },
}

-- A page of every stratagem the player can use. run(stratagem) returns the toast.
function U.stratagem_list(run)
	return function(page)
		for _, s in ipairs(api.catalog.stratagems()) do
			page:action(api.catalog.text(s.name), function() return run(s) end)
		end
	end
end

local call_delay = 0

-- Real flares at the cursor, on the two pages that offer them.
function U.call_rows(page)
	local stratagems, world = api.stratagems, api.world
	page:number(U.t("call_delay"), { min = 0, max = 120, step = 5, default = 0, get = function() return call_delay end, set = function(v) call_delay = v end })
	page:page(U.t("call_cursor"), U.stratagem_list(function(s) return U.result(stratagems.call(s.name, world.cursor(), call_delay)) end), { help = U.help("call_cursor") })
	page:action(U.t("reinforce_cursor"), function()
		return U.result(stratagems.call("stratagem_reinforce", world.cursor(), call_delay))
	end, { help = U.help("reinforce_cursor") })
end

function U.host_only()
	if api.game.is_host() then return true end
	return false, U.t("why_host_only")
end

function U.in_mission()
	if api.game.in_mission() then return true end
	return false, U.t("why_not_in_mission")
end

return U
