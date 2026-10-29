-- The loader log (rewritten on every line, so a crash leaves the last line on disk) and per-mod logs.
local B = require("kepler/loader/builtins")

local M = { dir = nil, lines = {}, opened = {}, counts = {} }

function M.setup(dir)
	M.dir = dir
end

function M.flush()
	if not M.dir then return end
	local f = B.open(M.dir .. "/loader.log", "w")
	if f then
		f:write(B.concat(M.lines, "\n"), "\n")
		f:close()
	end
end

function M.line(...)
	B.insert(M.lines, B.date("%H:%M:%S ") .. B.join(...))
	M.flush()
end

-- Logs at most 3 times per site, so an error repeated every frame can't flood the log.
function M.limited(site, ...)
	local n = (M.counts[site] or 0) + 1
	M.counts[site] = n
	if n <= 3 then M.line(...) end
end

-- Only [%w_-] characters from the mod id, so no mod can write outside the logs folder.
function M.file_name(id)
	local name = B.gsub(B.tostring(id), "[^%w_%-]", "")
	if name == "" then name = "unknown" end
	return name
end

function M.mod(id, ...)
	if not M.dir then return end
	local name = M.file_name(id)
	local f = B.open(M.dir .. "/" .. name .. ".log", M.opened[name] and "a" or "w")
	if f then
		M.opened[name] = true
		f:write(B.date("%H:%M:%S "), B.join(...), "\n")
		f:close()
	end
end

return M
