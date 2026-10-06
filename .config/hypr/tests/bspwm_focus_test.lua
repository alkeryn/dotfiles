-- lua tests/bspwm_focus_test.lua -- real bindings/provider, mocked native handles.
local focus = require("lua/extensions/bspwm_focus")
local tests = {}
package.loaded["lua/vars"] = { FLOAT_STEP = 20, terminal = "alacritty", GAPS = 4, GAPS_OUT = 8 }
package.loaded["lua/extensions/bspwm_state"] = { open_session = function() return nil end }

local function fixture()
	local f = { windows = {}, monitors = {}, binds = {}, events = {}, calls = {}, contexts = {} }
	local provider
	local function noop() return function() return { ok = true } end end
	local function handle() return { set_enabled = function() end } end
	function f.emit(event, ...)
		for _, callback in ipairs(f.events[event] or {}) do callback(...) end
	end
	function f.monitor(x, y, width, height)
		local id = #f.monitors + 1
		local mon = { id = id, name = "monitor-" .. id, position = { x = x, y = y },
			width = width, height = height, scale = 1 }
		mon.active_workspace = { id = id, monitor = mon, tiled_layout = "lua:bspwm", visible = true }
		f.monitors[id] = mon
		return mon
	end
	function f.add(x, y, width, height, floating, workspace)
		local id = #f.windows + 1
		local ws = workspace or f.monitors[1].active_workspace
		local w = { stable_id = id, at = { x = x, y = y }, size = { x = width, y = height },
			mapped = true, hidden = false, floating = floating or false, fullscreen = 0,
			focus_history_id = -1, workspace = ws, monitor = ws.monitor, tags = {} }
		f.windows[id] = w
		return w
	end
	function f.focus(w)
		for _, window in ipairs(f.windows) do
			window.active = window == w
			if window == w then window.focus_history_id = 0
			elseif window.focus_history_id >= 0 then window.focus_history_id = window.focus_history_id + 1 end
		end
		f.active, f.active_monitor = w, w and w.monitor or f.active_monitor
		f.emit("window.active", w)
	end
	function f.tile()
		local w = f.add(0, 0, 1, 1)
		local ctx = f.contexts[1]
		local target = { window = w }
		function target:place(box)
			w.at, w.size = { x = box.x, y = box.y }, { x = box.w, y = box.h }
		end
		ctx.targets[#ctx.targets + 1] = target
		provider.recalculate(ctx)
		f.focus(w)
		return w
	end
	function f.press(key)
		local binding = assert(f.binds["SUPER + " .. key])
		assert(binding.opts.repeating, "directional focus lost key repeat")
		binding.callback()
	end
	f.active_monitor = f.monitor(0, 0, 1000, 800)
	f.contexts[1] = { area = { x = 0, y = 0, w = 1000, h = 800 }, targets = {} }
	_G.hl = {
		layout = { register = function(name, impl) if name == "bspwm" then provider = impl end end },
		on = function(event, callback)
			f.events[event] = f.events[event] or {}
			table.insert(f.events[event], callback)
		end,
		window_rule = handle, workspace_rule = handle,
		get_active_window = function() return f.active end,
		get_active_workspace = function() return f.active_monitor.active_workspace end,
		get_active_monitor = function() return f.active_monitor end,
		get_windows = function() return f.windows end,
		get_monitors = function() return f.monitors end,
		bind = function(keys, callback, opts)
			local binding = handle()
			binding.callback, binding.opts = callback, opts
			f.binds[keys] = binding
			return binding
		end,
		dispatch = function(dispatcher) return dispatcher() end,
		dsp = setmetatable({
			focus = function(opts) return function()
				assert(not opts.direction, "must not fall through to native movefocus")
				f.calls[#f.calls + 1] = opts
				if opts.window then
					if f.reject_focus then return { ok = false } end
					f.focus(opts.window)
				else
					f.active_monitor = assert(opts.monitor)
					f.focus(nil)
					f.emit("monitor.focused", opts.monitor)
				end
				return { ok = true }
			end end,
			layout = function(message) return function()
				assert(provider.layout_msg(f.contexts[1], message) == true)
				provider.recalculate(f.contexts[1])
				return { ok = true }
			end end,
			window = setmetatable({ tag = function(opts) return function()
				opts.window.tags[opts.tag:sub(2)] = opts.tag:sub(1, 1) == "+" or nil
				return { ok = true }
			end end }, { __index = function() return noop end }),
		}, { __index = function() return noop end }),
	}
	f.api = dofile("lua/extensions/bspwm.lua")
	f.api.set_feedback_sink(function(states) f.states = states end)
	package.loaded["lua/extensions/bspwm"] = f.api
	package.loaded["lua/helpers"], package.loaded["lua/bindings"] = nil, nil
	require("lua/bindings")
	return f
end

function tests.contained_float_and_tile_are_reachable_in_every_direction()
	for _, key in ipairs({ "h", "j", "k", "l" }) do
		local f = fixture()
		local tile = f.add(0, 0, 500, 500)
		local float = f.add(150, 150, 100, 100, true)
		f.focus(tile); f.press(key)
		assert(f.active == float, "tile -> contained float failed: " .. key)
		f.press(key)
		assert(f.active == tile, "contained float -> tile failed: " .. key)
	end
end

function tests.all_four_bindings_use_the_right_direction()
	local positions = { h = { -200, 0 }, j = { 0, 200 }, k = { 0, -200 }, l = { 200, 0 } }
	for key, pos in pairs(positions) do
		for _, floating in ipairs({ false, true }) do
			local f = fixture()
			local source = f.add(0, 0, 100, 100, floating)
			local target = f.add(pos[1], pos[2], 100, 100, not floating)
			f.focus(source); f.press(key)
			assert(f.active == target)
		end
	end
end

function tests.distance_precedes_history_and_does_not_prefer_a_layer()
	for _, floating in ipairs({ false, true }) do
		local f = fixture()
		local source = f.add(0, 0, 100, 100)
		local near = f.add(105, 0, 100, 100, floating)
		local far = f.add(150, 0, 100, 100, not floating)
		f.focus(near); f.focus(far); f.focus(source); f.press("l")
		assert(f.active == near)
	end
end

function tests.overlap_is_ranked_by_absolute_facing_edge_distance_not_centres()
	local f = fixture()
	local source = f.add(0, 0, 100, 100)
	local overlap = f.add(80, 0, 20, 100, true) -- right-facing distance 19
	local outside = f.add(105, 0, 500, 100) -- distance 6, despite a much farther centre
	f.focus(overlap); f.focus(source); f.press("l")
	assert(f.active == outside)
end

function tests.equal_distance_uses_recent_history_and_unranked_is_last()
	local f = fixture()
	local source = f.add(0, 0, 100, 100)
	local a = f.add(100, 0, 100, 45)
	local b = f.add(100, 50, 100, 45, true)
	f.focus(b); f.focus(source); f.press("l")
	assert(f.active == b, "-1 must not beat a recorded focus rank")
	f.focus(a); f.focus(source); f.press("l")
	assert(f.active == a)
end

function tests.diagonal_or_opposite_windows_do_not_cause_a_wrap()
	local f = fixture()
	local source = f.add(0, 0, 100, 100)
	f.add(100, 100, 100, 100, true)
	f.add(-100, 0, 100, 100)
	f.focus(source); f.press("l")
	assert(f.active == source and #f.calls == 0)
end

function tests.searches_all_current_desktops_before_fallback_without_local_preference()
	local f = fixture()
	local other = f.monitor(1000, 0, 1000, 800)
	local source = f.add(900, 0, 100, 100)
	f.add(950, 0, 100, 100, true) -- local distance 49
	local remote = f.add(1000, 0, 100, 100, false, other.active_workspace) -- distance 1
	f.focus(source); f.press("l")
	assert(f.active == remote and #f.calls == 1 and f.calls[1].window == remote)
end

function tests.hidden_unmapped_and_inactive_desktop_windows_are_excluded()
	local f = fixture()
	local source = f.add(0, 0, 100, 100)
	f.add(100, 0, 100, 100, true).hidden = true
	f.add(100, 0, 100, 100, true).mapped = false
	local inactive = { id = 9, monitor = f.active_monitor, visible = true }
	f.add(100, 0, 100, 100, true, inactive)
	local target = f.add(120, 0, 100, 100)
	-- Alpha/occlusion is NOT bspwm's hidden flag (e.g. monocle/fullscreen).
	target.visible, target.accepts_input = false, false
	f.focus(source); f.press("l")
	assert(f.active == target)
end

function tests.empty_monitor_fallback_and_no_diagonal_monitor_wrap()
	local f = fixture()
	local right = f.monitor(1000, 0, 1000, 800)
	f.monitor(2000, 800, 1000, 800)
	f.focus(f.add(0, 0, 100, 100)); f.press("l")
	assert(f.active_monitor == right and f.calls[1].monitor == right)
	f.press("l")
	assert(#f.calls == 1, "must not jump diagonally or wrap from an empty desktop")
end

function tests.empty_source_searches_from_monitor_rectangle()
	local f = fixture()
	local mon = f.monitor(1000, 0, 1000, 800)
	local target = f.add(1000, 50, 100, 100, true, mon.active_workspace)
	f.press("l")
	assert(f.active == target and f.calls[1].window == target)
end

function tests.monitor_fallback_uses_monitor_range_not_the_small_window_range()
	local f = fixture()
	local right = f.monitor(1000, 0, 1000, 800)
	f.add(1000, 500, 100, 100, false, right.active_workspace)
	f.focus(f.add(0, 0, 100, 100)); f.press("l")
	assert(f.calls[1].monitor == right)
end

function tests.failed_window_focus_uses_the_sxhkd_monitor_fallback()
	local f = fixture()
	local right = f.monitor(1000, 0, 1000, 800)
	local source = f.add(0, 0, 100, 100)
	local target = f.add(100, 0, 100, 100, true)
	f.focus(source); f.reject_focus = true; f.press("l")
	assert(f.calls[1].window == target and f.calls[2].monitor == right)
end

function tests.selected_parent_excludes_descendants_and_clears_tags_on_float_focus()
	local f = fixture()
	local a, b, c = f.tile(), f.tile(), f.tile()
	-- right-hand subtree = b/c; its left edge is x=500.
	f.focus(c); f.press("b")
	local selected = assert(f.states[1].selected)
	assert(selected.t == "split" and b.tags.bspwm_selected and c.tags.bspwm_selected)
	-- The float's rightmost pixel is exactly the subtree's left edge (0
	-- distance, vs a's distance 1). It doesn't overlap representative c's
	-- vertical range: searching from c instead of its parent would miss it.
	local float = f.add(491, 100, 10, 100, true)
	f.press("h")
	assert(f.active == float and not f.states[1].selected)
	assert(not b.tags.bspwm_selected and not c.tags.bspwm_selected and not a.tags.bspwm_selected)
end

function tests.selected_root_does_not_focus_its_own_children()
	local f = fixture()
	f.tile(); f.tile(); f.press("b")
	local calls = #f.calls
	for _, key in ipairs({ "h", "j", "k", "l" }) do f.press(key) end
	assert(#f.calls == calls and f.states[1].selected)
end

function tests.monocle_and_fullscreen_do_not_force_native_focus_cycling()
	local f = fixture()
	local a, b = f.tile(), f.tile()
	f.press("v")
	local float = f.add(900, 100, 50, 100, true)
	f.focus(a); f.press("l")
	assert(f.active == float)
	f.focus(b); b.fullscreen = 2; f.press("l")
	assert(f.active == float)
end

function tests.pinned_float_on_an_inactive_desktop_is_still_a_candidate()
	local f = fixture()
	local source = f.add(0, 0, 100, 100)
	local ws = { id = 9, monitor = f.active_monitor }
	local pinned = f.add(100, 0, 100, 100, true, ws)
	pinned.pinned = true
	f.focus(source); f.press("l")
	assert(f.active == pinned)
end

function tests.special_workspace_replaces_normal_desktop_in_search()
	local f = fixture()
	local mon = f.active_monitor
	local special = { id = -99, monitor = mon, special = true }
	mon.active_special_workspace = special
	local source = f.add(0, 0, 100, 100, true, special)
	f.add(100, 0, 100, 100) -- normal desktop behind the scratchpad
	local target = f.add(110, 0, 100, 100, true, special)
	f.focus(source); f.press("l")
	assert(f.active == target)
end

function tests.inclusive_edges_and_negative_coordinates()
	local a = { x = -100, y = -100, w = 100, h = 100 }
	assert(focus.distance(a, { x = 0, y = -1, w = 10, h = 1 }, "r") == 1)
	assert(focus.distance(a, { x = 0, y = 0, w = 10, h = 1 }, "r") == nil)
	assert(focus.distance(a, { x = -150, y = -100, w = 50, h = 100 }, "r") == nil)
	assert(focus.distance(a, { x = -99, y = -99, w = 1, h = 1 }, "l") == 1)
end

local names = {}
for name in pairs(tests) do names[#names + 1] = name end
table.sort(names)
for _, name in ipairs(names) do tests[name](); print("ok - " .. name) end
print(string.format("%d directional focus tests passed", #names))
