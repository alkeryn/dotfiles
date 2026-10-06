-- helpers.lua -- shared helper functions (focus, swap, gaps, monitors)
-- ============================================================================
-- Module: returns the helpers table. Requires lua/vars.
-- ============================================================================

-- NOTE: module paths are relative to the main config dir; modules in lua/
-- are required as "lua/<name>" (see bindings.lua)
local vars = require("lua/vars")

local H = {}

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
	if t then hl.dsp.focus({ window = t })() end
end

function H.focus_last()
	local w = hl.get_last_window()
	if w then hl.dsp.focus({ window = w })() end
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

local bspwm = require("bspwm")

function H.swap_dir(d) -- d: l | r | u | d
	if bspwm.has_neighbor(d) then
		hl.dsp.layout("swap " .. d)()
		return
	end
	local mon = hl.get_monitor(d) -- relative to the focused monitor; nil if none
	if mon then hl.dsp.window.move({ monitor = mon, follow = true })() end
end

-- ---------------------------------------------------------------------------
-- workspace swap helpers (bspc desktop -s)
-- ---------------------------------------------------------------------------

function H.swap_with_workspace(sel)
	local cur = hl.get_active_workspace()
	local tgt = hl.get_workspace(sel)
	if not cur or not tgt or cur.id == tgt.id then return end
	-- snapshot BOTH lists before moving anything, otherwise the second loop
	-- would also move the windows we just moved over
	local from_tgt = tgt:get_windows()
	local from_cur = cur:get_windows()
	for _, w in ipairs(from_tgt) do
		hl.dsp.window.move({ workspace = cur.id, follow = false, window = w })()
	end
	for _, w in ipairs(from_cur) do
		hl.dsp.window.move({ workspace = tgt.id, follow = false, window = w })()
	end
end

function H.swap_workspace_rel(rel)
	local cur = hl.get_active_workspace()
	if cur then H.swap_with_workspace(cur.id + rel) end
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
