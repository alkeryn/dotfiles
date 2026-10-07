-- lua tests/bspwm_pull_test.lua -- pull, selected desktop move, desktop swap and pointer drag;
-- native move/recalculation ordering and pointer timers are mocked.
local codec = require("lua/extensions/bspwm_state")
local tests = {}
-- Bindings need constants, not the host's ~/bin/wpc machine detection.
package.loaded["lua/vars"] = { FLOAT_STEP = 20, terminal = "alacritty", GAPS = 4, GAPS_OUT = 8 }

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
		local mon = monitor or { id = id, name = "monitor-" .. id, position = { x = (id - 1) * 2000, y = 0 }, width = 1600, height = 900, scale = 1 }
		local ws = { id = id, name = tostring(id), monitor = mon, tiled_layout = "lua:bspwm", visible = true }
		function ws:get_windows()
			local result = {}
			for _, w in pairs(f.windows) do
				if w.mapped and w.workspace.id == self.id then result[#result + 1] = w end
			end
			table.sort(result, function(a, b) return a.stable_id < b.stable_id end)
			return result
		end
		f.workspaces[id] = ws
		mon.active_workspace = mon.active_workspace or ws
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
	function f.focus(id, reason)
		local window = f.windows[id]
		for _, w in pairs(f.windows) do w.active = w == window end
		local old_ws = f.active_ws
		f.active, f.active_ws = window, window.workspace
		window.workspace.last_window = window
		if old_ws ~= f.active_ws then
			f.emit("workspace.active", f.active_ws)
			if not old_ws or old_ws.monitor ~= f.active_ws.monitor then f.emit("monitor.focused", window.monitor) end
		end
		for i, old in ipairs(f.history) do if old == id then table.remove(f.history, i); break end end
		table.insert(f.history, 1, id)
		for rank, wid in ipairs(f.history) do f.windows[wid].focus_history_id = rank - 1 end
		f.emit("window.active", window, reason)
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
		f.rules = {}
		local function rule(spec)
			local handle = { spec = spec, enabled = true }
			function handle:set_enabled(enabled) self.enabled = enabled end
			f.rules[#f.rules + 1] = handle
			return handle
		end
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
			get_workspace = function(sel)
				if type(sel) == "table" then return f.workspaces[sel.id] end
				if tonumber(sel) then return f.workspaces[tonumber(sel)] end
				for _, ws in pairs(f.workspaces) do if sel == "name:" .. ws.name then return ws end end
			end,
			get_workspaces = function()
				local result = {}
				for _, ws in pairs(f.workspaces) do result[#result + 1] = ws end
				-- Native enumeration is not necessarily numeric workspace order.
				table.sort(result, function(a, b) return a.id > b.id end)
				return result
			end,
			bind = function(keys, dispatcher) f.binds[keys] = dispatcher end,
			dispatch = function(dispatcher) return dispatcher() end,
			dsp = setmetatable({
				layout = function(message) return function() return { ok = f.message(message) == true } end end,
				focus = function(opts) return function()
					if opts.workspace then
						f.active_ws, f.active = assert(hl.get_workspace(opts.workspace)), nil
						for _, w in pairs(f.windows) do w.active = false end
						f.emit("workspace.active", f.active_ws)
						f.emit("window.active", nil)
						return { ok = true }
					end
					f.focus_calls[#f.focus_calls + 1] = opts.window.stable_id
					if f.before_focus then f.before_focus(opts.window) end
					if f.fail_focus then return { ok = false } end
					f.focus(opts.window.stable_id)
					return { ok = true }
				end end,
				window = setmetatable({ tag = function(opts) return function()
					opts.window.tags[opts.tag:sub(2)] = opts.tag:sub(1, 1) == "+" or nil
					if f.after_tag then f.after_tag(opts.window) end
					return { ok = true }
				end end, move = function(opts) return function()
					local w, dest = opts.window or f.active, f.workspaces[tonumber(opts.workspace)]
					if type(opts.workspace) == "string" and opts.workspace:sub(1, 5) == "name:" then
						for _, ws in pairs(f.workspaces) do if ws.name == opts.workspace:sub(6) then dest = ws end end
					end
					if not dest and tonumber(opts.workspace) and tonumber(opts.workspace) > 0 then
						dest = f.workspace(tonumber(opts.workspace), f.active_ws.monitor)
					end
					assert(dest, "expected an absolute workspace ID or name selector")
					assert(type(opts.workspace) ~= "number" or opts.workspace > 0, "negative IDs parse as relative selectors")
					f.moves[#f.moves + 1] = opts
					if f.fail_id == w.stable_id or (f.fail_move and f.fail_move(w, dest)) then return { ok = false } end
					if f.throw_id == w.stable_id then error("synthetic dispatcher exception") end
					if f.ignore_move then return { ok = true } end
					local source = w.workspace
					if source == dest then return { ok = true } end
					w.workspace, w.monitor = dest, dest.monitor
					-- Like GlobalWindowController: update workspace BEFORE removing
					-- source target / adding destination target, with synchronous callbacks.
					f.emit("window.move_to_workspace", w, dest)
					local target
					for i, old in ipairs(f.contexts[source.id].targets) do
						if old.window == w then target = table.remove(f.contexts[source.id].targets, i); break end
					end
					f.recalculate(source.id)
					if not w.floating then table.insert(f.contexts[dest.id].targets, assert(target)) end
					f.recalculate(dest.id)
					if w.active then
						w.active = false
						local remaining = f.contexts[source.id].targets[1]
						if remaining then f.focus(remaining.window.stable_id)
						else f.active = nil; f.emit("window.active", nil) end
					end
					if opts.follow then f.focus(w.stable_id) end
					if f.after_move then f.after_move(w, dest) end
					return { ok = true }
				end end }, { __index = function() return noop end }),
			}, { __index = function() return noop end }),
		}
		f.api = dofile("lua/extensions/bspwm.lua")
		f.api.set_feedback_sink(function(states) f.states = states end)
		if saved then f.emit("config.reloaded"); f.emit("config.props_refreshed", true) end
	end
	function f.open(id, wsid, floating)
		local ws = f.workspace(wsid or 1)
		local window = { stable_id = id, workspace = ws, monitor = ws.monitor, mapped = true,
			active = false, floating = floating or false, hidden = false, fullscreen = 0, focus_history_id = -1, tags = { personal = true } }
		local target = { window = window }
		function target:place(box)
			if f.throw_placement then error("synthetic placement exception") end
			self.box = box
			window.at, window.size = { x = box.x, y = box.y }, { x = box.w, y = box.h }
		end
		f.windows[id] = window
		if not window.floating then table.insert(f.contexts[ws.id].targets, target) end
		f.recalculate(ws.id); f.focus(id)
		return window
	end
	function f.raw_message(message)
		return provider.layout_msg(f.snapshot(f.active_ws.id), message)
	end
	function f.message(message)
		local id = f.active_ws.id
		local result = f.raw_message(message)
		f.recalculate(id)
		return result
	end
	function f.presel(id, dir, ratio)
		f.focus(id); assert(f.message("preselect " .. dir) == true)
		if ratio then assert(f.message("pratio " .. ratio) == true) end
	end
	function f.pull() return f.message("pull") end
	function f.helpers()
		package.loaded["lua/extensions/bspwm"] = f.api
		package.loaded["lua/helpers"] = nil
		return require("lua/helpers")
	end
	function f.load_bindings()
		f.helpers(); package.loaded["lua/bindings"] = nil; require("lua/bindings")
	end
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

function tests.selected_move_does_not_prune_an_unrelated_vacant_leaf()
	local f = fixture()
	for id = 1, 3 do f.open(id) end
	local node = f.leaf(1)
	local target = table.remove(f.contexts[1].targets, 1)
	f.recalculate(1) -- removal before floating flag
	f.windows[1].floating = true
	f.emit("window.update_rules", f.windows[1])
	f.focus(3); f.message("focus parent")
	assert(f.api.move_to_workspace(2) == true)
	assert(f.states[1].tree == node and node.vacant and not next(f.states[1].boxes))
	f.windows[1].floating = false
	table.insert(f.contexts[1].targets, target)
	f.recalculate(1)
	assert(f.states[1].tree == node and not node.vacant and node.n == 1)
	f.consistent()
end

function tests.workspace_swap_keeps_floating_slots_with_their_original_trees()
	local f = fixture()
	for id = 1, 3 do f.open(id) end
	f.open(4, 2)
	local root, node = f.states[1].tree, f.leaf(2)
	local target = table.remove(f.contexts[1].targets, 2)
	f.recalculate(1)
	f.windows[2].floating = true
	f.emit("window.update_rules", f.windows[2])
	assert(f.api.swap_workspaces(f.workspaces[1], f.workspaces[2]) == true)
	assert(f.states[2].tree == root and root.b.a == node and node.vacant)
	f.windows[2].floating = false
	table.insert(f.contexts[2].targets, target)
	f.recalculate(2)
	assert(not node.vacant and node.n == 2 and f.states[2].seq == 3)
	f.consistent()
end

local function expect_box(b, x, y, w, h)
	assert(b.x == x and b.y == y and b.w == w and b.h == h,
		string.format("unexpected box %g,%g %gx%g", b.x, b.y, b.w, b.h))
end

function tests.selected_desktop_move_number_binding_transfers_intact_subtree()
	local f = fixture()
	for id = 1, 4 do f.open(id, 1) end
	f.open(5, 2); f.presel(5, "u", 0.3); f.focus(4)
	f.helpers(); package.loaded["lua/bindings"] = nil; require("lua/bindings")
	f.binds["SUPER + b"](); f.binds["SUPER + b"]()
	f.message("grow l 50"); f.message("preselect r"); f.message("pratio 0.4")
	local node = f.states[1].selected
	local before = codec.encode({ [1] = { tree = node, seq = 4, mode = "tiled" } })
	f.before_focus = function(w)
		assert(w == f.windows[4] and #f.moves == 3, "follow must wait for all selected windows")
		assert(f.states[2].tree.a == node, "follow must wait for subtree insertion")
		assert(f.box(4).x >= 2000, "follow must wait for destination geometry")
	end
	f.binds["SUPER + SHIFT + eacute"]()
	assert(#f.moves == 3, "desktop move only moved the representative, not all selected windows")
	for id = 2, 4 do
		assert(f.windows[id].workspace.id == 2 and f.windows[id].tags.bspwm_selected)
	end
	for _, move in ipairs(f.moves) do assert(move.follow == false) end
	assert(f.windows[1].workspace.id == 1 and f.windows[5].workspace.id == 2)
	assert(f.states[1].tree.id == 1 and f.states[2].tree.a == node and f.states[2].tree.ratio == 0.3)
	assert(not f.leaf(5).presel and f.states[2].selected == node and f.states[2].selected_focus_id == 4)
	assert(codec.encode({ [1] = { tree = node, seq = 4, mode = "tiled" } }) == before)
	assert(f.active == f.windows[4] and #f.focus_calls == 1)
	expect_box(f.box(1), 0, 0, 1600, 900)
	f.consistent()
end

function tests.selected_desktop_move_whole_tree_into_empty_or_new_workspace()
	for _, existing in ipairs({ false, true }) do
		for _, representative in ipairs({ 1, 3 }) do
			local f = fixture()
			for id = 1, 3 do f.open(id, 1) end
			if existing then f.workspace(2) end
			f.focus(representative); f.message("focus parent"); f.message("focus parent")
			local node = f.states[1].selected
			assert(f.api.move_to_workspace("2") == true)
			assert(#f.moves == 3 and not f.states[1].tree and not next(f.states[1].boxes))
			assert(f.states[2].tree == node and f.states[2].selected == node)
			assert(f.active.stable_id == representative and #f.focus_calls == 1)
			for _, w in pairs(f.windows) do assert(w.workspace.id == 2 and w.tags.bspwm_selected and w.tags.personal) end
			f.consistent()
		end
	end
end

function tests.selected_desktop_move_relative_bindings_resolve_once_and_repeat_with_selection()
	local f = fixture()
	local mon = f.workspace(5).monitor
	for _, id in ipairs({ 6, 8, 10, -98 }) do f.workspace(id, mon) end
	f.workspaces[-98].special = true
	f.workspace(1) -- another monitor must not be included in relative sends
	f.open(1, 5); f.open(2, 5); f.message("focus parent")
	local node = f.states[5].selected
	f.helpers(); package.loaded["lua/bindings"] = nil; require("lua/bindings")
	for _, step in ipairs({
		{ "dead_circumflex", 10 }, { "dollar", 5 }, { "dollar", 6 },
		{ "dollar", 8 }, { "dollar", 10 }, { "dollar", 5 },
	}) do
		local moves = #f.moves
		f.binds["SUPER + SHIFT + " .. step[1]]()
		assert(#f.moves == moves + 2 and f.active_ws.id == step[2])
		assert(f.windows[1].workspace.id == step[2] and f.windows[2].workspace.id == step[2])
		assert(f.states[step[2]].tree == node and f.states[step[2]].selected == node)
		for i = moves + 1, #f.moves do assert(f.moves[i].workspace == step[2] and not f.moves[i].follow) end
		f.consistent()
	end
end

function tests.selected_desktop_move_all_number_row_bindings()
	local keys = { "ampersand", "eacute", "quotedbl", "apostrophe", "parenleft",
		"minus", "egrave", "underscore", "ccedilla", "agrave" }
	local f = fixture()
	f.open(1, 11); f.open(2, 11); f.message("focus parent")
	local node = f.states[11].selected
	f.helpers(); package.loaded["lua/bindings"] = nil; require("lua/bindings")
	for id, key in ipairs(keys) do
		f.binds["SUPER + SHIFT + " .. key]()
		assert(f.windows[1].workspace.id == id and f.windows[2].workspace.id == id)
		assert(f.states[id].selected == node and f.states[id].tree == node)
		f.consistent()
	end
end

function tests.selected_desktop_move_same_workspace_and_single_slot_are_noops()
	local f = fixture()
	f.open(1, 1); f.open(2, 1); f.message("focus parent")
	local before = codec.encode(f.states)
	assert(f.api.move_to_workspace("1") == true)
	f.helpers().move_workspace_rel(1)
	assert(#f.moves == 0 and #f.focus_calls == 0 and codec.encode(f.states) == before)
end

function tests.selected_desktop_move_named_and_monocle_destination()
	local f = fixture()
	f.workspace(-1337).name = "named"
	f.workspaces[-1337].tiled_layout = "lua:bspwm_b"
	f.open(3, -1337); f.message("monocle")
	f.open(1, 1); f.open(2, 1); f.message("focus parent")
	local node = f.states[1].selected
	assert(f.api.move_to_workspace("name:named") == true)
	assert(f.moves[1].workspace == "name:named" and f.moves[2].workspace == "name:named")
	assert(f.states[-1337].mode == "monocle" and f.states[-1337].selected == node)
	assert(f.states[1].mode == "tiled")
	f.message("tiled")
	assert(f.states[-1337].tree.b == node and f.box(1).x ~= f.box(3).x)
	f.consistent()
end

function tests.selected_desktop_move_uses_destination_last_focus_not_arbitrary_leaf()
	local f = fixture()
	f.open(4, 2); f.open(5, 2); f.open(6, 2); f.focus(4)
	local anchor = f.leaf(4)
	f.open(1, 1); f.open(2, 1); f.message("focus parent")
	local node = f.states[1].selected
	assert(f.api.move_to_workspace(2) == true)
	assert(f.states[2].tree.a.a == anchor and f.states[2].tree.a.b == node)
	f.consistent()
end

function tests.selected_desktop_move_monitor_fallback_transfers_entire_selection()
	for _, dir in ipairs({ "l", "r", "u", "d" }) do
		local f = fixture()
		f.workspace(2); f.open(1, 1); f.open(2, 1); f.message("focus parent")
		local node = f.states[1].selected
		hl.get_monitor = function(requested)
			assert(requested == dir)
			return f.workspaces[2].monitor
		end
		-- Even on the representative's left, its sibling belongs to the
		-- selection and must not suppress the whole-subtree monitor transfer.
		f.helpers().swap_dir(dir)
		assert(#f.moves == 2 and f.states[2].tree == node and f.states[2].selected == node)
		f.consistent()
	end
end

function tests.desktop_move_floats_groups_and_other_layouts_keep_native_follow()
	for _, kind in ipairs({ "floating", "group", "layout" }) do
		local f = fixture()
		f.workspace(2); f.open(1, 1); f.open(2, 1); f.message("focus parent")
		if kind == "floating" then f.open(3, 1, true) else f.focus(1) end
		if kind == "group" then f.active.group = {} end
		if kind == "layout" then f.workspaces[2].tiled_layout = "dwindle" end
		local active = f.active
		assert(f.api.move_to_workspace(2) == true)
		assert(#f.moves == 1 and f.moves[1].window == active and f.moves[1].follow)
		assert(active.workspace.id == 2 and f.active == active and f.windows[2].workspace.id == 1)
		f.consistent()
	end
end

local function layout_signature(f, wsid)
	return codec.encode({ [wsid] = { tree = f.states[wsid].tree, seq = 0, mode = "tiled" } })
end

function tests.desktop_move_relative_round_trips_restore_every_leaf_and_split()
	for moving_id = 1, 5 do
		local f = fixture()
		local mon = f.workspace(1).monitor
		f.workspace(2, mon)
		for id = 1, 5 do f.open(id, 1) end
		for id = 6, 8 do f.open(id, 2) end
		f.focus(1); f.message("grow r 120")
		f.focus(moving_id)
		local node = f.leaf(moving_id)
		local original = layout_signature(f, 1)
		local boxes = {}
		for id = 1, 5 do boxes[id] = f.box(id) end
		f.load_bindings()
		local destination
		for _ = 1, 4 do
			f.binds["SUPER + SHIFT + dollar"]()
			assert(f.active_ws.id == 2 and f.leaf(moving_id) == node)
			local current = layout_signature(f, 2)
			assert(not destination or current == destination, "destination insertion drifted")
			destination = current
			f.binds["SUPER + SHIFT + dead_circumflex"]()
			assert(f.active_ws.id == 1 and f.leaf(moving_id) == node)
			assert(layout_signature(f, 1) == original, "return changed original split for leaf " .. moving_id)
			for id = 1, 5 do
				local b = boxes[id]
				expect_box(f.box(id), b.x, b.y, b.w, b.h)
			end
			assert(not f.states[1].selected and not f.states[2].selected)
			f.consistent()
		end
	end
end

function tests.desktop_move_subtree_round_trips_restore_outer_and_inner_splits()
	local f = fixture()
	for id = 1, 4 do f.open(id) end
	f.focus(1); f.message("grow r 100")
	f.focus(4); f.message("focus parent"); f.message("grow l 80")
	local node, original = f.states[1].selected, layout_signature(f, 1)
	f.workspace(2)
	for _ = 1, 4 do
		assert(f.api.move_to_workspace(2) == true)
		assert(f.api.move_to_workspace(1) == true)
		assert(f.states[1].selected == node and layout_signature(f, 1) == original)
		f.consistent()
	end
end

function tests.desktop_move_single_tile_snapshots_anchor_and_places_before_follow()
	local f = fixture()
	f.open(4, 2); f.open(5, 2); f.open(6, 2); f.focus(4)
	local anchor = f.leaf(4)
	f.open(1); f.open(2); f.focus(1)
	local node = f.leaf(1)
	f.after_move = function() f.workspaces[2].last_window = f.windows[6] end
	f.before_focus = function()
		assert(f.states[2].tree.a.a == anchor and f.states[2].tree.a.b == node)
		assert(f.box(1).x >= 2000)
	end
	assert(f.api.move_to_workspace(2) == true)
	assert(#f.moves == 1 and not f.moves[1].follow and #f.focus_calls == 1)
	assert(not f.states[2].selected and not f.windows[1].tags.bspwm_selected)
	f.consistent()
end

function tests.desktop_move_return_preselection_overrides_saved_slot()
	local f = fixture()
	f.open(1); f.open(2); f.focus(1)
	assert(f.api.move_to_workspace(2) == true)
	f.presel(2, "d", 0.3); f.focus(1)
	assert(f.api.move_to_workspace(1) == true)
	local root = f.states[1].tree
	assert(root.axis == "v" and root.ratio == 0.3 and root.a.id == 2 and root.b.id == 1)
	assert(not f.leaf(2).presel)
	-- The override becomes the new return slot, not the superseded one.
	local expected = layout_signature(f, 1)
	assert(f.api.move_to_workspace(2) == true)
	assert(f.api.move_to_workspace(1) == true)
	assert(layout_signature(f, 1) == expected)
	f.consistent()
end

function tests.desktop_move_stale_slot_falls_back_after_layout_changes()
	for _, change in ipairs({ "close", "insert", "rotate", "resize", "float" }) do
		local f = fixture()
		for id = 1, 4 do f.open(id) end
		f.focus(1)
		assert(f.api.move_to_workspace(2) == true)
		f.focus(2)
		if change == "close" then
			f.windows[3].mapped = false; f.emit("window.close", f.windows[3]); f.recalculate(1)
		elseif change == "insert" then f.open(5)
		elseif change == "rotate" then f.message("focus parent"); f.message("rotate 90")
		elseif change == "resize" then f.message("grow d 80")
		else
			f.windows[3].floating = true; f.emit("window.update_rules", f.windows[3]); f.recalculate(1)
		end
		local anchor = f.leaf(2)
		f.focus(2); f.focus(1)
		assert(f.api.move_to_workspace(1) == true)
		local path = require("lua/extensions/bspwm_tree").find_path(f.states[1].tree, 1)
		assert(path[#path - 1].a == anchor, "stale slot overrode current anchor after " .. change)
		f.consistent()
	end
end

function tests.desktop_move_failed_return_preserves_slot_for_retry()
	for _, kind in ipairs({ "fail_id", "throw_id", "ignore_move", "after_move" }) do
		local f = fixture()
		f.open(1); f.open(2); f.focus(1)
		local node, original = f.leaf(1), layout_signature(f, 1)
		assert(f.api.move_to_workspace(2) == true)
		if kind == "after_move" then
			f.after_move = function(_, dest)
				if dest.id == 1 then error("failure after ownership changed") end
			end
		else f[kind] = kind == "ignore_move" or 1 end
		assert(type(f.api.move_to_workspace(1)) == "string")
		assert(f.windows[1].workspace.id == 2 and f.leaf(1) == node)
		f[kind] = nil; f.focus(1)
		assert(f.api.move_to_workspace(1) == true)
		assert(layout_signature(f, 1) == original and f.leaf(1) == node)
		f.consistent()
	end
end

function tests.desktop_move_pending_preselection_overrides_saved_slot()
	local f = fixture()
	f.open(1); f.open(2); f.focus(1)
	assert(f.api.move_to_workspace(2) == true)
	-- Set a workspace-wide pending preselection while focused on an empty one.
	f.active_ws, f.active = f.workspace(3), nil
	f.windows[1].active = false
	f.message("preselect u"); f.message("pratio 0.4"); f.focus(1)
	assert(f.api.move_to_workspace(1) == true)
	local root = f.states[1].tree
	assert(root.axis == "v" and root.ratio == 0.4 and root.a.id == 1 and root.b.id == 2)
	f.consistent()
end

function tests.selected_desktop_move_rejects_unsafe_subtrees_and_other_layouts_without_partial_fallback()
	for _, kind in ipairs({ "group", "hidden", "floating", "mapped", "layout" }) do
		local f = fixture()
		f.workspace(2); f.open(1, 1); f.open(2, 1); f.message("focus parent")
		if kind == "layout" then f.workspaces[2].tiled_layout = "dwindle"
		else f.windows[1][kind] = kind ~= "mapped" end
		assert(type(f.api.move_to_workspace(2)) == "string")
		assert(#f.moves == 0 and #f.focus_calls == 0)
		assert(f.windows[1].workspace.id == 1 and f.windows[2].workspace.id == 1)
	end
end

for _, failure_kind in ipairs({ "fail_id", "throw_id", "ignore_move" }) do
	tests["selected_desktop_move_rolls_back_and_recovers_" .. failure_kind] = function()
		local f = fixture()
		f.open(3, 2); f.presel(3, "u", 0.3)
		f.open(1, 1); f.open(2, 1); f.message("focus parent")
		local node, anchor = f.states[1].tree, f.leaf(3)
		f[failure_kind] = failure_kind == "ignore_move" or 2
		assert(type(f.api.move_to_workspace(2)) == "string")
		assert(f.windows[1].workspace.id == 1 and f.windows[2].workspace.id == 1)
		assert(f.states[1].tree == node and f.states[2].tree == anchor and anchor.presel.ratio == 0.3)
		assert(#f.focus_calls == 0)
		f.consistent()
		f[failure_kind] = nil; f.focus(2); f.message("focus parent")
		assert(f.api.move_to_workspace(2) == true and f.states[2].selected == node)
		f.consistent()
	end
end

function tests.selected_desktop_move_incomplete_rollback_reconciles_ownership()
	local f = fixture()
	f.open(3, 2); f.open(1, 1); f.open(2, 1); f.message("focus parent")
	f.fail_move = function(w, dest) return w.stable_id == 2 or (w.stable_id == 1 and dest.id == 1) end
	local result = f.api.move_to_workspace(2)
	assert(type(result) == "string" and result:find("rollback incomplete"))
	assert(f.windows[1].workspace.id == 2 and f.windows[2].workspace.id == 1 and #f.focus_calls == 0)
	f.consistent()
	assert(codec.decode(codec.encode(f.states)))
end

function tests.selected_desktop_move_placement_exception_releases_guard()
	local f = fixture()
	f.workspace(2); f.open(1, 1); f.open(2, 1); f.message("focus parent")
	f.throw_placement = true
	assert(type(f.api.move_to_workspace(2)) == "string")
	assert(#f.focus_calls == 0)
	f.throw_placement = nil
	f.focus(2); f.recalculate(2); f.message("focus parent")
	assert(f.api.move_to_workspace(1) == true)
	f.consistent()
end

function tests.selected_desktop_move_failed_focus_keeps_completed_move_without_highlights()
	local f = fixture()
	f.workspace(2); f.open(1, 1); f.open(2, 1); f.message("focus parent")
	local node = f.states[1].selected
	f.fail_focus = true
	assert(type(f.api.move_to_workspace(2)) == "string")
	assert(f.states[2].tree == node and not f.states[1].tree and not f.states[2].selected)
	for _, w in pairs(f.windows) do assert(not w.tags.bspwm_selected) end
	f.consistent()
end

function tests.selected_desktop_move_checkpoints_only_completed_transfer_and_survives_reload()
	local f = fixture()
	f.workspace(2); f.open(1, 1); f.open(2, 1); f.message("focus parent")
	f.load(codec.encode(f.states))
	local before = f.saved
	f.after_move = function()
		assert(f.saved == before, "checkpoint exposed an intermediate transfer")
	end
	assert(f.api.move_to_workspace(2) == true)
	local saved = f.saved
	assert(saved ~= before)
	f.load(saved)
	assert(f.saved == saved and f.states[2].selected == f.states[2].tree)
	assert(f.states[2].selected_focus_id == 2 and f.windows[1].tags.bspwm_selected)
	f.consistent()
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

function tests.super_y_selected_send_on_same_desktop_reflows_before_focus()
	local f = fixture()
	for id = 1, 4 do f.open(id, 1) end
	f.presel(1, "l", 0.3); f.focus(4); f.message("focus parent")
	local selected = f.states[1].selected
	f.helpers(); package.loaded["lua/bindings"] = nil; require("lua/bindings")
	f.before_focus = function(w)
		assert(w.stable_id == 4 and #f.moves == 0)
		-- Detach (3,4), then insert it left of 1 as a single 30% subtree.
		expect_box(f.box(3), 0, 0, 120, 900)
		expect_box(f.box(4), 120, 0, 120, 900)
	end
	assert(f.binds["SUPER + y"]().ok, "selected send focused before applying the new geometry")
	assert(f.states[1].tree.a.a == selected and f.states[1].selected == selected)
	assert(f.windows[3].tags.bspwm_selected and f.windows[4].tags.bspwm_selected)
	f.consistent()
end

function tests.super_y_same_desktop_defers_reentrant_tag_callbacks_and_checkpoints()
	local f = fixture()
	for id = 1, 4 do f.open(id, 1) end
	f.presel(1, "l"); f.focus(4); f.message("focus parent")
	f.load(codec.encode(f.states))
	local before, selected = f.saved, f.states[1].selected
	local early_checkpoint = false
	f.after_tag = function(w)
		if w.tags.bspwm_selected then return end -- only the intermediate deselection
		f.recalculate(1)
		if f.saved ~= before then early_checkpoint = true end
	end
	assert(f.pull() == true)
	assert(not early_checkpoint, "tag recalculation exposed a partially updated selection checkpoint")
	assert(f.states[1].selected == selected)
	f.consistent()
end

function tests.super_y_subtree_placement_error_releases_transfer_guard()
	local f = fixture()
	f.open(1, 1); f.open(2, 1); f.open(3, 2); f.presel(3, "l")
	f.focus(2); f.message("focus parent")
	f.throw_placement = true
	local ok, result = pcall(f.raw_message, "pull")
	f.throw_placement = nil
	assert(ok and type(result) == "string", "placement error escaped instead of releasing the transfer guard")
	assert(#f.focus_calls == 0, "failed placement must not trigger follow")
	f.focus(2); f.recalculate(2); f.message("focus parent")
	assert(f.api.move_to_workspace(1) == true, "failed Super+y left the layout permanently busy")
	f.consistent()
end

for _, direction in ipairs({ "l", "r", "u", "d" }) do
	tests["super_y_selected_send_consumes_target_presel_" .. direction] = function()
		local f = fixture()
		for id = 1, 4 do f.open(id, 1) end
		-- A child's preselection must not make its selected parent manual.
		f.presel(3, "u", 0.2); f.presel(1, direction, 0.3); f.focus(4)
		f.load_bindings(); f.binds["SUPER + b"]()
		local node, target = f.states[1].selected, f.leaf(1)
		node.ratio = 0.37; f.recalculate(1)
		local original = codec.encode({ [1] = { tree = node, seq = 4, mode = "tiled" } })
		assert(f.binds["SUPER + y"]().ok)
		local wrapper = f.states[1].tree.a
		assert(wrapper.ratio == 0.3 and wrapper.axis == ((direction == "l" or direction == "r") and "h" or "v"))
		if direction == "l" or direction == "u" then assert(wrapper.a == node and wrapper.b == target)
		else assert(wrapper.a == target and wrapper.b == node) end
		assert(not target.presel and f.leaf(3).presel.ratio == 0.2)
		assert(codec.encode({ [1] = { tree = node, seq = 4, mode = "tiled" } }) == original)
		assert(f.states[1].selected == node and f.active.stable_id == 4 and #f.focus_calls == 1 and #f.moves == 0)
		for id = 1, 4 do assert((f.windows[id].tags.bspwm_selected == true) == (id >= 3)) end
		f.consistent()
	end
end

function tests.super_y_pulls_last_leaf_into_whole_selected_node_on_same_desktop()
	local f = fixture()
	for id = 1, 3 do f.open(id, 1) end
	f.focus(1); f.focus(3); f.message("focus parent")
	f.message("preselect u"); f.message("pratio 0.2")
	local anchor, a, b = f.states[1].selected, f.leaf(2), f.leaf(3)
	anchor.ratio = 0.37; f.recalculate(1)
	f.before_focus = function(w)
		assert(w.stable_id == 1 and #f.moves == 0)
		expect_box(f.box(1), 0, 0, 1600, 180)
		assert(anchor._box.y == 180 and anchor._box.h == 720)
	end
	f.load_bindings(); assert(f.binds["SUPER + y"]().ok)
	assert(f.states[1].tree.b == anchor and anchor.a == a and anchor.b == b and anchor.ratio == 0.37)
	assert(not anchor.presel and f.active.stable_id == 1 and not f.states[1].selected)
	f.consistent()
end

function tests.super_y_automatic_selection_without_manual_target_pulls_external_last_leaf()
	local f = fixture()
	for id = 1, 3 do f.open(id, 1) end
	f.focus(1); f.focus(3); f.message("focus parent")
	local selected = f.states[1].selected
	f.load_bindings(); assert(f.binds["SUPER + y"]().ok)
	assert(f.states[1].tree.a == selected and f.states[1].tree.b.id == 1)
	assert(f.active.stable_id == 1 and #f.moves == 0)
	-- This source was an ordinary leaf, not a remembered group. The selected
	-- destination remains an intact anchor.
	assert(selected.a.id == 2 and selected.b.id == 3)
	f.consistent()
end

function tests.super_y_root_with_only_internal_presels_is_noop()
	local f = fixture()
	for id = 1, 4 do f.open(id, 1) end
	f.presel(3, "u"); f.focus(4)
	for _ = 1, 3 do f.message("focus parent") end
	local before = codec.encode(f.states)
	f.load_bindings(); assert(f.binds["SUPER + y"]().ok)
	assert(codec.encode(f.states) == before and #f.moves == 0 and #f.focus_calls == 0)
	f.consistent()
end

function tests.super_y_sends_between_two_intact_subtrees_across_desktops()
	local f = fixture()
	f.open(1, 1); f.open(2, 1); f.message("focus parent")
	f.message("preselect r"); f.message("pratio 0.3")
	local anchor = f.states[1].selected
	anchor.ratio = 0.35; f.recalculate(1)
	f.open(3, 2); f.open(4, 2); f.presel(3, "d", 0.2); f.focus(4)
	f.load_bindings(); f.binds["SUPER + b"]()
	local selected = f.states[2].selected
	selected.ratio = 0.65; f.recalculate(2)
	assert(f.binds["SUPER + y"]().ok)
	assert(not f.states[2].tree and not next(f.states[2].boxes))
	assert(f.states[1].tree.a == anchor and f.states[1].tree.b == selected and f.states[1].tree.ratio == 0.3)
	assert(anchor.ratio == 0.35 and selected.ratio == 0.65 and not anchor.presel and f.leaf(3).presel.ratio == 0.2)
	assert(f.states[1].selected == selected and f.active.stable_id == 4 and #f.focus_calls == 1 and #f.moves == 2)
	for id = 1, 4 do assert((f.windows[id].tags.bspwm_selected == true) == (id >= 3)) end
	f.consistent()
end

for _, operation in ipairs({ "swap", "desktop_move" }) do
	tests["super_y_keeps_selection_after_" .. operation] = function()
		local f = fixture()
		for id = 1, 3 do f.open(id, 1) end
		f.open(4, 2); f.presel(4, "u", 0.25); f.focus(3)
		f.load_bindings(); f.binds["SUPER + b"]()
		local selected = f.states[1].selected
		if operation == "swap" then f.binds["SUPER + SHIFT + h"]()
		else f.binds["SUPER + SHIFT + quotedbl"]() end
		assert(f.states[f.active_ws.id].selected == selected)
		local moves, focuses = #f.moves, #f.focus_calls
		assert(f.binds["SUPER + y"]().ok)
		assert(#f.moves == moves + 2 and #f.focus_calls == focuses + 1)
		assert(f.states[2].tree.a == selected and f.states[2].selected == selected)
		assert(f.windows[2].workspace.id == 2 and f.windows[3].workspace.id == 2)
		assert(f.active.stable_id == 3 and f.windows[1].workspace.id == 1)
		f.consistent()
	end
end

function tests.super_y_moved_selection_checkpoint_survives_reload()
	local f = fixture()
	f.open(1, 1); f.open(2, 1); f.open(3, 2); f.presel(3, "u", 0.3)
	f.focus(2); f.message("focus parent")
	f.load(codec.encode(f.states))
	local before = f.saved
	f.after_move = function() assert(f.saved == before, "partial transfer overwrote checkpoint") end
	f.load_bindings(); assert(f.binds["SUPER + y"]().ok)
	local saved = f.saved
	assert(saved ~= before)
	f.load(saved)
	assert(f.saved == saved and not f.states[1].tree)
	assert(f.states[2].selected == f.states[2].tree.a and f.states[2].selected_focus_id == 2)
	assert(f.windows[1].tags.bspwm_selected and f.windows[2].tags.bspwm_selected and not f.windows[3].tags.bspwm_selected)
	f.consistent()
end

for _, destination_ws in ipairs({ 1, 2 }) do
	tests["super_y_pulls_previously_selected_subtree_to_focused_destination_" .. destination_ws] = function()
		local f = fixture()
		f.open(1, 1); f.open(2, 1); f.open(3, 1)
		-- Open the destination beside 1, not inside the source pair (2,3).
		f.focus(1); f.open(4, destination_ws); f.focus(3)
		f.load_bindings(); f.binds["SUPER + b"]()
		local selected = f.states[1].selected
		assert(find(selected, 2) and find(selected, 3) and not find(selected, 4))
		local a, b, ratio = selected.a, selected.b, selected.ratio
		f.focus(4)
		assert(not f.states[1].selected, "visual selection should clear on destination focus")
		f.binds["SUPER + CTRL + h"]() -- preselect left at the destination
		assert(f.binds["SUPER + y"]().ok)
		local dest = f.states[destination_ws]
		assert(dest.selected == selected, "Super+y pulled a leaf instead of the previously selected subtree")
		assert(selected.a == a and selected.b == b and selected.ratio == ratio)
		assert(f.windows[2].workspace.id == destination_ws and f.windows[3].workspace.id == destination_ws)
		assert(f.active.stable_id == 3 and f.windows[2].tags.bspwm_selected and f.windows[3].tags.bspwm_selected)
		assert(not f.windows[1].tags.bspwm_selected and not f.windows[4].tags.bspwm_selected)
		assert(#f.moves == (destination_ws == 1 and 0 or 2))
		f.consistent()
	end
end

function tests.super_y_pulls_remembered_group_without_destination_preselection()
	local f = fixture()
	f.open(1, 1); f.open(2, 1); f.open(3, 2)
	f.focus(2); f.message("focus parent")
	local selected = f.states[1].selected
	f.emit("window.active", f.windows[2]) -- duplicate representative notification
	f.focus(3); f.load_bindings()
	assert(f.binds["SUPER + y"]().ok)
	assert(f.states[2].tree.b == selected and f.states[2].selected == selected)
	assert(not f.states[1].tree and f.active.stable_id == 2 and #f.moves == 2)
	f.consistent()
end

function tests.super_y_pulls_remembered_group_into_another_selected_group()
	local f = fixture()
	f.open(1, 1); f.open(2, 1); f.open(3, 2); f.open(4, 2)
	f.focus(2); f.message("focus parent")
	local source = f.states[1].selected
	f.focus(4); f.message("focus parent"); f.message("preselect u"); f.message("pratio 0.3")
	local anchor = f.states[2].selected
	assert(f.pull() == true)
	assert(f.states[2].tree.a == source and f.states[2].tree.b == anchor and f.states[2].tree.ratio == 0.3)
	assert(f.states[2].selected == source and not f.states[1].tree and f.active.stable_id == 2)
	assert(source.a.id == 1 and source.b.id == 2 and anchor.a.id == 3 and anchor.b.id == 4)
	f.consistent()
end

function tests.super_y_newer_single_window_beats_an_older_remembered_group()
	local f = fixture()
	f.open(1, 1); f.open(2, 1); f.open(3, 2); f.open(4, 3)
	f.focus(2); f.message("focus parent")
	local group = f.states[1].selected
	f.focus(3); f.presel(4, "l")
	assert(f.pull() == true)
	assert(f.windows[3].workspace.id == 3 and #f.moves == 1)
	assert(f.states[1].tree == group and f.windows[1].workspace.id == 1 and f.windows[2].workspace.id == 1)
	f.consistent()
end

for _, cancellation in ipairs({ "member", "click", "first", "second" }) do
	tests["super_y_explicit_leaf_focus_cancels_remembered_group_" .. cancellation] = function()
		local f = fixture()
		f.open(1, 1); f.open(2, 1); f.open(3, 2)
		f.focus(2); f.message("focus parent")
		local selected = f.states[1].selected
		local expected = 2
		if cancellation == "member" then f.focus(1); expected = 1
		elseif cancellation == "click" then f.focus(2, 5)
		else f.message("focus " .. cancellation); expected = cancellation == "first" and 1 or 2 end
		assert(not selected.pull_focus_id)
		f.presel(3, "l")
		assert(f.pull() == true)
		assert(#f.moves == 1 and f.moves[1].window.stable_id == expected)
		assert(f.windows[expected].workspace.id == 2 and f.windows[3 - expected].workspace.id == 1)
		f.consistent()
	end
end

function tests.super_y_changed_membership_invalidates_remembered_group()
	local f = fixture()
	for id = 1, 4 do f.open(id, 1) end
	f.message("focus parent"); f.message("focus parent")
	local selected = f.states[1].selected
	f.focus(1)
	assert(selected.pull_focus_id == 4)
	f.message("pointer_swap 1 3")
	assert(not selected.pull_focus_id, "pointer swap left a remembered group with different members")
	f.consistent()
end

function tests.super_y_unavailable_member_does_not_fall_back_to_one_leaf()
	for _, member in ipairs({ 1, 2 }) do
		for _, kind in ipairs({ "hidden", "group" }) do
			local f = fixture()
			f.open(1, 1); f.open(2, 1); f.open(3, 2)
			f.focus(2); f.message("focus parent")
			local selected = f.states[1].selected
			f.presel(3, "l")
			f.windows[member][kind] = kind == "group" and {} or true
			local result = f.pull()
			assert(type(result) == "string" and result:find("unavailable window"))
			assert(#f.moves == 0 and f.states[1].tree == selected and f.leaf(3).presel)
			f.windows[member][kind] = nil
			assert(f.pull() == true and f.states[2].selected == selected and #f.moves == 2)
			f.consistent()
		end
	end
end

for _, operation in ipairs({ "swap", "desktop_move" }) do
	tests["super_y_remembers_source_after_" .. operation] = function()
		local f = fixture()
		f.open(1, 1); f.open(2, 1); f.open(3, 1); f.open(4, 2)
		f.focus(3); f.load_bindings(); f.binds["SUPER + b"]()
		local selected = f.states[1].selected
		if operation == "swap" then f.binds["SUPER + SHIFT + h"]()
		else f.binds["SUPER + SHIFT + quotedbl"]() end
		f.presel(4, "u", 0.25)
		local moves = #f.moves
		assert(f.binds["SUPER + y"]().ok)
		assert(#f.moves == moves + 2 and f.states[2].selected == selected and f.states[2].tree.a == selected)
		assert(f.active.stable_id == 3 and f.windows[1].workspace.id == 1)
		f.consistent()
	end
end

function tests.super_y_remembered_source_survives_reload_with_destination_focused()
	local f = fixture()
	f.open(1, 1); f.open(2, 1); f.open(3, 2)
	f.focus(2); f.message("focus parent")
	f.presel(3, "l", 0.3)
	assert(not f.states[1].selected and f.states[1].tree.pull_focus_id == 2)
	local saved = codec.encode(f.states)
	f.load(saved)
	assert(f.saved == saved and not f.states[1].selected and f.states[1].tree.pull_focus_id == 2)
	local selected = f.states[1].tree
	f.load_bindings(); assert(f.binds["SUPER + y"]().ok)
	assert(f.states[2].selected == selected and not f.states[1].tree and #f.moves == 2)
	f.consistent()
end

function tests.super_y_closed_member_does_not_restore_stale_source_after_reload()
	local f = fixture()
	for id = 1, 3 do f.open(id, 1) end
	f.open(4, 2); f.focus(3); f.message("focus parent"); f.message("focus parent")
	f.presel(4, "l")
	local saved = codec.encode(f.states)
	f.windows[2].mapped = false
	table.remove(f.contexts[1].targets, 2)
	f.load(saved)
	assert(not f.states[1].tree.pull_focus_id, "closed member left a stale remembered group")
	assert(f.pull() == true and #f.moves == 1 and f.windows[3].workspace.id == 2)
	assert(f.windows[1].workspace.id == 1)
	f.consistent()
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

function tests.workspace_swap_relative_wraps_on_the_current_monitor()
	local f = fixture()
	local first, second = f.workspace(1).monitor, f.workspace(5).monitor
	for id = 1, 10 do f.workspace(id, id <= 4 and first or second) end
	for _, id in ipairs({ 1, 4, 5, 10 }) do f.open(id, id) end
	local helpers = f.helpers()
	f.focus(5); helpers.swap_workspace_rel(-1)
	assert(f.active_ws.id == 10 and f.active == f.windows[5])
	assert(f.windows[10].workspace.id == 5 and f.windows[4].workspace.id == 4)
	helpers.swap_workspace_rel(1)
	assert(f.active_ws.id == 5 and f.windows[10].workspace.id == 10)
	f.focus(1); helpers.swap_workspace_rel(-1)
	assert(f.active_ws.id == 4 and f.windows[4].workspace.id == 1)
	helpers.swap_workspace_rel(1)
	assert(f.active_ws.id == 1 and f.windows[4].workspace.id == 4)
	f.consistent()
end

function tests.workspace_swap_relative_includes_empty_slots_and_skips_specials_and_gaps()
	local f = fixture()
	local mon = f.workspace(5).monitor
	f.workspace(8, mon)
	f.workspace(10, mon)
	f.workspace(-99, mon).special = true
	f.workspace(6) -- another monitor, despite adjacent ID
	f.open(1, 5)
	local helpers = f.helpers()
	helpers.swap_workspace_rel(1)
	assert(f.active_ws.id == 8 and f.windows[1].workspace.id == 8)
	helpers.swap_workspace_rel(1)
	assert(f.active_ws.id == 10)
	helpers.swap_workspace_rel(1)
	assert(f.active_ws.id == 5)
	f.consistent()
end

function tests.workspace_swap_single_monitor_covers_all_desktops_and_single_slot_is_noop()
	local f = fixture()
	f.open(1, 1)
	local helpers = f.helpers()
	helpers.swap_workspace_rel(-1)
	assert(#f.moves == 0 and #f.focus_calls == 0)
	for id = 2, 10 do f.workspace(id, f.workspaces[1].monitor) end
	helpers.swap_workspace_rel(-1)
	assert(f.active_ws.id == 10)
	helpers.swap_workspace_rel(1)
	assert(f.active_ws.id == 1)
	f.active_ws = nil
	helpers.swap_workspace_rel(1) -- no active desktop during startup
	f.consistent()
end

function tests.workspace_swap_preserves_both_trees_ratios_presels_and_geometry()
	local f = fixture()
	local mon = f.workspace(5).monitor
	f.workspace(10, mon)
	for id = 1, 4 do f.open(id, 5) end
	f.message("focus parent"); f.message("rotate 90"); f.message("grow r 113")
	f.message("preselect l"); f.message("pratio 0.27")
	for id = 5, 7 do f.open(id, 10) end
	f.message("grow u 81"); f.message("preselect d"); f.message("pratio 0.63")
	f.focus(3)
	local a, b = f.states[5], f.states[10]
	local before = codec.encode({ [5] = a, [10] = b })
	local boxes = {}
	for id = 1, 7 do boxes[id] = f.box(id) end
	f.before_focus = function(w)
		assert(w == f.windows[3] and #f.moves == 7)
		assert(f.states[5] == b and f.states[10] == a, "must exchange states before focusing")
		for id, box in pairs(boxes) do expect_box(f.box(id), box.x, box.y, box.w, box.h) end
	end
	f.helpers().swap_workspace_rel(-1)
	assert(f.active_ws.id == 10 and f.active == f.windows[3])
	assert(codec.encode({ [5] = f.states[10], [10] = f.states[5] }) == before)
	f.consistent()
	f.before_focus = nil
	for _ = 1, 10 do
		f.helpers().swap_workspace_rel(1)
		for id, box in pairs(boxes) do expect_box(f.box(id), box.x, box.y, box.w, box.h) end
		f.consistent()
	end
end

function tests.workspace_swap_monocle_mode_travels_and_tiled_tree_returns_on_toggle()
	local f = fixture()
	f.open(1, 1); f.open(2, 1); f.message("grow l 120")
	local tiled = f.box(2)
	f.message("monocle")
	f.open(3, 2); f.focus(2)
	f.helpers().swap_with_workspace(2) -- explicit numbered swap may cross monitors
	assert(f.states[2].mode == "monocle" and f.states[1].mode == "tiled")
	expect_box(f.box(2), 2000, 0, 1600, 900)
	f.message("tiled")
	expect_box(f.box(2), tiled.x + 2000, tiled.y, tiled.w, tiled.h)
	f.consistent()
end

function tests.workspace_swap_empty_and_float_only_desktops_follow_the_outgoing_desktop()
	local f = fixture()
	f.workspace(1); f.workspace(2, f.workspaces[1].monitor)
	f.open(1, 1); f.open(2, 1); f.message("monocle")
	local original = f.states[1]
	f.active, f.active_ws = nil, f.workspaces[2]
	for _, w in pairs(f.windows) do w.active = false end
	f.helpers().swap_with_workspace(1)
	assert(f.active_ws.id == 1 and not f.active and not f.states[1].tree)
	assert(f.states[2] == original and original.mode == "monocle")
	f.open(3, 1, true)
	f.helpers().swap_with_workspace(2)
	assert(f.active == f.windows[3] and f.active_ws.id == 2)
	assert(f.windows[3].floating and not f.states[2].tree and not next(f.states[2].boxes))
	assert(f.states[1] == original)
	for _, rule in ipairs(f.rules) do
		local selector = rule.spec.workspace or (rule.spec.match or {}).workspace
		if selector == "r[1-1]" then assert(rule.enabled, "monocle rules must travel to workspace 1") end
		if selector == "r[2-2]" then assert(not rule.enabled, "empty/float-only workspace must lose monocle rules") end
	end
	f.consistent()
end

function tests.workspace_swap_named_empty_desktop_uses_absolute_focus_selector()
	local f = fixture()
	f.workspace(-1337, f.workspace(1).monitor).name = "named"
	f.open(1, 1)
	f.helpers().swap_workspace_rel(-1)
	assert(f.moves[1].workspace == "name:named" and f.active_ws.id == -1337)
	f.active, f.active_ws = nil, f.workspaces[1]
	f.windows[1].active = false
	f.helpers().swap_with_workspace("name:named")
	assert(f.active_ws.id == -1337 and not f.active and f.windows[1].workspace.id == 1)
	f.consistent()
end

for _, failure_kind in ipairs({ "fail_id", "throw_id", "ignore_move" }) do
	tests["workspace_swap_failure_rolls_back_" .. failure_kind] = function()
		local f = fixture()
		f.open(1, 1); f.open(2, 1); f.open(3, 2); f.presel(3, "u", 0.3); f.focus(1)
		local before = codec.encode(f.states)
		f[failure_kind] = failure_kind == "ignore_move" and true or 2
		assert(type(f.api.swap_workspaces(f.workspaces[1], f.workspaces[2])) == "string")
		assert(codec.encode(f.states) == before, "failed swap must restore original layout")
		assert(#f.focus_calls == 0)
		f.consistent()
		f[failure_kind] = nil
		assert(f.api.swap_workspaces(f.workspaces[1], f.workspaces[2]) == true)
		f.consistent()
	end
end

function tests.workspace_swap_failed_rollback_reconciles_actual_ownership()
	local f = fixture()
	f.open(1, 1); f.open(2, 1); f.open(3, 2)
	f.fail_move = function(w, dest) return w.stable_id == 2 or (w.stable_id == 3 and dest.id == 2) end
	local result = f.api.swap_workspaces(f.workspaces[1], f.workspaces[2])
	assert(type(result) == "string" and result:find("rollback incomplete", 1, true))
	f.consistent()
	f.fail_move = nil
	assert(f.api.swap_workspaces(f.workspaces[1], f.workspaces[2]) == true)
	f.consistent()
end

function tests.workspace_swap_placement_exception_releases_transfer_guard()
	local f = fixture()
	f.open(1, 1); f.open(2, 2)
	f.throw_placement = true
	assert(type(f.api.swap_workspaces(f.workspaces[1], f.workspaces[2])) == "string")
	f.throw_placement = nil
	assert(f.api.swap_workspaces(f.workspaces[1], f.workspaces[2]) == true)
	f.consistent()
end

function tests.workspace_swap_survives_checkpoint_reload()
	local f = fixture()
	f.open(1, 1); f.open(2, 1); f.message("grow l 110"); f.presel(2, "u", 0.3)
	f.open(3, 2); f.message("monocle"); f.focus(2)
	f.load(codec.encode(f.states))
	f.helpers().swap_with_workspace(2)
	local before = codec.encode(f.states)
	assert(f.saved == before, "checkpoint must contain the exchanged trees")
	f.load(f.saved)
	assert(codec.encode(f.states) == before)
	f.consistent()
end

function tests.workspace_swap_bindings_reach_monitor_local_swap()
	local f = fixture()
	f.workspace(10, f.workspace(5).monitor)
	f.open(1, 5); f.open(2, 10)
	f.focus(1); f.helpers()
	package.loaded["lua/bindings"] = nil
	require("lua/bindings")
	f.binds["SUPER + ALT + dead_circumflex"]()
	assert(f.active_ws.id == 10)
	f.binds["SUPER + ALT + dollar"]()
	assert(f.active_ws.id == 5)
	f.consistent()
end

-- Drive the actual input module and real binding callbacks through the same
-- native-layout fixture. No desktop, IPC polling process or physical mouse.
local function pointer_fixture()
	local f = fixture()
	f.layers, f.timers, f.native_drags, f.native_resizes = {}, {}, 0, 0
	-- Older tree assertions use tag-name keys; also expose native HL.Window's
	-- array view so real Super+t routing can be exercised without a pseudo field.
	local native_tag = hl.dsp.window.tag
	hl.dsp.window.tag = function(opts)
		local apply = native_tag(opts)
		return function()
			local result = apply()
			local tags, value = opts.window.tags, opts.tag:sub(2)
			for i = #tags, 1, -1 do if tags[i] == value then table.remove(tags, i) end end
			if opts.tag:sub(1, 1) == "+" then tags[#tags + 1] = value end
			return result
		end
	end
	hl.get_cursor_pos = function() return f.pos end
	hl.get_monitor_at_cursor = function() return f.pointer_monitor end
	hl.get_layers = function() return f.layers end
	hl.timer = function(callback, opts)
		assert(opts.type == "repeat" and opts.timeout == 17)
		local timer = { enabled = true, callback = callback }
		function timer:set_enabled(enabled) self.enabled = enabled end
		f.timers[#f.timers + 1] = timer
		return timer
	end
	hl.dsp.window.drag = function() return function() f.native_drags = f.native_drags + 1 end end
	hl.dsp.window.resize = function() return function() f.native_resizes = f.native_resizes + 1 end end
	f.helpers()
	package.loaded["lua/bindings"] = nil
	require("lua/bindings")
	function f.point(x, y, mon)
		f.pos = { x = x, y = y }
		f.pointer_monitor = mon or f.workspaces[1].monitor
	end
	function f.tick()
		for _, timer in ipairs(f.timers) do if timer.enabled then timer.callback() end end
	end
	function f.start() f.binds["SUPER + mouse:272"]() end
	function f.release() f.binds["mouse:272"]() end
	function f.resize_start() f.binds["SUPER + mouse:273"]() end
	function f.resize_release() f.binds["mouse:273"]() end
	return f
end

function tests.pointer_swaps_repeatedly_while_held_without_floating_or_reinsertion()
	local f = pointer_fixture()
	f.open(1); f.open(2); f.open(3)
	f.presel(1, "l", 0.3); f.focus(3)
	local node, root = f.leaf(1), f.states[1].tree
	local original, second, third = f.box(1), f.box(2), f.box(3)
	local function center(b) f.point(b.x + b.w / 2, b.y + b.h / 2); f.tick() end
	center(original); f.start()
	assert(f.active.stable_id == 1, "must grab hovered window, not keyboard focus (3)")
	center(second)
	assert(f.box(1).x == second.x and f.box(1).y == second.y)
	assert(f.box(2).x == original.x and f.box(2).y == original.y)
	assert(f.leaf(1) == node and node.presel.dir == "l" and root == f.states[1].tree)
	local after = codec.encode(f.states)
	f.tick(); assert(codec.encode(f.states) == after, "stationary cursor must not swap back")
	center(third)
	assert(f.box(1).y == third.y and f.active.stable_id == 1)
	assert(f.leaf(1) == node and f.native_drags == 0 and #f.moves == 0)
	for _, w in pairs(f.windows) do assert(not w.floating) end
	f.release(); after = codec.encode(f.states)
	center(original)
	assert(codec.encode(f.states) == after and not f.timers[1].enabled, "release ends swapping")
	f.consistent()
end

function tests.pointer_swaps_siblings_and_back_and_survives_checkpoint_reload()
	local f = pointer_fixture()
	f.open(1); f.open(2)
	f.presel(1, "d", 0.23); f.presel(2, "l", 0.72)
	f.point(200, 200); f.start()
	local before = codec.encode(f.states)
	f.point(1000, 200); f.tick()
	assert(f.states[1].tree.a.id == 2 and f.states[1].tree.b.id == 1)
	f.point(200, 200); f.tick()
	assert(codec.encode(f.states) == before)
	f.point(1000, 200); f.tick(); f.release()
	local after = codec.encode(f.states)
	f.load(after)
	assert(codec.encode(f.states) == after)
	f.consistent()
end

function tests.pointer_empty_space_layers_and_floats_do_not_swap_underlying_tiles()
	local f = pointer_fixture()
	f.open(1); f.open(2)
	local float = f.open(3, 1, true)
	float.at, float.size = { x = 900, y = 100 }, { x = 200, y = 200 }
	f.point(200, 200); f.start()
	local before = codec.encode(f.states)
	f.point(1000, 200); f.tick()
	assert(codec.encode(f.states) == before, "floating occlusion")
	f.point(1700, 200); f.tick()
	assert(codec.encode(f.states) == before, "empty desktop/gap")
	f.layers = { { mapped = true, layer = 3, namespace = "launcher", x = 1100, y = 100, w = 200, h = 200 } }
	f.point(1200, 200); f.tick()
	assert(codec.encode(f.states) == before, "layer occlusion")
	f.layers[1].namespace = "bspwm-presel-feedback"
	f.point(1201, 200); f.tick()
	assert(codec.encode(f.states) ~= before, "feedback must be click-through")
	f.release()
end

function tests.pointer_native_float_drag_releases_and_ctrl_override_remains_native()
	local f = pointer_fixture()
	local float = f.open(1, 1, true)
	float.at, float.size = { x = 0, y = 0 }, { x = 500, y = 500 }
	f.point(200, 200); f.start()
	assert(f.native_drags == 1 and #f.timers == 0)
	f.release(); f.start() -- native releasePending reinvokes the press callback
	assert(f.native_drags == 2 and #f.timers == 0)
	f.start(); f.start(); f.release() -- reverse release callback order is safe too
	assert(f.native_drags == 4)
	f.binds["SUPER + CTRL + mouse:272"]()
	assert(f.native_drags == 5)
end

function tests.pointer_reuses_timer_and_cancels_on_close_submap_and_reload()
	local f = pointer_fixture()
	f.open(1); f.open(2)
	for _, event in ipairs({ "config.reloaded", "keybinds.submap", "monitor.removed", "hyprland.shutdown" }) do
		f.point(200, 200); f.start()
		assert(#f.timers == 1 and f.timers[1].enabled)
		f.emit(event)
		assert(not f.timers[1].enabled)
	end
	f.start(); f.emit("window.close", f.windows[2]); assert(f.timers[1].enabled)
	f.emit("window.close", f.windows[1]); assert(not f.timers[1].enabled)
end

function tests.pointer_focus_loss_or_missing_workspace_cancels_safely()
	local f = pointer_fixture()
	f.open(1); f.open(2)
	f.point(200, 200); f.start()
	f.active = nil -- e.g. a session lock taking focus
	f.tick(); assert(not f.timers[1].enabled)
	f.start(); f.windows[1].workspace = nil
	f.tick(); assert(not f.timers[1].enabled)
	assert(not f.api.drag_valid(nil))
	assert(not f.api.drag_valid({ mapped = true }))
end

function tests.pointer_invalid_sources_and_targets_never_enter_native_drag()
	for _, prop in ipairs({ "floating", "hidden", "fullscreen", "group", "visible", "mapped" }) do
		local f = pointer_fixture()
		f.open(1); f.open(2)
		f.point(200, 200); f.start()
		local before = codec.encode(f.states)
		f.windows[2][prop] = ({ fullscreen = 2, group = {}, visible = false, mapped = false })[prop]
		if prop == "floating" or prop == "hidden" then f.windows[2][prop] = true end
		f.point(1000, 200); f.tick()
		assert(codec.encode(f.states) == before and f.native_drags == 0, prop)
		f.windows[1].mapped = false
		f.tick(); assert(not f.timers[1].enabled)
	end
	local f = pointer_fixture()
	f.open(1); f.message("monocle")
	f.point(200, 200); f.start()
	assert(#f.timers == 0 and f.native_drags == 0)
end

function tests.pointer_cross_monitor_transfers_tiled_node_then_continues_swapping()
	local f = pointer_fixture()
	f.open(1, 1); f.open(2, 2); f.open(3, 2)
	f.presel(1, "u", 0.3); f.presel(2, "l", 0.25)
	local node, target_node = f.leaf(1), f.leaf(2)
	f.point(200, 200); f.start()
	f.point(2100, 200, f.workspaces[2].monitor); f.tick()
	assert(f.windows[1].workspace.id == 2 and f.active.stable_id == 1)
	assert(f.leaf(1) == node and node.presel.dir == "u" and not target_node.presel)
	assert(not f.states[1].tree and not next(f.states[1].boxes))
	assert(#f.moves == 1 and not f.windows[1].floating and f.native_drags == 0)
	local target = f.box(3)
	f.point(target.x + target.w / 2, target.y + target.h / 2, f.workspaces[2].monitor); f.tick()
	assert(f.box(1).x == target.x and f.box(1).y == target.y)
	f.release(); f.consistent()
end

function tests.pointer_transfers_to_empty_named_workspace()
	local f = pointer_fixture()
	f.open(1)
	local dest = f.workspace(-1300)
	dest.name = "named"
	f.point(200, 200); f.start()
	f.point(-2600000, 200, dest.monitor); f.tick()
	assert(f.windows[1].workspace == dest and f.active.stable_id == 1)
	assert(f.moves[1].workspace == "name:named")
	f.consistent(); f.release()
end

function tests.pointer_failed_native_transfer_stops_and_releases_layout_guard()
	for _, fail in ipairs({ "fail_id", "throw_id", "ignore_move", "throw_placement" }) do
		local f = pointer_fixture()
		f.open(1, 1); f.open(2, 2)
		f.point(200, 200); f.start()
		f[fail] = fail == "ignore_move" or fail == "throw_placement" or 1
		f.point(2100, 200, f.workspaces[2].monitor); f.tick()
		assert(not f.timers[1].enabled)
		f[fail] = nil
		assert(f.api.drag_valid(f.windows[1]), "transfer guard must be released")
		f.recalculate(1); f.recalculate(2); f.consistent()
	end
end

-- Resize input must bypass the native Lua bridge, which discards its delta.
function tests.pointer_resize_all_four_corners_target_hovered_leaf()
	local cases = {
		{ id = 1, x = 700, y = 350, bx = 0, by = 0, w = 880, h = 495 },
		{ id = 2, x = 900, y = 350, bx = 880, by = 0, w = 720, h = 495 },
		{ id = 3, x = 900, y = 550, bx = 880, by = 495, w = 720, h = 405 },
		{ id = 4, x = 700, y = 550, bx = 0, by = 495, w = 880, h = 405 },
	}
	for _, c in ipairs(cases) do
		local f = pointer_fixture()
		f.open(1); f.open(2); f.open(3); f.focus(1); f.open(4)
		f.focus(c.id == 4 and 1 or 4)
		local root, leaf = f.states[1].tree, f.leaf(c.id)
		f.point(c.x, c.y); f.resize_start()
		assert(f.active.stable_id == c.id, "resize must grab the hovered, not focused tile")
		f.point(c.x + 80, c.y + 45); f.tick()
		local box = f.box(c.id)
		assert(box.x == c.bx and box.y == c.by and box.w == c.w and box.h == c.h, "wrong corner: " .. c.id)
		assert(f.states[1].tree == root and f.leaf(c.id) == leaf)
		assert(f.native_resizes == 0 and f.native_drags == 0 and #f.moves == 0)
		for _, w in pairs(f.windows) do assert(not w.floating) end
		f.resize_release(); f.consistent()
	end
end

function tests.pointer_resize_uses_leaf_not_selected_subtree_and_preserves_metadata()
	local f = pointer_fixture()
	f.open(1); f.open(2); f.open(3)
	f.presel(2, "l", 0.3); f.focus(2); f.message("focus parent")
	assert(f.states[1].selected)
	local leaf = f.leaf(2)
	f.point(900, 350); f.resize_start()
	f.point(980, 395); f.tick()
	assert(f.box(2).w == 720 and f.box(2).h == 495)
	assert(not f.states[1].selected and f.leaf(2) == leaf and leaf.presel.ratio == 0.3)
	f.resize_release()
end

function tests.pointer_resize_ancestor_fence_and_outer_edges()
	local f = pointer_fixture()
	f.open(1); f.open(2); f.presel(2, "r"); f.open(3)
	f.point(850, 100); f.resize_start() -- middle tile's left edge belongs to root
	f.point(1010, 300); f.tick()
	assert(f.box(1).w == 960 and f.box(2).x == 960 and f.box(2).w == 320)
	assert(f.box(2).h == 900, "top screen edge must not resize another fence")
	f.resize_release()
	f.point(1590, 890); f.resize_start() -- bottom-right outer corner
	local before = codec.encode(f.states)
	f.point(1400, 700); f.tick(); f.resize_release()
	assert(codec.encode(f.states) == before, "outer edges must be no-ops")
end

function tests.pointer_resize_absolute_motion_clamps_and_returns_without_drift()
	local f = pointer_fixture()
	f.open(1); f.open(2)
	f.point(700, 700); f.resize_start()
	f.point(2700, 700); f.tick()
	assert(f.box(1).w == 1440)
	f.point(2600, 700); f.tick()
	assert(f.box(1).w == 1440, "ratio must stay clamped until cursor returns within range")
	f.point(-2000, 700); f.tick()
	assert(f.box(1).w == 160)
	f.point(700, 700); f.tick()
	assert(f.box(1).w == 800)
	for i = 1, 800 do f.point(700 + i / 10, 700); f.tick() end
	assert(f.box(1).w == 880, "fractional motion must not accumulate rounding drift")
	f.point(700, 700); f.tick()
	assert(f.box(1).w == 800, "corner must not change when pointer crosses tile centre")
	f.resize_release()
end

function tests.pointer_resize_release_flushes_last_motion_and_checkpoint_survives_reload()
	local f = pointer_fixture()
	f.open(1); f.open(2)
	f.point(700, 700); f.resize_start()
	f.point(780, 700); f.resize_release() -- no timer tick
	assert(f.box(1).w == 880 and not f.timers[1].enabled)
	local after = codec.encode(f.states)
	f.point(1000, 700); f.tick(); f.resize_release()
	assert(codec.encode(f.states) == after)
	f.load(after)
	assert(codec.encode(f.states) == after and f.box(1).w == 880)
end

function tests.pointer_resize_no_idle_recalculation_and_timer_reused()
	local f = pointer_fixture()
	f.open(1); f.open(2)
	f.point(700, 700); f.resize_start()
	local original_layout, calls = hl.dsp.layout, 0
	hl.dsp.layout = function(msg) calls = calls + 1; return original_layout(msg) end
	for _ = 1, 10 do f.tick() end
	assert(calls == 0)
	f.point(780, 700); f.tick()
	assert(calls == 1)
	for _ = 1, 10 do f.tick() end
	assert(calls == 1)
	f.resize_release(); f.resize_start()
	assert(#f.timers == 1 and f.timers[1].enabled)
end

function tests.pointer_resize_native_floats_and_other_layouts_keep_release_pairing()
	for _, floating in ipairs({ false, true }) do
		local f = pointer_fixture()
		local w = f.open(1, 1, floating)
		w.at, w.size = { x = 0, y = 0 }, { x = 500, y = 500 }
		if not floating then w.workspace.tiled_layout = "dwindle" end
		f.point(200, 200); f.resize_start()
		assert(f.native_resizes == 1 and #f.timers == 0)
		f.resize_release(); f.resize_start() -- native releasePending callback
		assert(f.native_resizes == 2 and #f.timers == 0)
		f.resize_start(); f.resize_start(); f.resize_release()
		assert(f.native_resizes == 4 and f.native_drags == 0)
	end
end

function tests.pointer_pseudo_resize_uses_native_path_without_changing_tree()
	for _, point in ipairs({ {310, 360}, {490, 360}, {310, 540}, {490, 540} }) do
		local f = pointer_fixture()
		local w = f.open(1); f.open(2)
		f.focus(1); f.binds["SUPER + t"]()
		-- Pseudo client geometry is smaller than the allocation. Hit testing
		-- must use it; native code owns corner selection and size/clamping.
		w.at, w.size = { x = 300, y = 350 }, { x = 200, y = 200 }
		f.focus(2)
		local before = codec.encode(f.states)
		f.point(point[1], point[2]); f.resize_start()
		assert(f.native_resizes == 1 and #f.timers == 0, "pseudo entered split resizing")
		f.point(point[1] + 80, point[2] + 45); f.tick()
		assert(codec.encode(f.states) == before and #f.moves == 0 and not w.floating)
		f.resize_release(); f.resize_start() -- native releasePending callback
		assert(f.native_resizes == 2 and f.native_drags == 0 and #f.timers == 0)
		f.point(point[1], point[2])
		f.resize_start(); f.resize_start(); f.resize_release() -- opposite release order
		assert(f.native_resizes == 4)
	end
end

function tests.pointer_pseudo_move_still_swaps_and_tiled_resize_returns_to_fences()
	local f = pointer_fixture()
	f.open(1); f.open(2)
	f.focus(1); f.binds["SUPER + t"]()
	f.point(700, 700); f.start()
	f.point(1000, 700); f.tick(); f.release()
	assert(f.states[1].tree.a.id == 2 and f.native_drags == 0, "pseudo move must still swap")
	f.binds["SUPER + s"]()
	f.point(900, 700); f.resize_start()
	f.point(980, 700); f.tick(); f.resize_release()
	assert(f.box(1).x == 880 and f.box(1).w == 720 and f.native_resizes == 0)
end

function tests.pointer_pseudo_release_stays_paired_after_returning_to_tiled()
	local f = pointer_fixture()
	f.open(1); f.open(2); f.focus(1)
	f.binds["SUPER + t"]()
	f.point(700, 700); f.resize_start()
	assert(f.native_resizes == 1)
	f.binds["SUPER + s"]()
	f.resize_release(); f.resize_start() -- release still belongs to native resize
	assert(f.native_resizes == 2 and #f.timers == 0)
	f.resize_start(); f.point(780, 700); f.tick(); f.resize_release()
	assert(f.box(1).w == 880 and f.native_resizes == 2)
end

function tests.pointer_tiled_resize_stops_if_window_becomes_pseudo()
	local f = pointer_fixture()
	f.open(1); f.open(2)
	f.point(700, 700); f.resize_start()
	f.binds["SUPER + t"]()
	local before = codec.encode(f.states)
	f.point(780, 700); f.tick()
	assert(not f.timers[1].enabled and codec.encode(f.states) == before)
end

function tests.pointer_pseudo_invalid_sources_do_not_start_native_resize()
	for _, prop in ipairs({ "fullscreen", "group", "monocle" }) do
		local f = pointer_fixture()
		local w = f.open(1)
		f.binds["SUPER + t"]()
		if prop == "monocle" then f.message("monocle")
		else w[prop] = prop == "fullscreen" and 2 or {} end
		f.point(700, 700); f.resize_start()
		assert(#f.timers == 0 and f.native_resizes == 0, prop)
	end
end

function tests.pointer_resize_layers_empty_space_and_feedback_hit_testing()
	local f = pointer_fixture()
	f.open(1); f.open(2)
	f.point(1700, 700); f.resize_start()
	assert(#f.timers == 0)
	f.layers = { { mapped = true, layer = 3, namespace = "launcher", x = 600, y = 600, w = 200, h = 200 } }
	f.point(700, 700); f.resize_start()
	assert(#f.timers == 0)
	f.layers[1].namespace = "bspwm-presel-feedback"
	f.resize_start(); f.point(780, 700); f.tick()
	assert(f.box(1).w == 880)
end

function tests.pointer_resize_invalid_sources_and_failed_focus_do_not_start()
	for _, prop in ipairs({ "fullscreen", "group", "monocle", "fail_focus" }) do
		local f = pointer_fixture()
		local w = f.open(1); f.open(2)
		if prop == "monocle" then f.message("monocle")
		elseif prop == "fail_focus" then f.fail_focus = true
		else w[prop] = prop == "fullscreen" and 2 or {} end
		f.point(700, 700); f.resize_start()
		assert(#f.timers == 0 and f.native_resizes == 0, prop)
	end
end

function tests.pointer_resize_cancels_when_grab_becomes_invalid()
	for _, prop in ipairs({ "floating", "hidden", "fullscreen", "group", "mapped", "visible", "workspace", "focus", "area", "topology" }) do
		local f = pointer_fixture()
		local w = f.open(1); f.open(2)
		f.point(700, 700); f.resize_start()
		if prop == "focus" then f.focus(2)
		elseif prop == "workspace" then w.workspace = f.workspace(2)
		elseif prop == "area" then f.contexts[1].area.w = 1800; f.recalculate(1)
		elseif prop == "topology" then f.message("focus parent"); f.message("rotate 90")
		else w[prop] = ({ floating = true, hidden = true, fullscreen = 2, group = {}, mapped = false, visible = false })[prop] end
		local before = codec.encode(f.states)
		f.point(780, 700); f.tick()
		assert(not f.timers[1].enabled and codec.encode(f.states) == before, prop)
	end
end

function tests.pointer_resize_cancels_on_close_reload_submap_monitor_and_shutdown()
	local f = pointer_fixture()
	f.open(1); f.open(2)
	for _, event in ipairs({ "config.reloaded", "keybinds.submap", "monitor.removed", "hyprland.shutdown" }) do
		f.point(700, 700); f.resize_start()
		assert(#f.timers == 1 and f.timers[1].enabled)
		f.emit(event)
		assert(not f.timers[1].enabled)
	end
	f.resize_start(); f.emit("window.close", f.windows[2]); assert(f.timers[1].enabled)
	f.emit("window.close", f.windows[1]); assert(not f.timers[1].enabled)
end

function tests.pointer_resize_never_transfers_or_swaps_across_monitors()
	local f = pointer_fixture()
	f.open(1); f.open(2); f.open(3, 2)
	local before = codec.encode({ [2] = f.states[2] })
	f.point(700, 700); f.resize_start()
	f.point(2100, 700, f.workspaces[2].monitor); f.tick()
	assert(f.windows[1].workspace.id == 1 and #f.moves == 0 and f.box(1).w == 1440)
	assert(codec.encode({ [2] = f.states[2] }) == before)
	f.resize_release(); f.consistent()
end

function tests.pointer_resize_skips_vacant_fences_and_stops_if_owner_changes()
	local f = pointer_fixture()
	f.open(1); f.open(2); f.presel(2, "r"); f.open(3)
	local dormant = f.states[1].tree.b
	table.remove(f.contexts[1].targets, 2)
	f.windows[2].floating = true
	f.windows[2].at, f.windows[2].size = { x = 10, y = 10 }, { x = 100, y = 100 }
	f.recalculate(1)
	f.point(900, 700); f.resize_start()
	f.point(1060, 700); f.tick()
	assert(f.box(1).w == 960 and f.box(3).w == 640 and dormant.ratio == 0.5)
	f.windows[1].floating = true
	f.recalculate(1)
	local before = codec.encode(f.states)
	f.point(1100, 700); f.tick()
	assert(not f.timers[1].enabled and codec.encode(f.states) == before)
end

function tests.pointer_move_and_resize_grabs_are_mutually_exclusive()
	local f = pointer_fixture()
	f.open(1); f.open(2)
	f.point(700, 700); f.start(); f.resize_start()
	assert(#f.timers == 2 and not f.timers[1].enabled and f.timers[2].enabled)
	f.point(780, 700); f.tick(); assert(f.box(1).w == 880)
	f.start()
	assert(f.timers[1].enabled and not f.timers[2].enabled)
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
