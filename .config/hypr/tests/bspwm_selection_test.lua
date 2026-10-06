-- Run from ~/.config/hypr: lua tests/bspwm_selection_test.lua [lua/extensions/bspwm.lua]
-- Real tree/navigation; mocked Hyprland focus events and reversible tag rules.
local layout_path = arg[1] or "lua/extensions/bspwm.lua"
local tests = {}
package.loaded["lua/extensions/bspwm_state"] = { open_session = function() return nil end }
-- Bindings need constants, not the host's ~/bin/wpc machine detection.
package.loaded["lua/vars"] = { FLOAT_STEP = 20, terminal = "alacritty", GAPS = 4, GAPS_OUT = 8 }
local selection_tag = "bspwm_selected"

local function fixture(count)
	local f = { windows = {}, events = {}, rules = {}, tag_calls = 0, binds = {}, close_requests = {} }
	local provider
	local ctx = { area = { x = 0, y = 0, w = 3840, h = 2160 }, targets = {} }
	f.ctx = ctx
	function f.emit(name, ...)
		for _, callback in ipairs(f.events[name] or {}) do callback(...) end
	end
	function f.focus(id, reason)
		for _, w in pairs(f.windows) do
			w.active = w.stable_id == id
			if w.active then w.focus_history_id = 0
			elseif w.focus_history_id >= 0 then w.focus_history_id = w.focus_history_id + 1 end
		end
		f.active = f.windows[id]
		f.emit("window.active", f.active, reason)
	end
	function f.recalculate() provider.recalculate(ctx) end
	_G.hl = {
		layout = { register = function(name, impl) if name == "bspwm" then provider = impl end end },
		on = function(name, callback)
			f.events[name] = f.events[name] or {}
			table.insert(f.events[name], callback)
		end,
		window_rule = function(rule) f.rules[rule.name] = rule end,
		bind = function(keys, callback, opts)
			local bind = { callback = callback, opts = opts, enabled = true }
			function bind:set_enabled(enabled) self.enabled = enabled end
			f.binds[keys] = bind
			return bind
		end,
		get_active_window = function() return f.active end,
		get_monitor = function(dir)
			f.monitor_fallback = dir
			return nil
		end,
		get_windows = function()
			local result = {}
			for _, w in pairs(f.windows) do if w.mapped then result[#result + 1] = w end end
			return result
		end,
		dispatch = function(callback) return callback() end,
		dsp = {
			focus = function(opts)
				return function()
					if f.reject_focus then return { ok = false } end
					local w = opts.window
					if type(w) == "string" then
						for _, candidate in pairs(f.windows) do
							if "address:" .. candidate.address == w then w = candidate; break end
						end
					end
					f.focus(w.stable_id) -- synchronous native window.active callback
					f.emit("monitor.focused", {})
					if f.recalculate_on_focus then f.recalculate() end
					return { ok = true }
				end
			end,
			window = { tag = function(opts)
				return function()
					f.tag_calls = f.tag_calls + 1
					local prefix, tag = opts.tag:sub(1, 1), opts.tag:sub(2)
					assert(prefix == "+" or prefix == "-", "tags must be idempotent, not toggled")
					opts.window.tags[tag] = prefix == "+" or nil
					return { ok = true }
				end
			end },
		},
	}
	-- Other dispatchers are only constructed when loading the real bindings.
	local function ignored_dispatcher() return function() end end
	setmetatable(hl.dsp, { __index = function() return ignored_dispatcher end })
	setmetatable(hl.dsp.window, { __index = function() return ignored_dispatcher end })
	hl.dsp.layout = function(msg) return function() f.message(msg) end end
	hl.dsp.window.close = function(opts)
		return function()
			local w = opts and opts.window or f.active
			if not w or not w.mapped then return { ok = true } end
			f.close_requests[#f.close_requests + 1] = w.stable_id
			if f.close_hook then f.close_hook(w) end
			return { ok = true }
		end
	end
	f.api = dofile(layout_path)
	f.api.set_feedback_sink(function(states) f.states = states end)

	function f.load_bindings()
		package.loaded["lua/extensions/bspwm"] = f.api
		package.loaded["lua/helpers"], package.loaded["lua/bindings"] = nil, nil
		require("lua/bindings")
	end
	function f.press(keys)
		local bind = assert(f.binds[keys], "missing binding " .. keys)
		if not bind.enabled then return false end -- Hyprland passes it to the app
		bind.callback()
		return true
	end
	function f.expect_box(id, x, y, w, h)
		for _, t in ipairs(ctx.targets) do
			if t.window.stable_id == id then
				local b = t.box
				assert(math.abs(b.x-x) < 1.01 and math.abs(b.y-y) < 1.01
					and math.abs(b.w-w) < 1.01 and math.abs(b.h-h) < 1.01,
					string.format("window %d: expected (%g,%g %gx%g), got (%g,%g %gx%g)",
						id, x, y, w, h, b.x, b.y, b.w, b.h))
				return
			end
		end
		error("missing window " .. id)
	end
	function f.snapshot()
		local boxes = {}
		for _, t in ipairs(ctx.targets) do
			local b = t.box
			boxes[t.window.stable_id] = { x = b.x, y = b.y, w = b.w, h = b.h }
		end
		return boxes
	end

	function f.open(id, wsid, focus_before_layout)
		local w = { stable_id = id, address = "0x" .. id, workspace = { id = wsid or 1 },
			mapped = true, active = false, floating = false, focus_history_id = -1, tags = { personal = true } }
		f.windows[id] = w
		local target = { window = w }
		function target:place(box) self.box = box end
		ctx.targets[#ctx.targets + 1] = target
		if focus_before_layout then f.focus(id) end
		f.recalculate()
		if not focus_before_layout then f.focus(id) end
		return w
	end
	function f.message(msg)
		assert(provider.layout_msg(ctx, msg) == true)
		f.recalculate()
	end
	function f.expect_selection(...)
		local expected, actual = {}, {}
		for _, id in ipairs({...}) do expected[#expected + 1] = tostring(id) end
		for id, w in pairs(f.windows) do
			if w.mapped and (w.active or w.tags[selection_tag]) then actual[#actual + 1] = tostring(id) end
			assert(w.tags.personal, "selection removed an unrelated tag")
		end
		table.sort(expected); table.sort(actual)
		assert(table.concat(expected, ",") == table.concat(actual, ","),
			"expected selected " .. table.concat(expected, ",") .. ", got " .. table.concat(actual, ","))
	end
	function f.expect_no_tags()
		for _, w in pairs(f.windows) do assert(not w.tags[selection_tag], "stale selection tag") end
	end
	function f.remove(id, close)
		local w = f.windows[id]
		if close then f.emit("window.close", w); w.mapped = false else w.floating = true end
		for i, t in ipairs(ctx.targets) do if t.window == w then table.remove(ctx.targets, i); break end end
		f.recalculate()
	end
	function f.reload()
		f.events = {} -- old Lua event subscriptions disappear on config reload
		f.api = dofile(layout_path)
		f.emit("config.reloaded")
		f.recalculate()
	end
	for id = 1, count or 4 do f.open(id) end
	return f
end

local function leaf_by_id(node, id)
	if node.t == "leaf" then return node.id == id and node or nil end
	return leaf_by_id(node.a, id) or leaf_by_id(node.b, id)
end

local function split(axis, a, b, ratio)
	return { t = "split", axis = axis, a = a, b = b, ratio = ratio or 0.5 }
end

function tests.parent_climbs_two_three_four_windows_and_stops()
	local f = fixture()
	f.message("focus parent"); f.expect_selection(3, 4)
	assert(f.active.stable_id == 4, "parent selection should not bounce input focus")
	f.message("focus parent"); f.expect_selection(2, 3, 4)
	f.message("focus parent"); f.expect_selection(1, 2, 3, 4)
	for _ = 1, 5 do f.message("focus parent"); f.expect_selection(1, 2, 3, 4) end
end

function tests.three_window_root()
	local f = fixture(3)
	f.message("focus parent"); f.expect_selection(2, 3)
	f.message("focus parent"); f.expect_selection(1, 2, 3)
end

function tests.first_second_descend_from_selected_node()
	local f = fixture()
	for _ = 1, 3 do f.message("focus parent") end
	f.message("focus second"); f.expect_selection(2, 3, 4)
	f.message("focus second"); f.expect_selection(3, 4)
	f.message("focus first"); f.expect_selection(3); f.expect_no_tags()
	for _ = 1, 3 do f.message("focus first"); f.message("focus second"); f.expect_selection(3) end
end

function tests.brother_switches_whole_branches()
	local f = fixture()
	f.message("focus parent"); f.expect_selection(3, 4)
	f.message("focus brother"); f.expect_selection(2)
	f.message("focus brother"); f.expect_selection(3, 4)
	f.message("focus parent"); f.expect_selection(2, 3, 4)
	f.message("focus brother"); f.expect_selection(1)
	f.message("focus brother"); f.expect_selection(2, 3, 4)
end

function tests.root_brother_and_single_window_are_noops()
	local f = fixture(1)
	for _, msg in ipairs({ "focus parent", "focus brother", "focus first", "focus second" }) do
		f.message(msg); f.expect_selection(1); f.expect_no_tags()
	end
	f = fixture(3)
	f.message("focus parent"); f.message("focus parent")
	f.message("focus brother"); f.expect_selection(1, 2, 3)
end

function tests.normal_focus_within_selection_resets_cursor()
	local f = fixture()
	f.message("focus parent"); f.message("focus parent")
	f.focus(3); f.expect_selection(3); f.expect_no_tags()
	f.message("focus parent"); f.expect_selection(3, 4)
end

function tests.normal_focus_outside_selection_resets_cursor()
	local f = fixture()
	f.message("focus parent")
	f.focus(1); f.expect_selection(1); f.expect_no_tags()
	f.message("focus parent"); f.expect_selection(1, 2, 3, 4)
end

function tests.representative_focus_events_do_not_reset_selection()
	local f = fixture()
	f.recalculate_on_focus = true
	f.message("focus parent")
	f.message("focus brother"); f.expect_selection(2)
	f.message("focus brother"); f.expect_selection(3, 4)
	f.message("focus parent"); f.expect_selection(2, 3, 4)
end

function tests.selection_survives_recalculation_without_tag_churn()
	local f = fixture()
	f.message("focus parent")
	local calls = f.tag_calls
	for _ = 1, 10 do f.recalculate() end
	f.expect_selection(3, 4)
	assert(f.tag_calls == calls, "unchanged selection re-dispatched border tags")
	f.message("focus parent"); f.expect_selection(2, 3, 4)
end

function tests.rule_colors_both_focus_states()
	local f = fixture()
	local rule = assert(f.rules["bspwm-subtree-selection"], "missing selection border rule")
	assert(rule.match.tag == selection_tag)
	assert(rule.border_color == "rgb(bb0000) rgb(bb0000)", "inactive members need the active border too")
end

function tests.workspace_and_monitor_changes_clear_highlights()
	for _, event in ipairs({ "workspace.active", "workspace.special_active", "monitor.focused" }) do
		local f = fixture()
		f.message("focus parent")
		f.emit(event, { id = 2 }); f.expect_no_tags()
		f.message("focus parent"); f.expect_selection(3, 4)
	end
end

function tests.focus_to_float_or_empty_clears_highlights()
	local f = fixture()
	f.message("focus parent")
	f.emit("window.active", { floating = true }); f.expect_no_tags()
	f.message("focus parent")
	f.emit("window.active", nil); f.expect_no_tags()
end

function tests.tree_focus_on_float_does_not_select_arbitrary_tiles()
	local f = fixture()
	for _, w in pairs(f.windows) do w.active = false end
	f.emit("window.active", { floating = true })
	f.message("focus parent")
	f.expect_selection(); f.expect_no_tags()
end

function tests.remapping_window_removes_stale_selection_tag()
	local f = fixture()
	local w = f.windows[4]
	w.tags[selection_tag] = true -- retained by a previously unmapped object
	f.emit("window.open", w)
	f.expect_no_tags()
	assert(w.tags.personal)
end

function tests.close_selected_window_clears_highlights()
	local f = fixture()
	f.message("focus parent")
	f.remove(3, true); f.expect_selection(4); f.expect_no_tags()
	f.message("focus parent"); f.expect_selection(2, 4)
end

function tests.float_selected_window_clears_cursor_but_preserves_parent()
	local f = fixture()
	f.message("focus parent")
	local parent = f.states[1].selected
	f.remove(3, false); f.expect_selection(4); f.expect_no_tags()
	f.message("focus parent"); f.expect_selection(4)
	assert(f.states[1].selected == parent and parent.a.id == 3 and parent.a.vacant)
	f.message("focus parent"); f.expect_selection(2, 4)
end

function tests.new_window_clears_selection_but_wraps_whole_subtree()
	local f = fixture()
	f.message("focus parent"); f.message("focus parent")
	f.open(5); f.expect_selection(5); f.expect_no_tags()
	f.expect_box(1, 0, 0, 1920, 2160)
	f.expect_box(5, 1920, 1080, 1920, 1080)
	f.message("focus parent"); f.expect_selection(2, 3, 4, 5)
end

function tests.reload_removes_old_tags_without_touching_personal_tags()
	local f = fixture()
	f.message("focus parent"); f.message("focus parent")
	f.reload(); f.expect_selection(4); f.expect_no_tags()
	f.message("focus parent"); f.expect_selection(3, 4)
end

function tests.workspace_move_and_fullscreen_clear_selection()
	for _, event in ipairs({ "window.move_to_workspace", "window.fullscreen" }) do
		local f = fixture()
		f.message("focus parent")
		f.emit(event, f.windows[3]); f.expect_no_tags()
	end
end

function tests.failed_branch_focus_clears_selection()
	local f = fixture()
	f.message("focus parent")
	f.reject_focus = true
	f.message("focus brother"); f.expect_selection(4); f.expect_no_tags()
	f.reject_focus = false
	f.focus(3) -- ensure the internal-focus guard was released
	f.message("focus parent"); f.expect_selection(3, 4)
end

function tests.flip_applies_to_selected_three_window_subtree()
	local f = fixture()
	f.message("focus parent"); f.message("focus parent")
	f.message("flip v")
	assert(f.ctx.targets[1].box.w == 1920 and f.ctx.targets[1].box.h == 2160)
	assert(f.ctx.targets[2].box.y == 1080, "flip affected only the representative's parent")
	assert(f.ctx.targets[3].box.y == 0 and f.ctx.targets[4].box.y == 0)
	f.expect_selection(2, 3, 4)
end

for _, case in ipairs({
	{ key = "h", rotation = 0 }, { key = "k", rotation = 90 },
	{ key = "l", rotation = 180 }, { key = "j", rotation = 270 },
}) do
	tests["directional_swap_selected_subtree_" .. case.key] = function()
		local f = fixture(3)
		f.message("focus parent"); f.message("focus parent")
		if case.rotation ~= 0 then f.message("rotate " .. case.rotation) end
		f.focus(1); f.message("preselect l"); f.message("pratio 0.2")
		f.focus(3); f.message("focus parent")
		f.message("preselect u"); f.message("pratio 0.3")
		local st = f.states[1]
		local root, selected = st.tree, st.selected
		selected.ratio = 0.37; f.recalculate()
		local a, b = selected.a, selected.b
		local target = root.a == selected and root.b or root.a
		local target_box, selection_box = target._box, selected._box
		local selected_first = root.a == selected
		local tag_calls = f.tag_calls
		f.load_bindings(); f.press("SUPER + SHIFT + " .. case.key)
		assert((selected_first and root.b or root.a) == selected, "swapped a leaf instead of the whole subtree")
		assert((selected_first and root.a or root.b) == target, "target did not take the selection's old slot")
		assert(selected.a == a and selected.b == b and selected.ratio == 0.37)
		assert(selected.presel.dir == "u" and selected.presel.ratio == 0.3 and target.presel.ratio == 0.2)
		assert(selected._box.x == target_box.x and selected._box.y == target_box.y
			and selected._box.w == target_box.w and selected._box.h == target_box.h)
		f.expect_box(1, selection_box.x, selection_box.y, selection_box.w, selection_box.h)
		assert(f.active.stable_id == 3 and st.selected == selected and st.selected_focus_id == 3)
		assert(f.tag_calls == tag_calls and not f.monitor_fallback)
		f.expect_selection(2, 3)
	end
end

function tests.directional_swap_non_siblings_and_repeated_inverse()
	local f = fixture(4)
	f.focus(1); f.focus(4); f.message("focus parent")
	local st = f.states[1]
	local root, selected, target, other = st.tree, st.selected, st.tree.a, st.tree.b.a
	local parent = root.b
	local ratio = selected.ratio
	local before = f.snapshot()
	f.load_bindings()
	for _ = 1, 5 do
		f.press("SUPER + SHIFT + h")
		assert(root.a == selected and parent.b == target and parent.a == other)
		f.expect_box(2, before[2].x, before[2].y, before[2].w, before[2].h)
		f.expect_selection(3, 4)
		assert(selected.ratio == ratio and f.active.stable_id == 4)
		f.press("SUPER + SHIFT + l")
		assert(root.a == target and parent.b == selected and parent.a == other)
		for id, b in pairs(before) do f.expect_box(id, b.x, b.y, b.w, b.h) end
		f.expect_selection(3, 4)
	end
end

function tests.directional_swap_uses_full_selection_box_and_focus_history()
	local f = fixture(4)
	local st, nodes = f.states[1], {}
	for id = 1, 4 do nodes[id] = leaf_by_id(st.tree, id) end
	st.tree = split("h", split("v", nodes[1], nodes[2]), split("v", nodes[3], nodes[4]))
	f.recalculate()
	-- The representative is bottom-right, but the selected right column also
	-- overlaps top-left. Equidistant neighbours use history, not its leaf box.
	f.focus(1); f.focus(4); f.message("focus parent")
	local selected, left = st.selected, st.tree.a
	f.load_bindings(); f.press("SUPER + SHIFT + h")
	assert(left.a == selected and left.b == nodes[2] and st.tree.b == nodes[1])
	f.expect_selection(3, 4)
end

function tests.directional_swap_prefers_boundary_distance_to_centres_and_breaks_ties_by_history()
	local f = fixture(5)
	local st, nodes = f.states[1], {}
	for id = 1, 5 do nodes[id] = leaf_by_id(st.tree, id) end
	local lower = split("h", nodes[2], nodes[3])
	local left = split("v", nodes[1], lower)
	st.tree = split("h", left, split("v", nodes[4], nodes[5]), 0.75)
	f.recalculate()
	-- 1 and 3 touch the selection. 3 has a closer centre, but 1 was focused
	-- later. 2 is even newer, but its boundary is farther away than either.
	f.focus(1); f.focus(2); f.focus(5); f.message("focus parent")
	local selected = st.selected
	f.message("swap l")
	assert(left.a == selected and st.tree.b == nodes[1] and lower.a == nodes[2] and lower.b == nodes[3])
	f.expect_selection(4, 5)
end

function tests.directional_swap_skips_hidden_neighbours()
	local f = fixture(4)
	local st, nodes = f.states[1], {}
	for id = 1, 4 do nodes[id] = leaf_by_id(st.tree, id) end
	local left = split("v", nodes[1], nodes[2])
	st.tree = split("h", left, split("v", nodes[3], nodes[4]))
	f.recalculate(); f.focus(1); f.focus(4); f.message("focus parent")
	f.windows[1].hidden = true
	local selected = st.selected
	f.message("swap l")
	assert(left.a == nodes[1] and left.b == selected and st.tree.b == nodes[2])
	f.expect_selection(3, 4)
end

function tests.directional_swap_unranked_ties_use_stable_tree_order()
	local f = fixture(4)
	local st, nodes = f.states[1], {}
	for id = 1, 4 do nodes[id] = leaf_by_id(st.tree, id) end
	local left = split("v", nodes[1], nodes[2])
	st.tree = split("h", left, split("v", nodes[3], nodes[4]))
	f.recalculate(); f.message("focus parent")
	for _, w in pairs(f.windows) do w.focus_history_id = -1 end
	local selected = st.selected
	f.message("swap l")
	assert(left.a == selected and st.tree.b == nodes[1])
end

function tests.directional_swap_root_excludes_all_descendants_and_reaches_monitor_fallback()
	local f = fixture(4)
	f.message("focus parent"); f.message("focus parent"); f.message("focus parent")
	local selected, before, calls = f.states[1].selected, f.snapshot(), f.tag_calls
	f.load_bindings()
	for key, dir in pairs({ h = "l", j = "d", k = "u", l = "r" }) do
		assert(not f.api.has_neighbor(dir), "a descendant was treated as an external neighbour")
		f.message("swap " .. dir)
		f.monitor_fallback = nil
		f.press("SUPER + SHIFT + " .. key)
		assert(f.monitor_fallback == dir and f.states[1].selected == selected)
		for id, b in pairs(before) do f.expect_box(id, b.x, b.y, b.w, b.h) end
		f.expect_selection(1, 2, 3, 4)
	end
	assert(f.tag_calls == calls)
end

function tests.directional_swap_leaf_identity_age_and_presels_travel_with_window()
	for _, explicit_selection in ipairs({ false, true }) do
		local f = fixture(2)
		f.focus(1); f.message("preselect u"); f.message("pratio 0.2")
		f.focus(2); f.message("preselect r"); f.message("pratio 0.3")
		if explicit_selection then f.message("focus parent"); f.message("focus second") end
		local st = f.states[1]
		local root, a, b = st.tree, st.tree.a, st.tree.b
		local age_a, age_b = a.n, b.n
		f.load_bindings(); f.press("SUPER + SHIFT + h")
		assert(root.a == b and root.b == a and a.id == 1 and b.id == 2)
		assert(a.n == age_a and b.n == age_b and a.presel.ratio == 0.2 and b.presel.ratio == 0.3)
		assert(f.active.stable_id == 2)
		if explicit_selection then assert(st.selected == b and st.selected_focus_id == 2) end
		f.expect_selection(2); f.expect_no_tags()
	end
end

function tests.directional_swap_preserves_selection_as_new_window_insertion_anchor()
	local f = fixture(3)
	f.message("focus parent"); f.message("preselect r"); f.message("pratio 0.3")
	local st = f.states[1]
	local selected, target = st.selected, st.tree.a
	f.message("swap l")
	assert(st.tree.a == selected)
	f.open(4)
	assert(st.tree.a.a == selected and st.tree.a.b.id == 4 and st.tree.b == target)
	assert(st.tree.a.ratio == 0.3 and not selected.presel)
	f.expect_selection(4); f.expect_no_tags()
end

function tests.directional_swap_no_external_target_is_noop()
	local f = fixture(4)
	f.message("focus parent") -- bottom-right pair; no tile to its right/below
	local st, before = f.states[1], f.snapshot()
	local selected = st.selected
	for _, dir in ipairs({ "r", "d" }) do
		assert(not f.api.has_neighbor(dir))
		f.message("swap " .. dir)
		assert(st.selected == selected)
		for id, b in pairs(before) do f.expect_box(id, b.x, b.y, b.w, b.h) end
		f.expect_selection(3, 4)
	end
end

function tests.directional_swap_does_not_mutate_tiles_without_active_tile_or_in_monocle()
	for _, mode in ipairs({ "float", "no_focus", "monocle" }) do
		local f = fixture(3)
		f.message("focus parent")
		if mode == "float" then
			f.windows[99] = { stable_id = 99, mapped = true, floating = true, tags = { personal = true }, workspace = { id = 1 } }
			f.focus(99)
		elseif mode == "no_focus" then f.focus(nil)
		else
			hl.workspace_rule = function() return { set_enabled = function() end } end
			f.message("monocle")
		end
		local before, root = f.snapshot(), f.states[1].tree
		local a, b = root.a, root.b
		for _, dir in ipairs({ "l", "r", "u", "d" }) do
			assert(not f.api.has_neighbor(dir))
			f.message("swap " .. dir)
			assert(root.a == a and root.b == b)
			for id, box in pairs(before) do f.expect_box(id, box.x, box.y, box.w, box.h) end
		end
	end
end

function tests.resize_selected_subtree_uses_its_outer_edge()
	local f = fixture()
	f.message("focus parent"); f.message("focus parent")
	f.message("grow l 20")
	assert(f.ctx.targets[1].box.w == 1900, "resized a leaf's internal split instead of the selection")
	assert(f.ctx.targets[2].box.x == 1900)
	f.expect_selection(2, 3, 4)
	f.message("shrink l 20")
	assert(f.ctx.targets[1].box.w == 1920)
end

-- Rotation oracle: rotate normalized rectangles geometrically. This is
-- independent of the implementation's binary-tree traversal and axis names.
for _, degrees in ipairs({ 90, 180, 270 }) do
	for _, root in ipairs({ false, true }) do
		local name = "rotate_" .. degrees .. (root and "_root" or "_three_windows")
		tests[name] = function()
			local f = fixture()
			f.message("focus parent"); f.message("grow u 200") -- asymmetric inner split
			f.message("focus parent"); f.message("grow l 120") -- asymmetric outer split
			if root then f.message("focus parent") end
			local before = f.snapshot()
			local area = root and { x = 0, y = 0, w = 3840, h = 2160 }
				or { x = before[2].x, y = 0, w = before[2].w, h = 2160 }
			f.message("rotate " .. degrees)
			for id, b in pairs(before) do
				if root or id ~= 1 then
					local x, y, w, h = (b.x-area.x)/area.w, b.y/area.h, b.w/area.w, b.h/area.h
					for _ = 1, degrees / 90 do x, y, w, h = 1-y-h, x, h, w end
					f.expect_box(id, area.x+x*area.w, y*area.h, w*area.w, h*area.h)
				else f.expect_box(id, b.x, b.y, b.w, b.h) end
			end
			if root then f.expect_selection(1, 2, 3, 4) else f.expect_selection(2, 3, 4) end
		end
	end
end

function tests.rotation_inverse_and_four_quarter_turns()
	local f = fixture()
	f.message("focus parent"); f.message("grow u 100"); f.message("focus parent")
	local before = f.snapshot()
	for _, sequence in ipairs({ {90, 270}, {90, 90, 90, 90}, {270, 270, 270, 270} }) do
		for _, degrees in ipairs(sequence) do f.message("rotate " .. degrees) end
		for id, b in pairs(before) do f.expect_box(id, b.x, b.y, b.w, b.h) end
	end
end

function tests.rotating_leaf_does_not_implicitly_rotate_parent()
	local f = fixture()
	local before = f.snapshot()
	f.message("rotate 90")
	for id, b in pairs(before) do f.expect_box(id, b.x, b.y, b.w, b.h) end
end

function tests.same_window_notification_preserves_selection_but_click_clears()
	local f = fixture()
	f.message("focus parent"); f.message("focus parent")
	f.focus(4, 6) -- FOCUS_REASON_OTHER: compositor re-notification
	f.expect_selection(2, 3, 4)
	f.message("rotate 90"); f.expect_selection(2, 3, 4)
	f.focus(4, 5) -- FOCUS_REASON_CLICK: explicit leaf selection
	f.expect_selection(4); f.expect_no_tags()
end

-- tree.c:insert_node copies presel->split_ratio directly to the FIRST child.
local presel_boxes = {
	l = {1920, 0, 576, 2160}, r = {2496, 0, 1344, 2160},
	u = {1920, 0, 1920, 648}, d = {1920, 648, 1920, 1512},
}
for direction, expected in pairs(presel_boxes) do
	for _, early_focus in ipairs({ false, true }) do
		tests["subtree_presel_" .. direction .. (early_focus and "_early_focus" or "")] = function()
			local f = fixture()
			f.message("focus parent"); f.message("focus parent")
			f.message("preselect " .. direction); f.message("pratio 0.3")
			f.open(5, 1, early_focus)
			f.expect_box(1, 0, 0, 1920, 2160)
			f.expect_box(5, (table.unpack or unpack)(expected))
			f.expect_selection(5); f.expect_no_tags()
			f.message("focus parent"); f.expect_selection(2, 3, 4, 5)
		end
	end
end

function tests.automatic_subtree_insertion_before_focus_layout()
	local f = fixture()
	f.message("focus parent"); f.message("focus parent")
	f.open(5, 1, true)
	f.expect_box(5, 1920, 1080, 1920, 1080)
	f.open(6)
	f.expect_box(6, 2880, 1080, 960, 1080) -- now split window 5, not the old selection
	f.message("focus parent"); f.expect_selection(5, 6)
end

function tests.root_insertion_wraps_entire_desktop()
	local f = fixture(3)
	f.message("focus parent"); f.message("focus parent")
	f.open(4)
	f.expect_box(4, 1920, 0, 1920, 2160)
	f.message("focus parent"); f.expect_selection(1, 2, 3, 4)
end

function tests.presel_ratio_only_defaults_east_and_direction_preserves_ratio()
	for _, direction in ipairs({ "r", "u" }) do
		local f = fixture()
		f.message("focus parent"); f.message("focus parent")
		f.message("pratio 0.3") -- bspwm make_presel defaults to east
		if direction == "u" then f.message("preselect u") end
		f.open(5)
		f.expect_box(5, (table.unpack or unpack)(presel_boxes[direction]))
	end
end

function tests.presel_is_consumed_once()
	local f = fixture()
	f.message("focus parent"); f.message("focus parent")
	f.message("preselect u"); f.message("pratio 0.3")
	f.open(5); f.open(6)
	f.expect_box(6, 2880, 0, 960, 648)
	f.message("focus parent"); f.expect_selection(5, 6)
end

function tests.presel_stays_on_node_when_focus_changes()
	local f = fixture()
	f.message("focus parent"); f.message("focus parent")
	f.message("preselect u"); f.message("pratio 0.3")
	f.focus(1); f.open(5)
	f.expect_box(5, 0, 1080, 1920, 1080) -- must NOT consume the other node's presel
	f.focus(4); f.message("focus parent"); f.message("focus parent")
	f.open(6)
	f.expect_box(6, 1920, 0, 1920, 648)
end

function tests.cancel_presel_restores_longest_side_for_selected_subtree()
	for _, command in ipairs({ "cancel", "clear" }) do
		local f = fixture()
		f.message("focus parent"); f.message("focus parent")
		f.message("preselect l"); f.message("pratio 0.3")
		f.message("preselect " .. command)
		f.open(5)
		f.expect_box(5, 1920, 1080, 1920, 1080)
	end
end

function tests.actual_bindings_select_rotate_and_preselect_whole_subtree()
	local f = fixture()
	f.load_bindings()
	f.press("SUPER + b"); f.press("SUPER + b")
	f.press("SUPER + r")
	f.expect_selection(2, 3, 4)
	f.expect_box(2, 2880, 0, 960, 2160)
	f.expect_box(3, 1920, 0, 960, 1080)
	f.expect_box(4, 1920, 1080, 960, 1080)
	f.press("SUPER + CTRL + h")
	f.open(5)
	f.expect_box(5, 1920, 0, 960, 2160)
	f.press("SUPER + b"); f.expect_selection(2, 3, 4, 5)
end

function tests.pending_subtree_anchor_survives_duplicate_new_window_focus()
	local f = fixture()
	f.message("focus parent"); f.message("focus parent")
	local recalculate = f.recalculate
	f.recalculate = function() end -- delay first layout pass
	f.open(5, 1, true)
	f.focus(5, 6)
	f.recalculate = recalculate
	f.recalculate()
	f.expect_box(5, 1920, 1080, 1920, 1080)
end

function tests.explicit_focus_change_cancels_pending_subtree_anchor()
	local f = fixture()
	f.message("focus parent"); f.message("focus parent")
	local recalculate = f.recalculate
	f.recalculate = function() end
	f.open(5, 1, true)
	f.focus(1, 5)
	f.recalculate = recalculate
	f.recalculate()
	f.expect_box(5, 0, 1080, 1920, 1080)
end

function tests.super_x_closes_selected_subtree_and_leaves_ctrl_x_alone()
	local f = fixture()
	f.load_bindings()
	assert(not f.binds["CTRL + x"], "Ctrl+x must remain an application shortcut")
	f.message("focus parent"); f.message("focus parent")
	assert(f.press("SUPER + x"))
	table.sort(f.close_requests)
	assert(table.concat(f.close_requests, ",") == "2,3,4")
	f.expect_no_tags()
	assert(f.binds["SUPER + x"].opts.repeating, "preserve the existing repeat setting")
	assert(f.binds["SUPER + CTRL + x"].enabled, "pin binding must remain available")
end

function tests.close_snapshot_survives_immediate_close_and_focus_changes()
	local f = fixture()
	f.load_bindings()
	f.message("focus parent"); f.message("focus parent")
	f.close_hook = function(w)
		f.remove(w.stable_id, true)
		f.focus(1) -- focus changes immediately after each request
	end
	f.press("SUPER + x")
	table.sort(f.close_requests)
	assert(table.concat(f.close_requests, ",") == "2,3,4", "close escaped or lost the selection")
	assert(f.windows[1].mapped)
end

function tests.close_root_requests_all_windows_once()
	local f = fixture()
	f.load_bindings()
	for _ = 1, 3 do f.message("focus parent") end
	f.press("SUPER + x")
	table.sort(f.close_requests)
	assert(table.concat(f.close_requests, ",") == "1,2,3,4")
end

function tests.super_x_closes_single_window_without_subtree_selection()
	local f = fixture()
	f.load_bindings()
	f.press("SUPER + x")
	assert(table.concat(f.close_requests, ",") == "4")
end

function tests.super_x_closes_only_new_focus_after_deselecting()
	local f = fixture()
	f.load_bindings()
	f.message("focus parent"); f.message("focus parent")
	f.focus(1)
	f.press("SUPER + x")
	assert(table.concat(f.close_requests, ",") == "1")
end

function tests.super_x_closes_only_explicitly_selected_leaf()
	local f = fixture()
	f.load_bindings()
	f.message("focus parent"); f.message("focus first")
	f.press("SUPER + x")
	assert(table.concat(f.close_requests, ",") == "3")
end

function tests.super_x_closes_floating_window()
	local f = fixture()
	f.load_bindings()
	f.remove(4, false)
	f.press("SUPER + x")
	assert(table.concat(f.close_requests, ",") == "4")
end

function tests.super_x_without_focused_window_is_noop()
	local f = fixture()
	f.load_bindings()
	f.focus(nil)
	f.press("SUPER + x")
	assert(#f.close_requests == 0)
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
