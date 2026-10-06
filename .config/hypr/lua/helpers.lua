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
	local wins = hl.query.get_windows() or {}
	if #wins < 2 then return end
	table.sort(wins, function(a, b)
		return (a.focus_history_id or 0) < (b.focus_history_id or 0)
	end)
	local cur = hl.query.get_active_window()
	local idx
	for i, w in ipairs(wins) do
		if cur and w.address == cur.address then idx = i break end
	end
	if not idx then return end
	local t = wins[((idx - 1 + step) % #wins) + 1]
	if t then hl.dsp.focus({ window = "address:" .. t.address })() end
end

function H.focus_last()
	local w = hl.query.get_last_window()
	if w then hl.dsp.focus({ window = "address:" .. w.address })() end
end

-- ---------------------------------------------------------------------------
-- focus / swap with bspwm-style fallbacks
-- ---------------------------------------------------------------------------

local DIRFULL = { l = "left", r = "right", u = "up", d = "down" }

function H.focus_dir(d)
	local ok = hl.dsp.focus({ direction = DIRFULL[d] })()
	if not ok then hl.dsp.focus({ monitor = d })() end
end

function H.swap_dir(d)
	-- bspc node -s "$A" --follow (tree-aware swap in the bspwm layout);
	-- fallback: bspc node -d "$A":focused --follow
	local ok = hl.dsp.layout("swap " .. d)()
	if not ok then
		if d == "l" then hl.dsp.window.move({ workspace = "m-1" })()
		elseif d == "r" then hl.dsp.window.move({ workspace = "m+1" })() end
	end
end

-- ---------------------------------------------------------------------------
-- workspace swap helpers (bspc desktop -s)
-- ---------------------------------------------------------------------------

function H.swap_with_workspace(sel)
	local cur = hl.query.get_active_workspace()
	local tgt = hl.query.get_workspace(sel)
	if not cur or not tgt or cur.id == tgt.id then return end
	for _, w in ipairs(tgt.windows or {}) do
		hl.dsp.window.move({ workspace = cur.id, follow = false, window = "address:" .. w.address })()
	end
	for _, w in ipairs(cur.windows or {}) do
		hl.dsp.window.move({ workspace = tgt.id, follow = false, window = "address:" .. w.address })()
	end
end

function H.swap_workspace_rel(rel)
	local cur = hl.query.get_active_workspace()
	if cur then H.swap_with_workspace(cur.id + rel) end
end

-- ---------------------------------------------------------------------------
-- gap presets (bspc config -d focused window_gap)
-- ---------------------------------------------------------------------------
-- Hyprland gaps are global here (Next/Prior adjust, BackSpace resets to 0,
-- shift+BackSpace restores the default). Per-workspace gaps are possible via
-- hl.workspace_rule({ workspace = "N", gaps_in = X }) at runtime, at the cost
-- of rule churn; global was chosen for predictability.

function H.set_gaps(v)
	hl.config({ general = { gaps_in = v, gaps_out = v } })
end

-- ---------------------------------------------------------------------------
-- monitor layout (docked laptop detection, replaces the xrandr branch)
-- ---------------------------------------------------------------------------

function H.apply_monitor_layout()
	local mons = hl.query.get_monitors() or {}
	if vars.PC == "mainpc" or #mons > 1 then
		-- docked: 1-4 on primary, 5-10 on secondary
		for i = 1, 4 do
			hl.workspace_rule({ workspace = tostring(i), monitor = vars.M1, persistent = true })
		end
		for i = 5, 10 do
			hl.workspace_rule({ workspace = tostring(i), monitor = vars.M2, persistent = true })
		end
	elseif vars.PC == "laptop" then
		for i = 1, 10 do
			hl.workspace_rule({ workspace = tostring(i), monitor = #mons > 0 and mons[1].name or "", persistent = true })
		end
	end
end

return H
