-- lua/extensions/bspwm.lua -- bspwm-style binary-tree layout for Hyprland (v0.56.2+)
-- ============================================================================
-- Register with:  require("lua/extensions/bspwm")    -- from hyprland.lua
-- Select with:    general.layout = "lua:bspwm"   (or workspace_rule layout=)
--
-- Implements a real per-workspace binary tree like bspwm:
--   * automatic insertion: split the focused window's longest side (ratio 0.5)
--   * preselection: direction (-p), ratio (-o), click-through feedback rectangle
--   * subtree rotate (-R 90/270), flip (-F h/v), balance (-B), equalize (-E)
--   * transplant (-n @/), global history-based send/pull (super+y)
--   * selected-subtree desktop transfers (-d --follow)
--   * directional subtree swap, leaf move, subtree edge grow/shrink
--   * tiled pointer swaps and corner resizing (input in bspwm_drag.lua)
--   * cross-layer directional focus, node focus: parent / brother / first / second
--   * monocle mode (stack, focused on top)
--   * vacant floating leaves retain their original splits when tiled again
--   * native pseudo-tiled sizing (resize routing in bspwm_pseudo.lua)
--
-- NOT implemented (see discussion):
--   * unmodified border-drag resize (use Super + right drag)
--
-- layout_msg commands (via hl.dsp.layout("...")):
--   preselect <l|r|u|d|west|east|north|south>
--   pratio <0.1..0.9>
--   preselect cancel | preselect clear
--   swap <l|r|u|d>          move <l|r|u|d>
--   pointer_swap <source stable_id> <target stable_id> (decimal, same workspace)
--   pointer_resize <stable_id> <l|r> <ratio> <u|d> <ratio> (grabbed leaf, -1 = no fence)
--   grow <l|r|u|d> <px>     shrink <l|r|u|d> <px>
--   rotate <90|270>         flip <h|v>
--   balance                 equalize
--   transplant              pull
--   mode                    monocle                 tiled
--   focus <parent|brother|first|second>
-- ============================================================================

-- Independent features, registered before either layout provider:
-- repair lost fullscreen records, then let policy adopt the restored live modes.
-- The readiness gate also excludes reentrant refreshes during restoration.
local fullscreen_reload = require("lua/extensions/bspwm_fullscreen_reload")
fullscreen_reload.setup()
require("lua/extensions/bspwm_fullscreen_policy").setup({ reload_ready = fullscreen_reload.is_ready })

-- Load BEFORE registering either provider: registration itself can reattach
-- existing windows and call recalculate with an incomplete target list.
local state_store, store_error = require("lua/extensions/bspwm_state").open_session()
local restored, restore_error
if state_store then restored, restore_error = state_store:load() end
if store_error or restore_error then print("bspwm checkpoint: " .. tostring(store_error or restore_error)) end
local states = restored and restored.states or {}
local pending_presel = restored and restored.pending or nil
local rehydrating = state_store ~= nil
local config_seen = false
local last_store_error
local selection_focus = false -- guard our own representative-window focus events
local selection_tag = "bspwm_selected"
local feedback_sink
local prune_pull_sources
local transfer_contexts -- defer reentrant layout callbacks during cross-workspace moves
local transferring = false -- also suppress checkpoints/feedback through final replay
local closing = {} -- stable_id -> HL.Window (native weak ref), until destroy/remap
local float_geometry = require("lua/extensions/bspwm_float_geometry")
local monocle_display = require("lua/extensions/bspwm_monocle")
local monocle = monocle_display.new()

local function checkpoint()
	if rehydrating or transferring then return end
	if prune_pull_sources then prune_pull_sources() end
	if not state_store then return end
	local ok, err = state_store:save(states, pending_presel)
	if not ok and err ~= last_store_error then print("bspwm checkpoint: " .. tostring(err)) end
	last_store_error = ok and nil or err
end

local function on_event(name, callback)
	hl.on(name, function(...)
		callback(...)
		checkpoint()
	end)
end

local function publish_feedback()
	if transferring then return end
	checkpoint()
	if feedback_sink then feedback_sink(states) end
end

-- Pure tree operations are separate from native focus/layout callbacks.
local tree = require("lua/extensions/bspwm_tree")
local directional_focus = require("lua/extensions/bspwm_focus")
local leaf, find_path, collect_ids = tree.leaf, tree.find_path, tree.collect_ids
local leaves, last_leaf = tree.leaves, tree.last_leaf
local prune_tree, walk_splits = tree.prune, tree.walk_splits
local insert_adjacent, detach_node, swap_nodes = tree.insert_adjacent, tree.detach, tree.swap_nodes
local resize, subtree_of = tree.resize, tree.parent_or_root
local rotate, flip, balance, equalize = tree.rotate, tree.flip, tree.balance, tree.equalize
local transplant, place, clear_presels = tree.transplant, tree.place, tree.clear_presels

-- ---------------------------------------------------------------------------
-- remembered pull sources
-- ---------------------------------------------------------------------------

-- A visual selection is cleared when focus moves to the insertion target.
-- Keep its logical node in focus history, instead of reducing it to the one
-- representative window that Hyprland's history can store. Annotations travel
-- with the node through swaps/transfers and are checkpointed with the tree.
local function forget_pull_source(node)
	node.pull_focus_id, node.pull_ids = nil, nil
end

local function forget_pull_sources_for_window(id)
	for _, st in pairs(states) do
		walk_splits(st.tree, function(node)
			if node.pull_ids and node.pull_ids[id] then forget_pull_source(node) end
		end)
	end
end

local function remember_pull_source(st, node, focus_id)
	-- Explicitly selecting a child or parent supersedes overlapping groups.
	walk_splits(st.tree, function(other)
		if other.pull_focus_id and (find_path(other, node) or find_path(node, other)) then
			forget_pull_source(other)
		end
	end)
	if node.t == "split" then
		node.pull_focus_id, node.pull_ids = focus_id, {}
		collect_ids(node, node.pull_ids)
	end
end

prune_pull_sources = function()
	for _, st in pairs(states) do
		walk_splits(st.tree, function(node)
			if not node.pull_focus_id then return end
			local ids = {}
			collect_ids(node, ids)
			local expected = node.pull_ids or {}
			local valid = ids[node.pull_focus_id] and expected[node.pull_focus_id]
			for _, child in ipairs(leaves(node)) do if child.vacant then valid = false end end
			for id in pairs(ids) do if not expected[id] then valid = false end end
			for id in pairs(expected) do if not ids[id] then valid = false end end
			-- A closed/floated member or an insertion/pointer swap inside the
			-- group must not silently turn it into a different pull source.
			if not valid then forget_pull_source(node) end
		end)
	end
end

-- ---------------------------------------------------------------------------
-- geometry helpers (uses boxes recorded by place())
-- ---------------------------------------------------------------------------

-- bspwm find_nearest_neighbor uses the selected NODE's rectangle, excludes
-- descendants, then ranks leaves by boundary distance and focus history.
-- These are disjoint tiled rectangles: direction requires an overlapping
-- perpendicular range and a candidate beyond the selection's outer edge.
local function neighbor_id(st, id, dir)
	if st.mode ~= "tiled" then return nil end
	local path = find_path(st.tree, id)
	local node = path and path[#path]
	local b = node and node._box
	if not b then return nil end
	local excluded, windows = {}, {}
	collect_ids(node, excluded)
	for _, w in ipairs(hl.get_windows()) do
		if w.mapped and not w.floating and not w.hidden then windows[w.stable_id] = w end
	end
	local best, best_distance, best_rank
	for _, candidate in ipairs(leaves(st.tree)) do
		local oid = candidate.id
		local ob, w = st.boxes[oid], windows[oid]
		if ob and w and not excluded[oid] then
			local distance
			if (dir == "l" or dir == "r") and b.y < ob.y + ob.h and ob.y < b.y + b.h then
				if dir == "l" and ob.x + ob.w <= b.x then distance = b.x - (ob.x + ob.w)
				elseif dir == "r" and ob.x >= b.x + b.w then distance = ob.x - (b.x + b.w) end
			elseif (dir == "u" or dir == "d") and b.x < ob.x + ob.w and ob.x < b.x + b.w then
				if dir == "u" and ob.y + ob.h <= b.y then distance = b.y - (ob.y + ob.h)
				elseif dir == "d" and ob.y >= b.y + b.h then distance = ob.y - (b.y + b.h) end
			end
			local rank = w.focus_history_id
			if not rank or rank < 0 then rank = math.huge end
			if distance and (not best_distance or distance < best_distance
				or (distance == best_distance and rank < best_rank)) then
				best, best_distance, best_rank = oid, distance, rank
			end
		end
	end
	return best
end

-- Needs the provider's recalculation function; implemented below layout_impl.
local pull

local function focus_subtree_node(st, id, which)
	local path = find_path(st.tree, st.selected or id)
	if not path then return nil end
	local node = path[#path]
	local parent = path[#path - 1]
	if which == "parent" then
		return parent -- already at root: no-op
	elseif which == "brother" then
		return parent and ((parent.a == node) and parent.b or parent.a)
	elseif which == "first" then
		return node.a -- a leaf has no children
	elseif which == "second" then
		return node.b
	end
end

-- ---------------------------------------------------------------------------
-- state plumbing
-- ---------------------------------------------------------------------------

local function workspace_id(ctx)
	for _, t in ipairs(ctx.targets) do
		local w = t.window
		if w and w.workspace and w.workspace.id then
			return w.workspace.id
		end
	end
	return nil
end

local function state_for(wsid)
	local st = states[wsid]
	if not st then
		st = { seq = 0, mode = "tiled", boxes = {}, highlighted = {} }
		states[wsid] = st
	end
	return st
end

-- Membership is NOT the tiled target list. Native Algorithm::setFloating
-- removes the target (and calls Lua) BEFORE changing window.floating. Keep
-- mapped leaves belonging to this desktop even during that intermediate pass.
local function workspace_members(wsid)
	local members, tiled = {}, {}
	for _, w in ipairs(hl.get_windows()) do
		if w.mapped and not closing[w.stable_id] and w.workspace and w.workspace.id == wsid then
			members[w.stable_id] = true
			if not w.floating and not w.hidden then tiled[w.stable_id] = true end
		end
	end
	return members, tiled
end

local function workspace_selector(ws)
	-- Negative IDs are parsed as relative moves; named/special desktops need
	-- an absolute name selector even when a workspace object is available.
	return ws.id > 0 and ws.id or "name:" .. ws.name
end

local function compatible_workspace(ws)
	return ws.tiled_layout == "lua:bspwm" or ws.tiled_layout == "lua:bspwm_b"
end

local function move_window(window, workspace)
	if window.workspace and window.workspace.id == workspace.id then return true end
	local result = hl.dispatch(hl.dsp.window.move({
		window = window, workspace = workspace_selector(workspace), follow = false,
	}))
	return not (result and result.ok == false) and window.workspace and window.workspace.id == workspace.id
end

local function take_preselection(anchor)
	if anchor and anchor.presel then
		local pre = anchor.presel
		anchor.presel = nil
		return pre
	end
	local pre = pending_presel
	pending_presel = nil
	return pre
end

-- ---------------------------------------------------------------------------
-- subtree selection and visual feedback
-- ---------------------------------------------------------------------------

local function tag_window(w, enabled)
	if w and w.mapped then
		hl.dispatch(hl.dsp.window.tag({
			tag = (enabled and "+" or "-") .. selection_tag, window = w,
		}))
	end
end

local function highlight_selection(st, targets)
	if rehydrating then return end
	local ids, desired = {}, {}
	-- Ordinary leaf selection uses Hyprland's normal active border.
	if st.selected and st.selected.t == "split" then collect_ids(st.selected, ids) end
	for _, t in ipairs(targets) do
		local w = t.window
		if w and ids[w.stable_id] then desired[w.stable_id] = w end
	end
	local previous = st.highlighted
	st.highlighted = desired -- set before dispatching, in case rules recalculate
	for id, w in pairs(previous) do
		if not desired[id] then tag_window(w, false) end
	end
	for id, w in pairs(desired) do
		if not previous[id] then tag_window(w, true) end
	end
end

local function clear_selection(st)
	st.selected, st.selected_focus_id = nil, nil
	st.insertion_anchor, st.insertion_window_id = nil, nil
	highlight_selection(st, {})
end

local function reconcile_tree(st, members, tiled)
	st.tree = prune_tree(st.tree, members)
	tree.update_vacancy(st.tree, tiled)
	for id in pairs(st.boxes) do if not tiled[id] then st.boxes[id] = nil end end
	local lost_selection = st.selected and (not find_path(st.tree, st.selected) or not tiled[st.selected_focus_id])
	for id in pairs(st.highlighted) do if not tiled[id] then lost_selection = true end end
	if lost_selection then clear_selection(st) end
end

local function clear_selections()
	if selection_focus or rehydrating or transferring then return end
	for _, st in pairs(states) do clear_selection(st) end
end

-- A tag-based rule is reversible: removing only OUR tag restores normal
-- window rules instead of leaving permanent set_prop border overrides behind.
-- Same red as general.col.active_border in hyprland.lua, for both focus states.
hl.window_rule({
	name = "bspwm-subtree-selection",
	match = { tag = selection_tag },
	border_color = "rgb(bb0000) rgb(bb0000)",
})

on_event("window.active", function(w, reason)
	if rehydrating or transferring then return end
	local st = w and w.workspace and states[w.workspace.id]
	if st and st.mode == "monocle" then monocle.raise(w) end
	if selection_focus then return end
	-- Re-notification of the same keyboard-focused representative is not a
	-- new tree selection. An explicit click (FOCUS_REASON_CLICK = 5) is.
	if st and st.selected_focus_id == w.stable_id and reason ~= 5 then return end
	-- Focusing any member explicitly selects a leaf again. Focusing OUTSIDE
	-- the group only clears its border, leaving it available as a pull source.
	if w then forget_pull_sources_for_window(w.stable_id) end
	local anchor
	if st and not w.floating and not find_path(st.tree, w.stable_id) then
		-- A newly mapped window can receive focus BEFORE its first layout pass.
		anchor = st.selected or (st.insertion_window_id == w.stable_id and st.insertion_anchor)
	end
	clear_selections()
	if anchor then st.insertion_anchor, st.insertion_window_id = anchor, w.stable_id end
end)
on_event("workspace.active", clear_selections)
on_event("workspace.special_active", clear_selections)
on_event("monitor.focused", clear_selections)

local function window_leaves_selection(w)
	if not w or rehydrating or transferring then return end
	forget_pull_sources_for_window(w.stable_id)
	for _, st in pairs(states) do
		if st.highlighted[w.stable_id] or st.selected_focus_id == w.stable_id
			or st.insertion_window_id == w.stable_id then
			clear_selection(st)
		end
	end
end
on_event("window.close", function(w)
	local id = w and w.stable_id
	if not id then return end
	closing[id] = w -- retaining Lua userdata does not keep the native window alive
	window_leaves_selection(w)
	if rehydrating or transferring then return end
	-- Floats (and the last tile) may never trigger another layout callback.
	for _, st in pairs(states) do
		detach_node(st, id)
		st.boxes[id] = nil
		tree.update_vacancy(st.tree)
	end
end)
local function clear_closing(w)
	local id = w and w.stable_id
	if id then closing[id] = nil end
end
on_event("window.destroy", function(w)
	clear_closing(w)
	-- v0.56.2 emits destroy from ~CWindow: the weak reference has already
	-- expired. CLuaWindow::push still creates truthy userdata, but stable_id
	-- (like every property) is nil. Sweep the weak handles saved at close
	-- instead of indexing by that missing ID or leaking its tombstone.
	for id, window in pairs(closing) do
		if not window.stable_id then closing[id] = nil end
	end
end)
on_event("window.open_early", clear_closing)
-- A client can unmap/remap the same window object, retaining its old tags.
on_event("window.open", function(w)
	clear_closing(w)
	tag_window(w, false)
end)
on_event("window.move_to_workspace", function(w, ws)
	window_leaves_selection(w)
	if not w or rehydrating or transferring then return end
	ws = ws or w.workspace
	for id, st in pairs(states) do
		if not ws or id ~= ws.id then
			detach_node(st, w.stable_id)
			st.boxes[w.stable_id] = nil
			tree.update_vacancy(st.tree)
		end
	end
end)
-- setFloating updates rules after setting the flag, even when removing the
-- last tile skipped the Lua layout callback. Do not revive leaves here: on the
-- return transition the tiled target has not been added yet.
on_event("window.update_rules", function(w)
	if not w or not w.floating or rehydrating or transferring then return end
	local st = w.workspace and states[w.workspace.id]
	local path = st and find_path(st.tree, w.stable_id)
	if not path or path[#path].vacant then return end
	path[#path].vacant = true
	tree.update_vacancy(st.tree)
	st.boxes[w.stable_id] = nil
	window_leaves_selection(w)
end)
on_event("window.fullscreen", window_leaves_selection)
on_event("workspace.removed", function(ws)
	if ws then monocle.remove(ws) end
	local st = ws and states[ws.id]
	if st then
		clear_selection(st)
		states[ws.id] = nil
	end
end)
on_event("config.reloaded", function()
	if state_store then
		-- The alias flip in hyprland.lua can reattach windows again. Wait for
		-- the scheduled property refresh before leaving the restore phase.
		rehydrating, config_seen = true, true
	else
		clear_selections()
		for _, w in ipairs(hl.get_windows()) do tag_window(w, false) end
	end
end)
on_event("config.props_refreshed", function()
	if transferring or (rehydrating and not config_seen) then return end
	if not rehydrating then
		-- Lua has no window.floating event in v0.56.2. The property-refresh
		-- barrier also reconciles float-only desktops (no layout callback).
		for id, st in pairs(states) do
			local members, tiled = workspace_members(id)
			reconcile_tree(st, members, tiled)
		end
		publish_feedback()
		return
	end
	local windows, live, tiled, targets = hl.get_windows(), {}, {}, {}
	for _, w in ipairs(windows) do
		if w.mapped and not closing[w.stable_id] and w.workspace then
			local id = w.workspace.id
			live[id], tiled[id], targets[id] = live[id] or {}, tiled[id] or {}, targets[id] or {}
			live[id][w.stable_id] = true
			if not w.floating and not w.hidden then
				tiled[id][w.stable_id] = true
				targets[id][#targets[id] + 1] = { window = w }
			end
		end
	end
	rehydrating, config_seen = false, false
	-- Remove old tags, then restore the saved selection with fresh userdata.
	for _, w in ipairs(windows) do tag_window(w, false) end
	local active = hl.get_active_window()
	for id, st in pairs(states) do
		st.highlighted = {}
		reconcile_tree(st, live[id] or {}, tiled[id] or {})
		if st.selected and (not find_path(st.tree, st.selected) or not active
			or active.stable_id ~= st.selected_focus_id
			or not find_path(st.selected, st.selected_focus_id)) then clear_selection(st) end
		if st.selected then remember_pull_source(st, st.selected, st.selected_focus_id) end
		if st.insertion_anchor and (not find_path(st.tree, st.insertion_anchor)
			or not (live[id] and live[id][st.insertion_window_id])) then
			st.insertion_anchor, st.insertion_window_id = nil, nil
		end
		highlight_selection(st, targets[id] or {})
	end
	local active_state = active and active.workspace and states[active.workspace.id]
	if active_state and active_state.mode == "monocle" then monocle.raise(active) end
	publish_feedback()
end)

-- ---------------------------------------------------------------------------
-- the layout
-- ---------------------------------------------------------------------------

local layout_impl = {

	recalculate = function(ctx)
		local targets = {}
		for _, t in ipairs(ctx.targets) do
			if t.window and t.window.mapped ~= false and not closing[t.window.stable_id] and not t.window.floating then
				table.insert(targets, t)
			end
		end

		local n = #targets
		if n == 0 then publish_feedback(); return end

		local wsid = workspace_id(ctx)
		if not wsid then return end
		if transfer_contexts then
			-- Native window.move removes/adds targets synchronously, one at a
			-- time. Do not prune a subtree halfway through moving its leaves.
			transfer_contexts[wsid] = ctx
			return
		end
		local st = state_for(wsid)
		monocle.sync(targets[1].window.workspace, st.mode == "monocle")
		local area = { x = ctx.area.x, y = ctx.area.y, w = ctx.area.w, h = ctx.area.h }

		-- live table: stable_id -> target
		local live = {}
		for _, t in ipairs(targets) do
			live[t.window.stable_id] = t
		end
		local members, tiled = workspace_members(wsid)
		if rehydrating then
			-- newTarget() recalculates after EACH reattached window. Missing
			-- tiled targets are not vacant during partial reload reattachment.
			for id in pairs(tiled) do live[id] = live[id] or true end
		end

		-- focused id
		local focused_id
		for _, t in ipairs(targets) do
			if t.window.active then focused_id = t.window.stable_id end
		end

		-- Prune only closed/moved leaves; absent tiled targets become vacant.
		reconcile_tree(st, members, live)
		if st.selected and (not rehydrating and focused_id and focused_id ~= st.selected_focus_id and find_path(st.tree, focused_id)) then
			clear_selection(st)
		end

		-- insert new windows
		local present = {}
		collect_ids(st.tree, present)
		local anchor = st.selected or focused_id
		if not anchor or not find_path(st.tree, anchor) then
			-- Mapping may have focused the NEW window already, or this may
			-- be an inactive workspace. Split its last focused surviving leaf
			-- rather than an arbitrary leaf at the end of the tree.
			local best_rank
			for _, t in ipairs(targets) do
				local id = t.window.stable_id
				local rank = t.window.focus_history_id
				if present[id] and rank and rank >= 0 and (not best_rank or rank < best_rank) then
					anchor, best_rank = id, rank
				end
			end
		end
		for _, t in ipairs(targets) do
			local id = t.window.stable_id
			if not present[id] then
				if st.insertion_window_id == id and find_path(st.tree, st.insertion_anchor) then
					anchor = st.insertion_anchor
				end
				local anchor_path = anchor and find_path(st.tree, anchor)
				local anchor_node = anchor_path and anchor_path[#anchor_path] or last_leaf(st.tree)
				-- Snapshot the subtree BEFORE clearing its highlight/selection.
				clear_selection(st)
				st.seq = st.seq + 1
				local pre = take_preselection(anchor_node)
				if not st.tree then
					st.tree = leaf(id)
					st.tree.n = st.seq
				else
					-- Recompute after pruning and before EACH insertion: a reload
					-- can supply a batch, and old boxes may predate a monitor resize.
					-- Use tiled geometry even while displaying monocle mode.
					place(st.tree, area, {})
					insert_adjacent(st, id, anchor_node,
						pre and pre.dir or nil, pre and pre.ratio or nil)
					local path = find_path(st.tree, id)
					if path then path[#path].n = st.seq end
					anchor = id -- multiple new windows chain off each other
				end
			end
		end

		-- Insertions and transfers can introduce new internal nodes.
		tree.update_vacancy(st.tree, live)
		-- place
		st.boxes = {}
		if st.mode == "monocle" then
			-- ctx.area has outer gaps and reserved panel space removed. Monocle
			-- fills the actual monitor; the scoped rules also stop place() from
			-- adding inner gaps/decorations to this larger box.
			local box = monocle_display.monitor_box(targets[1].window, area)
			for _, t in ipairs(targets) do
				t:place(box)
				st.boxes[t.window.stable_id] = box
			end
			if not rehydrating then
				for _, t in ipairs(targets) do
					if t.window.active then monocle.raise(t.window) end
				end
			end
		else
			if not st.tree then
				-- safety net
				st.tree = leaf(targets[1].window.stable_id)
			end
			place(st.tree, area, st.boxes)
			for _, t in ipairs(targets) do
				local b = st.boxes[t.window.stable_id]
				if b then t:place(b) end
			end
		end
		highlight_selection(st, targets)
		publish_feedback()
	end,

	layout_msg = function(ctx, msg)
		local wsid = workspace_id(ctx)
		local st = wsid and state_for(wsid) or nil
		local parts = {}
		for token in msg:gmatch("%S+") do table.insert(parts, token) end
		local cmd = parts[1] or ""

		local function focused()
			for _, t in ipairs(ctx.targets) do
				if t.window and t.window.active then return t.window end
			end
			for _, t in ipairs(ctx.targets) do
				if t.window then return t.window end
			end
			return nil
		end

		local function focus_id(id)
			for _, t in ipairs(ctx.targets) do
				if t.window and t.window.stable_id == id then
					selection_focus = true
					local result = hl.dispatch(hl.dsp.focus({ window = t.window }))
					selection_focus = false
					return not result or result.ok ~= false
				end
			end
			return false
		end

		local fw = focused()
		local fid = fw and fw.stable_id or nil
		if st and st.selected and (st.selected_focus_id ~= fid or not find_path(st.tree, st.selected)) then
			clear_selection(st)
		end
		local path = st and fid and find_path(st.tree, fid)
		local node = st and (st.selected or (path and path[#path]))

		-- Like bspwm, preselection belongs to the selected NODE, not to a
		-- workspace-wide next-window slot. Changing direction preserves ratio.
		if cmd == "preselect" or cmd == "pratio" then
			local arg = parts[2] or ""
			if cmd == "preselect" and (arg == "cancel" or arg == "clear") then
				if arg == "clear" and st then clear_presels(st.tree)
				elseif node then node.presel = nil end
				pending_presel = nil
				return true
			end
			local pre = (node and node.presel) or (not node and pending_presel) or { dir = "r", ratio = 0.5 }
			if cmd == "pratio" then
				local r = tonumber(arg)
				if not r or r <= 0 or r >= 1 then return "pratio: expected 0.1..0.9" end
				pre.ratio = r
			else
				pre.dir = arg
			end
			if node then node.presel = pre else pending_presel = pre end
			return true
		end

		if not node then return true end -- empty workspace
		-- Do not select/rotate arbitrary tiles while keyboard focus is on a float.
		if (cmd == "focus" or cmd == "rotate") and not fw.active then return true end

		if cmd == "pointer_swap" then
			if rehydrating or transferring or st.mode ~= "tiled" then return true end
			local source, target = tonumber(parts[2]), tonumber(parts[3])
			if source ~= fid or not fw.active or source == target then return true end
			if target and swap_nodes(st, source, target) then clear_selection(st) end
			return true

		elseif cmd == "pointer_resize" then
			if rehydrating or transferring or st.mode ~= "tiled" or not fw.active
				or tonumber(parts[2]) ~= fid or fw.floating or fw.hidden or fw.group
				or (fw.fullscreen or 0) ~= 0 then return true end
			-- Mouse gestures always target the grabbed leaf, not a keyboard
			-- subtree selection. Both axes commit in one layout recalculation.
			for i = 3, 5, 2 do
				local dir, ratio = parts[i], tonumber(parts[i + 1])
				if (dir == "l" or dir == "r" or dir == "u" or dir == "d")
					and ratio and ratio >= 0.1 and ratio <= 0.9 then
					local fence = tree.resize_fence(st, fid, dir)
					if fence then fence.ratio = ratio end
				end
			end
			clear_selection(st)
			return true

		elseif cmd == "swap" then
			if rehydrating or transferring or not fw.active or fw.floating or fw.hidden then return true end
			local nid = neighbor_id(st, node, parts[2] or "r")
			if not nid then return true end -- no external neighbour in that direction
			swap_nodes(st, node, nid)
			-- Keep keyboard focus and the selection on the same node. Its
			-- representative moves with it, so no focus/tag dispatch is needed.
			return true

		elseif cmd == "move" then
			local nid = neighbor_id(st, fid, parts[2] or "r")
			if not nid then return true end
			local moved = detach_node(st, fid)
			-- Keep per-window metadata, including the last floating rectangle.
			insert_adjacent(st, moved, nid, (parts[2] == "l" or parts[2] == "u") and parts[2] or "r", nil)
			return true

		elseif cmd == "grow" or cmd == "shrink" then
			local px = tonumber(parts[3]) or 20
			resize(st, st.selected or fid, parts[2] or "r", cmd == "grow" and px or -px)
			return true -- no owning split (e.g. screen edge) is a no-op, not an error

		elseif cmd == "rotate" then
			local degrees = tonumber(parts[2]) or 90
			if degrees ~= 90 and degrees ~= 180 and degrees ~= 270 then return "rotate: expected 90, 180 or 270" end
			rotate(node, degrees)
			return true

		elseif cmd == "flip" then
			local sub = st.selected or subtree_of(st, fid)
			flip(sub, parts[2] == "v" and "v" or "h")
			return true

		elseif cmd == "balance" then
			balance(st.tree)
			return true

		elseif cmd == "equalize" then
			equalize(st.tree, 0.5)
			return true

		elseif cmd == "transplant" then
			transplant(st, fid)
			return true

		elseif cmd == "pull" then
			if rehydrating or transferring or not fw.active then return true end
			return pull(st, node, fw, ctx)

		elseif cmd == "mode" then
			st.mode = (st.mode == "monocle") and "tiled" or "monocle"
			return true

		elseif cmd == "monocle" or cmd == "tiled" then
			st.mode = cmd
			return true

		elseif cmd == "focus" then
			local target = focus_subtree_node(st, fid, parts[2] or "brother")
			if not target then return true end
			-- Hyprland still needs one keyboard-focused window. Keep it when
			-- climbing; pick a representative only when entering another branch.
			local tid = find_path(target, fid) and fid or nil
			if not tid then
				for _, child in ipairs(leaves(target)) do
					if not child.vacant then tid = child.id; break end
				end
			end
			if not tid then return true end -- branch contains only floats
			st.selected, st.selected_focus_id = target, tid
			if tid ~= fid and not focus_id(tid) then clear_selection(st) end
			if st.selected then remember_pull_source(st, target, tid) end
			highlight_selection(st, ctx.targets)
			return true

		end

		return "bspwm layout: unknown command '" .. cmd .. "'"
	end,
}

-- Replay only targets still owned by each workspace. Empty layouts do not
-- generate a native callback, so their last snapshot may contain departed tiles.
local function replay_transfer_contexts(contexts)
	for wsid, context in pairs(contexts) do
		local targets = {}
		for _, target in ipairs(context.targets) do
			local w = target.window
			if w and w.mapped and not w.floating and w.workspace and w.workspace.id == wsid then
				targets[#targets + 1] = target
			end
		end
		layout_impl.recalculate({ area = context.area, targets = targets })
	end
end

-- Original sxhkd: focused.automatic && node -n last.!automatic || node last.leaf -n focused
-- Extend its last.leaf fallback to the previously selected logical node: native
-- window history alone forgets a subtree as soon as the destination gets focus.
pull = function(st, node, focused, context)
	prune_pull_sources()
	local candidates, windows = {}, {}
	for _, w in ipairs(hl.get_windows()) do
		local ws = w.workspace
		local state = ws and states[ws.id]
		local layout = ws and ws.tiled_layout
		local path = state and find_path(state.tree, w.stable_id)
		if w.mapped and not w.floating and not w.hidden and not w.group and path
			and (layout == "lua:bspwm" or layout == "lua:bspwm_b") then
			windows[w.stable_id] = w
			local rank = w.focus_history_id
			if rank and rank >= 0 then
				candidates[#candidates + 1] = { window = w, st = state, path = path, rank = rank }
			end
		end
	end
	if not windows[focused.stable_id] then return true end
	table.sort(candidates, function(a, b)
		if a.rank == b.rank then return a.window.stable_id < b.window.stable_id end
		return a.rank < b.rank
	end)
	local function disjoint(other)
		return not find_path(node, other) and not find_path(other, node)
	end
	local from = { st = st, node = node, window = focused }
	local to
	if not node.presel then
		for _, candidate in ipairs(candidates) do
			-- Internal-node preselections survive loss of selection. Associate
			-- them with their representative leaves' native focus history.
			for i = #candidate.path, 1, -1 do
				local anchor = candidate.path[i]
				if anchor.presel and disjoint(anchor) then
					to = { st = candidate.st, node = anchor, window = candidate.window }
					break
				end
			end
			if to then break end
		end
	end
	if not to then
		to = from
		from = nil
		for _, candidate in ipairs(candidates) do
			local last, representative = candidate.path[#candidate.path], candidate.window
			for i = #candidate.path - 1, 1, -1 do
				local group = candidate.path[i]
				if group.pull_focus_id then
					last, representative = group, windows[group.pull_focus_id]
					break
				end
			end
			if disjoint(last) then
				if not representative then return "pull: selected subtree contains an unavailable window" end
				from = { st = candidate.st, node = last, window = representative }
				break
			end
		end
	end
	if not from then return true end

	local moving = {}
	for _, child in ipairs(leaves(from.node)) do
		if not windows[child.id] then return "pull: selected subtree contains an unavailable window" end
		moving[#moving + 1] = windows[child.id]
	end
	local source_ws, dest_ws = from.window.workspace, to.window.workspace
	local cross_workspace = source_ws.id ~= dest_ws.id
	-- Keep the calling workspace's native targets even for a local transplant:
	-- no native window.move callback will otherwise reflow it before follow.
	local contexts, failure = { [focused.workspace.id] = context }, nil
	-- Border-tag updates can synchronously recalculate on the SAME desktop,
	-- too. Suppress intermediate selection events/checkpoints for both paths.
	transferring, transfer_contexts = true, contexts
	if cross_workspace then
		-- Workspace objects stringify to their ID in this API, but negative
		-- named/special IDs are parsed as relative selectors. Use their name.
		local selector = workspace_selector(dest_ws)
		local ok, err = pcall(function()
			for _, w in ipairs(moving) do
				local result = hl.dispatch(hl.dsp.window.move({ window = w, workspace = selector, follow = false }))
				if (result and result.ok == false) or not w.workspace or w.workspace.id ~= dest_ws.id then
					failure = "pull: could not move window " .. w.stable_id
					break
				end
			end
		end)
		if not ok then failure = "pull: " .. tostring(err) end
	end

	local replay_ok, replay_error = pcall(function()
		if not failure then
			-- Commit only after native moves succeeded. Reuse the node so split
			-- ratios, ages and its own preselections travel with it.
			detach_node(from.st, from.node)
			local dest_area = contexts[dest_ws.id] and contexts[dest_ws.id].area or context.area
			place(to.st.tree, dest_area, {})
			local pre = to.node.presel
			to.node.presel = nil
			insert_adjacent(to.st, from.node, to.node, pre and pre.dir, pre and pre.ratio)
			for _, child in ipairs(leaves(from.node)) do to.st.seq = math.max(to.st.seq, child.n) end
		end
		clear_selection(from.st)
		if to.st ~= from.st then clear_selection(to.st) end
		-- Prune before replay/checkpointing: an empty source produces no native
		-- callback, and a partially failed move must not leave duplicate leaves.
		local live = workspace_members(source_ws.id)
		from.st.tree = prune_tree(from.st.tree, live)
		if not from.st.tree then from.st.boxes = {} end
		transfer_contexts = nil

		-- Apply the final geometry before focusing, including same-desktop
		-- sends/pulls where no native moves generated layout callbacks.
		replay_transfer_contexts(contexts)
	end)
	-- A rule/placement exception must not disable every later transfer.
	transfer_contexts, transferring = nil, false
	if not replay_ok then
		failure = (failure and failure .. "; " or "pull: ") .. tostring(replay_error)
	end
	if not failure then
		-- Move silently above, then focus ONCE after committing/replaying the
		-- insertion. Focus the incoming node, not the old destination anchor.
		local ok, result = pcall(function()
			return hl.dispatch(hl.dsp.focus({ window = from.window }))
		end)
		local active = hl.get_active_window()
		if not ok or (result and result.ok == false) or not active or active.stable_id ~= from.window.stable_id then
			failure = "pull: could not focus inserted node" .. (not ok and ": " .. tostring(result) or "")
		elseif from.node.t == "split" then
			-- Workspace/monitor focus events clear selection. Restore the moved
			-- subtree AFTER those events, retaining its original representative.
			to.st.selected, to.st.selected_focus_id = from.node, active.stable_id
			remember_pull_source(to.st, from.node, active.stable_id)
			local targets = {}
			for _, w in ipairs(moving) do targets[#targets + 1] = { window = w } end
			highlight_selection(to.st, targets)
		end
	end
	publish_feedback()
	return failure or true
end

-- Messages can change state without moving windows (e.g. preselection).
local handle_message = layout_impl.layout_msg
layout_impl.layout_msg = function(ctx, msg)
	local result = handle_message(ctx, msg)
	checkpoint()
	return result
end

-- Registered twice, under "lua:bspwm" and "lua:bspwm_b". Hyprland v0.56.2 keeps a
-- workspace's existing layout instance across a config reload when the layout
-- NAME is unchanged, but that instance still points at the pre-reload provider
-- (marked inactive, Lua state closed), so every recalculation fails and Hyprland
-- falls back to a plain grid -- windows open side by side. hyprland.lua flips
-- general.layout between the two names on config.reloaded, which forces fresh
-- instances bound to the new provider.
hl.layout.register("bspwm", layout_impl)
hl.layout.register("bspwm_b", layout_impl)

-- ---------------------------------------------------------------------------
-- module API (require("lua/extensions/bspwm"))
-- ---------------------------------------------------------------------------

local M = {}

-- Explicit state shortcuts can bracket the synchronous native transition.
-- Unlike rule events, the return from float() is after native placement, so
-- restoring here needs neither a timer nor a plugin hook, and cannot interfere
-- with Hyprland's temporary floating state during native pointer drags.
function M.set_floating(window, floating)
	local was_floating = window.floating
	local captured = was_floating and not floating and float_geometry.capture(window) or nil
	local function node_for_window()
		if rehydrating or transferring then return nil end
		local ws = window.workspace
		local st = ws and compatible_workspace(ws) and states[ws.id]
		local path = st and find_path(st.tree, window.stable_id)
		return path and path[#path]
	end
	local node = node_for_window()
	local saved = node and node.floating_geometry
	local result = hl.dispatch(hl.dsp.window.float({ action = floating and "on" or "off", window = window }))
	if (result and result.ok == false) or not window.mapped or window.floating ~= floating then return result end
	if captured then
		-- An initially floating client has no tree leaf until the tile dispatch
		-- inserts it. Attach to that leaf only after the transition succeeds.
		node = node_for_window()
		if node then node.floating_geometry = captured; checkpoint() end
	elseif not was_floating and floating then
		float_geometry.restore(window, saved)
	end
	return result
end

-- Transfer intact nodes, including unselected tiles, beside the destination's
-- last-focused node. Preserve their metadata, not an old destination position.
function M.move_to_workspace(selector)
	if rehydrating or transferring then return "workspace move: layout is busy" end
	local active = hl.get_active_window()
	if not active or not active.mapped or not active.workspace then return true end
	local source = active.workspace
	local from = states[source.id]
	local node = from and from.selected
	local dest = hl.get_workspace(selector)
	if dest and dest.id == source.id then return true end
	if not node or node.t ~= "split" or active.floating or from.selected_focus_id ~= active.stable_id
		or not find_path(from.tree, node) then
		local path = from and find_path(from.tree, active.stable_id)
		if path and not active.floating and not active.hidden and not active.group
			and compatible_workspace(source) and (not dest or compatible_workspace(dest)) then
			node = path[#path]
		else
			-- Floats, native groups and other layouts still use native follow.
			local result = hl.dispatch(hl.dsp.window.move({
				window = active, workspace = dest and workspace_selector(dest) or selector, follow = true,
			}))
			return result and result.ok == false and "workspace move: could not move focused window" or true
		end
	end
	if not compatible_workspace(source) or (dest and not compatible_workspace(dest)) then
		return "workspace move: selected subtree requires the bspwm layout"
	end

	-- Snapshot handles and the destination anchor before native moves trigger
	-- synchronous focus/layout events. Never fall back to moving just one leaf
	-- if part of the selected subtree is stale or belongs to a native group.
	local windows, moving = {}, {}
	for _, w in ipairs(hl.get_windows()) do windows[w.stable_id] = w end
	for _, child in ipairs(leaves(node)) do
		local w = windows[child.id]
		if not w or not w.mapped or w.floating or w.hidden or w.group
			or not w.workspace or w.workspace.id ~= source.id then
			return "workspace move: selected subtree contains an unavailable window"
		end
		moving[#moving + 1] = w
	end
	-- Actions::moveToWorkspace(silent=true) otherwise focuses the window at
	-- the departing tile's OLD center, then falls back to cursor refocus. That
	-- overwrites workspace.last_window and contaminates native focus history.
	-- Pick a surviving source window BEFORE any of those callbacks can run.
	local moving_ids, source_focus, best_rank = {}, nil, nil
	for _, w in ipairs(moving) do moving_ids[w.stable_id] = true end
	for _, w in pairs(windows) do
		if w.mapped and not w.hidden and not closing[w.stable_id] and not moving_ids[w.stable_id]
			and w.workspace and w.workspace.id == source.id then
			local rank = w.focus_history_id
			if not rank or rank < 0 then rank = math.huge end
			if not source_focus or rank < best_rank or (rank == best_rank and w.stable_id < source_focus.stable_id) then
				source_focus, best_rank = w, rank
			end
		end
	end
	local source_focus_requested = false
	local function focus_source()
		if not source_focus or not source_focus.mapped or source_focus.hidden
			or not source_focus.workspace or source_focus.workspace.id ~= source.id or source_focus.active then return end
		source_focus_requested = true
		local result = hl.dispatch(hl.dsp.focus({ window = source_focus }))
		local current = hl.get_active_window()
		if (result and result.ok == false) or not current or current.stable_id ~= source_focus.stable_id then
			error("could not focus source workspace survivor", 0)
		end
	end
	local to, anchor
	local function set_destination(ws)
		if not compatible_workspace(ws) then error("selected subtree requires the bspwm layout", 0) end
		to = state_for(ws.id)
		local path = ws.last_window and find_path(to.tree, ws.last_window.stable_id)
		anchor = to.selected or (path and path[#path]) or last_leaf(to.tree)
	end
	if dest then set_destination(dest) end
	local contexts = {}
	transferring, transfer_contexts = true, contexts
	local ok, failure = pcall(function()
		-- Focus a STAYING window while still on this desktop. The moving
		-- window is then inactive, so native silent moves skip spatial refocus.
		-- Do not demote a covering fullscreen window before it is transferred.
		if not source.has_fullscreen and (active.fullscreen or 0) == 0 then focus_source() end
		for _, w in ipairs(moving) do
			local moved
			if not dest then
				-- A numbered/named desktop may not exist yet. Let the first native
				-- move create it, then pin every remaining move to its absolute ID.
				local result = hl.dispatch(hl.dsp.window.move({ window = w, workspace = selector, follow = false }))
				if w.workspace and w.workspace.id ~= source.id then
					dest = w.workspace
					set_destination(dest)
				end
				moved = dest and not (result and result.ok == false)
			else
				moved = move_window(w, dest)
			end
			if not moved then error("could not move window " .. w.stable_id, 0) end
		end
		-- Fullscreen transfers defer this until the covering window has left.
		-- Also repair a native callback that changed focus during the moves.
		focus_source()
	end)
	if not ok then
		-- Best-effort rollback: even a dispatcher that reports failure may
		-- already have moved its window. Reconcile ownership if rollback fails.
		for i = #moving, 1, -1 do
			local restored_ok, restored = pcall(move_window, moving[i], source)
			if not restored_ok or not restored then failure = tostring(failure) .. "; rollback incomplete" end
		end
	end
	local replay_ok, replay_error = pcall(function()
		if ok then
			detach_node(from, node)
			local context = contexts[dest.id]
			if context then place(to.tree, context.area, {}) end
			-- Every send, including a return, uses the destination focus
			-- snapshotted before native moves could change its history.
			local pre = take_preselection(anchor)
			insert_adjacent(to, node, anchor, pre and pre.dir, pre and pre.ratio)
			for _, child in ipairs(leaves(node)) do to.seq = math.max(to.seq, child.n) end
		end
		for _, ws in ipairs(dest and { source, dest } or { source }) do
			local st, live = states[ws.id], {}
			for _, w in ipairs(ws:get_windows() or {}) do
				if w.mapped and not closing[w.stable_id] then live[w.stable_id] = true end
			end
			if st then
				st.tree = prune_tree(st.tree, live)
				st.boxes = {}
				clear_selection(st)
			end
		end
		transfer_contexts = nil
		replay_transfer_contexts(contexts)
	end)
	transfer_contexts, transferring = nil, false
	if ok and replay_ok then
		local focused, result = pcall(function() return hl.dispatch(hl.dsp.focus({ window = active })) end)
		local current = hl.get_active_window()
		if not focused or (result and result.ok == false) or not current or current.stable_id ~= active.stable_id then
			failure = "could not focus moved node"
		elseif node.t == "split" then
			-- Workspace/monitor focus notifications clear selection. Restore it
			-- afterwards so another send/rotate/close still acts on the subtree.
			to.selected, to.selected_focus_id = node, active.stable_id
			remember_pull_source(to, node, active.stable_id)
			local targets = {}
			for _, w in ipairs(moving) do targets[#targets + 1] = { window = w } end
			highlight_selection(to, targets)
		end
	elseif not ok and source_focus_requested and active.mapped and active.workspace and active.workspace.id == source.id then
		-- A rejected/rolled-back move must not leave our preparatory source
		-- focus behind. Do not follow a window whose rollback did not succeed.
		local restored_focus, result = pcall(function() return hl.dispatch(hl.dsp.focus({ window = active })) end)
		local current = hl.get_active_window()
		if not restored_focus or (result and result.ok == false) or not current or current.stable_id ~= active.stable_id then
			failure = tostring(failure) .. "; could not restore source focus"
		end
	end
	publish_feedback()
	if failure then return "workspace move: " .. tostring(failure) end
	if not replay_ok then return "workspace move: " .. tostring(replay_error) end
	return true
end

-- Exchange desktop contents without reinserting every tile into a new tree.
-- The native API only moves individual windows; defer its intermediate layout
-- callbacks, exchange the intact states, then replay both final target lists.
function M.swap_workspaces(cur, tgt)
	if cur.id == tgt.id then return true end
	if rehydrating or transferring then return "workspace swap: layout is busy" end
	local contexts, moves = {}, {}
	local cur_state, tgt_state = state_for(cur.id), state_for(tgt.id)
	-- Snapshot BOTH sides before any window (or native group) changes ownership.
	for _, pair in ipairs({ { tgt, cur }, { cur, tgt } }) do
		for _, w in ipairs(pair[1]:get_windows() or {}) do
			if w.mapped then moves[#moves + 1] = { window = w, source = pair[1], dest = pair[2] } end
		end
	end

	transferring, transfer_contexts = true, contexts
	local ok, failure = pcall(function()
		for _, move in ipairs(moves) do
			if not move_window(move.window, move.dest) then
				error("could not move window " .. move.window.stable_id, 0)
			end
		end
	end)
	if ok then
		-- Ratios, orientation, ages, preselections and tiled/monocle mode travel
		-- with the desktop. Geometry is recomputed for the destination monitor.
		states[cur.id], states[tgt.id] = tgt_state, cur_state
	else
		-- Best-effort rollback keeps a rejected move from partially exchanging
		-- desktops. If rollback also fails, reconcile actual ownership below.
		for i = #moves, 1, -1 do
			local move = moves[i]
			local restored_ok, restored = pcall(move_window, move.window, move.source)
			if not restored_ok or not restored then failure = tostring(failure) .. "; rollback incomplete" end
		end
	end

	local replay_ok, replay_error = pcall(function()
		local live = { [cur.id] = {}, [tgt.id] = {} }
		for _, w in ipairs(hl.get_windows()) do
			local ids = w.workspace and live[w.workspace.id]
			if ids and w.mapped and not closing[w.stable_id] then ids[w.stable_id] = true end
		end
		for _, ws in ipairs({ cur, tgt }) do
			local st = states[ws.id]
			st.tree = prune_tree(st.tree, live[ws.id])
			st.boxes = {}
			-- Selection is transient; per-node preselection stays in the tree.
			clear_selection(st)
			-- Also update empty/float-only workspaces, which never recalculate.
			monocle.sync(ws, st.mode == "monocle")
		end
		transfer_contexts = nil
		replay_transfer_contexts(contexts)
	end)
	-- Always release the guard, even if native rule/placement dispatch throws.
	transfer_contexts, transferring = nil, false
	publish_feedback()
	if not ok then return "workspace swap: " .. tostring(failure) end
	if not replay_ok then return "workspace swap: " .. tostring(replay_error) end
	return true
end

-- Pointer operations never enter Hyprland's native tiled drag controller:
-- it temporarily floats/removes the source instead of doing bspwm pointer swaps.
function M.drag_valid(w)
	local ws = w and w.workspace
	local st = ws and states[ws.id]
	return ws ~= nil and st ~= nil and not rehydrating and not transferring and w.mapped and not w.floating
		and not w.hidden and w.visible ~= false and not w.group and (w.fullscreen or 0) == 0
		and ws.visible ~= false and (ws.tiled_layout == "lua:bspwm" or ws.tiled_layout == "lua:bspwm_b")
		and st.mode == "tiled" and find_path(st.tree, w.stable_id) ~= nil
end

-- The native Lua layout bridge's resizeTarget() only recalculates: it never
-- forwards the corner/delta to Lua. Snapshot the two visible fences ourselves.
function M.resize_begin(w, pos)
	if not M.drag_valid(w) or not w.at or not w.size then return nil end
	local st = states[w.workspace.id]
	local path = find_path(st.tree, w.stable_id)
	local box = st.tree._box
	if not box then return nil end
	local grab = {
		workspace_id = w.workspace.id, leaf = path[#path],
		origin = { x = pos.x, y = pos.y },
		area = { x = box.x, y = box.y, w = box.w, h = box.h }, fences = {},
	}
	local directions = {
		pos.x < w.at.x + w.size.x / 2 and "l" or "r",
		pos.y < w.at.y + w.size.y / 2 and "u" or "d",
	}
	for i, dir in ipairs(directions) do
		local node = tree.resize_fence(st, w.stable_id, dir)
		grab.fences[i] = { dir = dir, node = node }
		if node then
			local fence = grab.fences[i]
			fence.a, fence.b, fence.axis, fence.ratio = node.a, node.b, node.axis, node.ratio
			fence.span = i == 1 and node._box.w or node._box.h
		end
	end
	return grab
end

function M.resize_motion(w, grab, pos)
	if not grab or not M.drag_valid(w) or not w.active or w.workspace.id ~= grab.workspace_id then return false end
	local st = states[w.workspace.id]
	local path = find_path(st.tree, w.stable_id)
	if path[#path] ~= grab.leaf then return false end
	local box, area = st.tree._box, grab.area
	if not box or box.x ~= area.x or box.y ~= area.y or box.w ~= area.w or box.h ~= area.h then return false end
	local ratios, changed = {}, false
	for i, fence in ipairs(grab.fences) do
		local node = tree.resize_fence(st, w.stable_id, fence.dir)
		-- Stop if topology/vacancy changed; never resize a replacement split.
		if node ~= fence.node then return false end
		ratios[i] = -1
		if node then
			local span = i == 1 and node._box.w or node._box.h
			if node.a ~= fence.a or node.b ~= fence.b or node.axis ~= fence.axis or span ~= fence.span then return false end
			local delta = i == 1 and (pos.x - grab.origin.x) or (pos.y - grab.origin.y)
			-- Absolute displacement avoids rounding drift and keeps the original
			-- corner pinned when crossing the centre or reaching a ratio limit.
			ratios[i] = math.min(0.9, math.max(0.1, fence.ratio + delta / math.max(fence.span, 1)))
			changed = changed or ratios[i] ~= node.ratio
		end
	end
	if not changed then return true end
	local result = hl.dispatch(hl.dsp.layout(string.format("pointer_resize %d %s %.17g %s %.17g",
		w.stable_id, grab.fences[1].dir, ratios[1], grab.fences[2].dir, ratios[2])))
	return not result or result.ok ~= false
end

function M.drag_swap(w, other)
	if not M.drag_valid(w) or not M.drag_valid(other) or w.workspace.id ~= other.workspace.id then return false end
	if not w.active then hl.dispatch(hl.dsp.focus({ window = w })) end
	if not w.active then return false end
	local result = hl.dispatch(hl.dsp.layout("pointer_swap " .. w.stable_id .. " " .. other.stable_id))
	return not result or result.ok ~= false
end

-- bspwm window.c:move_client transfers (rather than swaps) when crossing a
-- monitor boundary, then subsequent motion swaps in the destination desktop.
function M.drag_transfer(w, dest)
	if not M.drag_valid(w) or not dest or dest.id == w.workspace.id or dest.visible == false
		or (dest.tiled_layout ~= "lua:bspwm" and dest.tiled_layout ~= "lua:bspwm_b") then return false end
	local source = w.workspace
	local from, to = states[source.id], state_for(dest.id)
	local path = find_path(from.tree, w.stable_id)
	local node = path[#path]
	local anchor = dest.last_window and dest.last_window.stable_id
	local contexts = {}
	local function move_to(ws)
		local selector = workspace_selector(ws)
		local result = hl.dispatch(hl.dsp.window.move({ window = w, workspace = selector, follow = false }))
		return not (result and result.ok == false) and w.workspace and w.workspace.id == ws.id
	end
	transferring, transfer_contexts = true, contexts
	local ok, moved = pcall(move_to, dest)
	local success = ok and moved
	if not success and w.workspace and w.workspace.id ~= source.id then pcall(move_to, source) end
	local replay_ok, replay_error = pcall(function()
		if success then
			detach_node(from, node)
			local anchor_path = anchor and find_path(to.tree, anchor)
			local anchor_node = anchor_path and anchor_path[#anchor_path] or last_leaf(to.tree)
			local context = contexts[dest.id]
			if context then place(to.tree, context.area, {}) end
			local pre = take_preselection(anchor_node)
			insert_adjacent(to, node, anchor_node, pre and pre.dir, pre and pre.ratio)
			to.seq = math.max(to.seq, node.n)
		end
		-- Reconcile even after a failed native move/rollback. Empty sources
		-- have no callback, so must be pruned explicitly before checkpointing.
		for _, ws in ipairs({ source, dest }) do
			local st, live = states[ws.id], {}
			for _, window in ipairs(ws:get_windows() or {}) do
				if window.mapped and not closing[window.stable_id] then live[window.stable_id] = true end
			end
			st.tree = prune_tree(st.tree, live)
			st.boxes = {}
			clear_selection(st)
		end
		transfer_contexts = nil
		replay_transfer_contexts(contexts)
	end)
	transfer_contexts, transferring = nil, false
	publish_feedback()
	if not replay_ok then print("bspwm pointer transfer: " .. tostring(replay_error)) end
	if success and replay_ok then hl.dispatch(hl.dsp.focus({ window = w })) end
	return success and replay_ok
end

function M.reload()
	checkpoint()
	hl.exec_cmd("hyprctl reload")
end

-- Optional renderer kept separate from the layout's tree logic.
function M.set_feedback_sink(sink)
	feedback_sink = sink
	publish_feedback()
end

function M.close_selected()
	local active = hl.get_active_window()
	local st = active and active.workspace and states[active.workspace.id]
	if not st or not st.selected or st.selected.t ~= "split" or active.floating
		or st.selected_focus_id ~= active.stable_id or not find_path(st.tree, st.selected) then return false end

	-- bspwm close_node walks all leaves. Snapshot live handles first: clients
	-- may close immediately and change focus/the tree while requests are sent.
	local ids, windows = {}, {}
	collect_ids(st.selected, ids)
	for _, w in ipairs(hl.get_windows()) do
		if ids[w.stable_id] and w.mapped and not w.floating
			and w.workspace and w.workspace.id == active.workspace.id then windows[#windows + 1] = w end
	end
	if #windows < 2 then return false end
	clear_selection(st)
	for _, w in ipairs(windows) do
		if w.mapped then hl.dispatch(hl.dsp.window.close({ window = w })) end
	end
	checkpoint()
	return true
end

-- Normal close shortcut: selected subtree, otherwise the focused window.
function M.close()
	if M.close_selected() then return end
	local w = hl.get_active_window()
	if w and w.mapped then hl.dispatch(hl.dsp.window.close({ window = w })) end
end

-- Floats aren't layout targets, so directional focus is a public callback,
-- not a layout message (which would run against an unrelated tiled window).
function M.focus_dir(dir)
	if rehydrating or transferring then return end
	directional_focus.focus(dir, states)
end

-- Use the same selected node/search as `swap`, so an internal neighbour does
-- not suppress the monitor fallback when the whole selection is at an edge.
function M.has_neighbor(dir)
	if rehydrating or transferring then return false end
	local w = hl.get_active_window()
	if not w or not w.mapped or w.floating or w.hidden or not w.workspace then return false end
	local st = states[w.workspace.id]
	if not st then return false end
	local node = st.selected
	if not node or st.selected_focus_id ~= w.stable_id or not find_path(st.tree, node) then
		node = w.stable_id
	end
	return neighbor_id(st, node, dir) ~= nil
end

return M
