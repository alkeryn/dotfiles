-- Shared window, focus, workspace, gap and monitor helpers.
-- Module paths resolve against the main config directory, not lua/.
local vars = require("lua/vars")
local M = {}

-- ---------------------------------------------------------------------------
-- Explicit window states (bspc node -t), never toggles
-- ---------------------------------------------------------------------------

function M.set_window_state(state)
	local window = hl.get_active_window()
	if not window or window.mapped == false then return end

	local fullscreen = state == "fullscreen"
	-- Clear compositor AND client fullscreen/maximized modes before changing
	-- float state, or Hyprland restores fullscreen. Repeated Super+f must not
	-- leave/re-enter fullscreen unless the window is floating.
	if not fullscreen or window.floating then
		hl.dispatch(hl.dsp.window.fullscreen_state({
			internal = 0, client = 0, action = "set", layout_aware = false, window = window,
		}))
	end
	hl.dispatch(hl.dsp.window.pseudo({ action = state == "pseudo_tiled" and "on" or "off", window = window }))
	hl.dispatch(hl.dsp.window.float({ action = state == "floating" and "on" or "off", window = window }))
	if fullscreen then
		-- fullscreen_state: 2 = full fullscreen, 1 = maximized.
		hl.dispatch(hl.dsp.window.fullscreen_state({
			internal = 2, client = 2, action = "set", layout_aware = false, window = window,
		}))
	end
end

-- ---------------------------------------------------------------------------
-- Focus history
-- ---------------------------------------------------------------------------

function M.focus_history(step)
	local windows = hl.get_windows() or {}
	if #windows < 2 then return end
	table.sort(windows, function(a, b)
		return (a.focus_history_id or 0) < (b.focus_history_id or 0)
	end)
	local current = hl.get_active_window()
	local index
	for i, window in ipairs(windows) do
		if current and window.address == current.address then
			index = i
			break
		end
	end
	if not index then return end
	local target = windows[((index - 1 + step) % #windows) + 1]
	if target then hl.dispatch(hl.dsp.focus({ window = target })) end
end

function M.focus_last()
	local window = hl.get_last_window()
	if window then hl.dispatch(hl.dsp.focus({ window = window })) end
end

-- ---------------------------------------------------------------------------
-- Directional focus/swap with monitor fallback
-- ---------------------------------------------------------------------------
local bspwm = require("lua/extensions/bspwm")

function M.focus_dir(direction) -- l | r | u | d
	bspwm.focus_dir(direction)
end

-- Swap needs the selected node's OUTER box: its own children must not hide the
-- monitor fallback. Query first; a rejected layout message would otherwise
-- produce an on-screen error overlay.

function M.swap_dir(direction) -- l | r | u | d
	if bspwm.has_neighbor(direction) then
		hl.dispatch(hl.dsp.layout("swap " .. direction))
		return
	end
	local monitor = hl.get_monitor(direction)
	if monitor and monitor.active_workspace then M.move_to_workspace(monitor.active_workspace) end
end

-- ---------------------------------------------------------------------------
-- Edge resize: positive delta grows, negative delta shrinks
-- ---------------------------------------------------------------------------

function M.resize_edge(edge, delta)
	local window = hl.get_active_window()
	if not window or window.mapped == false or (window.fullscreen or 0) ~= 0 then return end

	if not window.floating then
		local command = delta >= 0 and "grow" or "shrink"
		hl.dispatch(hl.dsp.layout(command .. " " .. edge .. " " .. math.abs(delta)))
		return
	end

	-- Floats aren't layout targets; a layout message could resize an unrelated
	-- tile. Resize the original window, even if dispatch changes keyboard focus.
	local position, size = window.at, window.size
	local horizontal = edge == "l" or edge == "r"
	local result = hl.dispatch(hl.dsp.window.resize({
		x = math.max(1, size.x + (horizontal and delta or 0)),
		y = math.max(1, size.y + (horizontal and 0 or delta)),
		relative = false,
		window = window,
	}))
	if result and result.ok == false then return end

	-- Hyprland v0.56.2 resizes floats around their centre. Read back goal size
	-- (constraints may limit the requested change), then keep the opposite edge
	-- fixed: shift the origin for left/top, restore it for right/bottom.
	local resized = window.size
	hl.dispatch(hl.dsp.window.move({
		x = position.x + (edge == "l" and size.x - resized.x or 0),
		y = position.y + (edge == "u" and size.y - resized.y or 0),
		relative = false,
		window = window,
	}))
end

-- ---------------------------------------------------------------------------
-- Workspace sends/swaps (bspc node -d / desktop -s)
-- ---------------------------------------------------------------------------

function M.move_to_workspace(selector)
	local result = bspwm.move_to_workspace(selector)
	if result ~= true then print(tostring(result)) end
end

function M.move_workspace_rel(step)
	local target = M.relative_workspace(step)
	if target then M.move_to_workspace(target) end
end

function M.swap_with_workspace(selector)
	local current = hl.get_active_workspace()
	local target = hl.get_workspace(selector)
	if not current or not target or current.id == target.id then return end
	-- bspwm swaps desktop objects: their windows travel with them, then focus
	-- follows the outgoing desktop. Re-focus its window in the destination slot.
	local focused = hl.get_active_window()
	local result = bspwm.swap_workspaces(current, target)
	if result ~= true then
		print(tostring(result))
		return
	end
	local destination = target.id > 0 and target.id or "name:" .. target.name
	if focused and focused.workspace and focused.workspace.id == target.id then
		local focus_result = hl.dispatch(hl.dsp.focus({ window = focused }))
		if focus_result and focus_result.ok ~= false then return end
	end
	hl.dispatch(hl.dsp.focus({ workspace = destination }))
end

function M.relative_workspace(step)
	local current = hl.get_active_workspace()
	if not current or not current.monitor or current.special then return end
	-- IDs are global, not monitor-relative. Include empty persistent desktops,
	-- sort this monitor's actual slots and wrap at either end.
	local workspaces = {}
	for _, workspace in ipairs(hl.get_workspaces() or {}) do
		if not workspace.special and workspace.monitor and workspace.monitor.name == current.monitor.name then
			workspaces[#workspaces + 1] = workspace
		end
	end
	table.sort(workspaces, function(a, b) return a.id < b.id end)
	for i, workspace in ipairs(workspaces) do
		if workspace.id == current.id then
			return workspaces[((i - 1 + step) % #workspaces) + 1]
		end
	end
end

function M.swap_workspace_rel(step)
	local target = M.relative_workspace(step)
	if target then M.swap_with_workspace(target) end
end

-- ---------------------------------------------------------------------------
-- Gap presets
-- ---------------------------------------------------------------------------
-- Gaps are global here; per-workspace gaps would require workspace-rule churn.
-- Reloading re-evaluates the module and resets the tracked values to defaults.
local gaps = { inner = vars.GAPS, outer = vars.GAPS_OUT }

local function apply_gaps()
	hl.config({ general = { gaps_in = gaps.inner, gaps_out = gaps.outer } })
end

function M.adjust_gaps(delta)
	gaps.inner = math.max(0, gaps.inner + delta)
	gaps.outer = math.max(0, gaps.outer + delta)
	apply_gaps()
end

function M.reset_gaps()
	gaps.inner, gaps.outer = vars.GAPS, vars.GAPS_OUT
	apply_gaps()
end

function M.zero_gaps()
	gaps.inner, gaps.outer = 0, 0
	apply_gaps()
end

-- ---------------------------------------------------------------------------
-- Monitor layout
-- ---------------------------------------------------------------------------
-- Initial config loads before the backend, so get_monitors() is empty. Callers
-- retry on monitor.added/removed; removal fires while the monitor is still
-- listed, hence the exclusion parameter.
local function connected_monitors(exclude)
	local names = {}
	for _, monitor in ipairs(hl.get_monitors() or {}) do
		if not (exclude and monitor.name == exclude.name) then names[#names + 1] = monitor.name end
	end
	return names
end

function M.is_docked(exclude)
	return vars.PC == "mainpc" or #connected_monitors(exclude) > 1
end

-- Tags 1-4 on the first monitor, 5-10 on the second; all on one when undocked.
function M.apply_monitor_layout(exclude)
	local first, second
	if vars.PC == "mainpc" then
		first, second = vars.M1, vars.M2 -- pinned by output name
	else
		local names = connected_monitors(exclude)
		first, second = names[1], names[2]
	end
	if not first then return end
	for i = 1, 10 do
		hl.workspace_rule({
			workspace = tostring(i),
			monitor = (second and i > 4) and second or first,
			persistent = true,
		})
	end
end

return M
