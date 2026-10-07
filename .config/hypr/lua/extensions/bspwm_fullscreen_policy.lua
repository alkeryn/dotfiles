-- One-way application/WM fullscreen policy. No mode checkpoints or replay.
-- Applications enter monitor fullscreen; WM changes preserve the client mode.
local module_name = "lua/extensions/bspwm_fullscreen_policy"
-- Stable session tag: ownership of this policy, not the value of sync_fullscreen.
local policy_tag = "bspwm_fullscreen_independent"
local M = {}
local changing = 0
local before_set, after_set = function() end, function() end

local function tagged(window)
	for _, tag in ipairs(window and window.tags or {}) do
		if tag == policy_tag then return true end
	end
	return false
end

local function managed(window)
	local workspace = window and window.workspace
	local bspwm = workspace and (workspace.tiled_layout == "lua:bspwm" or workspace.tiled_layout == "lua:bspwm_b")
	return window and window.mapped and not window.hidden and (bspwm or tagged(window))
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
		print("bspwm fullscreen policy: " .. kind .. " failed: " .. tostring(reason))
		return false
	end
	return true
end

local function apply_policy(window, enroll)
	local _, client = modes(window)
	if not enroll and not tagged(window) and client ~= 2 then return true end
	-- Sync outside application fullscreen so its NEXT request covers the monitor.
	-- Once fullscreen, stop WM demotions from clearing the application's flag.
	if not dispatch("set_prop", { window = window, prop = "sync_fullscreen",
		value = client == 2 and "false" or "true" }) then return false end
	if not tagged(window) then return dispatch("tag", { window = window, tag = "+" .. policy_tag }) end
	return true
end

-- The native pair dispatcher rewrites sync_fullscreen on return. Reapply policy
-- AFTER it, even for no-op pairs, without interpreting our writes as app input.
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

-- Optional reload_ready() is supplied by the caller when a separate restoration
-- feature is installed. This module neither imports it nor knows its tag format.
function M.setup(options)
	local reload_ready = options and options.reload_ready or function() return true end
	local ready, waiting, writing = false, false, false
	local observed, pending = {}, {}

	local function current_config()
		return package.loaded[module_name] == M
	end

	local function cancel_exit(id)
		-- Let invalidated oneshots expire: v0.56.2 only releases their registry
		-- callbacks after they fire. Disabling them would retain those references.
		if id then pending[id] = nil end
	end

	local function clear_policy(window)
		if not window or not window.mapped or not tagged(window) then return end
		writing = true
		dispatch("set_prop", { window = window, prop = "sync_fullscreen", value = "unset" })
		dispatch("tag", { window = window, tag = "-" .. policy_tag })
		writing = false
	end

	local function defer_client_exit(window, client)
		local id = identity(window)
		local entry = {}
		pending[id] = entry
		-- Reconcile AFTER the native controller returns, not recursively inside
		-- its in-flight rule update. One shot, never a polling loop.
		hl.timer(function()
			if pending[id] ~= entry then return end
			pending[id] = nil
			if not ready or not current_config() or changing > 0 or not managed(window) then return end
			local internal, live_client = modes(window)
			if internal == 2 and live_client == client then M.set_wm_modes(window, 0, client) end
		end, { timeout = 1, type = "oneshot" })
	end

	local function observe(window, adopt, policy_applied)
		if not ready or writing or changing > 0 or not current_config() or not managed(window) then return end
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

	before_set = function(window) cancel_exit(identity(window)) end
	after_set = function(window, policy_applied) observe(window, true, policy_applied) end

	-- Client-only transitions emit update_rules without an internal FS event.
	-- A WM demotion keeps client=2: it is not an app exit or a fresh entry.
	for _, event in ipairs({ "window.fullscreen", "window.update_rules" }) do hl.on(event, observe) end
	hl.on("window.move_to_workspace", function(window) observe(window, true) end)
	hl.on("window.open_early", function(window)
		if ready and not writing and changing == 0 and current_config() then
			local id = identity(window)
			cancel_exit(id)
			if id then observed[id] = nil end
			clear_policy(window) -- retire the previous mapping before initial FS
		end
	end)
	hl.on("window.open", function(window) observe(window, true) end)
	hl.on("window.close", function(window)
		if ready and not writing and changing == 0 and current_config() then
			local id = identity(window)
			cancel_exit(id)
			if id then observed[id] = nil end
			clear_policy(window)
		end
	end)
	hl.on("window.destroy", function()
		for id, entry in pairs(observed) do
			if not entry.window.mapped then cancel_exit(id); observed[id] = nil end
		end
	end)

	-- This is policy lifecycle, not fullscreen restoration: discard old observer
	-- baselines and pending exits, then adopt whatever live modes exist afterward.
	hl.on("config.reloaded", function()
		ready, waiting = false, true
		observed, pending = {}, {}
		if package.loaded[module_name] == nil then package.loaded[module_name] = M end
	end)
	hl.on("config.props_refreshed", function()
		if not waiting or not current_config() or not reload_ready() then return end
		waiting, ready = false, true
		for _, window in ipairs(hl.get_windows() or {}) do observe(window, true) end
	end)
end

return M
