-- Console: the game's own developer commands, run from the menu. The runtime refuses the ones that
-- reach the shared backend, wipe saves or unlock paid content.
local U = obsidian.module("pages/ui")
local api, t = U.api, U.t
local console = api.console

local function run(line)
	local ok, message = console.run(line)
	if ok then
		if message and message ~= "" then return message end
		return t("done")
	end
	return U.why(message)
end

return function(page)
	page:input(t("console_type"), run, { help = U.help("console_type") })
	page:header(t("console_list"))
	local names = console.commands()
	if #names == 0 then page:label(t("console_none")) end
	for _, name in ipairs(names) do
		page:action(name, function() return run(name) end)
	end
end
