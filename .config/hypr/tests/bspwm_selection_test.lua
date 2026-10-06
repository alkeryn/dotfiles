-- Run from ~/.config/hypr: lua tests/bspwm_selection_test.lua [bspwm.lua]
-- Real tree/navigation; mocked Hyprland focus events and reversible tag rules.
local layout_path = arg[1] or "bspwm.lua"
local tests = {}
local selection_tag = "bspwm_selected"

local function fixture(count)
	local f = { windows = {}, events = {}, rules = {}, tag_calls = 0 }
	local provider
	local ctx = { area = { x = 0, y = 0, w = 3840, h = 2160 }, targets = {} }
	f.ctx = ctx
	function f.emit(name, ...)
		for _, callback in ipairs(f.events[name] or {}) do callback(...) end
	end
	function f.focus(id)
		for _, w in pairs(f.windows) do
			w.active = w.stable_id == id
			if w.active then w.focus_history_id = 0
			elseif w.focus_history_id >= 0 then w.focus_history_id = w.focus_history_id + 1 end
		end
		f.active = f.windows[id]
		f.emit("window.active", f.active)
	end
	function f.recalculate() provider.recalculate(ctx) end
	_G.hl = {
		layout = { register = function(name, impl) if name == "bspwm" then provider = impl end end },
		on = function(name, callback)
			f.events[name] = f.events[name] or {}
			table.insert(f.events[name], callback)
		end,
		window_rule = function(rule) f.rules[rule.name] = rule end,
		get_active_window = function() return f.active end,
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
	dofile(layout_path)

	function f.open(id, wsid)
		local w = { stable_id = id, address = "0x" .. id, workspace = { id = wsid or 1 },
			mapped = true, active = false, floating = false, focus_history_id = -1, tags = { personal = true } }
		f.windows[id] = w
		local target = { window = w }
		function target:place(box) self.box = box end
		ctx.targets[#ctx.targets + 1] = target
		f.recalculate()
		f.focus(id)
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
		dofile(layout_path)
		f.emit("config.reloaded")
		f.recalculate()
	end
	for id = 1, count or 4 do f.open(id) end
	return f
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

function tests.float_selected_window_prunes_cursor()
	local f = fixture()
	f.message("focus parent")
	f.remove(3, false); f.expect_selection(4); f.expect_no_tags()
	f.message("focus parent"); f.expect_selection(2, 4)
end

function tests.new_window_clears_selection()
	local f = fixture()
	f.message("focus parent"); f.message("focus parent")
	f.open(5); f.expect_selection(5); f.expect_no_tags()
	f.message("focus parent"); f.expect_selection(4, 5)
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
