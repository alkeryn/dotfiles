-- lua tests/bspwm_floating_test.lua [provider_path]
-- Real layout, with v0.56.2 Algorithm::setFloating ordering: removeTarget()
-- recalculates BEFORE setFloating(), and zero-target layouts skip Lua entirely.
local codec = require("lua/extensions/bspwm_state")
local tree = require("lua/extensions/bspwm_tree")
local tests = {}
package.loaded["lua/extensions/bspwm_state"] = { open_session = function() return nil end }

local function fixture(count)
	package.loaded["lua/extensions/bspwm_state"] = { open_session = function() return nil end }
	local f = { windows = {}, targets = {}, events = {}, contexts = {}, geometry_calls = {} }
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
		end end,
		fullscreen_state = function(opts) return function()
			local w = opts.window
			if opts.internal ~= 0 and (w.fullscreen or 0) == 0 then w.before_fullscreen = { at=w.at, size=w.size } end
			w.fullscreen, w.fullscreen_client = opts.internal, opts.client
			if opts.internal == 0 and w.before_fullscreen then
				w.at, w.size = w.before_fullscreen.at, w.before_fullscreen.size
				w.before_fullscreen = nil
			elseif opts.internal ~= 0 then
				w.at, w.size = { x=0, y=0 }, { x=1200, y=800 }
			end
		end end,
		pseudo = function(opts) return function() opts.window.pseudo = opts.action == "on" end end,
		float = function(opts) return function()
			local w, floating = opts.window, opts.action == "on"
			if f.reject_float then return { ok=false } end
			if floating ~= w.floating and not f.ignore_float then
				if floating then f.float(w.stable_id) else f.tile(w.stable_id) end
			end
			if f.after_float_dispatch then f.after_float_dispatch(w) end
			return { ok=true }
		end end,
		resize = function(opts) return function()
			local w = opts.window
			assert(w.floating and not opts.relative)
			table.insert(f.geometry_calls, "resize:" .. w.stable_id)
			if f.reject_resize then return { ok=false } end
			w.at = { x=w.at.x - (opts.x-w.size.x)/2, y=w.at.y - (opts.y-w.size.y)/2 }
			w.size = { x=opts.x, y=opts.y }
			return { ok=true }
		end end,
		move = function(opts) return function()
			local w = opts.window
			assert(w.floating and not opts.relative)
			table.insert(f.geometry_calls, "move:" .. w.stable_id)
			w.at = { x=opts.x, y=opts.y }
			return { ok=true }
		end end }, focus = function(opts) return function() f.focus(opts.window.stable_id) end end },
	}
	f.api = dofile(arg[1] or "lua/extensions/bspwm.lua")
	f.api.set_feedback_sink(function(states) f.states = states end)
	function f.open(id, wsid)
		local w = { stable_id = id, workspace = { id = wsid or 1, tiled_layout = "lua:bspwm" }, mapped = true,
			floating = false, focus_history_id = 100, active = false,
			monitor = { position = { x=0, y=0 }, width=1200, height=800, scale=1 } }
		f.windows[id] = w
		f.emit("window.open_early", w)
		local target = { window = w, placements = 0 }
		function target:place(box)
			self.box = box; self.placements = self.placements + 1
			w.at, w.size = { x=box.x, y=box.y }, { x=box.w, y=box.h }
		end
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
		-- DefaultFloatingAlgorithm::movedTarget runs AFTER update_rules and
		-- recentres on the current tile, even if a float was previously moved.
		local size = w.last_float_size or { x=640, y=400 }
		local width, height = size.x, size.y
		if math.abs(width-w.size.x) < 5 and math.abs(height-w.size.y) < 5 then width, height = width+10, height+10 end
		w.at = { x=w.at.x+(w.size.x-width)/2, y=w.at.y+(w.size.y-height)/2 }
		w.size = { x=width, y=height }
		f.recalculate(w.workspace.id)
		assert(f.targets[id].placements == placements, "layout placed a floating target")
	end
	function f.tile(id)
		local w = f.windows[id]
		assert(w.floating)
		w.last_float_size = { x=w.size.x, y=w.size.y }
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
	function f.destroy(id)
		local w = assert(f.windows[id])
		f.windows[id], f.targets[id] = nil, nil
		if f.active == w then f.active = nil end
		-- CLuaWindow::push creates truthy userdata even for an expired weak
		-- reference. Its __index returns nil for EVERY property, including ID.
		-- The saved handle expires too; the event supplies a fresh wrapper.
		for key in pairs(w) do w[key] = nil end
		f.emit("window.destroy", {})
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
	function f.set_state(state)
		package.loaded["lua/extensions/bspwm"] = f.api
		package.loaded["lua/helpers"] = nil
		package.loaded["lua/vars"] = { GAPS=4, GAPS_OUT=8 }
		require("lua/helpers").set_window_state(state)
	end
	function f.reload()
		local saved = f.snapshot()
		f.events = {}
		package.loaded["lua/extensions/bspwm_state"] = { open_session = function() return {
			load = function() return assert(codec.decode(saved)) end,
			save = function(_, states) f.saved = codec.encode(states); return true end,
		} end }
		f.api = dofile(arg[1] or "lua/extensions/bspwm.lua")
		f.api.set_feedback_sink(function(states) f.states = states end)
		f.emit("config.reloaded"); f.emit("config.props_refreshed", true)
		for id in pairs(f.contexts) do f.recalculate(id) end
	end
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

function tests.destroy_expired_windows_does_not_raise_or_restore_closed_slots()
	local f = fixture(3)
	f.float(2)
	for _, id in ipairs({ 2, 3, 1 }) do
		f.close(id)
		f.destroy(id)
		assert(not f.leaf(id), "destroy restored a closed leaf")
		f.emit("config.props_refreshed", true)
	end
	assert(not f.states[1].tree and not next(f.states[1].boxes))
	f.open(4)
	expect_box(f.targets[4].box, 0, 0, 1200, 800)
end

function tests.destroy_releases_saved_weak_handles()
	local f = fixture(1)
	local handles = setmetatable({ f.windows[1] }, { __mode = "v" })
	f.close(1)
	f.destroy(1)
	collectgarbage("collect")
	assert(not handles[1], "destroy leaked a closing record")
end

function tests.destroy_untracked_or_nil_window_is_harmless()
	local f = fixture(1)
	local original = f.snapshot()
	f.emit("window.destroy", {}) -- destroyed before ever mapping
	f.emit("window.destroy", nil)
	f.emit("config.props_refreshed", true)
	assert(f.snapshot() == original)
end

function tests.destroy_does_not_clear_another_in_progress_close()
	local f = fixture(3)
	f.close(1)
	local closing = f.windows[2]
	f.emit("window.close", closing) -- still mapped and still a native target
	local placements = f.targets[2].placements
	f.destroy(1)
	f.recalculate()
	assert(not f.leaf(2) and f.targets[2].placements == placements,
		"destroying another window forgot the in-progress close")
	-- The same native object can remap without being destroyed first.
	f.remove_target(2)
	f.open(2)
	assert(f.leaf(2) and not f.leaf(2).vacant)
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

local function set_rectangle(w, x, y, width, height)
	w.at, w.size = { x=x, y=y }, { x=width, y=height }
end

local function expect_rectangle(w, x, y, width, height)
	expect_box({ x=w.at.x, y=w.at.y, w=w.size.x, h=w.size.y }, x, y, width, height)
end

function tests.state_shortcuts_restore_latest_float_position_without_reinsertion()
	local f = fixture(3)
	f.focus(2)
	local root, node, age = f.states[1].tree, f.leaf(2), f.leaf(2).n
	f.set_state("floating")
	assert(#f.geometry_calls == 0, "first float must keep native placement")
	for i = 1, 4 do
		set_rectangle(f.windows[2], 70+i, 90+i, 630+i, 420+i)
		f.set_state("tiled")
		assert(node.floating_geometry.x == 70+i)
		f.set_state("tiled") -- repeat must not overwrite with tiled geometry
		f.set_state("floating")
		expect_rectangle(f.windows[2], 70+i, 90+i, 630+i, 420+i)
		assert(f.states[1].tree == root and f.leaf(2) == node and node.n == age and f.states[1].seq == 3)
	end
end

function tests.leaf_move_preserves_saved_floating_rectangle()
	local f = fixture(3)
	f.focus(1); f.set_state("floating")
	set_rectangle(f.windows[1], 80, 90, 650, 430)
	f.set_state("tiled")
	local node, saved = f.leaf(1), f.leaf(1).floating_geometry
	f.message("move r")
	assert(f.leaf(1) == node and node.floating_geometry == saved)
	f.set_state("floating")
	expect_rectangle(f.windows[1], 80, 90, 650, 430)
end

function tests.repeated_float_shortcut_does_not_undo_a_manual_move()
	local f = fixture(1)
	f.set_state("floating")
	set_rectangle(f.windows[1], 80, 90, 500, 300)
	f.set_state("tiled"); f.set_state("floating")
	set_rectangle(f.windows[1], 250, 320, 550, 310)
	local calls = #f.geometry_calls
	for _ = 1, 4 do f.set_state("floating") end
	expect_rectangle(f.windows[1], 250, 320, 550, 310)
	assert(#f.geometry_calls == calls)
end

function tests.native_equal_size_growth_is_undone_before_restoring_position()
	local f = fixture(1)
	f.set_state("floating")
	set_rectangle(f.windows[1], -20, 40, 1200, 800)
	f.set_state("tiled"); f.set_state("floating")
	expect_rectangle(f.windows[1], -20, 40, 1200, 800)
	assert(table.concat(f.geometry_calls, ",") == "resize:1,move:1")
end

function tests.float_geometry_survives_reload_while_tiled_or_floating()
	local f = fixture(2)
	f.focus(1); f.set_state("floating")
	set_rectangle(f.windows[1], 170, 230, 680, 440)
	f.set_state("tiled")
	for _ = 1, 3 do
		f.reload(); f.set_state("floating")
		expect_rectangle(f.windows[1], 170, 230, 680, 440)
		f.set_state("tiled")
	end
	f.set_state("floating")
	set_rectangle(f.windows[1], 220, 140, 500, 350)
	f.reload(); f.set_state("tiled"); f.set_state("floating")
	expect_rectangle(f.windows[1], 220, 140, 500, 350)
end

function tests.initially_floating_client_acquires_geometry_on_first_tile()
	local f = fixture(0)
	f.open(1); f.float(1)
	f.states[1].tree = nil -- window was born floating; no previous tiled slot
	set_rectangle(f.windows[1], 110, 120, 640, 380)
	f.set_state("tiled")
	assert(f.leaf(1).floating_geometry.x == 110)
	f.set_state("floating")
	expect_rectangle(f.windows[1], 110, 120, 640, 380)
end

function tests.fullscreen_and_pseudo_transitions_do_not_replace_float_rectangle()
	for _, state in ipairs({ "fullscreen", "pseudo_tiled" }) do
		local f = fixture(2)
		f.focus(1); f.set_state("floating")
		set_rectangle(f.windows[1], 75, 85, 650, 450)
		f.set_state(state); f.set_state(state); f.set_state("floating")
		expect_rectangle(f.windows[1], 75, 85, 650, 450)
	end
	local f = fixture(1)
	f.set_state("floating"); set_rectangle(f.windows[1], 75, 85, 650, 450)
	-- A client can request fullscreen while retaining its floating flag.
	hl.dispatch(hl.dsp.window.fullscreen_state({ window=f.windows[1], internal=2, client=2 }))
	f.set_state("tiled"); f.set_state("floating")
	expect_rectangle(f.windows[1], 75, 85, 650, 450)
end

function tests.restoration_uses_original_window_even_if_dispatch_changes_focus()
	local f = fixture(2)
	f.focus(1); f.set_state("floating")
	set_rectangle(f.windows[1], 80, 90, 650, 430)
	f.set_state("tiled")
	f.after_float_dispatch = function() f.focus(2) end
	f.set_state("floating")
	expect_rectangle(f.windows[1], 80, 90, 650, 430)
	assert(f.active.stable_id == 2 and table.concat(f.geometry_calls, ",") == "move:1")
end

function tests.failed_or_interrupted_float_dispatch_never_moves_a_tile_or_closed_window()
	for _, failure in ipairs({ "reject_float", "ignore_float", "close" }) do
		local f = fixture(1)
		f.set_state("floating"); set_rectangle(f.windows[1], 80, 90, 650, 430)
		f.set_state("tiled")
		if failure == "close" then f.after_float_dispatch = function() f.close(1) end
		else f[failure] = true end
		f.set_state("floating")
		assert(#f.geometry_calls == 0)
	end
end

function tests.monitor_change_translates_saved_position_and_fits_smaller_output()
	local f = fixture(1)
	f.set_state("floating"); set_rectangle(f.windows[1], 900, 550, 300, 200)
	f.set_state("tiled")
	f.windows[1].monitor = { position={ x=-800, y=0 }, width=800, height=600, scale=1 }
	f.set_state("floating")
	expect_rectangle(f.windows[1], -300, 400, 300, 200)
end

function tests.remapped_client_does_not_inherit_old_float_geometry()
	local f = fixture(1)
	f.set_state("floating"); set_rectangle(f.windows[1], 80, 90, 650, 430)
	f.set_state("tiled"); f.close(1); f.open(1); f.set_state("floating")
	assert(not f.leaf(1).floating_geometry and #f.geometry_calls == 0)
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
