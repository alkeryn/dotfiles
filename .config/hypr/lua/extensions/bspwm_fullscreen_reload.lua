-- Hyprland v0.56.2 Lua-layout reload workaround only. No fullscreen policy.
-- Static mode tags survive the native layout replacement that loses FS records.
local module_name = "lua/extensions/bspwm_fullscreen_reload"
local prefix = "bspwm_fullscreen_"
local M = {}
local ready = false

-- Optional integration barrier: consumers may adopt live modes only once the
-- reload replay is complete, including during reentrant props_refreshed events.
function M.is_ready()
	return ready and package.loaded[module_name] == M
end

local function markers(window)
	local result = {}
	for _, tag in ipairs(window.tags or {}) do
		if tag:match("^" .. prefix .. "[012]_[012]$") then result[#result + 1] = tag end
	end
	return result
end

local function eligible(window)
	local workspace = window and window.workspace
	return window and window.mapped and not window.floating and not window.hidden and workspace
		and (workspace.tiled_layout == "lua:bspwm" or workspace.tiled_layout == "lua:bspwm_b")
end

local function modes(window)
	return window.fullscreen or 0, window.fullscreen_client or 0
end

local function dispatch(kind, args)
	local ok, result = pcall(function() return hl.dispatch(hl.dsp.window[kind](args)) end)
	if not ok or (result and result.ok == false) then
		local reason = type(result) == "table" and (result.error or result.message or "dispatcher rejected request") or result
		print("bspwm fullscreen reload: " .. kind .. " failed: " .. tostring(reason))
		return false
	end
	return true
end

function M.setup()
	ready = false
	local waiting, writing = false, false
	local closed = {}

	local function current_config()
		-- Cache clear precedes provider teardown, while old callbacks can still
		-- run. Never overwrite saved tags with teardown's now-zero mode queries.
		return package.loaded[module_name] == M
	end

	local function set_marker(window, desired)
		if not window or not window.mapped then return end
		local previous = markers(window)
		if (#previous == 0 and not desired) or (#previous == 1 and previous[1] == desired) then return end
		writing = true -- tag changes synchronously emit update_rules
		for _, tag in ipairs(previous) do dispatch("tag", { tag = "-" .. tag, window = window }) end
		if desired then dispatch("tag", { tag = "+" .. desired, window = window }) end
		writing = false
	end

	local function remember(window)
		if not M.is_ready() or writing or not window or closed[window.stable_id] then return end
		local desired
		if eligible(window) then
			local internal, client = modes(window)
			if (internal == 0 or internal == 1 or internal == 2) and (client == 0 or client == 1 or client == 2)
				and (internal ~= 0 or client ~= 0) then
				desired = string.format("%s%d_%d", prefix, internal, client)
			end
		end
		set_marker(window, desired)
	end

	-- update_rules covers client-only changes with no internal fullscreen event.
	for _, event in ipairs({ "window.fullscreen", "window.update_rules", "window.move_to_workspace" }) do hl.on(event, remember) end
	hl.on("window.open_early", function(window)
		if window and M.is_ready() and not writing then
			if window.stable_id then closed[window.stable_id] = nil end
			set_marker(window, nil)
		end
	end)
	hl.on("window.open", function(window)
		if window and window.stable_id then closed[window.stable_id] = nil end
		remember(window)
	end)
	hl.on("window.close", function(window)
		if window and M.is_ready() and not writing then
			-- Other close subscribers can change rules while mapped is still true.
			-- Those notifications must not recreate the mode tag we just removed.
			if window.stable_id then closed[window.stable_id] = window end
			set_marker(window, nil)
		end
	end)
	hl.on("window.destroy", function()
		for id, window in pairs(closed) do
			if not window.mapped then closed[id] = nil end
		end
	end)

	hl.on("config.reloaded", function()
		ready, waiting = false, true
		-- Syntax-failed reloads retain callbacks despite clearing the cache.
		if package.loaded[module_name] == nil then package.loaded[module_name] = M end
	end)

	hl.on("config.props_refreshed", function()
		if not waiting or not current_config() then return end
		waiting = false -- consume BEFORE dispatch; reentrant refreshes are no-ops
		local windows, saved = hl.get_windows() or {}, {}
		for _, window in ipairs(windows) do
			local tags = markers(window)
			if #tags == 1 and not closed[window.stable_id] then
				local internal, client = tags[1]:match("^" .. prefix .. "([012])_([012])$")
				saved[#saved + 1] = { window = window, internal = tonumber(internal), client = tonumber(client) }
			end
		end
		for _, entry in ipairs(saved) do
			local window = entry.window
			if eligible(window) then
				local internal, client = modes(window)
				-- Only repair lost records. Never evict a surviving fullscreen
				-- window or override a new live request with an old checkpoint.
				if internal == 0 and client == 0 and (entry.internal ~= 0 or entry.client ~= 0)
					and not window.workspace.has_fullscreen then
					dispatch("fullscreen_state", { window = window, internal = entry.internal,
						client = entry.client, action = "set", layout_aware = false })
				end
			end
		end
		ready = true
		for _, window in ipairs(windows) do remember(window) end
	end)
end

return M
