-- Run from ~/.config/hypr: lua tests/close_refocus_test.lua
-- Loads the actual close_refocus module over a mock hl and models the v0.56.2
-- onUnmap sequence: window.close fires while the dying window is still mapped
-- and focused; Hyprland's cursor-based empty-workspace fallback then focuses
-- some window and emits window.active -- the module must detect the drift
-- there (get_active_workspace = focused monitor's active workspace) and
-- restore with a workspace round-trip.
local tests = {}

local function fixture(windows, active, workspaces, active_ws)
	local f = { focus_calls = {}, timers = {} }
	local focus_dsp
	focus_dsp = function(opts)
		return function()
			f.focus_calls[#f.focus_calls + 1] = opts
			return { ok = true }
		end
	end
	_G.hl = {
		on = function(name, cb)
			if name == "window.close" then f.on_close = cb end
			if name == "window.active" then f.on_active = cb end
			if name == "monitor.focused" then f.on_monitor_focused = cb end
		end,
		dispatch = function(callback) return callback() end,
		get_active_window = function() return active end,
		get_windows = function() return windows end,
		get_workspace = function(sel) return workspaces and workspaces[sel] or nil end,
		get_active_workspace = function() return active_ws end,
		get_cursor_pos = function() return 0, 0 end,
		timer = function(fn, opts)
			f.timers[#f.timers + 1] = { fn = fn, opts = opts }
			return {}
		end,
		dsp = { focus = focus_dsp },
	}
	package.loaded["lua/extensions/close_refocus"] = nil
	require("lua/extensions/close_refocus")
	assert(f.on_close and f.on_active, "module must register window.close and window.active")
	return f
end

local function w(id, ws_id, mapped)
	return {
		stable_id = id,
		mapped = mapped ~= false,
		workspace = { id = ws_id, monitor = { name = (type(ws_id) == "number" and ws_id > 4) and "DP-2" or "DP-1" } },
	}
end

-- tag workspaces 1-10 on two monitors, like helpers.apply_monitor_layout
local function tags()
	return {
		["1"] = { id = 1, monitor = { name = "DP-1" }, get_windows = function() return {} end },
		["2"] = { id = 2, monitor = { name = "DP-1" }, get_windows = function() return {} end },
		["5"] = { id = 5, monitor = { name = "DP-2" }, get_windows = function() return {} end },
		["6"] = { id = 6, monitor = { name = "DP-2" }, get_windows = function() return {} end },
	}
end

function tests.fallback_focus_on_other_monitor_is_restored()
	local closed = w("a", 1)
	local f = fixture({ closed }, closed, tags())
	f.on_close(closed)
	-- the cursor fallback focused a window on DP-2
	local drifted = w("b", 5)
	f.on_active(drifted)
	assert(#f.focus_calls == 2, "expected the round-trip, got " .. #f.focus_calls .. " dispatches")
	assert(f.focus_calls[1].workspace == "2", "must switch to a spare on the emptied workspace's monitor")
	assert(f.focus_calls[2].workspace == "1", "must switch back to the emptied workspace")
end

function tests.fallback_focus_on_same_monitor_wrong_workspace_is_restored()
	local closed = w("a", 1)
	local f = fixture({ closed }, closed, tags())
	f.on_close(closed)
	-- refocus landed on a window that pulled DP-1 to another workspace
	local drifted = w("b", 2)
	f.on_active(drifted)
	assert(#f.focus_calls == 2, "expected the round-trip")
	assert(f.focus_calls[2].workspace == "1", "must switch back to the emptied workspace")
end

function tests.focus_that_stayed_put_is_left_alone()
	local closed = w("a", 1)
	local stayed = { id = 1, monitor = { name = "DP-1" } }
	local f = fixture({ closed }, closed, tags(), stayed)
	f.on_close(closed)
	-- cursor was over dead space on DP-1: no fallback window, monitor unchanged
	f.on_active(closed)
	assert(#f.focus_calls == 0, "correct focus must not be touched")
end

function tests.no_round_trip_when_workspace_still_has_windows()
	local closed = w("a", 1)
	local f = fixture({ closed, w("b", 1) }, closed, tags())
	f.on_close(closed)
	f.on_active(closed)
	assert(#f.focus_calls == 0, "non-empty workspace close must not dispatch anything")
end

function tests.no_round_trip_when_closing_an_unfocused_window()
	local closed = w("a", 1)
	local active = w("b", 2)
	local f = fixture({ closed, active }, active, tags())
	f.on_close(closed)
	f.on_active(active)
	assert(#f.focus_calls == 0, "closing an unfocused window must not dispatch anything")
end

function tests.special_workspaces_are_left_alone()
	local closed = w("a", "special:scratchpad")
	local f = fixture({ closed }, closed, tags())
	f.on_close(closed)
	f.on_active(closed)
	assert(#f.focus_calls == 0, "special workspace close must not dispatch anything")
end

function tests.nil_payload_is_ignored()
	local f = fixture({}, nil, tags())
	f.on_close(nil)
	f.on_active(nil)
	assert(#f.focus_calls == 0, "nil event payload must not dispatch anything")
end

function tests.round_trip_emissions_do_not_recurse()
	local closed = w("a", 1)
	local f = fixture({ closed }, closed, tags())
	f.on_close(closed)
	local drifted = w("b", 5)
	f.on_active(drifted)
	assert(#f.focus_calls == 2, "expected the round-trip")
	-- the round-trip itself emits window.active (focus cleared); with pending
	-- already consumed these must be no-ops
	f.on_active(nil)
	f.on_active(drifted)
	assert(#f.focus_calls == 2, "follow-up window.active events must not dispatch again")
end

function tests.empty_spare_preferred_over_non_empty()
	local workspaces = {
		["1"] = { id = 1, monitor = { name = "DP-1" }, get_windows = function() return {} end },
		["2"] = { id = 2, monitor = { name = "DP-1" }, get_windows = function() return { w("x", 2) } end },
		["3"] = { id = 3, monitor = { name = "DP-1" }, get_windows = function() return {} end },
	}
	local closed = w("a", 1)
	local f = fixture({ closed }, closed, workspaces)
	f.on_close(closed)
	f.on_active(w("b", 5))
	assert(f.focus_calls[1].workspace == "3",
		"must switch through the empty spare, not the non-empty first candidate")
end

function tests.no_spare_on_the_same_monitor_means_no_round_trip()
	local workspaces = {
		["1"] = { id = 1, monitor = { name = "DP-1" }, get_windows = function() return {} end },
		["2"] = { id = 2, monitor = { name = "DP-2" }, get_windows = function() return {} end },
	}
	local closed = w("a", 1)
	local f = fixture({ closed }, closed, workspaces)
	f.on_close(closed)
	f.on_active(w("b", 5))
	assert(#f.focus_calls == 0, "without a same-monitor spare the drift cannot be restored")
end

function tests.recheck_restores_late_steal()
	local closed = w("a", 1)
	local f = fixture({ closed }, closed, tags())
	f.on_close(closed)
	assert(#f.timers == 1 and f.timers[1].opts.timeout == 10, "close must schedule a 10ms recheck tick")
	local drifted = w("b", 5)
	f.on_active(drifted)
	assert(#f.focus_calls == 2, "immediate restore expected")
	-- a destroy-path refocus steals focus back to DP-4 before the next tick
	local late = { id = 5, monitor = { name = "DP-4" } }
	_G.hl.get_active_workspace = function() return late end
	f.timers[1].fn()
	assert(#f.focus_calls == 4, "recheck must restore the drifted state again")
	assert(f.focus_calls[4].workspace == "1", "recheck round-trip must end on the emptied workspace")
	assert(#f.timers == 2, "a drifted tick must chain the next one")
	-- ticks that find the state held keep the coverage alive without dispatching
	_G.hl.get_active_workspace = function() return { id = 1, monitor = { name = "DP-1" } } end
	f.timers[2].fn()
	assert(#f.focus_calls == 4, "stable tick must not dispatch")
	assert(#f.timers == 3, "stable ticks keep the coverage alive")
end

function tests.recheck_coverage_is_bounded()
	local closed = w("a", 1)
	local held = { id = 1, monitor = { name = "DP-1" } }
	local f = fixture({ closed }, closed, tags(), held)
	f.on_close(closed)
	for _ = 1, 24 do f.timers[#f.timers].fn() end -- 25 ticks total
	assert(#f.timers == 25, "chain must cover exactly " .. 25 .. " ticks")
	local before = #f.timers
	f.timers[#f.timers].fn() -- the last tick must not chain further
	assert(#f.timers == before, "coverage must stop after the last tick")
	assert(#f.focus_calls == 0, "stable coverage must never dispatch")
end

local names = {}
for name in pairs(tests) do names[#names + 1] = name end
table.sort(names)
local failures = 0
for _, name in ipairs(names) do
	local ok, err = pcall(tests[name])
	if ok then print("PASS " .. name)
	else failures = failures + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
print(string.format("%d/%d tests passed", #names - failures, #names))
os.exit(failures == 0 and 0 or 1)