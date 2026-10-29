-- Runs one named test from one test file. Used by run.lua.
package.path = "loader/tests/?.lua;" .. package.path
math.randomseed(os.time() + os.clock() * 1e6)
local file, name = arg[1], arg[2]
local tests = assert(loadfile("loader/tests/" .. file))()
for _, t in ipairs(tests) do
	if t[1] == name then
		local ok, err = xpcall(t[2], debug.traceback)
		io.write(ok and "PASS\n" or ("FAIL " .. tostring(err) .. "\n"))
		os.exit(ok and 0 or 1)
	end
end
io.write("FAIL no test named " .. name .. "\n")
os.exit(1)
