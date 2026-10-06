-- Held-button pointer moves, without Hyprland's temporary floating tile.
-- v0.56.2 exposes cursor queries/timers but no Lua pointer-motion event.
-- Sample only during a grab, at bspwm's default pointer_motion_interval (17ms).
local M = {}

local function contains(pos, at, size)
	return at and size and pos.x >= at.x and pos.y >= at.y
		and pos.x < at.x + size.x and pos.y < at.y + size.y
end

local function pointer_window(pos, monitor)
	local ws = monitor and (monitor.active_special_workspace or monitor.active_workspace)
	if not ws then return nil end
	-- Do not swap a tile through a panel/launcher. Our feedback is explicitly
	-- click-through; keyboard interactivity alone does not imply that.
	for _, layer in ipairs(hl.get_layers({ monitor = monitor })) do
		if layer.mapped and layer.layer >= 2 and layer.namespace ~= "bspwm-presel-feedback"
			and contains(pos, { x = layer.x, y = layer.y }, { x = layer.w, y = layer.h }) then return nil end
	end
	local best, best_level, best_rank
	for _, w in ipairs(hl.get_windows()) do
		if w.mapped and not w.hidden and w.visible ~= false and w.workspace
			and (w.workspace.id == ws.id or (w.pinned and w.floating)) and contains(pos, w.at, w.size) then
			-- Floating windows occlude tiles; fullscreen occludes normal floats.
			-- Native focus history resolves overlapping floats/monocle windows.
			local level = (w.fullscreen or 0) ~= 0 and 3 or (w.floating and 2 or 1)
			if w.floating and w.allowed_over_fullscreen then level = 4 end
			local rank = w.focus_history_id
			if not rank or rank < 0 then rank = math.huge end
			if not best or level > best_level or (level == best_level and rank < best_rank) then
				best, best_level, best_rank = w, level, rank
			end
		end
	end
	return best
end

function M.new(layout)
	local grabbed, timer, last_pos
	local native_active = false
	local native_drag = hl.dsp.window.drag()
	local drag = {}

	function drag.stop()
		grabbed, last_pos = nil, nil
		if timer then timer:set_enabled(false) end
	end

	local function motion()
		if not grabbed or not layout.drag_valid(grabbed) or not hl.get_active_window() then drag.stop(); return end
		local pos, monitor = hl.get_cursor_pos(), hl.get_monitor_at_cursor()
		if not pos or not monitor then drag.stop(); return end
		if last_pos and pos.x == last_pos.x and pos.y == last_pos.y then return end
		last_pos = pos
		local source_monitor = grabbed.workspace.monitor
		if source_monitor and source_monitor.id ~= monitor.id then
			local dest = monitor.active_special_workspace or monitor.active_workspace
			if not layout.drag_transfer(grabbed, dest) then drag.stop() end
			return -- bspwm does not also swap on the monitor-crossing motion
		end
		local hovered = pointer_window(pos, monitor)
		if hovered and hovered.stable_id ~= grabbed.stable_id and layout.drag_valid(hovered) then
			if not layout.drag_swap(grabbed, hovered) then drag.stop() end
		end
	end

	function drag.begin()
		-- The native dispatcher marks its invoking binding release-pending:
		-- this SAME Lua callback runs again on release for floating windows.
		if native_active then
			native_active = false
			hl.dispatch(native_drag)
			return
		end
		drag.stop()
		local pos, monitor = hl.get_cursor_pos(), hl.get_monitor_at_cursor()
		local w = pos and pointer_window(pos, monitor)
		if not w then return end
		local ws = w.workspace
		if w.floating or (ws and ws.tiled_layout ~= "lua:bspwm" and ws.tiled_layout ~= "lua:bspwm_b") then
			native_active = true
			hl.dispatch(native_drag)
			return
		end
		if not layout.drag_valid(w) then return end
		-- Grab the window under the pointer, not the keyboard-focused window.
		hl.dispatch(hl.dsp.focus({ window = w }))
		grabbed, last_pos = w, pos
		if not timer then
			timer = hl.timer(function()
				local ok, err = pcall(motion)
				if not ok then drag.stop(); print("bspwm pointer drag: " .. tostring(err)) end
			end, { timeout = 17, type = "repeat" })
			hl.on("window.close", function(closed)
				if grabbed and closed and closed.stable_id == grabbed.stable_id then drag.stop() end
			end)
			for _, event in ipairs({ "config.reloaded", "keybinds.submap", "monitor.removed", "hyprland.shutdown" }) do
				hl.on(event, drag.stop)
			end
		else
			timer:set_enabled(true)
		end
	end

	return drag
end

return M
