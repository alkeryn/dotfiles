-- close_refocus.lua -- keep the right monitor focused when a workspace empties
-- ============================================================================
-- Replaces scripts/close_refocus_fix (a socat/sed socket2 watcher that
-- dispatched focusmonitor after the fact, broken by the socket2 event format
-- change). Everything it did is expressible in the Lua event API.
--
-- The bug (v0.56.2, CWindow::onUnmap): when the FOCUSED window closes and its
-- workspace is left empty, no focus candidate is found and
-- InputManager::refocus() picks whatever sits under the cursor -- on a
-- multi-monitor setup that can be a window on another monitor, stealing both
-- keyboard focus and the monitor where new windows open.
--
-- Fix, in two phases (see git history for why close-time pre-emption fails:
-- the workspace round-trip back re-focuses the dying window via
-- workspace->getLastFocusedWindow() and undoes itself):
--   1. window.close records the workspace that just emptied (focused close).
--   2. The cursor fallback's own focus change emits window.active; by then
--      the dying window is unmapped, so a workspace round-trip on the
--      emptied workspace's monitor ends with the keyboard focus cleared:
--      monitor focused, emptied workspace active, nothing focused -- bspwm
--      behavior. New windows open there.
--
-- Only the persistent tag workspaces (1-10, assigned per monitor in
-- rules.lua/helpers.lua) are handled; special workspaces are left to
-- Hyprland's own fallback. For non-empty workspaces the built-in
-- input:focus_on_close applies (2 = focus history, bspwm-like, set in
-- hyprland.lua).
-- ============================================================================

-- TEMPORARY instrumentation: trace decisions to /tmp/close_refocus.log and
-- stdout (hyprctl rollinglogger). Remove once the behavior is confirmed.
local TRACE = false
local function trace(...)
	if not TRACE then return end
	local n = select("#", ...)
	local parts = {}
	for i = 1, n do parts[i] = tostring(select(i, ...)) end
	local line = os.date("%H:%M:%S") .. " " .. table.concat(parts, " ")
	print("[close_refocus] " .. table.concat(parts, " "))
	local ok, f = pcall(io.open, "/tmp/close_refocus.log", "a")
	if ok and f then
		f:write(line .. "\n")
		f:close()
	end
end

local TAG_COUNT = 10

-- { id = ..., mon = "DP-1" } set when a focused close empties a tag workspace
local pending

local function win_str(w)
	if not w then return "nil" end
	return string.format("%s(ws=%s,mon=%s)", tostring(w.stable_id),
		w.workspace and tostring(w.workspace.id) or "?",
		w.monitor and tostring(w.monitor.name) or "?")
end

local function state_str()
	local cur = hl.get_active_workspace()
	if not cur then return "ws=nil" end
	local w = hl.get_active_window()
	return string.format("ws=%s@%s win=%s cursor=%s,%s", tostring(cur.id),
		cur.monitor and cur.monitor.name or "?", win_str(w),
		(select(1, hl.get_cursor_pos())), (select(2, hl.get_cursor_pos())))
end

-- first same-monitor spare workspace, empty ones preferred (an empty spare
-- clears the keyboard focus cleanly instead of focusing its windows briefly)
local function spare_workspace_on(ws_id, mon_name)
	local spare, spare_empty
	for i = 1, TAG_COUNT do
		local cand = hl.get_workspace(tostring(i))
		if cand and cand.id ~= ws_id and cand.monitor and cand.monitor.name == mon_name then
			if not spare then spare = cand end
			if #(cand:get_windows() or {}) == 0 then
				spare_empty = cand
				break
			end
		end
	end
	return spare_empty or spare
end

local function restore(ws_id, mon_name)
	local spare = spare_workspace_on(ws_id, mon_name)
	if not spare then
		trace("restore: no spare on", mon_name, "-- bailing")
		return
	end
	trace("restore: round-trip through", spare.id, "back to", ws_id)
	local r1 = hl.dispatch(hl.dsp.focus({ workspace = tostring(spare.id) }))
	trace("restore: spare dispatch ->", r1 and tostring(r1.ok) or "nil", r1 and r1.error or "")
	local r2 = hl.dispatch(hl.dsp.focus({ workspace = tostring(ws_id) }))
	trace("restore: back dispatch ->", r2 and tostring(r2.ok) or "nil", r2 and r2.error or "")
end

-- Whatever steals focus after the close (destroy-path refocus, mouse
-- re-entry) does so shortly after the restore. A oneshot recheck at a fixed
-- delay either fires too late (visible glitch) or misses the steal entirely,
-- so instead chain short ticks: every RECHECK_INTERVAL_MS, restore if the
-- state drifted, up to RECHECK_MAX_TICKS total (~250ms coverage, matching
-- what empirically fixed it). A tick that finds the state correct is pure
-- bookkeeping, so the correction latency is ~one interval, not the full
-- coverage window.
local RECHECK_INTERVAL_MS = 10
local RECHECK_MAX_TICKS   = 25

local function schedule_recheck(ws_id, mon_name)
	local tick = 0
	local function run()
		tick = tick + 1
		local cur = hl.get_active_workspace()
		if not (cur and cur.id == ws_id and cur.monitor and cur.monitor.name == mon_name) then
			trace("recheck", tick, "/", RECHECK_MAX_TICKS, ": drifted (", state_str(), ") -- restoring")
			restore(ws_id, mon_name)
		end
		if tick < RECHECK_MAX_TICKS then
			hl.timer(run, { timeout = RECHECK_INTERVAL_MS, type = "oneshot" })
		end
	end
	hl.timer(run, { timeout = RECHECK_INTERVAL_MS, type = "oneshot" })
end

hl.on("window.close", function(w)
	trace("close event:", win_str(w))
	if not w or not w.workspace or not w.workspace.monitor then return end

	-- Only matters when the closing window was focused and nothing remains on
	-- its workspace; otherwise Hyprland keeps the current focus on its own
	-- (wasLastWindow stays false, no cursor fallback happens).
	local focused = hl.get_active_window()
	trace("close: focused =", win_str(focused), "match =", focused and focused.stable_id == w.stable_id)
	if not focused or focused.stable_id ~= w.stable_id then return end

	local ws = w.workspace
	if type(ws.id) ~= "number" or ws.id < 1 then
		trace("close: ws", tostring(ws.id), "not a tag workspace -- skip")
		return
	end

	local remaining = 0
	for _, x in ipairs(hl.get_windows() or {}) do
		if x.mapped and x.workspace and x.workspace.id == ws.id
			and x.stable_id ~= w.stable_id then
			remaining = remaining + 1
		end
	end
	trace("close: ws", ws.id, "on", ws.monitor.name, "remaining =", remaining)
	if remaining > 0 then return end

	pending = { id = ws.id, mon = ws.monitor.name }
	trace("close: pending set for ws", ws.id, "@", ws.monitor.name)
	schedule_recheck(ws.id, ws.monitor.name)
end)

-- The fallback's own focus change emits this last; by then the dying window
-- is unmapped and a round-trip can actually clear the focus.
hl.on("window.active", function(w)
	trace("active event: w =", win_str(w), pending and ("pending ws " .. pending.id) or "(no pending)")
	if not pending then return end
	local pend = pending
	pending = nil
	trace("active event: w =", win_str(w), "pending ws", pend.id, "@", pend.mon)

	-- get_active_workspace() is the FOCUSED monitor's active workspace: it
	-- names both the monitor focus landed on and what that monitor shows.
	local cur = hl.get_active_workspace()
	local cur_str = cur and string.format("%s@%s", tostring(cur.id),
		cur.monitor and cur.monitor.name or "?") or "nil"
	trace("active: current =", cur_str, "expected =", pend.id .. "@" .. pend.mon)

	if cur and cur.id == pend.id and cur.monitor and cur.monitor.name == pend.mon then
		trace("active: focus stayed put -- nothing to do")
		return
	end

	trace("active: focus drifted -- restoring")
	restore(pend.id, pend.mon)
end)

trace("loaded")

hl.on("monitor.focused", function(mon)
	trace("monitor.focused:", mon and mon.name or "nil", pending and ("pending ws " .. pending.id) or "")
end)