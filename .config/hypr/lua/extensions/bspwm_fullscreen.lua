-- Lua-only one-way fullscreen policy and reload checkpoint.
-- Applications enter monitor fullscreen; WM changes preserve the client mode.
local module_name = "lua/extensions/bspwm_fullscreen"
local prefix = "bspwm_fullscreen_"
-- Keep this session tag stable across reloads; it records policy ownership,
-- not the value of sync_fullscreen.
local policy_tag = prefix .. "independent"
local M = {}
local changing = 0
local before_set, after_set = function() end, function() end

local function tagged(window)
	for _, tag in ipairs(window and window.tags or {}) do
		if tag == policy_tag then return true end
	end
	return false
end

local function markers(window)
	local result = {}
	for _, tag in ipairs(window.tags or {}) do
		if tag:match("^" .. prefix .. "[012]_[012]$") then result[#result + 1] = tag end
	end
	return result
end

local function bspwm_workspace(window)
	local workspace = window and window.workspace
	return workspace and (workspace.tiled_layout == "lua:bspwm" or workspace.tiled_layout == "lua:bspwm_b")
end

local function eligible(window)
	return window and window.mapped and not window.floating and not window.hidden and bspwm_workspace(window)
end

local function managed(window)
	return window and window.mapped and not window.hidden and (bspwm_workspace(window) or tagged(window))
end

local function identity(window)
	return window and (window.stable_id or window.address)
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

local function apply_policy(window, enroll)
	local _, client = modes(window)
	if not enroll and not tagged(window) and client ~= 2 then return true end
	-- Sync while the client is not fullscreen: its NEXT fullscreen request
	-- takes over the monitor natively. Once fullscreen, disable reverse sync
	-- BEFORE a new window/focus change can evict it and clear its client flag.
	if not dispatch("set_prop", { window = window, prop = "sync_fullscreen",
		value = client == 2 and "false" or "true" }) then return false end
	if not tagged(window) then return dispatch("tag", { window = window, tag = "+" .. policy_tag }) end
	return true
end

-- Explicit WM requests preserve the supplied client mode. The native pair
-- dispatcher rewrites sync_fullscreen on return, so apply our policy AFTER it,
-- even for equal/no-op pairs. Observers must not interpret this as an app exit.
function M.set_wm_modes(window, internal, client)
	if not window or not window.mapped then return false end
	before_set(window)
	changing = changing + 1
	local ok = dispatch("fullscreen_state", { window = window, internal = internal, client = client,
		action = "set", layout_aware = false })
	if ok then ok = apply_policy(window, true) end
	changing = changing - 1
	after_set(window, ok)
	return ok
end

function M.setup()
	local ready, waiting, writing = false, false, false
	local observed, pending = {}, {}

	local function current_config()
		-- v0.56.2 clears package.loaded BEFORE provider teardown; old event
		-- callbacks must not overwrite the saved markers with now-zero modes.
		return package.loaded[module_name] == M
	end

	local function cancel_exit(id)
		-- Invalidate, but let the oneshot expire: v0.56.2 only releases its
		-- registry callback after it fires. Disabling it would retain that ref.
		if id then pending[id] = nil end
	end

	local function clear_policy(window)
		if not window or not window.mapped or not tagged(window) then return end
		writing = true
		dispatch("set_prop", { window = window, prop = "sync_fullscreen", value = "unset" })
		dispatch("tag", { window = window, tag = "-" .. policy_tag })
		writing = false
	end

	local function set_marker(window, desired)
		if not window or not window.mapped then return end
		local previous = markers(window)
		if (#previous == 0 and not desired) or (#previous == 1 and previous[1] == desired) then return end
		-- Tag writes emit update_rules synchronously. Ignore intermediate sets.
		writing = true
		for _, tag in ipairs(previous) do dispatch("tag", { tag = "-" .. tag, window = window }) end
		if desired then dispatch("tag", { tag = "+" .. desired, window = window }) end
		writing = false
	end

	local function defer_client_exit(window, client)
		local id = identity(window)
		local entry = {}
		pending[id] = entry
		-- Don't recursively change fullscreen inside the native controller's
		-- in-flight rule update. One shot after it returns, never a poll loop.
		hl.timer(function()
			if pending[id] ~= entry then return end
			pending[id] = nil
			if not ready or not current_config() or changing > 0 or not managed(window) then return end
			local internal, live_client = modes(window)
			if internal == 2 and live_client == client then M.set_wm_modes(window, 0, client) end
		end, { timeout = 1, type = "oneshot" })
	end

	local function remember(window, adopt, policy_applied)
		if not ready or writing or changing > 0 or not current_config() then return end
		if managed(window) then
			local internal, client = modes(window)
			local id = identity(window)
			local previous = id and observed[id]
			if id then
				observed[id] = { window = window, client = client }
				if adopt or client == 2 or internal ~= 2 then cancel_exit(id)
				elseif previous and previous.client == 2 then defer_client_exit(window, client) end
			end
			if not policy_applied and (adopt or not previous or previous.client ~= client or (client == 2 and not tagged(window))) then
				writing = true
				apply_policy(window, false)
				writing = false
			end
		end
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

	before_set = function(window) cancel_exit(identity(window)) end
	-- Adopt/checkpoint explicit requests without repeating a successful policy write.
	after_set = function(window, policy_applied) remember(window, true, policy_applied) end

	-- Native application requests emit update_rules even when internal mode
	-- stays unchanged. A WM demotion keeps client=2, so it is NOT an app exit
	-- and must never be promoted back to monitor fullscreen by this observer.
	for _, event in ipairs({ "window.fullscreen", "window.update_rules" }) do hl.on(event, remember) end
	hl.on("window.move_to_workspace", function(window) remember(window, true) end)
	hl.on("window.open_early", function(window)
		if ready and not writing and changing == 0 and current_config() then
			local id = identity(window)
			cancel_exit(id)
			if id then observed[id] = nil end
			clear_policy(window) -- retire a previous mapping before initial FS is applied
			set_marker(window, nil)
		end
	end)
	-- Adopt initial fullscreen without erasing policy installed during native map.
	hl.on("window.open", function(window) remember(window, true) end)
	hl.on("window.close", function(window)
		if ready and not writing and changing == 0 and current_config() then
			local id = identity(window)
			cancel_exit(id)
			if id then observed[id] = nil end
			set_marker(window, nil)
			clear_policy(window)
		end
	end)
	hl.on("window.destroy", function()
		for id, entry in pairs(observed) do
			if not entry.window.mapped then cancel_exit(id); observed[id] = nil end
		end
	end)

	hl.on("config.reloaded", function()
		ready, waiting = false, true
		observed, pending = {}, {} -- invalidates pending oneshot tokens too
		-- A syntax-failed reload retains these callbacks despite cache clear.
		if package.loaded[module_name] == nil then package.loaded[module_name] = M end
	end)

	hl.on("config.props_refreshed", function()
		if not waiting or not current_config() then return end
		waiting = false -- consume BEFORE dispatch; reentrant refreshes are no-ops
		local windows, saved = hl.get_windows() or {}, {}
		for _, window in ipairs(windows) do
			local tags = markers(window)
			if #tags == 1 then
				local internal, client = tags[1]:match("^" .. prefix .. "([012])_([012])$")
				saved[#saved + 1] = { window = window, internal = tonumber(internal), client = tonumber(client) }
			end
		end
		for _, entry in ipairs(saved) do
			local window = entry.window
			if eligible(window) then
				local internal, client = modes(window)
				-- Repair only records lost during layout replacement. Never evict
				-- a surviving fullscreen window or override a new live request.
				if internal == 0 and client == 0 and (entry.internal ~= 0 or entry.client ~= 0)
					and not window.workspace.has_fullscreen then
					dispatch("fullscreen_state", { window = window, internal = entry.internal,
						client = entry.client, action = "set", layout_aware = false })
				end
			end
		end
		ready = true
		-- Reapply AFTER replay (which rewrites sync_fullscreen), including
		-- floats and 0/0 windows. Adopt, don't treat hydration as client input.
		for _, window in ipairs(windows) do remember(window, true) end
	end)
end

return M
