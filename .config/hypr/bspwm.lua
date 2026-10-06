-- bspwm.lua -- bspwm-style binary-tree layout for Hyprland (v0.56.2+)
-- ============================================================================
-- Register with:  require("bspwm")          -- from hyprland.lua (same dir)
-- Select with:    general.layout = "lua:bspwm"   (or workspace_rule layout=)
--
-- Implements a real per-workspace binary tree like bspwm:
--   * automatic insertion: split the focused window's longest side (ratio 0.5)
--   * preselection: direction (-p), ratio (-o), click-through feedback rectangle
--   * subtree rotate (-R 90/270), flip (-F h/v), balance (-B), equalize (-E)
--   * transplant (-n @/), pull last leaf (super+y emulation)
--   * directional swap / move / grow / shrink between leaves
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
--   grow <l|r|u|d> <px>     shrink <l|r|u|d> <px>
--   rotate <90|270>         flip <h|v>
--   balance                 equalize
--   transplant              pull
--   mode                    monocle                 tiled
--   focus <parent|brother|first|second>
-- ============================================================================

local S    = {}   -- per-workspace tree, geometry, preselection and selected node
local PEND = nil  -- pending preselect for a not-yet-identifiable (empty) ws
local selection_focus = false -- guard our own representative-window focus events
local selection_tag = "bspwm_selected"
local feedback_sink

local function publish_feedback()
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

-- insert new_id as sibling of anchor_id (window id OR subtree), on side `dir`.
-- Without preselection, match bspwm's default longest_side / second_child.
-- Automatic callers must refresh the tree's boxes before inserting.
local function insert_adjacent(st, new_id, anchor_id, dir, ratio)
	local r    = ratio or 0.5
	local new  = leaf(new_id)
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

-- super+y: if focused is newest, move it next to the last manual window;
-- otherwise pull the newest other leaf next to focused.
local function pull(st, focused_id)
	local all = leaves(st.tree)
	local newest, oldest, newest_other, oldest_other
	for _, l in ipairs(all) do
		if not newest or l.n > newest.n then newest = l end
		if not oldest or l.n < oldest.n then oldest = l end
		if l.id ~= focused_id then
			if not newest_other or l.n > newest_other.n then newest_other = l end
			if not oldest_other or l.n < oldest_other.n then oldest_other = l end
		end
	end
	if not newest_other then return false end
	if newest.id == focused_id then
		-- focused is automatic: send it next to the last manual window
		remove_leaf(st, focused_id)
		insert_adjacent(st, focused_id, oldest_other.id, "r", nil)
	else
		local n = newest_other.n
		remove_leaf(st, newest_other.id)
		insert_adjacent(st, newest_other.id, focused_id, "r", nil)
		-- preserve insertion age
		local path = find_path(st.tree, newest_other.id)
		if path then path[#path].n = n end
	end
	return true
end

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
	if selection_focus then return end
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

hl.on("window.active", function(w, reason)
	if selection_focus then return end
	local st = w and w.workspace and S[w.workspace.id]
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
hl.on("workspace.active", clear_selections)
hl.on("workspace.special_active", clear_selections)
hl.on("monitor.focused", clear_selections)

local function window_leaves_selection(w)
	if not w then return end
	for _, st in pairs(S) do
		if st.highlighted[w.stable_id] or st.selected_focus_id == w.stable_id
			or st.insertion_window_id == w.stable_id then
			clear_selection(st)
		end
	end
end
hl.on("window.close", window_leaves_selection)
-- A client can unmap/remap the same window object, retaining its old tags.
hl.on("window.open", function(w) tag_window(w, false) end)
hl.on("window.move_to_workspace", window_leaves_selection)
hl.on("window.fullscreen", window_leaves_selection)
hl.on("workspace.removed", function(ws)
	local st = ws and S[ws.id]
	if st then clear_selection(st); S[ws.id] = nil end
end)
hl.on("config.reloaded", function()
	clear_selections()
	-- Tags survive a Lua-state reload; the old selected-node references do not.
	for _, w in ipairs(hl.get_windows()) do tag_window(w, false) end
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
		local st = state_for(wsid)
		local area = { x = ctx.area.x, y = ctx.area.y, w = ctx.area.w, h = ctx.area.h }

		-- live table: stable_id -> target
		local live = {}
		for _, t in ipairs(targets) do
			live[t.window.stable_id] = t
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
			or (focused_id and focused_id ~= st.selected_focus_id and find_path(st.tree, focused_id))) then
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
			for _, t in ipairs(targets) do
				t:place(area)
				st.boxes[t.window.stable_id] = area
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

		if cmd == "swap" then
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
			pull(st, fid)
			return true

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
-- module API (require("bspwm"))
-- ---------------------------------------------------------------------------

local M = {}

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
