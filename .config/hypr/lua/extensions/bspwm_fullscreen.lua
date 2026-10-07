-- Lua-only fullscreen checkpoint. Static window tags survive both Lua-state
-- destruction and the native tiled-layout replacement that loses FS records.
local module_name = "lua/extensions/bspwm_fullscreen"
local prefix = "bspwm_fullscreen_"
local M = {}

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
		print("bspwm fullscreen: " .. kind .. " failed: " .. tostring(reason))
		return false
	end
	return true
end

function M.setup()
	local ready, waiting, writing = false, false, false

	local function set_marker(window, desired)
		if not window or not window.mapped then return end
		local previous = markers(window)
		if (#previous == 0 and not desired) or (#previous == 1 and previous[1] == desired) then return end
		-- Tag changes synchronously emit update_rules. Never observe the
		-- intermediate tag set or recurse back into our own writes.
		writing = true
		for _, tag in ipairs(previous) do dispatch("tag", { tag = "-" .. tag, window = window }) end
		if desired then dispatch("tag", { tag = "+" .. desired, window = window }) end
		writing = false
	end

	local function current_config()
		-- v0.56.2 clears package.loaded user modules BEFORE tearing down
		-- providers, but old event callbacks can still run during teardown.
		-- Their now-zero FS queries must NOT overwrite the saved markers.
		return package.loaded[module_name] == M
	end

	local function remember(window)
		if not ready or writing or not current_config() then return end
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

	-- update_rules also covers client-only fullscreen changes, which do not
	-- emit window.fullscreen when the internal mode stays unchanged.
	for _, event in ipairs({ "window.fullscreen", "window.update_rules", "window.open", "window.move_to_workspace" }) do
		hl.on(event, remember)
	end
	hl.on("window.close", function(window)
		if ready and not writing and current_config() then set_marker(window, nil) end
	end)

	hl.on("config.reloaded", function()
		ready, waiting = false, true
		-- Syntax-failed reloads keep the old Lua callbacks, although phase 1
		-- already cleared package.loaded. Re-arm that retained instance too.
		if package.loaded[module_name] == nil then package.loaded[module_name] = M end
	end)

	hl.on("config.props_refreshed", function()
		if not waiting or not current_config() then return end
		waiting = false -- consume BEFORE dispatch; reentrant refreshes are no-ops
		local windows, saved = hl.get_windows() or {}, {}
		for _, window in ipairs(windows) do
			local tags = markers(window)
			-- Ambiguous markers are not authority to fullscreen an arbitrary window.
			if #tags == 1 then
				local internal, client = tags[1]:match("^" .. prefix .. "([012])_([012])$")
				saved[#saved + 1] = { window = window, internal = tonumber(internal), client = tonumber(client) }
			end
		end
		for _, entry in ipairs(saved) do
			local window = entry.window
			if eligible(window) then
				local internal, client = modes(window)
				-- Only repair records lost during layout replacement. Retain live
				-- states/new requests, and never evict another fullscreen window
				-- (notably a float whose handler survived the reload).
				if internal == 0 and client == 0 and (entry.internal ~= 0 or entry.client ~= 0)
					and not window.workspace.has_fullscreen then
					dispatch("fullscreen_state", { window = window, internal = entry.internal,
						client = entry.client, action = "set", layout_aware = false })
				end
			end
		end
		ready = true
		-- Adopt final live states once; ordinary property refreshes never replay
		-- these markers. Closing/exiting/remapping cannot resurrect old FS.
		for _, window in ipairs(windows) do remember(window) end
	end)
end

return M
