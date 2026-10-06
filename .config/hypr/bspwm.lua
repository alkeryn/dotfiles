-- bspwm.lua -- bspwm-style binary-tree layout for Hyprland (v0.56.2+)
-- ============================================================================
-- Register with:  require("bspwm")          -- from hyprland.lua (same dir)
-- Select with:    general.layout = "lua:bspwm"   (or workspace_rule layout=)
--
-- Implements a real per-workspace binary tree like bspwm:
--   * automatic insertion as sibling of the focused window (split_ratio)
--   * preselection: direction (-p) and ratio (-o), consumed on next insert
--   * subtree rotate (-R 90/270), flip (-F h/v), balance (-B), equalize (-E)
--   * transplant (-n @/), pull last leaf (super+y emulation)
--   * directional swap / move / grow / shrink between leaves
--   * node focus: parent / brother / first / second
--   * monocle mode (stack, focused on top)
--
-- NOT implemented (see discussion):
--   * preselection feedback rectangle (needs a C++ plugin to draw)
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

local S    = {}   -- state per workspace id: {tree, boxes, seq, mode, pend}
local PEND = nil  -- pending preselect for a not-yet-identifiable (empty) ws

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

local function find_path(node, id, path)
	if not node then return nil end
	path = path or {}
	table.insert(path, node)
	if node.t == "leaf" then
		if node.id == id then return path end
	else
		local p = find_path(node.a, id, path)
		if p then return p end
		table.remove(path) -- undo failed a-branch, try b
		table.insert(path, node)
		p = find_path(node.b, id, path)
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

-- insert new_id as sibling of anchor_id, on side `dir`, with split ratio
local function insert_adjacent(st, new_id, anchor_id, dir, ratio)
	local ax   = axis_for(dir)
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
	local split  = { t = "split", axis = ax, ratio = r }
	-- ratio = fraction of the FIRST child. bspwm semantics: -o X gives the
	-- preselected side fraction X.
	if new_is_first(dir) then
		split.a, split.b = new, anchor
	else
		split.a, split.b = anchor, new
		if ratio then r = 1 - r; split.ratio = r end
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

-- grow/shrink the focused leaf's edge by px.
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

local function rotate(node, mode)
	if not node or node.t ~= "split" then return end
	node.axis = (node.axis == "h") and "v" or "h"
	if mode == 90 then node.a, node.b = node.b, node.a end
	rotate(node.a, mode)
	rotate(node.b, mode)
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
	local path = find_path(st.tree, id)
	if not path or #path < 2 then return nil end
	local parent = path[#path - 1]
	local target
	if which == "brother" or which == "parent" then
		target = (parent.a == path[#path]) and parent.b or parent.a
	elseif which == "first" then
		target = parent.a
	elseif which == "second" then
		target = parent.b
	end
	if not target then return nil end
	local l = first_leaf(target)
	return l and l.id or nil
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
		st = { seq = 0, mode = "tiled", pend = nil, boxes = {} }
		S[wsid] = st
	end
	return st
end

local function apply_pend(st)
	local pre = st.pend or PEND
	if pre == PEND and pre then PEND = nil end
	st.pend = nil
	return pre
end

-- ---------------------------------------------------------------------------
-- the layout
-- ---------------------------------------------------------------------------

hl.layout.register("bspwm", {

	recalculate = function(ctx)
		local targets = {}
		for _, t in ipairs(ctx.targets) do
			if t.window and t.window.mapped ~= false then
				table.insert(targets, t)
			end
		end

		local n = #targets
		if n == 0 then return end

		local wsid = ws_of(ctx)
		if not wsid then return end
		local st = state_for(wsid)

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

		-- prune dead windows
		st.tree = prune_tree(st.tree, live)

		-- insert new windows
		local present = {}
		collect_ids(st.tree, present)
		local anchor = focused_id
		for _, t in ipairs(targets) do
			local id = t.window.stable_id
			if not present[id] then
				st.seq = st.seq + 1
				local pre = apply_pend(st)
				if not st.tree then
					st.tree = leaf(id)
					st.tree.n = st.seq
				else
					local ok = anchor and find_path(st.tree, anchor)
					insert_adjacent(st, id, ok and anchor or (any_leaf(st.tree).id),
						pre and pre.dir or nil, pre and pre.ratio or nil)
					local path = find_path(st.tree, id)
					if path then path[#path].n = st.seq end
					anchor = id -- multiple new windows chain off each other
				end
			end
		end

		-- place
		st.boxes = {}
		local area = { x = ctx.area.x, y = ctx.area.y, w = ctx.area.w, h = ctx.area.h }
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
					hl.dsp.focus({ window = "address:" .. t.window.address })()
					return true
				end
			end
			return false
		end

		-- preselection (works even on an empty workspace)
		if cmd == "preselect" then
			local arg = parts[2] or ""
			if arg == "cancel" or arg == "clear" then
				if st then st.pend = nil end
				PEND = nil
			else
				local p = { dir = arg, ratio = nil }
				if st and (st.tree or #ctx.targets > 0) then st.pend = p else PEND = p end
			end
			return true
		elseif cmd == "pratio" then
			local r = tonumber(parts[2])
			if not r or r <= 0 or r >= 1 then
				return "pratio: expected 0.1..0.9"
			end
			local p = (st and (st.tree or #ctx.targets > 0)) and (st.pend or { dir = nil }) or (PEND or { dir = nil })
			p.ratio = r
			if st and (st.tree or #ctx.targets > 0) then st.pend = p else PEND = p end
			return true

		elseif not st or not st.tree then
			return "bspwm layout: no windows on this workspace"
		end

		local fw = focused()
		local fid = fw and fw.stable_id or nil
		if not fid then return "bspwm layout: no focused window" end

		if cmd == "swap" then
			local nid = neighbor_id(st, fid, parts[2] or "r")
			if not nid then return true end -- nothing in that direction: ok
			local pa = find_path(st.tree, fid)
			local pb = find_path(st.tree, nid)
			if not pa or not pb then return false end
			local la, lb = pa[#pa], pb[#pb]
			la.id, lb.id = lb.id, la.id
			return true

		elseif cmd == "move" then
			local nid = neighbor_id(st, fid, parts[2] or "r")
			if not nid then return false end
			local pa  = find_path(st.tree, fid)
			local n   = pa and pa[#pa].n or 0
			remove_leaf(st, fid)
			insert_adjacent(st, fid, nid, (parts[2] == "l" or parts[2] == "u") and parts[2] or "r", nil)
			local path = find_path(st.tree, fid)
			if path then path[#path].n = n end
			return true

		elseif cmd == "grow" or cmd == "shrink" then
			local px = tonumber(parts[3]) or 20
			return resize(st, fid, parts[2] or "r", cmd == "grow" and px or -px)

		elseif cmd == "rotate" then
			local sub = subtree_of(st, fid)
			rotate(sub, tonumber(parts[2]) or 90)
			return true

		elseif cmd == "flip" then
			local sub = subtree_of(st, fid)
			flip(sub, parts[2] == "v" and "v" or "h")
			return true

		elseif cmd == "balance" then
			balance(st.tree)
			return true

		elseif cmd == "equalize" then
			equalize(st.tree, 0.5)
			return true

		elseif cmd == "transplant" then
			return transplant(st, fid)

		elseif cmd == "pull" then
			return pull(st, fid)

		elseif cmd == "mode" then
			st.mode = (st.mode == "monocle") and "tiled" or "monocle"
			return true

		elseif cmd == "monocle" or cmd == "tiled" then
			st.mode = cmd
			return true

		elseif cmd == "focus" then
			local which = parts[2] or "brother"
			local tid   = focus_subtree_node(st, fid, which)
			if not tid then return false end
			return focus_id(tid)

		end

		return "bspwm layout: unknown command '" .. cmd .. "'"
	end,
})
