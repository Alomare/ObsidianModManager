-- Runs every test of every loader/tests/test_*.lua file, each in a fresh LuaJIT process.
-- Usage (from the repository root): luajit loader/tests/run.lua [file filter]

local exe = arg[-1]
local filter = arg[1]
local windows = package.config:sub(1, 1) == "\\"
local files = {}
local list = io.popen(windows and 'dir /b "loader\\tests\\test_*.lua" 2>nul' or "ls loader/tests")
for name in list:lines() do
	if name:match("^test_.*%.lua$") and (not filter or name:find(filter, 1, true)) then files[#files + 1] = name end
end
list:close()
table.sort(files)

local passed, failed = 0, 0
for _, file in ipairs(files) do
	package.path = "loader/tests/?.lua;" .. package.path
	local tests = assert(loadfile("loader/tests/" .. file))()
	for _, t in ipairs(tests) do
		local line = string.format('"%s" loader/tests/one.lua "%s" "%s" 2>&1', exe, file, t[1])
		-- cmd.exe drops the outer pair of quotes.
		local cmd = windows and '"' .. line .. '"' or line
		local p = io.popen(cmd)
		local out = p:read("*a")
		p:close()
		if out:match("^PASS") then
			passed = passed + 1
		else
			failed = failed + 1
			print("FAIL " .. file .. " " .. t[1] .. "\n" .. out)
		end
	end
end
print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
