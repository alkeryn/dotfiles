-- lua tests/plugins_test.lua
local original_getenv, original_popen = os.getenv, io.popen
local declared, commands = {}, {}
local output = "/cache/hypr/plugin-cache/hypr_extras/hash-one.so\n"
local instance = "test-session"
os.getenv = function(name)
	if name == "HOME" then return "/home/a'b $user" end
	if name == "HYPRLAND_INSTANCE_SIGNATURE" then return instance end
end
io.popen = function(command, mode)
	assert(mode == "r")
	commands[#commands + 1] = command
	return {
		read = function(_, what) assert(what == "*a"); return output end,
		close = function() return nil, "No child processes", 10 end,
	}
end
hl = { plugin = { load = function(path) declared[#declared + 1] = path end } }

local function load_config()
	package.loaded["lua/plugins"] = nil -- each config reload creates a fresh Lua state
	require("lua/plugins").load("/config/a'b $plugin.so")
end
load_config()
assert(declared[1] == output:sub(1, -2))
assert(commands[1] == "python3 '/home/a'\\''b $user/.config/hypr/scripts/plugin_snapshot.py' '/config/a'\\''b $plugin.so' 2>&1")
load_config()
assert(declared[2] == declared[1], "plugin-triggered reload must keep the same path")
output = "/cache/hypr/plugin-cache/hypr_extras/hash-two.so\n"
load_config()
assert(declared[3] ~= declared[2], "changed binary must change the declared plugin path")
load_config()
assert(declared[4] == declared[3], "replacement's own reload must converge")
output = "plugin_snapshot: build failed\n"
assert(not pcall(load_config))
assert(#declared == 4, "helper failure must not declare a bogus path")
output = "/path/one.so\n/path/two.so\n"
assert(not pcall(load_config), "multiple output lines must be rejected")
instance = nil
local before = #commands
load_config()
assert(#commands == before, "verify-config must not create plugin snapshots")
assert(declared[5] == "/config/a'b $plugin.so")
os.getenv, io.popen = original_getenv, original_popen
print("PASS plugin declarations: changes, reload convergence, quoting, errors and config verification")
