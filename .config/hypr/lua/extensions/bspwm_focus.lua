-- Directional focus: bspwm tree.c:find_nearest_neighbor / monitor.c:nearest_monitor.
-- Geometry is translated from bspwm geometry.c (directional_focus_tightness=low).
-- Copyright (c) 2012, Bastien Dejean. BSD-2-Clause; see bspwm_focus.LICENSE.
local geometry = require("lua/extensions/bspwm_geometry")
local tree = require("lua/extensions/bspwm_tree")
local M = {}

-- Return the facing-edge distance, or nil when outside the directional range.
-- Inclusive pixel endpoints are intentional. With tightness=low, overlapping
-- (even fully contained) rectangles qualify: this is NOT a centre/angle test.
function M.distance(a, b, dir)
	local ax, ay = a.x + a.w - 1, a.y + a.h - 1
	local bx, by = b.x + b.w - 1, b.y + b.h - 1
	if dir == "u" then
		if b.y > ay then return nil end
	elseif dir == "l" then
		if b.x > ax then return nil end
	elseif dir == "d" then
		if by < a.y then return nil end
	elseif dir == "r" then
		if bx < a.x then return nil end
	else
		return nil
	end
	if dir == "u" or dir == "d" then
		if not ((b.x >= a.x and b.x <= ax) or (bx >= a.x and bx <= ax)
			or (a.x > b.x and a.x < bx)) then return nil end
		return dir == "u" and math.abs(by - a.y) or math.abs(b.y - ay)
	end
	if not ((b.y >= a.y and b.y <= ay) or (by >= a.y and by <= ay)
		or (a.y > b.y and ay < by)) then return nil end
	return dir == "l" and math.abs(bx - a.x) or math.abs(b.x - ax)
end

local function window_box(window)
	-- Native goal geometry, not tree allocation boxes: includes pseudo-tile
	-- sizing and fullscreen/monocle, and does not change mid-animation.
	local at, size = window.at, window.size
	if at and size and size.x > 0 and size.y > 0 then
		return { x = at.x, y = at.y, w = size.x, h = size.y }
	end
end

local function same_monitor(a, b)
	return a and b and a.name == b.name
end

function M.focus(dir, states)
	if dir ~= "l" and dir ~= "r" and dir ~= "u" and dir ~= "d" then return end
	local active = hl.get_active_window()
	local monitor = hl.get_active_monitor()
	if not monitor then return end
	local source = geometry.monitor_box(monitor)
	local excluded = {}
	if active then
		if not active.mapped or active.hidden then return end
		source = window_box(active)
		excluded[active.stable_id] = true
		local st = active.workspace and states[active.workspace.id]
		local selected = st and st.selected
		if selected and not active.floating and st.selected_focus_id == active.stable_id
			and tree.find_path(st.tree, selected) and tree.find_path(selected, active.stable_id) then
			tree.collect_ids(selected, excluded)
			-- Monocle placement doesn't refresh split _boxes; use its actual
			-- full-screen tile rectangle rather than the previous tiled split.
			if selected.t == "split" and st.mode == "tiled" then source = selected._box end
		end
	end
	if not source then return end

	local monitors, windows = hl.get_monitors(), hl.get_windows()
	local by_id = {}
	for _, window in ipairs(windows) do by_id[window.stable_id] = window end
	local best, best_distance, best_rank
	local seen = {}
	local function consider(window, workspace, mon)
		if not window or seen[window.stable_id] then return end
		local id, ws = window.stable_id, window.workspace
		local pinned = window.pinned and window.floating and same_monitor(window.monitor, mon)
		if not window.mapped or window.hidden or excluded[id] or not ws
			or not ((workspace and ws.id == workspace.id) or pinned) then return end
		seen[id] = true
		local box = window_box(window)
		local distance = box and M.distance(source, box, dir)
		local rank = window.focus_history_id
		if not rank or rank < 0 then rank = math.huge end
		if distance and (not best_distance or distance < best_distance
			or (distance == best_distance and rank < best_rank)) then
			best, best_distance, best_rank = window, distance, rank
		end
	end
	-- Like bspwm, search ALL monitors' current desktops before monitor fallback.
	-- No preference for the local desktop, tiled state, stacking layer or centre.
	for _, mon in ipairs(monitors) do
		if not mon.is_mirror then
			-- Scratchpads have no bspwm counterpart. Treat an open special
			-- workspace as that monitor's current desktop, without closing it.
			local ws = mon.active_special_workspace or mon.active_workspace
			local st = ws and states[ws.id]
			if st then
				for _, node in ipairs(tree.leaves(st.tree)) do consider(by_id[node.id], ws, mon) end
			end
			-- Floats aren't layout targets; include them in the SAME ranking.
			for _, window in ipairs(windows) do consider(window, ws, mon) end
		end
	end
	if best then
		local result = hl.dispatch(hl.dsp.focus({ window = best }))
		if not result or result.ok ~= false then return end
	end

	-- sxhkd: bspc node -f "$A" || bspc monitor -f "$A". Use the same low-
	-- tightness geometry here too; native directional fallback uses other rules.
	local origin = geometry.monitor_box(monitor)
	if not origin then return end
	local next_monitor, monitor_distance
	for _, mon in ipairs(monitors) do
		local box = not mon.is_mirror and not same_monitor(mon, monitor) and geometry.monitor_box(mon)
		local distance = box and M.distance(origin, box, dir)
		if distance and (not monitor_distance or distance < monitor_distance) then
			next_monitor, monitor_distance = mon, distance
		end
	end
	if next_monitor then hl.dispatch(hl.dsp.focus({ monitor = next_monitor })) end
end

return M
