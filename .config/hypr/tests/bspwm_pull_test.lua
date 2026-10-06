-- lua tests/bspwm_pull_test.lua -- native move/recalculation ordering is mocked.
local codec = require("lua/extensions/bspwm_state")
local tests = {}

local function find(node, id)
	if not node then return end
	if node.t == "leaf" then return node.id == id and node or nil end
	return find(node.a, id) or find(node.b, id)
end

local function fixture()
	local f = { windows = {}, workspaces = {}, contexts = {}, events = {}, moves = {}, history = {}, binds = {}, focus_calls = {} }
	local provider
	function f.emit(event, ...)
		for _, callback in ipairs(f.events[event] or {}) do callback(...) end
	end
	function f.workspace(id, monitor)
		if f.workspaces[id] then return f.workspaces[id] end
		local mon = monitor or { position = { x = (id - 1) * 2000, y = 0 }, width = 1600, height = 900, scale = 1 }
		local ws = { id = id, name = tostring(id), monitor = mon, tiled_layout = "lua:bspwm", visible = true }
		f.workspaces[id] = ws
		f.contexts[id] = { area = { x = mon.position.x, y = mon.position.y, w = 1600, h = 900 }, targets = {} }
		return ws
	end
	function f.snapshot(id)
		local ctx, targets = f.contexts[id], {}
		for _, target in ipairs(ctx.targets) do targets[#targets + 1] = target end
		return { area = ctx.area, targets = targets }
	end
	function f.recalculate(id)
		-- CLuaTiledAlgorithm skips Lua callbacks when the target list is empty.
		if #f.contexts[id].targets > 0 then provider.recalculate(f.snapshot(id)) end
	end
	function f.focus(id)
		local window = f.windows[id]
		for _, w in pairs(f.windows) do w.active = w == window end
		local old_ws = f.active_ws
		f.active, f.active_ws = window, window.workspace
		if old_ws ~= f.active_ws then
			f.emit("workspace.active", f.active_ws)
			if not old_ws or old_ws.monitor ~= f.active_ws.monitor then f.emit("monitor.focused", window.monitor) end
		end
		for i, old in ipairs(f.history) do if old == id then table.remove(f.history, i); break end end
		table.insert(f.history, 1, id)
		for rank, wid in ipairs(f.history) do f.windows[wid].focus_history_id = rank - 1 end
		f.emit("window.active", window)
	end
	local function all_windows()
		local result = {}
		for _, w in pairs(f.windows) do result[#result + 1] = w end
		-- Deliberately not focus order.
		table.sort(result, function(a, b) return a.stable_id < b.stable_id end)
		return result
	end
	function f.load(saved)
		f.events = {}
		package.loaded["lua/extensions/bspwm_state"] = { open_session = function()
			if not saved then return nil end
			return {
				load = function() return assert(codec.decode(saved)) end,
				save = function(_, states, pending)
					f.saved = codec.encode(states, pending)
					assert(codec.decode(f.saved))
					return true
				end,
			}
		end }
		local noop = function() return function() return { ok = true } end end
		local function rule() return { set_enabled = function() end } end
		_G.hl = {
			layout = { register = function(name, impl)
				if name ~= "bspwm" then return end
				provider = impl
				if saved then
					for id, ctx in pairs(f.contexts) do
						local targets = {}
						for _, target in ipairs(ctx.targets) do
							targets[#targets + 1] = target
							impl.recalculate({ area = ctx.area, targets = targets })
						end
					end
				end
			end },
			on = function(event, callback)
				f.events[event] = f.events[event] or {}
				table.insert(f.events[event], callback)
			end,
			window_rule = rule, workspace_rule = rule,
			get_windows = all_windows,
			get_active_window = function() return f.active end,
			get_active_workspace = function() return f.active_ws end,
			bind = function(keys, dispatcher) f.binds[keys] = dispatcher end,
			dispatch = function(dispatcher) return dispatcher() end,
			dsp = setmetatable({
				layout = function(message) return function() return f.message(message) end end,
				focus = function(opts) return function()
					f.focus_calls[#f.focus_calls + 1] = opts.window.stable_id
					if f.before_focus then f.before_focus(opts.window) end
					if f.fail_focus then return { ok = false } end
					f.focus(opts.window.stable_id)
					return { ok = true }
				end end,
				window = setmetatable({ move = function(opts) return function()
					local w, dest = opts.window, f.workspaces[opts.workspace]
					if type(opts.workspace) == "string" and opts.workspace:sub(1, 5) == "name:" then
						for _, ws in pairs(f.workspaces) do if ws.name == opts.workspace:sub(6) then dest = ws end end
					end
					assert(dest, "expected an absolute workspace ID or name selector")
					assert(type(opts.workspace) ~= "number" or opts.workspace > 0, "negative IDs parse as relative selectors")
					assert(opts.follow == false, "defer focus until the whole insertion is complete")
					f.moves[#f.moves + 1] = opts
					if f.fail_id == w.stable_id then return { ok = false } end
					if f.throw_id == w.stable_id then error("synthetic dispatcher exception") end
					if f.ignore_move then return { ok = true } end
					local source = w.workspace
					w.workspace, w.monitor = dest, dest.monitor
					-- Like GlobalWindowController: update workspace BEFORE removing
					-- source target / adding destination target, with synchronous callbacks.
					f.emit("window.move_to_workspace", w, dest)
					local target
					for i, old in ipairs(f.contexts[source.id].targets) do
						if old.window == w then target = table.remove(f.contexts[source.id].targets, i); break end
					end
					f.recalculate(source.id)
					table.insert(f.contexts[dest.id].targets, assert(target))
					f.recalculate(dest.id)
					if w.active then
						w.active = false
						local remaining = f.contexts[source.id].targets[1]
						if remaining then f.focus(remaining.window.stable_id)
						else f.active = nil; f.emit("window.active", nil) end
					end
					return { ok = true }
				end end }, { __index = function() return noop end }),
			}, { __index = function() return noop end }),
		}
		f.api = dofile("lua/extensions/bspwm.lua")
		f.api.set_feedback_sink(function(states) f.states = states end)
		if saved then f.emit("config.reloaded"); f.emit("config.props_refreshed", true) end
	end
	function f.open(id, wsid)
		local ws = f.workspace(wsid or 1)
		local window = { stable_id = id, workspace = ws, monitor = ws.monitor, mapped = true,
			active = false, floating = false, hidden = false, fullscreen = 0, focus_history_id = -1 }
		local target = { window = window }
		function target:place(box) self.box = box end
		f.windows[id] = window
		table.insert(f.contexts[ws.id].targets, target)
		f.recalculate(ws.id); f.focus(id)
		return window
	end
	function f.message(message)
		local id = f.active_ws.id
		local result = provider.layout_msg(f.snapshot(id), message)
		f.recalculate(id)
		return result
	end
	function f.presel(id, dir, ratio)
		f.focus(id); assert(f.message("preselect " .. dir) == true)
		if ratio then assert(f.message("pratio " .. ratio) == true) end
	end
	function f.pull() return f.message("pull") end
	function f.leaf(id) return find(f.states[f.windows[id].workspace.id].tree, id) end
	function f.box(id)
		for _, target in ipairs(f.contexts[f.windows[id].workspace.id].targets) do
			if target.window.stable_id == id then return target.box end
		end
	end
	function f.consistent()
		local seen = {}
		local function walk(node, wsid)
			if not node then return end
			if node.t == "split" then walk(node.a, wsid); walk(node.b, wsid); return end
			assert(not seen[node.id], "duplicate leaf " .. node.id)
			assert(f.windows[node.id].workspace.id == wsid, "wrong workspace ownership")
			seen[node.id] = true
		end
		for id, state in pairs(f.states) do walk(state.tree, id) end
		for _, w in ipairs(all_windows()) do if w.mapped and not w.floating then assert(seen[w.stable_id]) end end
	end
	f.load()
	return f
end

local function expect_box(b, x, y, w, h)
	assert(b.x == x and b.y == y and b.w == w and b.h == h,
		string.format("unexpected box %g,%g %gx%g", b.x, b.y, b.w, b.h))
end

function tests.pulls_last_focused_not_newest_across_monitors()
	local f = fixture()
	f.open(1, 1); f.open(2, 2); f.open(3, 2)
	f.focus(2); f.focus(1)
	local age = f.leaf(2).n
	assert(f.pull() == true)
	assert(f.windows[2].workspace.id == 1 and f.windows[3].workspace.id == 2)
	assert(f.windows[2].monitor == f.windows[1].monitor)
	assert(f.active == f.windows[2] and f.active_ws.id == 1 and f.leaf(2).n == age)
	assert(#f.focus_calls == 1 and f.focus_calls[1] == 2)
	expect_box(f.box(1), 0, 0, 800, 900)
	expect_box(f.box(2), 800, 0, 800, 900)
	expect_box(f.box(3), 2000, 0, 1600, 900)
	f.consistent()
end

function tests.pulls_from_hidden_desktop_on_same_monitor_and_prunes_empty_source()
	local f = fixture()
	local ws = f.workspace(1)
	f.workspace(2, ws.monitor).visible = false
	f.open(1, 1); f.open(2, 2); f.focus(1)
	assert(f.pull() == true)
	assert(f.windows[2].workspace.id == 1 and not f.states[2].tree and not next(f.states[2].boxes))
	assert(f.active == f.windows[2] and f.active_ws.id == 1 and not f.workspaces[2].visible)
	f.consistent()
end

function tests.automatic_sends_to_last_manual_then_focuses_the_inserted_node()
	local f = fixture()
	f.open(1, 1); f.open(2, 2); f.open(3, 3)
	f.presel(2, "r"); f.presel(1, "u", 0.3); f.focus(3)
	local age = f.leaf(3).n
	assert(f.pull() == true)
	assert(f.windows[3].workspace.id == 1 and not f.states[3].tree)
	assert(f.active_ws.id == 1 and f.active == f.windows[3], "focus must follow the inserted node")
	assert(not f.leaf(1).presel and f.leaf(2).presel and f.leaf(3).n == age)
	expect_box(f.box(3), 0, 0, 1600, 270)
	expect_box(f.box(1), 0, 270, 1600, 630)
	f.consistent()
end

function tests.manual_focus_pulls_instead_of_sending_to_another_manual()
	local f = fixture()
	f.open(1, 1); f.open(2, 2); f.open(3, 3)
	f.presel(2, "u"); f.focus(3); f.presel(1, "l", 0.25)
	assert(f.pull() == true)
	assert(f.windows[3].workspace.id == 1 and f.windows[2].workspace.id == 2)
	assert(f.leaf(2).presel and not f.leaf(1).presel)
	expect_box(f.box(3), 0, 0, 400, 900)
	f.consistent()
end

function tests.same_workspace_uses_history_and_longest_side_not_always_right()
	local f = fixture()
	for id = 1, 3 do f.open(id) end
	f.focus(2); f.focus(1)
	assert(f.pull() == true)
	assert(#f.moves == 0)
	assert(f.active == f.windows[2] and #f.focus_calls == 1)
	-- After detaching 2, anchor 1 is taller than wide: insert below it.
	expect_box(f.box(1), 0, 0, 800, 450)
	expect_box(f.box(2), 0, 450, 800, 450)
	expect_box(f.box(3), 800, 0, 800, 900)
	f.consistent()
end

function tests.subtree_destination_presel_survives_focus_on_another_monitor()
	local f = fixture()
	f.open(1, 1); f.open(2, 1)
	f.message("focus parent"); f.message("preselect u"); f.message("pratio 0.25")
	local anchor = f.states[1].selected
	f.open(3, 2)
	assert(not f.states[1].selected and anchor.presel)
	assert(f.pull() == true)
	assert(f.states[1].tree.b == anchor and not anchor.presel)
	expect_box(f.box(3), 0, 0, 1600, 225)
	f.consistent()
end

function tests.selected_automatic_subtree_moves_intact_despite_partial_callbacks()
	local f = fixture()
	for id = 1, 3 do f.open(id, 1) end
	f.message("focus parent"); f.message("grow u 50")
	local moving = f.states[1].selected
	local ratio = moving.ratio
	f.open(4, 2); f.presel(4, "r", 0.4)
	f.focus(3); f.message("focus parent")
	f.before_focus = function(window)
		assert(#f.moves == 2 and window == f.windows[3], "must finish every move before focusing the representative")
		assert(f.states[2].tree.b == moving, "focus preceded tree insertion")
		expect_box(f.box(1), 0, 0, 1600, 900)
		assert(f.box(3).x >= 2000, "destination geometry was not replayed before focus")
	end
	assert(f.pull() == true)
	assert(f.windows[2].workspace.id == 2 and f.windows[3].workspace.id == 2)
	assert(f.states[2].tree.b == moving and moving.ratio == ratio)
	assert(f.states[1].tree.id == 1 and f.active_ws.id == 2 and f.active == f.windows[3])
	assert(#f.focus_calls == 1 and f.states[2].selected == moving and f.states[2].selected_focus_id == 3)
	expect_box(f.box(1), 0, 0, 1600, 900)
	f.consistent()
end

function tests.whole_workspace_subtree_move_filters_stale_source_snapshots()
	local f = fixture()
	f.open(1, 1); f.open(2, 1); f.open(3, 2); f.presel(3, "u")
	f.focus(2); f.message("focus parent")
	assert(f.pull() == true)
	assert(not f.states[1].tree and #f.contexts[1].targets == 0)
	assert(f.windows[1].workspace.id == 2 and f.windows[2].workspace.id == 2)
	f.consistent()
end

function tests.pull_into_selected_manual_subtree_preserves_anchor_shape()
	local f = fixture()
	f.open(3, 2); f.open(1, 1); f.open(2, 1)
	f.focus(3); f.focus(2); f.message("focus parent")
	f.message("preselect l"); f.message("pratio 0.2")
	local anchor = f.states[1].selected
	assert(f.pull() == true)
	assert(f.states[1].tree.b == anchor and f.states[1].tree.a.id == 3)
	expect_box(f.box(3), 0, 0, 320, 900)
	f.consistent()
end

function tests.no_history_peer_or_floating_focus_is_a_noop()
	local f = fixture()
	f.open(1, 1); assert(f.pull() == true and #f.moves == 0 and #f.focus_calls == 0)
	f.open(2, 2); f.windows[2].focus_history_id = -1; f.focus(1)
	f.windows[2].focus_history_id = -1
	assert(f.pull() == true and #f.moves == 0)
	f.active.active = false -- native layout context has no active tile while a float is focused
	assert(f.pull() == true and #f.moves == 0)
	f.consistent()
end

function tests.hidden_windows_and_other_layouts_are_not_candidates()
	local f = fixture()
	for id = 1, 4 do f.open(id, id) end
	f.windows[3].hidden = true
	f.workspaces[4].tiled_layout = "dwindle"
	f.focus(2); f.focus(3); f.focus(4); f.focus(1)
	assert(f.pull() == true)
	assert(f.windows[2].workspace.id == 1)
	f.consistent()
end

function tests.native_groups_are_not_partially_moved()
	local f = fixture()
	f.open(1, 1); f.open(2, 2); f.open(3, 3)
	f.windows[3].group = {}
	f.focus(1)
	assert(f.pull() == true)
	assert(f.windows[2].workspace.id == 1 and f.windows[3].workspace.id == 3)
	f.consistent()
end

function tests.repeated_global_moves_keep_one_leaf_per_window()
	local f = fixture()
	for id = 1, 8 do f.open(id, (id % 3) + 1) end
	for step = 1, 60 do
		f.focus((step * 3) % 8 + 1)
		if step % 3 == 0 then f.message("focus parent") end
		if step % 2 == 0 then f.message("preselect u") end
		assert(f.pull() == true)
		f.consistent()
		assert(codec.decode(codec.encode(f.states)))
	end
end

function tests.named_workspace_uses_name_not_relative_negative_id()
	local f = fixture()
	local named = f.workspace(-1337, f.workspace(1).monitor)
	named.name, named.tiled_layout = "named-fixture", "lua:bspwm_b"
	f.open(1, 1); f.open(2, -1337); f.presel(2, "r"); f.focus(1)
	assert(f.pull() == true and f.moves[1].workspace == "name:named-fixture")
	f.consistent()
end

function tests.special_workspace_uses_its_full_name()
	local f = fixture()
	local special = f.workspace(-98, f.workspace(1).monitor)
	special.name, special.special = "special:fixture", true
	f.open(1, 1); f.open(2, -98); f.presel(2, "r"); f.focus(1)
	assert(f.pull() == true and f.moves[1].workspace == "name:special:fixture")
	f.consistent()
end

for _, failure_kind in ipairs({ "fail_id", "throw_id", "ignore_move" }) do
	tests["failed_move_preserves_trees_and_presel_" .. failure_kind] = function()
		local f = fixture()
		f.open(1, 1); f.open(2, 2); f.presel(2, "u"); f.focus(1)
		local before = codec.encode(f.states)
		f[failure_kind] = failure_kind == "ignore_move" and true or 1
		assert(type(f.pull()) == "string")
		assert(codec.encode(f.states) == before)
		assert(#f.focus_calls == 0 and f.active == f.windows[1], "failed move must not refocus")
		f[failure_kind] = nil
		assert(f.pull() == true, "transfer guard did not recover after failure")
		f.consistent()
	end
end

function tests.partial_subtree_failure_reconciles_actual_ownership()
	local f = fixture()
	f.open(1, 1); f.open(2, 1); f.open(3, 2); f.presel(3, "r")
	f.focus(2); f.message("focus parent")
	f.fail_id = 2
	assert(type(f.pull()) == "string")
	assert(f.windows[1].workspace.id == 2 and f.windows[2].workspace.id == 1)
	assert(#f.focus_calls == 0 and f.active == f.windows[2], "partial failure must not jump focus")
	f.consistent()
end

function tests.failed_focus_keeps_completed_transfer_and_reports_failure()
	local f = fixture()
	f.open(1, 1); f.open(2, 2); f.focus(1)
	f.fail_focus = true
	assert(type(f.pull()) == "string")
	assert(f.windows[2].workspace.id == 1 and f.active == f.windows[1])
	f.consistent()
	f.fail_focus = nil
	assert(f.pull() == true and f.active == f.windows[2])
end

function tests.monocle_workspace_is_still_a_valid_pull_destination()
	local f = fixture()
	f.open(1, 1); f.message("monocle"); f.open(2, 2); f.focus(1)
	assert(f.pull() == true and f.states[1].mode == "monocle")
	assert(f.active == f.windows[2])
	expect_box(f.box(1), 0, 0, 1600, 900)
	expect_box(f.box(2), 0, 0, 1600, 900)
	f.consistent()
end

function tests.global_history_and_presels_work_after_reload()
	local f = fixture()
	f.open(1, 1); f.open(2, 2); f.presel(1, "u", 0.3); f.focus(2)
	f.load(codec.encode(f.states))
	assert(f.pull() == true)
	assert(f.windows[2].workspace.id == 1 and not f.leaf(1).presel)
	f.consistent()
	local restored = assert(codec.decode(f.saved))
	assert(find(restored.states[1].tree, 2) and not restored.states[2].tree)
end

function tests.super_y_binding_reaches_global_pull()
	local f = fixture()
	f.open(1, 1); f.open(2, 2); f.focus(1)
	package.loaded["lua/extensions/bspwm"] = f.api
	package.loaded["lua/bindings"], package.loaded["lua/helpers"] = nil, nil
	require("lua/bindings")
	assert(f.binds["SUPER + y"])
	f.binds["SUPER + y"]()
	assert(f.windows[2].workspace.id == 1 and f.active == f.windows[2])
	f.consistent()
end

local names, failures = {}, 0
for name in pairs(tests) do names[#names + 1] = name end
table.sort(names)
for _, name in ipairs(names) do
	local ok, err = pcall(tests[name])
	if ok then print("PASS " .. name)
	else failures = failures + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
print(string.format("%d/%d tests passed", #names - failures, #names))
os.exit(failures == 0 and 0 or 1)
