-- Declare plugins by content, letting Hyprland replace only changed libraries.
local M = {}

local function shell_quote(value)
	return "'" .. value:gsub("'", "'\\''") .. "'"
end

function M.load(path, build)
	-- --verify-config has no compositor instance: never build or load plugins.
	local instance = os.getenv("HYPRLAND_INSTANCE_SIGNATURE")
	if not instance then
		hl.plugin.load(path)
		return
	end
	local scripts = assert(os.getenv("HOME")) .. "/.config/hypr/scripts/"
	if build then
		local file, err, errno = io.open(path, "rb")
		if file then
			file:close()
		else
			assert(errno == 2, err) -- only a missing binary should trigger compilation
			assert(type(build.source_dir) == "string" and type(build.target) == "string", "plugin build needs source_dir and target")
			hl.exec_cmd("python3 " .. shell_quote(scripts .. "plugin_build.py")
				.. " --source-dir " .. shell_quote(build.source_dir)
				.. " --output " .. shell_quote(path)
				.. " --target " .. shell_quote(build.target)
				.. " --instance " .. shell_quote(instance))
			print("[plugins] building missing " .. path .. "; log: " .. path .. ".build.log")
			return -- the worker reloads this instance after a successful build
		end
	end
	local pipe = assert(io.popen("python3 " .. shell_quote(scripts .. "plugin_snapshot.py") .. " " .. shell_quote(path) .. " 2>&1", "r"))
	local output = pipe:read("*a")
	-- Hyprland uses SA_NOCLDWAIT: pclose may report ECHILD after success.
	pipe:close()
	local snapshot = output and output:match("^(/[^\r\n]+)\n?$")
	assert(snapshot, "plugin snapshot failed: " .. tostring(output))
	hl.plugin.load(snapshot)
end

return M
