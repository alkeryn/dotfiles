-- Binary-tree operations, independent of the compositor and session state.
-- Nodes retain their identity and metadata through insertion, removal and swaps.
local geometry = require("lua/extensions/bspwm_geometry")
local M = {}

function M.leaf(id)
	return { t = "leaf", id = id, n = 0 }
end

local function axis_for(direction)
	if direction == "u" or direction == "d" or direction == "up" or direction == "down"
		or direction == "north" or direction == "south" then
		return "v"
	end
	return "h" -- l, r, west, east, nil
end

local function new_is_first(direction)
	return direction == "l" or direction == "west"
		or direction == "u" or direction == "up" or direction == "north"
end

-- A target is either a stable window ID or an internal node reference.
function M.find_path(node, target, path)
	if not node then return nil end
	path = path or {}
	table.insert(path, node)
	if node == target or (node.t == "leaf" and node.id == target) then return path end
	if node.t == "split" then
		local found = M.find_path(node.a, target, path) or M.find_path(node.b, target, path)
		if found then return found end
	end
	table.remove(path)
	return nil
end

function M.collect_ids(node, ids)
	if not node then return end
	if node.t == "leaf" then
		ids[node.id] = true
	else
		M.collect_ids(node.a, ids)
		M.collect_ids(node.b, ids)
	end
end

function M.leaves(node, result)
	result = result or {}
	if not node then return result end
	if node.t == "leaf" then
		table.insert(result, node)
	else
		M.leaves(node.a, result)
		M.leaves(node.b, result)
	end
	return result
end

function M.first_leaf(node)
	while node and node.t == "split" do node = node.a end
	return node
end

function M.last_leaf(node)
	local leaves = M.leaves(node)
	return leaves[#leaves]
end

-- Remove dead leaves and promote siblings. Returns (new subtree, alive?).
function M.prune(node, live)
	if not node then return nil, false end
	if node.t == "leaf" then
		if live[node.id] then return node, true end
		return nil, false
	end
	local first, first_alive = M.prune(node.a, live)
	local second, second_alive = M.prune(node.b, live)
	if first_alive and second_alive then
		node.a, node.b = first, second
		return node, true
	end
	if first_alive then return first, true end
	if second_alive then return second, true end
	return nil, false
end

-- bspwm keeps floating clients in the tree. Vacancy affects geometry, never
-- topology: a split is vacant only when BOTH children are vacant. The tiled
-- set is separate from the set of mapped windows used by prune(). Omit it to
-- recompute internal flags after structural operations, retaining leaf flags.
function M.update_vacancy(node, tiled)
	if not node then return true end
	if node.t == "leaf" then
		if tiled then node.vacant = not tiled[node.id] end
	else
		local first = M.update_vacancy(node.a, tiled)
		local second = M.update_vacancy(node.b, tiled)
		node.vacant = first and second
	end
	-- tree.c:set_vacant_local cancels preselections on vacant nodes.
	if node.vacant then node.presel = nil end
	return node.vacant or false
end

function M.walk_splits(node, callback)
	if not node or node.t ~= "split" then return end
	callback(node)
	M.walk_splits(node.a, callback)
	M.walk_splits(node.b, callback)
end

-- Insert a window ID or intact subtree beside an anchor. Automatic callers
-- must refresh boxes first: bspwm splits the longest side, new child second.
function M.insert_adjacent(state, incoming, anchor_id, direction, ratio)
	local new_node = type(incoming) == "table" and incoming or M.leaf(incoming)
	local path = M.find_path(state.tree, anchor_id)
	if not path then
		-- The anchor vanished: attach beside the last leaf, or become root.
		local other = M.last_leaf(state.tree)
		if not other then
			state.tree = new_node
			return
		end
		path = M.find_path(state.tree, other.id)
	end

	local anchor = path[#path]
	if not direction then
		local box = anchor._box
		direction = (box and box.w > box.h) and "r" or "d"
	end
	local split = { t = "split", axis = axis_for(direction), ratio = ratio or 0.5 }
	-- Ratio is ALWAYS the first child's share, even for east/south insertion.
	if new_is_first(direction) then
		split.a, split.b = new_node, anchor
	else
		split.a, split.b = anchor, new_node
	end
	if #path == 1 then
		state.tree = split
	else
		local parent = path[#path - 1]
		if parent.a == anchor then parent.a = split else parent.b = split end
	end
end

-- Detach a leaf OR subtree, promoting its sibling without rebuilding either.
function M.detach(state, target)
	local path = M.find_path(state.tree, target)
	if not path then return nil end
	local node = path[#path]
	if #path == 1 then
		state.tree = nil
		return node
	end
	local parent = path[#path - 1]
	local sibling = parent.a == node and parent.b or parent.a
	if #path == 2 then
		state.tree = sibling
	else
		local grandparent = path[#path - 2]
		if grandparent.a == parent then grandparent.a = sibling else grandparent.b = sibling end
	end
	return node
end

-- Exchange disjoint nodes in-place (bspwm tree.c:swap_nodes). Capture both
-- parent slots before writing, since the nodes may be siblings.
function M.swap_nodes(state, source, target)
	local source_path = M.find_path(state.tree, source)
	local target_path = M.find_path(state.tree, target)
	if not source_path or not target_path then return false end
	local first, second = source_path[#source_path], target_path[#target_path]
	if M.find_path(first, second) or M.find_path(second, first) then return false end
	local first_parent, second_parent = source_path[#source_path - 1], target_path[#target_path - 1]
	if not first_parent or not second_parent then return false end
	local first_slot, second_slot = first_parent.a == first, second_parent.a == second
	if first_slot then first_parent.a = second else first_parent.b = second end
	if second_slot then second_parent.a = first else second_parent.b = first end
	return true
end

-- Find the split OWNING an edge: first-child east/south or second-child
-- west/north. Skip invisible (vacant) splits and ancestors on the wrong side.
function M.resize_fence(state, target, direction)
	local path = M.find_path(state.tree, target)
	if not path or #path < 2 then return nil end
	local axis = (direction == "l" or direction == "r") and "h" or "v"
	for i = #path - 1, 1, -1 do
		local parent, child = path[i], path[i + 1]
		if parent.axis == axis and parent._box and not parent.a.vacant and not parent.b.vacant then
			local is_first = parent.a == child
			local owns_edge = (is_first and (direction == "r" or direction == "d"))
				or (not is_first and (direction == "l" or direction == "u"))
			if owns_edge then return parent end
		end
	end
	return nil
end

function M.resize(state, target, direction, delta)
	local fence = M.resize_fence(state, target, direction)
	if not fence then return false end
	local dimension = fence.axis == "h" and fence._box.w or fence._box.h
	local sign = (direction == "r" or direction == "d") and 1 or -1
	fence.ratio = math.min(0.9, math.max(0.1, fence.ratio + sign * delta / math.max(dimension, 1)))
	return true
end

function M.parent_or_root(state, target)
	local path = M.find_path(state.tree, target)
	if not path then return nil end
	return #path >= 2 and path[#path - 1] or state.tree
end

function M.rotate(node, degrees)
	if not node or node.t ~= "split" or degrees == 0 then return end
	-- bspwm tree.c:rotate_tree_rec: our "v" is its TYPE_HORIZONTAL;
	-- our "h" is its TYPE_VERTICAL.
	if (degrees == 90 and node.axis == "v")
		or (degrees == 270 and node.axis == "h") or degrees == 180 then
		node.a, node.b = node.b, node.a
		node.ratio = 1 - node.ratio
	end
	if degrees ~= 180 then node.axis = node.axis == "h" and "v" or "h" end
	M.rotate(node.a, degrees)
	M.rotate(node.b, degrees)
end

function M.flip(node, axis)
	if not node or node.t ~= "split" then return end
	if node.axis == axis then node.a, node.b = node.b, node.a end
	M.flip(node.a, axis)
	M.flip(node.b, axis)
end

function M.balance(node)
	if not node or node.vacant then return 0 end
	if node.t == "leaf" then return 1 end
	local first_count, second_count = M.balance(node.a), M.balance(node.b)
	if first_count > 0 and second_count > 0 then
		node.ratio = first_count / (first_count + second_count)
	end
	return first_count + second_count
end

function M.equalize(node, ratio)
	if not node or node.vacant or node.t ~= "split" then return end
	node.ratio = ratio
	M.equalize(node.a, ratio)
	M.equalize(node.b, ratio)
end

-- Make the focused window a child of the root split (bspc node -n @/).
function M.transplant(state, target)
	local removed = M.detach(state, target)
	if not removed then return false end
	local root = state.tree
	if not root then
		state.tree = removed
		return true
	end
	state.tree = { t = "split", axis = root.axis, ratio = 0.5, a = root, b = removed }
	return true
end

local function place(node, box, boxes)
	if not node then return end
	node._box = box
	if node.t == "leaf" then
		if not node.vacant then boxes[node.id] = box end
		return
	end
	-- tree.c:apply_layout gives both children the parent's rectangle when
	-- either is vacant. Keep the dormant split's axis and ratio untouched.
	local first, second = box, box
	if not node.a.vacant and not node.b.vacant then
		first, second = geometry.split_box(box, node.axis, node.ratio)
	end
	place(node.a, first, boxes)
	place(node.b, second, boxes)
end

function M.place(node, box, boxes)
	M.update_vacancy(node)
	place(node, box, boxes)
end

function M.clear_presels(node)
	if not node then return end
	node.presel = nil
	M.clear_presels(node.a)
	M.clear_presels(node.b)
end

return M
