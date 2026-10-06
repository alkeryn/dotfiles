-- lua tests/plugins_test.lua
local original_getenv, original_popen, original_open = os.getenv, io.popen, io.open
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
-- Missing local plugins are built asynchronously, never declared before ready.
local spawned = {}
hl.exec_cmd = function(command) spawned[#spawned + 1] = command end
local file_exists, file_errno = false, 2
io.open = function(path, mode)
	assert(path == "/config/build/test.so" and mode == "rb")
	if file_exists then return { close = function() end } end
	return nil, "cannot open plugin", file_errno
end
local build = { source_dir = "/config/a'b", target = "test" }
local function load_local()
	package.loaded["lua/plugins"] = nil
	require("lua/plugins").load("/config/build/test.so", build)
end
local before_declared, before_commands = #declared, #commands
load_local() -- verify-config still must not spawn builds
assert(#spawned == 0 and #commands == before_commands)
assert(#declared == before_declared + 1)
instance = "test-session"
load_local()
assert(#spawned == 1 and #commands == before_commands)
assert(#declared == before_declared + 1, "must not declare an unbuilt library")
assert(spawned[1] == "python3 '/home/a'\\''b $user/.config/hypr/scripts/plugin_build.py' --source-dir '/config/a'\\''b' --output '/config/build/test.so' --target 'test' --instance 'test-session'")
file_exists = true
output = "/cache/hypr/plugin-cache/test/built.so\n"
load_local() -- builder's follow-up reload sees the completed output
assert(#spawned == 1 and declared[#declared] == output:sub(1, -2))
load_local()
assert(#spawned == 1, "existing plugins must never be rebuilt automatically")
file_exists, file_errno = false, 13
assert(not pcall(load_local), "permission errors must not be treated as missing binaries")
assert(#spawned == 1)
os.getenv, io.popen, io.open = original_getenv, original_popen, original_open
print("PASS plugin declarations: first builds, reload convergence, quoting, errors and config verification")
