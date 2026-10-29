-- Obsidian Loader. The game requires this chunk as foundation/lua/build_date_information, so the
-- first line does what the vanilla chunk does, and a failure in anything after it leaves the game vanilla.
BUILD_DATE_INFORMATION = "2020-12-22 09:33:14"

local ok, core = pcall(require, "obsidian/loader/core")
if ok and type(core) == "table" and type(core.boot) == "function" then
	pcall(core.boot)
end
