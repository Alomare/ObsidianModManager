-- Runs every test of every loader/tests/test_*.lua file, each in a fresh LuaJIT process.
-- Usage (from the repository root): luajit loader/tests/run.lua [file filter]

local exe = arg[-1]
local filter = arg[1]
local files = {}
local list = io.popen('dir /b "loader\\tests\\test_*.lua" 2>nul')
for name in list:lines() do
	if not filter or name:find(filter, 1, true) then files[#files + 1] = name end
end
list:close()
table.sort(files)

local passed, failed = 0, 0
for _, file in ipairs(files) do
	package.path = "loader/tests/?.lua;" .. package.path
	local tests = assert(loadfile("loader/tests/" .. file))()
	for _, t in ipairs(tests) do
		local cmd = string.format('""%s" loader/tests/one.lua "%s" "%s" 2>&1"', exe, file, t[1])
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
