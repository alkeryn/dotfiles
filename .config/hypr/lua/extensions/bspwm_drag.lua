-- Held-button pointer moves/resizes, without Hyprland's temporary floating tile.
-- v0.56.2 exposes cursor queries/timers but no Lua pointer-motion event.
-- Sample only during a grab, at bspwm's default pointer_motion_interval (17ms).
local pseudo = require("lua/extensions/bspwm_pseudo")
local M = {}
local MOTION_INTERVAL_MS = 17
local STOP_EVENTS = { "config.reloaded", "keybinds.submap", "monitor.removed", "hyprland.shutdown" }

local function contains(position, origin, size)
	return origin and size and position.x >= origin.x and position.y >= origin.y
		and position.x < origin.x + size.x and position.y < origin.y + size.y
end

local function stacking_level(window)
	local level = (window.fullscreen or 0) ~= 0 and 3 or (window.floating and 2 or 1)
	if window.floating and window.allowed_over_fullscreen then level = 4 end
	return level
end

local function pointer_window(pos, monitor)
	local ws = monitor and (monitor.active_special_workspace or monitor.active_workspace)
	if not ws then return nil end
	-- Do not swap a tile through a panel/launcher. Our feedback is explicitly
	-- click-through; keyboard interactivity alone does not imply that.
	for _, layer in ipairs(hl.get_layers({ monitor = monitor })) do
		if layer.mapped and layer.layer >= 2 and layer.namespace ~= "bspwm-presel-feedback"
			and contains(pos, { x = layer.x, y = layer.y }, { x = layer.w, y = layer.h }) then
			return nil
		end
	end
	local best, best_level, best_rank
	for _, w in ipairs(hl.get_windows()) do
		if w.mapped and not w.hidden and w.visible ~= false and w.workspace
			and (w.workspace.id == ws.id or (w.pinned and w.floating)) and contains(pos, w.at, w.size) then
			-- Floating windows occlude tiles; fullscreen occludes normal floats.
			-- Native focus history resolves overlapping floats/monocle windows.
			local level = stacking_level(w)
			local rank = w.focus_history_id
			if not rank or rank < 0 then rank = math.huge end
			if not best or level > best_level or (level == best_level and rank < best_rank) then
				best, best_level, best_rank = w, level, rank
			end
		end
	end
	return best
end

function M.new(layout, action)
	local resizing = action == "resize"
	local grabbed, timer, last_pos, resize_grab
	local native_active = false
	local native_drag = resizing and hl.dsp.window.resize() or hl.dsp.window.drag()
	local drag = {}

	function drag.stop()
		grabbed, last_pos, resize_grab = nil, nil, nil
		if timer then timer:set_enabled(false) end
	end

	local function motion()
		local active = hl.get_active_window()
		if not grabbed or not layout.drag_valid(grabbed) or not active
			or (resizing and (pseudo.is_pseudo(grabbed) or active.stable_id ~= grabbed.stable_id
				or grabbed.workspace.id ~= resize_grab.workspace_id)) then
			drag.stop()
			return
		end
		local pos, monitor = hl.get_cursor_pos(), hl.get_monitor_at_cursor()
		if not pos or not monitor then
			drag.stop()
			return
		end
		if last_pos and pos.x == last_pos.x and pos.y == last_pos.y then return end
		last_pos = { x = pos.x, y = pos.y }
		if resizing then
			if not layout.resize_motion(grabbed, resize_grab, pos) then drag.stop() end
			return -- resizing never swaps or transfers the grabbed window
		end
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

	local function sample()
		local ok, err = pcall(motion)
		if not ok then
			drag.stop()
			print("bspwm pointer " .. (resizing and "resize" or "drag") .. ": " .. tostring(err))
		end
	end

	function drag.release()
		-- Commit motion since the last timer tick, even on a quick release.
		if resizing and grabbed then sample() end
		drag.stop()
	end

	function drag.begin()
		-- The native dispatcher marks its invoking binding release-pending:
		-- this SAME Lua callback runs again on release for native grabs.
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
		-- Native resizeTarget consumes pseudo deltas before the Lua bridge.
		-- Only resize goes native: moving a pseudo tile still swaps BSP leaves.
		if resizing and pseudo.is_pseudo(w) then
			native_active = true
			hl.dispatch(native_drag)
			return
		end
		-- Grab the window under the pointer, not the keyboard-focused window.
		hl.dispatch(hl.dsp.focus({ window = w }))
		if resizing then
			if not w.active then return end
			resize_grab = layout.resize_begin(w, pos)
			if not resize_grab then return end
		end
		grabbed, last_pos = w, { x = pos.x, y = pos.y }
		if not timer then
			timer = hl.timer(sample, { timeout = MOTION_INTERVAL_MS, type = "repeat" })
			hl.on("window.close", function(closed)
				if grabbed and closed and closed.stable_id == grabbed.stable_id then drag.stop() end
			end)
			for _, event in ipairs(STOP_EVENTS) do
				hl.on(event, drag.stop)
			end
		else
			timer:set_enabled(true)
		end
	end

	return drag
end

return M
