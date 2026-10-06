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
--   * directional swap / move / grow / shrink between leaves
--   * tiled pointer swaps during Super-drag (input in bspwm_drag.lua)
--   * node focus: parent / brother / first / second
--   * monocle mode (stack, focused on top)
--
-- NOT implemented (see discussion):
--   * mouse border-drag resize (use the grow/shrink binds)
--   * pseudo_tiled (use stock hl.dsp.window.pseudo)
--
-- layout_msg commands (via hl.dsp.layout("...")):
--   preselect <l|r|u|d|west|east|north|south>
--   pratio <0.1..0.9>
--   preselect cancel | preselect clear
--   swap <l|r|u|d>          move <l|r|u|d>
--   pointer_swap <source stable_id> <target stable_id> (decimal, same workspace)
--   grow <l|r|u|d> <px>     shrink <l|r|u|d> <px>
--   rotate <90|270>         flip <h|v>
--   balance                 equalize
--   transplant              pull
--   mode                    monocle                 tiled
--   focus <parent|brother|first|second>
-- ============================================================================

-- Load BEFORE registering either provider: registration itself can reattach
-- existing windows and call recalculate with an incomplete target list.
local state_store, store_error = require("lua/extensions/bspwm_state").open_session()
local restored, restore_error
if state_store then restored, restore_error = state_store:load() end
if store_error or restore_error then print("bspwm checkpoint: " .. tostring(store_error or restore_error)) end
local S = restored and restored.states or {}
local PEND = restored and restored.pending or nil
local rehydrating = state_store ~= nil
local config_seen = false
local last_store_error
local selection_focus = false -- guard our own representative-window focus events
local selection_tag = "bspwm_selected"
local feedback_sink
local transfer_contexts -- defer reentrant layout callbacks during cross-workspace moves
local transferring = false -- also suppress checkpoints/feedback through final replay
local monocle_display = require("lua/extensions/bspwm_monocle")
local monocle = monocle_display.new()

local function checkpoint()
	if not state_store or rehydrating or transferring then return end
	local ok, err = state_store:save(S, PEND)
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
	if feedback_sink then feedback_sink(S) end
end

-- ---------------------------------------------------------------------------
-- tree primitives
-- ---------------------------------------------------------------------------

local function leaf(id)
	return { t = "leaf", id = id, n = 0 }
end

local function axis_for(dir)
	if dir == "u" or dir == "d" or dir == "up" or dir == "down"
		or dir == "north" or dir == "south" then
		return "v"
	end
	return "h" -- l, r, west, east, nil
end

-- side the NEW window takes when preselecting `dir`
local function new_is_first(dir)
	return dir == "l" or dir == "west" or dir == "u" or dir == "up" or dir == "north"
end

-- target can be a stable window id OR an internal node reference.
local function find_path(node, target, path)
	if not node then return nil end
	path = path or {}
	table.insert(path, node)
	if node == target or (node.t == "leaf" and node.id == target) then return path end
	if node.t == "split" then
		local p = find_path(node.a, target, path) or find_path(node.b, target, path)
		if p then return p end
	end
	table.remove(path)
	return nil
end

local function collect_ids(node, ids)
	if not node then return end
	if node.t == "leaf" then
		ids[node.id] = true
	else
		collect_ids(node.a, ids)
		collect_ids(node.b, ids)
	end
end

local function leaves(node, out)
	out = out or {}
	if not node then return out end
	if node.t == "leaf" then
		table.insert(out, node)
	else
		leaves(node.a, out)
		leaves(node.b, out)
	end
	return out
end

local function count_leaves(node)
	return #leaves(node)
end

local function first_leaf(node)
	while node and node.t == "split" do node = node.a end
	return node
end

local function any_leaf(node)
	local l = leaves(node)
	return l[#l]
end

-- remove dead leaves, promote siblings; returns (new subtree, alive?)
local function prune_tree(node, live)
	if not node then return nil, false end
	if node.t == "leaf" then
		if live[node.id] then return node, true end
		return nil, false
	end
	local a, aok = prune_tree(node.a, live)
	local b, bok = prune_tree(node.b, live)
	if aok and bok then node.a, node.b = a, b; return node, true end
	if aok then return a, true end
	if bok then return b, true end
	return nil, false
end

local function walk_splits(node, fn)
	if not node or node.t ~= "split" then return end
	fn(node)
	walk_splits(node.a, fn)
	walk_splits(node.b, fn)
end

-- ---------------------------------------------------------------------------
-- insertion / removal
-- ---------------------------------------------------------------------------

-- insert new_id (window id OR intact subtree) beside anchor_id, on side `dir`.
-- Without preselection, match bspwm's default longest_side / second_child.
-- Automatic callers must refresh the tree's boxes before inserting.
local function insert_adjacent(st, new_id, anchor_id, dir, ratio)
	local r    = ratio or 0.5
	local new  = type(new_id) == "table" and new_id or leaf(new_id)
	local path = find_path(st.tree, anchor_id)

	if not path then
		-- anchor vanished: attach next to an arbitrary leaf, or become root
		local other = any_leaf(st.tree)
		if not other then st.tree = new; return end
		anchor_id = other.id
		path = find_path(st.tree, anchor_id)
	end

	local anchor = path[#path]
	if not dir then
		local box = anchor._box
		dir = (box and box.w > box.h) and "r" or "d"
	end
	local split = { t = "split", axis = axis_for(dir), ratio = r }
	-- bspwm tree.c:insert_node: ratio is ALWAYS the first child's share,
	-- including east/south preselection where the new window is second.
	if new_is_first(dir) then
		split.a, split.b = new, anchor
	else
		split.a, split.b = anchor, new
	end

	if #path == 1 then
		st.tree = split
	else
		local parent = path[#path - 1]
		if parent.a == anchor then parent.a = split else parent.b = split end
	end
end

local function remove_leaf(st, id)
	local path = find_path(st.tree, id)
	if not path then return nil end
	local node = path[#path]
	if #path == 1 then
		st.tree = nil
		return node
	end
	local parent = path[#path - 1]
	local sib    = (parent.a == node) and parent.b or parent.a
	if #path == 2 then
		st.tree = sib
	else
		local gp = path[#path - 2]
		if gp.a == parent then gp.a = sib else gp.b = sib end
	end
	return node
end

-- ---------------------------------------------------------------------------
-- geometry helpers (uses boxes recorded by place())
-- ---------------------------------------------------------------------------

local function neighbor_id(st, id, dir)
	local b = st.boxes[id]
	if not b then return nil end
	local cx, cy = b.x + b.w / 2, b.y + b.h / 2
	local best, bestD
	for oid, ob in pairs(st.boxes) do
		if oid ~= id then
			local ox, oy = ob.x + ob.w / 2, ob.y + ob.h / 2
			local ok
			if dir == "l" then
				ok = ox < cx and b.y < ob.y + ob.h and ob.y < b.y + b.h
			elseif dir == "r" then
				ok = ox > cx and b.y < ob.y + ob.h and ob.y < b.y + b.h
			elseif dir == "u" then
				ok = oy < cy and b.x < ob.x + ob.w and ob.x < b.x + b.w
			elseif dir == "d" then
				ok = oy > cy and b.x < ob.x + ob.w and ob.x < b.x + b.w
			end
			if ok then
				local d = (dir == "l" or dir == "r") and math.abs(ox - cx) or math.abs(oy - cy)
				if not bestD or d < bestD then best, bestD = oid, d end
			end
		end
	end
	return best
end

-- grow/shrink the focused leaf or selected subtree's edge by px.
-- Only splits OWNING that edge are adjusted: for axis h, the boundary is
-- first-child-east (r) or second-child-west (l); for axis v, first-child-south
-- (d) or second-child-north (u). Otherwise walk up to the next ancestor.
local function resize(st, id, dir, delta)
	local path = find_path(st.tree, id)
	if not path or #path < 2 then return false end
	local axis = (dir == "l" or dir == "r") and "h" or "v"
	for i = #path - 1, 1, -1 do
		local p     = path[i]
		local child = path[i + 1]
		if p.axis == axis and p._box then
			local is_first  = (p.a == child)
			-- does this split own the edge being moved?
			local edge_here = (is_first and (dir == "r" or dir == "d"))
				or ((not is_first) and (dir == "l" or dir == "u"))
			if edge_here then
				local dim  = (axis == "h") and p._box.w or p._box.h
				local dr   = math.abs(delta) / math.max(dim, 1)
				-- grow (delta > 0): focused side gains; shrink: loses
				local sign = ((delta >= 0) == is_first) and 1 or -1
				p.ratio   = math.min(0.9, math.max(0.1, p.ratio + sign * dr))
				return true
			end
		end
		-- else: this split does not own the edge; try the ancestor above
	end
	return false
end

-- ---------------------------------------------------------------------------
-- tree surgery commands
-- ---------------------------------------------------------------------------

local function subtree_of(st, id)
	local path = find_path(st.tree, id)
	if not path then return nil end
	return (#path >= 2) and path[#path - 1] or st.tree
end

local function rotate(node, degrees)
	if not node or node.t ~= "split" or degrees == 0 then return end
	-- Direct counterpart of bspwm tree.c:rotate_tree_rec. Our "v" means
	-- top/bottom (TYPE_HORIZONTAL there); "h" is TYPE_VERTICAL there.
	if (degrees == 90 and node.axis == "v")
		or (degrees == 270 and node.axis == "h") or degrees == 180 then
		node.a, node.b = node.b, node.a
		node.ratio = 1 - node.ratio
	end
	if degrees ~= 180 then node.axis = (node.axis == "h") and "v" or "h" end
	rotate(node.a, degrees)
	rotate(node.b, degrees)
end

local function flip(node, axis)
	if not node or node.t ~= "split" then return end
	if node.axis == axis then node.a, node.b = node.b, node.a end
	flip(node.a, axis)
	flip(node.b, axis)
end

local function balance(node)
	if not node or node.t ~= "split" then return end
	local ca, cb = count_leaves(node.a), count_leaves(node.b)
	node.ratio = ca / (ca + cb)
	balance(node.a)
	balance(node.b)
end

local function equalize(node, r)
	if not node or node.t ~= "split" then return end
	node.ratio = r
	equalize(node.a, r)
	equalize(node.b, r)
end

-- focused window becomes a child of the root split (bspc node -n @/)
local function transplant(st, id)
	local removed = remove_leaf(st, id)
	if not removed then return false end
	local root = st.tree
	if not root then
		st.tree = removed
		return true
	end
	st.tree = { t = "split", axis = root.axis, ratio = 0.5, a = root, b = removed }
	return true
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
-- placement
-- ---------------------------------------------------------------------------

local function place(node, box, boxes)
	if not node then return end
	if node.t == "leaf" then
		boxes[node.id] = box
		node._box = box
		return
	end
	node._box = box
	local r = node.ratio
	if node.axis == "h" then
		local w1 = math.floor(box.w * r)
		place(node.a, { x = box.x, y = box.y, w = w1, h = box.h }, boxes)
		place(node.b, { x = box.x + w1, y = box.y, w = box.w - w1, h = box.h }, boxes)
	else
		local h1 = math.floor(box.h * r)
		place(node.a, { x = box.x, y = box.y, w = box.w, h = h1 }, boxes)
		place(node.b, { x = box.x, y = box.y + h1, w = box.w, h = box.h - h1 }, boxes)
	end
end

-- ---------------------------------------------------------------------------
-- state plumbing
-- ---------------------------------------------------------------------------

local function ws_of(ctx)
	for _, t in ipairs(ctx.targets) do
		local w = t.window
		if w and w.workspace and w.workspace.id then
			return w.workspace.id
		end
	end
	return nil
end

local function state_for(wsid)
	local st = S[wsid]
	if not st then
		st = { seq = 0, mode = "tiled", boxes = {}, highlighted = {} }
		S[wsid] = st
	end
	return st
end

local function apply_pend(anchor)
	if anchor and anchor.presel then
		local pre = anchor.presel
		anchor.presel = nil
		return pre
	end
	local pre = PEND
	PEND = nil
	return pre
end

local function clear_presels(node)
	if not node then return end
	node.presel = nil
	clear_presels(node.a)
	clear_presels(node.b)
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

local function clear_selections()
	if selection_focus or rehydrating or transferring then return end
	for _, st in pairs(S) do clear_selection(st) end
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
	local st = w and w.workspace and S[w.workspace.id]
	if st and st.mode == "monocle" then monocle.raise(w) end
	if selection_focus then return end
	-- Re-notification of the same keyboard-focused representative is not a
	-- new tree selection. An explicit click (FOCUS_REASON_CLICK = 5) is.
	if st and st.selected_focus_id == w.stable_id and reason ~= 5 then return end
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
	for _, st in pairs(S) do
		if st.highlighted[w.stable_id] or st.selected_focus_id == w.stable_id
			or st.insertion_window_id == w.stable_id then
			clear_selection(st)
		end
	end
end
on_event("window.close", window_leaves_selection)
-- A client can unmap/remap the same window object, retaining its old tags.
on_event("window.open", function(w) tag_window(w, false) end)
on_event("window.move_to_workspace", window_leaves_selection)
on_event("window.fullscreen", window_leaves_selection)
on_event("workspace.removed", function(ws)
	if ws then monocle.remove(ws) end
	local st = ws and S[ws.id]
	if st then clear_selection(st); S[ws.id] = nil end
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
	if not rehydrating or not config_seen then return end
	local windows, live, targets = hl.get_windows(), {}, {}
	for _, w in ipairs(windows) do
		if w.mapped and not w.floating and w.workspace then
			local id = w.workspace.id
			live[id], targets[id] = live[id] or {}, targets[id] or {}
			live[id][w.stable_id] = true
			targets[id][#targets[id] + 1] = { window = w }
		end
	end
	rehydrating, config_seen = false, false
	-- Remove old tags, then restore the saved selection with fresh userdata.
	for _, w in ipairs(windows) do tag_window(w, false) end
	local active = hl.get_active_window()
	for id, st in pairs(S) do
		st.highlighted = {}
		st.tree = prune_tree(st.tree, live[id] or {})
		if st.selected and (not find_path(st.tree, st.selected) or not active
			or active.stable_id ~= st.selected_focus_id
			or not find_path(st.selected, st.selected_focus_id)) then clear_selection(st) end
		if st.insertion_anchor and (not find_path(st.tree, st.insertion_anchor)
			or not (live[id] and live[id][st.insertion_window_id])) then
			st.insertion_anchor, st.insertion_window_id = nil, nil
		end
		highlight_selection(st, targets[id] or {})
	end
	local active_state = active and active.workspace and S[active.workspace.id]
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
			if t.window and t.window.mapped ~= false then
				table.insert(targets, t)
			end
		end

		local n = #targets
		if n == 0 then publish_feedback(); return end

		local wsid = ws_of(ctx)
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
		if rehydrating then
			-- newTarget() recalculates after EACH reattached window. Missing
			-- ctx targets are not closed windows: preserve all live saved leaves.
			for _, w in ipairs(hl.get_windows()) do
				if w.mapped and not w.floating and w.workspace and w.workspace.id == wsid then
					live[w.stable_id] = live[w.stable_id] or { window = w }
				end
			end
		end

		-- focused id
		local focused_id
		for _, t in ipairs(targets) do
			if t.window.active then focused_id = t.window.stable_id end
		end

		-- prune dead windows, including a selection whose node was collapsed
		st.tree = prune_tree(st.tree, live)
		if st.selected and (not find_path(st.tree, st.selected)
			or not live[st.selected_focus_id]
			or (not rehydrating and focused_id and focused_id ~= st.selected_focus_id and find_path(st.tree, focused_id))) then
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
				local anchor_node = anchor_path and anchor_path[#anchor_path] or any_leaf(st.tree)
				-- Snapshot the subtree BEFORE clearing its highlight/selection.
				clear_selection(st)
				st.seq = st.seq + 1
				local pre = apply_pend(anchor_node)
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
		local wsid   = ws_of(ctx)
		local st     = wsid and state_for(wsid) or nil
		local parts  = {}
		for tok in msg:gmatch("%S+") do table.insert(parts, tok) end
		local cmd    = parts[1] or ""

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
				PEND = nil
				return true
			end
			local pre = (node and node.presel) or (not node and PEND) or { dir = "r", ratio = 0.5 }
			if cmd == "pratio" then
				local r = tonumber(arg)
				if not r or r <= 0 or r >= 1 then return "pratio: expected 0.1..0.9" end
				pre.ratio = r
			else
				pre.dir = arg
			end
			if node then node.presel = pre else PEND = pre end
			return true
		end

		if not node then return true end -- empty workspace
		-- Do not select/rotate arbitrary tiles while keyboard focus is on a float.
		if (cmd == "focus" or cmd == "rotate") and not fw.active then return true end

		if cmd == "pointer_swap" then
			if rehydrating or transferring or st.mode ~= "tiled" then return true end
			local source, target = tonumber(parts[2]), tonumber(parts[3])
			if source ~= fid or not fw.active or source == target then return true end
			local pa, pb = find_path(st.tree, source), target and find_path(st.tree, target)
			if not pa or not pb then return true end
			-- Swap NODES, not just IDs: age and preselection belong to the
			-- window, just as in bspwm tree.c:swap_nodes(). No remove/reinsert.
			local a, b = pa[#pa], pb[#pb]
			local ap, bp = pa[#pa - 1], pb[#pb - 1]
			local a_first, b_first = ap.a == a, bp.a == b
			clear_selection(st)
			if a_first then ap.a = b else ap.b = b end
			if b_first then bp.a = a else bp.b = a end
			return true

		elseif cmd == "swap" then
			local nid = neighbor_id(st, fid, parts[2] or "r")
			if not nid then return true end -- nothing in that direction: ok
			local pa = find_path(st.tree, fid)
			local pb = find_path(st.tree, nid)
			if not pa or not pb then return true end
			local la, lb = pa[#pa], pb[#pb]
			la.id, lb.id = lb.id, la.id
			return true

		elseif cmd == "move" then
			local nid = neighbor_id(st, fid, parts[2] or "r")
			if not nid then return true end
			local pa  = find_path(st.tree, fid)
			local n   = pa and pa[#pa].n or 0
			remove_leaf(st, fid)
			insert_adjacent(st, fid, nid, (parts[2] == "l" or parts[2] == "u") and parts[2] or "r", nil)
			local path = find_path(st.tree, fid)
			if path then path[#path].n = n end
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
			return pull(st, node, fw, ctx.area)

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
			local tid = find_path(target, fid) and fid or first_leaf(target).id
			st.selected, st.selected_focus_id = target, tid
			if tid ~= fid and not focus_id(tid) then clear_selection(st) end
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
-- "automatic" means NO preselection, not newest; "last" is global focus history.
pull = function(st, node, focused, area)
	local candidates, windows = {}, {}
	for _, w in ipairs(hl.get_windows()) do
		local ws = w.workspace
		local state = ws and S[ws.id]
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
			local last = candidate.path[#candidate.path]
			if disjoint(last) then
				from = { st = candidate.st, node = last, window = candidate.window }
				break
			end
		end
	end
	if not from then return true end

	local moving = {}
	for _, child in ipairs(leaves(from.node)) do
		if not windows[child.id] then return true end -- stale/hidden/grouped subtree
		moving[#moving + 1] = windows[child.id]
	end
	local source_ws, dest_ws = from.window.workspace, to.window.workspace
	local cross_workspace = source_ws.id ~= dest_ws.id
	local contexts, failure = {}, nil
	if cross_workspace then
		transferring, transfer_contexts = true, contexts
		-- Workspace objects stringify to their ID in this API, but negative
		-- named/special IDs are parsed as relative selectors. Use their name.
		local selector = dest_ws.id > 0 and dest_ws.id or "name:" .. dest_ws.name
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

	if not failure then
		-- Commit only after native moves succeeded. Reuse the node so split
		-- ratios, ages and its own preselections travel with it.
		remove_leaf(from.st, from.node)
		local dest_area = contexts[dest_ws.id] and contexts[dest_ws.id].area or area
		place(to.st.tree, dest_area, {})
		local pre = to.node.presel
		to.node.presel = nil
		insert_adjacent(to.st, from.node, to.node, pre and pre.dir, pre and pre.ratio)
		for _, child in ipairs(leaves(from.node)) do to.st.seq = math.max(to.st.seq, child.n) end
	end
	clear_selection(from.st)
	clear_selection(to.st)
	-- Prune before replay/checkpointing: an empty source produces no native
	-- callback, and a partially failed move must not leave duplicate leaves.
	local live = {}
	for _, w in ipairs(hl.get_windows()) do
		if w.mapped and not w.floating and w.workspace and w.workspace.id == source_ws.id then live[w.stable_id] = true end
	end
	from.st.tree = prune_tree(from.st.tree, live)
	if not from.st.tree then from.st.boxes = {} end
	transfer_contexts = nil

	-- Replay the latest native snapshots now that ALL windows have moved.
	replay_transfer_contexts(contexts)
	transferring = false
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
	local function move_window(w, ws)
		if w.workspace and w.workspace.id == ws.id then return true end
		local selector = ws.id > 0 and ws.id or "name:" .. ws.name
		local result = hl.dispatch(hl.dsp.window.move({ window = w, workspace = selector, follow = false }))
		return not (result and result.ok == false) and w.workspace and w.workspace.id == ws.id
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
		S[cur.id], S[tgt.id] = tgt_state, cur_state
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
			if ids and w.mapped and not w.floating then ids[w.stable_id] = true end
		end
		for _, ws in ipairs({ cur, tgt }) do
			local st = S[ws.id]
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
-- it temporarily floats/removes the source and destroys its original slot.
function M.drag_valid(w)
	local ws = w and w.workspace
	local st = ws and S[ws.id]
	return ws ~= nil and st ~= nil and not rehydrating and not transferring and w.mapped and not w.floating
		and not w.hidden and w.visible ~= false and not w.group and (w.fullscreen or 0) == 0
		and ws.visible ~= false and (ws.tiled_layout == "lua:bspwm" or ws.tiled_layout == "lua:bspwm_b")
		and st.mode == "tiled" and find_path(st.tree, w.stable_id) ~= nil
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
	local from, to = S[source.id], state_for(dest.id)
	local path = find_path(from.tree, w.stable_id)
	local node = path[#path]
	local anchor = dest.last_window and dest.last_window.stable_id
	local contexts = {}
	local function move_to(ws)
		local selector = ws.id > 0 and ws.id or "name:" .. ws.name
		local result = hl.dispatch(hl.dsp.window.move({ window = w, workspace = selector, follow = false }))
		return not (result and result.ok == false) and w.workspace and w.workspace.id == ws.id
	end
	transferring, transfer_contexts = true, contexts
	local ok, moved = pcall(move_to, dest)
	local success = ok and moved
	if not success and w.workspace and w.workspace.id ~= source.id then pcall(move_to, source) end
	local replay_ok, replay_error = pcall(function()
		if success then
			remove_leaf(from, node)
			local anchor_path = anchor and find_path(to.tree, anchor)
			local anchor_node = anchor_path and anchor_path[#anchor_path] or any_leaf(to.tree)
			local context = contexts[dest.id]
			if context then place(to.tree, context.area, {}) end
			local pre = apply_pend(anchor_node)
			insert_adjacent(to, node, anchor_node, pre and pre.dir, pre and pre.ratio)
			to.seq = math.max(to.seq, node.n)
		end
		-- Reconcile even after a failed native move/rollback. Empty sources
		-- have no callback, so must be pruned explicitly before checkpointing.
		for _, ws in ipairs({ source, dest }) do
			local st, live = S[ws.id], {}
			for _, window in ipairs(ws:get_windows() or {}) do
				if window.mapped and not window.floating then live[window.stable_id] = true end
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
	local st = active and active.workspace and S[active.workspace.id]
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

-- true when the focused window has a tiled neighbour in direction `dir`
-- (l|r|u|d); lets callers pick a fallback without making the layout reject a
-- message (a rejected layout message is shown as an ERROR overlay).
function M.has_neighbor(dir)
	local w = hl.get_active_window()
	if not w or not w.workspace then return false end
	local st = S[w.workspace.id]
	if not st or st.mode == "monocle" then return false end
	return neighbor_id(st, w.stable_id, dir) ~= nil
end

return M
