-- Transient return positions for explicit desktop sends. Store only plain data:
-- no old tree/window handles, duplicate leaves or dormant layout placeholders.
local tree = require("lua/extensions/bspwm_tree")
local M = {}

-- Geometry/selection/focus changes are harmless; topology, split ratios and
-- floating vacancies must still match. Omission models detach's sibling promotion.
local function shape(node, omitted)
	if not node or node == omitted then return "" end
	if node.t == "leaf" then return "L" .. node.id .. (node.vacant and "f" or "t") end
	local first, second = shape(node.a, omitted), shape(node.b, omitted)
	if first == "" then return second end
	if second == "" then return first end
	return "(" .. node.axis .. string.format("%.17g", node.ratio) .. ":" .. first .. "," .. second .. ")"
end

function M.capture(state, node)
	local path = tree.find_path(state.tree, node)
	if not path then return nil end
	local slot = { remainder = shape(state.tree, node) }
	local parent = path[#path - 1]
	if parent then
		local first = parent.a == node
		local sibling = first and parent.b or parent.a
		slot.sibling_id = tree.first_leaf(sibling).id
		slot.depth = #path - 1
		slot.direction = parent.axis == "h" and (first and "l" or "r") or (first and "u" or "d")
		slot.ratio = parent.ratio
	end
	return slot
end

function M.restore(state, node, slot)
	if not slot or shape(state.tree) ~= slot.remainder then return false end
	if not slot.sibling_id then
		if state.tree then return false end
		state.tree = node
	else
		local path = tree.find_path(state.tree, slot.sibling_id)
		local sibling = path and path[slot.depth]
		if not sibling then return false end
		tree.insert_adjacent(state, node, sibling, slot.direction, slot.ratio)
	end
	return true
end

return M
