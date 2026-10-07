-- lua tests/bspwm_floating_test.lua [provider_path]
-- Real layout, with v0.56.2 Algorithm::setFloating ordering: removeTarget()
-- recalculates BEFORE setFloating(), and zero-target layouts skip Lua entirely.
local codec = require("lua/extensions/bspwm_state")
local tree = require("lua/extensions/bspwm_tree")
local tests = {}
package.loaded["lua/extensions/bspwm_state"] = { open_session = function() return nil end }

local function fixture(count)
	local f = { windows = {}, targets = {}, events = {}, contexts = {} }
	local provider
	function f.context(id)
		if not f.contexts[id] then
			f.contexts[id] = { area = { x = 0, y = 0, w = 1200, h = 800 }, targets = {} }
		end
		return f.contexts[id]
	end
	function f.emit(event, ...)
		for _, callback in ipairs(f.events[event] or {}) do callback(...) end
	end
	function f.recalculate(id)
		local ctx = f.context(id or 1)
		if #ctx.targets > 0 then provider.recalculate(ctx) end
	end
	function f.focus(id)
		for _, w in pairs(f.windows) do
			w.active = w.stable_id == id
			w.focus_history_id = w.active and 0 or w.focus_history_id + 1
		end
		f.active = f.windows[id]
		f.emit("window.active", f.active)
	end
	local function noop() return function() end end
	local function rule() return { set_enabled = function() end } end
	_G.hl = {
		layout = { register = function(name, impl) if name == "bspwm" then provider = impl end end },
		on = function(event, callback)
			f.events[event] = f.events[event] or {}
			table.insert(f.events[event], callback)
		end,
		get_windows = function()
			local result = {}
			for _, w in pairs(f.windows) do result[#result + 1] = w end
			return result
		end,
		get_active_window = function() return f.active end,
		window_rule = rule, workspace_rule = rule,
		dispatch = function(callback) return callback() end,
		dsp = { window = { alter_zorder = noop, tag = function() return function()
			if f.reenter_tags then f.recalculate() end
		end end }, focus = function(opts) return function() f.focus(opts.window.stable_id) end end },
	}
	f.api = dofile(arg[1] or "lua/extensions/bspwm.lua")
	f.api.set_feedback_sink(function(states) f.states = states end)
	function f.open(id, wsid)
		local w = { stable_id = id, workspace = { id = wsid or 1 }, mapped = true,
			floating = false, focus_history_id = 100, active = false }
		f.windows[id] = w
		f.emit("window.open_early", w)
		local target = { window = w, placements = 0 }
		function target:place(box) self.box = box; self.placements = self.placements + 1 end
		f.targets[id] = target
		table.insert(f.context(w.workspace.id).targets, target)
		f.recalculate(w.workspace.id); f.emit("window.open", w); f.focus(id)
	end
	function f.remove_target(id)
		local targets = f.context(f.windows[id].workspace.id).targets
		for i, target in ipairs(targets) do
			if target.window.stable_id == id then table.remove(targets, i); return end
		end
	end
	function f.float(id)
		local w = f.windows[id]
		assert(not w.floating)
		local placements = f.targets[id].placements
		f.remove_target(id)
		f.recalculate(w.workspace.id) -- flag is still false!
		if f.after_remove then f.after_remove(w) end
		w.floating = true
		f.emit("window.update_rules", w)
		f.recalculate(w.workspace.id)
		assert(f.targets[id].placements == placements, "layout placed a floating target")
	end
	function f.tile(id)
		local w = f.windows[id]
		assert(w.floating)
		w.floating = false
		f.emit("window.update_rules", w) -- before movedTarget/newTarget
		table.insert(f.context(w.workspace.id).targets, f.targets[id])
		f.recalculate(w.workspace.id)
	end
	function f.close(id)
		local w = f.windows[id]
		f.emit("window.close", w) -- native close event precedes mapped=false
		w.mapped = false
		f.remove_target(id)
		f.recalculate(w.workspace.id)
	end
	function f.message(message, wsid)
		assert(provider.layout_msg(f.context(wsid or 1), message) == true)
		f.recalculate(wsid)
	end
	function f.leaf(id, wsid)
		local path = tree.find_path(f.states[wsid or 1].tree, id)
		return path and path[#path]
	end
	function f.snapshot() return codec.encode(f.states) end
	for id = 1, count or 4 do f.open(id) end
	return f
end

local function expect_box(box, x, y, w, h)
	assert(box and box.x == x and box.y == y and box.w == w and box.h == h, "unexpected tile geometry")
end

function tests.native_removal_before_floating_flag_retains_node_and_metadata()
	for id = 1, 4 do
		local f = fixture()
		f.focus(1); f.message("grow r 80")
		local original, node, age = f.snapshot(), f.leaf(id), f.leaf(id).n
		local boxes = {}
		for wid, target in pairs(f.targets) do boxes[wid] = target.box end
		f.after_remove = function(w)
			assert(not w.floating and f.leaf(id) == node and node.vacant, "removed live leaf instead of vacating it")
		end
		for _ = 1, 3 do
			f.float(id)
			f.focus(id == 1 and 4 or 1) -- reinsertion must NOT use current focus
			f.tile(id)
			assert(f.leaf(id) == node and node.n == age and not node.vacant)
			assert(f.snapshot() == original, "floating round trip changed the tree")
			for wid, b in pairs(boxes) do expect_box(f.targets[wid].box, b.x, b.y, b.w, b.h) end
		end
	end
end

function tests.vacant_subtree_expands_sibling_and_restores_in_any_order()
	local f = fixture(3)
	local original, root, branch = f.snapshot(), f.states[1].tree, f.states[1].tree.b
	f.float(2)
	expect_box(f.targets[3].box, 600, 0, 600, 800)
	f.float(3)
	assert(branch.vacant and f.states[1].tree == root)
	expect_box(f.targets[1].box, 0, 0, 1200, 800)
	f.float(1) -- NO callback after removal: update_rules must mark the root
	assert(root.vacant and not next(f.states[1].boxes))
	f.tile(3); expect_box(f.targets[3].box, 0, 0, 1200, 800)
	f.tile(1); expect_box(f.targets[3].box, 600, 0, 600, 800)
	f.tile(2)
	assert(f.snapshot() == original)
end

function tests.new_window_while_floating_changes_only_the_chosen_branch()
	local f = fixture(3)
	local root, branch, node = f.states[1].tree, f.states[1].tree.b, f.leaf(2)
	f.float(2); f.focus(1); f.open(4)
	f.tile(2)
	assert(f.states[1].tree == root and root.b == branch and branch.a == node)
	assert(root.a.a.id == 1 and root.a.b.id == 4 and f.states[1].seq == 4)
	expect_box(f.targets[2].box, 600, 0, 600, 400)
	expect_box(f.targets[3].box, 600, 400, 600, 400)
end

function tests.closing_sibling_while_floating_promotes_the_saved_leaf()
	local f = fixture(3)
	local node = f.leaf(2)
	f.float(2); f.close(3)
	assert(f.states[1].tree.b == node and node.vacant)
	f.tile(2)
	expect_box(f.targets[2].box, 600, 0, 600, 800)
	assert(f.states[1].seq == 3)
end

function tests.close_last_float_and_remap_do_not_resurrect_stale_slot()
	local f = fixture(1)
	f.float(1); f.close(1)
	assert(not f.states[1].tree and not next(f.states[1].boxes))
	f.open(1)
	assert(f.leaf(1).n == 2 and not f.leaf(1).vacant)
end

function tests.close_selected_tile_is_safe_during_reentrant_tag_updates()
	local f = fixture(3)
	f.message("focus parent")
	f.reenter_tags = true
	f.close(2)
	assert(not f.leaf(2) and f.states[1].seq == 3)
end

function tests.moving_a_float_discards_only_its_old_workspace_slot()
	local f = fixture(3)
	f.float(2)
	local w = f.windows[2]
	w.workspace = { id = 2 }
	f.emit("window.move_to_workspace", w, w.workspace)
	assert(not f.leaf(2) and f.states[1].tree.b.id == 3)
	f.tile(2)
	assert(f.leaf(2, 2) and not f.leaf(2))
end

function tests.float_cancels_only_vacant_preselections_and_does_not_consume_others()
	local f = fixture(3)
	f.focus(2); f.message("preselect l")
	f.focus(3); f.message("focus parent"); f.message("preselect u")
	local branch = f.states[1].tree.b
	f.float(2)
	assert(not f.leaf(2).presel and branch.presel)
	f.focus(1); f.message("preselect d"); f.message("pratio 0.3")
	local pre = f.leaf(1).presel
	f.tile(2)
	assert(f.leaf(1).presel == pre and f.states[1].seq == 3)
	f.float(2); f.float(3)
	assert(branch.vacant and not branch.presel)
end

function tests.monocle_float_round_trip_keeps_the_underlying_tree()
	local f = fixture(3)
	local original = f.snapshot()
	f.message("monocle"); f.float(2); f.focus(1); f.tile(2); f.message("tiled")
	assert(f.snapshot() == original)
	expect_box(f.targets[2].box, 600, 0, 600, 400)
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
