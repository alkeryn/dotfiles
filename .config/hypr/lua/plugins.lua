-- Declare plugins by content, letting Hyprland replace only changed libraries.
local M = {}

local function shell_quote(value)
	return "'" .. value:gsub("'", "'\\''") .. "'"
end

function M.load(path)
	-- --verify-config has no compositor instance and does not load plugins.
	if not os.getenv("HYPRLAND_INSTANCE_SIGNATURE") then
		hl.plugin.load(path)
		return
	end
	local helper = assert(os.getenv("HOME")) .. "/.config/hypr/scripts/plugin_snapshot.py"
	local pipe = assert(io.popen("python3 " .. shell_quote(helper) .. " " .. shell_quote(path) .. " 2>&1", "r"))
	local output = pipe:read("*a")
	-- Hyprland uses SA_NOCLDWAIT: pclose may report ECHILD after success.
	pipe:close()
	local snapshot = output and output:match("^(/[^\r\n]+)\n?$")
	assert(snapshot, "plugin snapshot failed: " .. tostring(output))
	hl.plugin.load(snapshot)
end

return M
