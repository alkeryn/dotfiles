-- helpers.lua -- shared helper functions (window state, focus, swap, resize, gaps, monitors)
-- ============================================================================
-- Module: returns the helpers table. Requires lua/vars.
-- ============================================================================

-- NOTE: module paths are relative to the main config dir; modules in lua/
-- are required as "lua/<name>" (see bindings.lua)
local vars = require("lua/vars")

local H = {}

-- ---------------------------------------------------------------------------
-- explicit window states (bspc node -t), never toggles
-- ---------------------------------------------------------------------------

function H.set_window_state(state)
	local w = hl.get_active_window()
	if not w or w.mapped == false then return end

	local fullscreen = state == "fullscreen"
	-- Clear both compositor and client fullscreen/maximized modes before
	-- changing float state: Hyprland otherwise restores fullscreen afterward.
	-- Don't leave/re-enter fullscreen on repeated Super+f.
	if not fullscreen or w.floating then
		hl.dispatch(hl.dsp.window.fullscreen_state({
			internal = 0, client = 0, action = "set", layout_aware = false, window = w,
		}))
	end
	hl.dispatch(hl.dsp.window.pseudo({ action = state == "pseudo_tiled" and "on" or "off", window = w }))
	hl.dispatch(hl.dsp.window.float({ action = state == "floating" and "on" or "off", window = w }))
	if fullscreen then
		-- fullscreen_state uses 2 for full fullscreen (1 is maximized).
		hl.dispatch(hl.dsp.window.fullscreen_state({
			internal = 2, client = 2, action = "set", layout_aware = false, window = w,
		}))
	end
end

-- ---------------------------------------------------------------------------
-- focus history (super + {parenright,equal} -> older/newer)
-- ---------------------------------------------------------------------------

function H.focus_history(step)
	local wins = hl.get_windows() or {}
	if #wins < 2 then return end
	table.sort(wins, function(a, b)
		return (a.focus_history_id or 0) < (b.focus_history_id or 0)
	end)
	local cur = hl.get_active_window()
	local idx
	for i, w in ipairs(wins) do
		if cur and w.address == cur.address then idx = i break end
	end
	if not idx then return end
	local t = wins[((idx - 1 + step) % #wins) + 1]
	if t then hl.dispatch(hl.dsp.focus({ window = t })) end
end

function H.focus_last()
	local w = hl.get_last_window()
	if w then hl.dispatch(hl.dsp.focus({ window = w })) end
end

-- ---------------------------------------------------------------------------
-- swap with bspwm-style fallback
-- ---------------------------------------------------------------------------
-- Focus needs no helper: hl.dsp.focus({ direction = ... }) already falls back
-- to the neighbouring monitor (binds:window_direction_monitor_fallback, on by
-- default), which is `bspc node -f $A || bspc monitor -f $A`.
--
-- Swap: `bspc node -s $A --follow || bspc node -d $A:focused --follow`, i.e. swap
-- with the tree neighbour, or else send the window to the monitor in that
-- direction. A layout rejecting a message is reported as an ERROR (on-screen
-- overlay), so we ask the layout whether a neighbour exists instead of using
-- failure as control flow.

local bspwm = require("lua/extensions/bspwm")

function H.swap_dir(d) -- d: l | r | u | d
	if bspwm.has_neighbor(d) then
		hl.dispatch(hl.dsp.layout("swap " .. d))
		return
	end
	local mon = hl.get_monitor(d) -- relative to the focused monitor; nil if none
	if mon and mon.active_workspace then H.move_to_workspace(mon.active_workspace) end
end

-- ---------------------------------------------------------------------------
-- edge resize (bspc node -z): delta > 0 grows, delta < 0 shrinks
-- ---------------------------------------------------------------------------

function H.resize_edge(edge, delta)
	local w = hl.get_active_window()
	if not w or w.mapped == false or (w.fullscreen or 0) ~= 0 then return end

	if not w.floating then
		local cmd = delta >= 0 and "grow" or "shrink"
		hl.dispatch(hl.dsp.layout(cmd .. " " .. edge .. " " .. math.abs(delta)))
		return
	end

	-- Floating windows are not in the tiled layout; a layout message would
	-- do nothing or resize an unrelated tiled window on the same workspace.
	local pos, size = w.at, w.size
	local horizontal = edge == "l" or edge == "r"
	local result = hl.dispatch(hl.dsp.window.resize({
		x = math.max(1, size.x + (horizontal and delta or 0)),
		y = math.max(1, size.y + (horizontal and 0 or delta)),
		relative = false,
		window = w,
	}))
	if result and result.ok == false then return end

	-- Hyprland v0.56.2 resizes floats around their CENTER. Restore the old
	-- top-left for right/bottom resizes; shift it for left/top resizes so the
	-- opposite edge stays fixed. Read back goal size (not animated geometry),
	-- rather than assuming the requested size change was applied in full.
	local resized = w.size
	hl.dispatch(hl.dsp.window.move({
		x = pos.x + (edge == "l" and size.x - resized.x or 0),
		y = pos.y + (edge == "u" and size.y - resized.y or 0),
		relative = false,
		window = w,
	}))
end

-- ---------------------------------------------------------------------------
-- workspace send/swap helpers (bspc node -d / desktop -s)
-- ---------------------------------------------------------------------------

function H.move_to_workspace(sel)
	local result = bspwm.move_to_workspace(sel)
	if result ~= true then print(tostring(result)) end
end

function H.move_workspace_rel(rel)
	local target = H.relative_workspace(rel)
	if target then H.move_to_workspace(target) end
end

function H.swap_with_workspace(sel)
	local cur = hl.get_active_workspace()
	local tgt = hl.get_workspace(sel)
	if not cur or not tgt or cur.id == tgt.id then return end
	-- bspwm `desktop -s --follow` swaps the desktop OBJECTS (windows travel
	-- with them) and then focus follows the focused desktop
	-- (swap_desktops(): focus_node(m2, d1, d1->focus)): after the swap you
	-- are looking at your own windows, on the target's slot/monitor. The
	-- focused window belongs to the outgoing desktop, so re-focus it once
	-- it has landed on the target workspace.
	local focused = hl.get_active_window()
	local result = bspwm.swap_workspaces(cur, tgt)
	if result ~= true then
		print(tostring(result))
		return
	end
	local selector = tgt.id > 0 and tgt.id or "name:" .. tgt.name
	if focused and focused.workspace and focused.workspace.id == tgt.id then
		local result = hl.dispatch(hl.dsp.focus({ window = focused }))
		if not result or result.ok == false then
			hl.dispatch(hl.dsp.focus({ workspace = selector }))
		end
	else
		hl.dispatch(hl.dsp.focus({ workspace = selector }))
	end
end

function H.relative_workspace(rel)
	local cur = hl.get_active_workspace()
	if not cur or not cur.monitor or cur.special then return end
	-- Workspace IDs are global, not monitor-relative. Include empty persistent
	-- desktops, sort the actual slots on this monitor and wrap at either end.
	local workspaces = {}
	for _, ws in ipairs(hl.get_workspaces() or {}) do
		if not ws.special and ws.monitor and ws.monitor.name == cur.monitor.name then
			workspaces[#workspaces + 1] = ws
		end
	end
	table.sort(workspaces, function(a, b) return a.id < b.id end)
	for i, ws in ipairs(workspaces) do
		if ws.id == cur.id then
			return workspaces[((i - 1 + rel) % #workspaces) + 1]
		end
	end
end

function H.swap_workspace_rel(rel)
	local target = H.relative_workspace(rel)
	if target then H.swap_with_workspace(target) end
end

-- ---------------------------------------------------------------------------
-- gap presets (bspc config -d focused window_gap)
-- ---------------------------------------------------------------------------
-- bspwm: Next/Prior = current gap +/- 5, BackSpace = default, shift+BackSpace = 0.
-- Hyprland gaps are global here (per-workspace gaps would need workspace-rule
-- churn); the current value is tracked in this module. A config reload
-- re-evaluates the modules, which also resets this state to the configured gaps.

local gaps = { inner = vars.GAPS, outer = vars.GAPS_OUT }

local function apply_gaps()
	hl.config({ general = { gaps_in = gaps.inner, gaps_out = gaps.outer } })
end

function H.adjust_gaps(delta)
	gaps.inner = math.max(0, gaps.inner + delta)
	gaps.outer = math.max(0, gaps.outer + delta)
	apply_gaps()
end

function H.reset_gaps()
	gaps.inner, gaps.outer = vars.GAPS, vars.GAPS_OUT
	apply_gaps()
end

function H.zero_gaps()
	gaps.inner, gaps.outer = 0, 0
	apply_gaps()
end

-- ---------------------------------------------------------------------------
-- monitor layout (replaces bspwmrc's `bspc monitor ^1/^2 -d ...` + xrandr dock test)
-- ---------------------------------------------------------------------------
-- The config is loaded BEFORE the backend starts, so hl.get_monitors() is empty
-- on first load; callers re-run these from hl.on("monitor.added"/"monitor.removed").
-- monitor.removed fires while the monitor is still listed, hence `exclude`.

local function connected(exclude)
	local names = {}
	for _, m in ipairs(hl.get_monitors() or {}) do
		if not (exclude and m.name == exclude.name) then names[#names + 1] = m.name end
	end
	return names
end

-- bspwmrc: `xrandr | grep -c " connected"` -gt 1 (always true on mainpc)
function H.is_docked(exclude)
	return vars.PC == "mainpc" or #connected(exclude) > 1
end

-- tags 1-4 on the first monitor, 5-10 on the second (all on one when undocked)
function H.apply_monitor_layout(exclude)
	local first, second
	if vars.PC == "mainpc" then
		first, second = vars.M1, vars.M2 -- pinned by output name
	else
		local names = connected(exclude)
		first, second = names[1], names[2]
	end
	if not first then return end -- no monitors known yet
	for i = 1, 10 do
		hl.workspace_rule({
			workspace  = tostring(i),
			monitor    = (second and i > 4) and second or first,
			persistent = true,
		})
	end
end

return H
