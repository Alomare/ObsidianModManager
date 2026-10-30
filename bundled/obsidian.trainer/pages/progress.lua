-- Progress: the player's own save. XP and rank aren't here on purpose: see lib/progress.lua in
-- Obsidian API.
local U = obsidian.module("pages/ui")
local api, t = U.api, U.t
local progress = api.progress

return function(page)
	page:label(function()
		local rank, xp = progress.rank()
		if not rank then return t("no_rank") end
		return t("rank_info", api.catalog.text(rank.name or ""), tostring(xp))
	end)
	page:number(t("samples_owned"), {
		min = 0, max = progress.max_samples(), step = 10, help = U.help("samples_owned"),
		get = function() return progress.samples() end,
		set = function(v)
			local ok, why = progress.set_samples(v)
			if not ok then obsidian.toast(U.why(why)) end
		end,
	})
	U.action(page, "unlock_items", progress.unlock_items)
	U.action(page, "upgrade_all", progress.upgrade_all)
end
