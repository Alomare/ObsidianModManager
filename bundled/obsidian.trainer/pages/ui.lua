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
		get = function() return effects.is_on(id) end,
		set = function(on) effects.set(id, on) end,
		help = U.help(key),
	})
end

-- A number that is an effect: the off value switches the effect off.
function U.effect_number(page, key, id, opts)
	local off = opts.off
	return page:number(U.t(key), {
		min = opts.min, max = opts.max, step = opts.step, format = opts.format, help = U.help(key),
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
		choices = choices, help = U.help(key),
		get = function() return effects.get(id) end,
		set = function(v) effects.set(id, v) end,
	})
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
