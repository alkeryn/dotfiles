-- lua tests/bspwm_tree_test.lua -- pure tree/geometry contracts, no compositor.
local tree = require("lua/extensions/bspwm_tree")
local geometry = require("lua/extensions/bspwm_geometry")
local tests = {}

local function split(first, second, axis, ratio)
	return { t = "split", a = first, b = second, axis = axis or "h", ratio = ratio or 0.5 }
end

function tests.find_path_backtracks_and_accepts_internal_references()
	local a, b, c = tree.leaf(1), tree.leaf(2), tree.leaf(3)
	local branch = split(a, b)
	local root = split(branch, c)
	local path = assert(tree.find_path(root, 3))
	assert(#path == 2 and path[1] == root and path[2] == c)
	path = assert(tree.find_path(root, branch))
	assert(#path == 2 and path[2] == branch)
	local scratch = {}
	assert(tree.find_path(root, 99, scratch) == nil and #scratch == 0)
	assert(tree.first_leaf(root) == a and tree.last_leaf(root) == c)
	local leaves = tree.leaves(root)
	assert(#leaves == 3 and leaves[1] == a and leaves[2] == b and leaves[3] == c)
end

function tests.detach_subtree_preserves_identity_and_promotes_sibling()
	local a, b, c, d = tree.leaf(1), tree.leaf(2), tree.leaf(3), tree.leaf(4)
	local branch = split(a, b, "v", 0.3)
	branch.presel = { dir = "u", ratio = 0.7 }
	local root = split(split(branch, c), d)
	local state = { tree = root }
	assert(tree.detach(state, branch) == branch)
	assert(state.tree == root and root.a == c and root.b == d)
	assert(branch.a == a and branch.b == b and branch.ratio == 0.3 and branch.presel.dir == "u")
	assert(tree.detach(state, 99) == nil and state.tree == root)
	assert(tree.detach(state, root) == root and state.tree == nil)
end

function tests.prune_promotes_survivors_without_rebuilding_metadata()
	local a, b, c = tree.leaf(1), tree.leaf(2), tree.leaf(3)
	local branch = split(a, b, "v", 0.3)
	local root = split(branch, c)
	local pruned, alive = tree.prune(root, { [1] = true, [2] = true })
	assert(alive and pruned == branch and pruned.ratio == 0.3)
	pruned, alive = tree.prune(pruned, { [2] = true })
	assert(alive and pruned == b)
	pruned, alive = tree.prune(pruned, {})
	assert(pruned == nil and alive == false)
end

function tests.insert_uses_first_child_ratio_and_preserves_incoming_subtree()
	local anchor = tree.leaf(1)
	local incoming = split(tree.leaf(2), tree.leaf(3), "v", 0.7)
	local state = { tree = anchor }
	tree.insert_adjacent(state, incoming, anchor, "r", 0.3)
	assert(state.tree.a == anchor and state.tree.b == incoming and state.tree.ratio == 0.3)
	assert(incoming.ratio == 0.7)
	local boxes = {}
	tree.place(state.tree, { x = -20, y = 10, w = 101, h = 99 }, boxes)
	assert(boxes[1].w == 30 and incoming._box.w == 71 and boxes[2].h == 69 and boxes[3].h == 30)
end

function tests.swaps_reject_overlaps_and_capture_sibling_slots()
	local a, b, c = tree.leaf(1), tree.leaf(2), tree.leaf(3)
	local branch = split(a, b)
	local root = split(branch, c)
	local state = { tree = root }
	assert(not tree.swap_nodes(state, root, a))
	assert(not tree.swap_nodes(state, a, a))
	assert(not tree.swap_nodes(state, a, 99))
	assert(tree.swap_nodes(state, a, b) and branch.a == b and branch.b == a)
	assert(tree.swap_nodes(state, branch, c) and root.a == c and root.b == branch)
end

function tests.balance_and_equalize_leave_identity_and_presels_intact()
	local a, b, c = tree.leaf(1), tree.leaf(2), tree.leaf(3)
	local branch = split(a, b, "v", 0.2)
	local root = split(branch, c, "h", 0.8)
	local presel = { dir = "l", ratio = 0.4 }
	branch.presel = presel
	tree.balance(root)
	assert(root.ratio == 2 / 3 and branch.ratio == 0.5)
	tree.equalize(root, 0.3)
	assert(root.ratio == 0.3 and branch.ratio == 0.3)
	assert(root.a == branch and branch.a == a and branch.presel == presel)
	tree.clear_presels(root)
	assert(branch.presel == nil)
end

function tests.flip_swaps_children_without_complementing_ratios()
	local a, b = tree.leaf(1), tree.leaf(2)
	local root = split(a, b, "h", 0.3)
	tree.flip(root, "v")
	assert(root.a == a and root.b == b and root.ratio == 0.3)
	tree.flip(root, "h")
	assert(root.a == b and root.b == a and root.ratio == 0.3)
end

function tests.transplant_preserves_leaf_and_original_root_axis()
	local a, b, c = tree.leaf(1), tree.leaf(2), tree.leaf(3)
	local root = split(split(a, b), c, "v", 0.3)
	local state = { tree = root }
	a.n, a.presel = 5, { dir = "r", ratio = 0.4 }
	assert(tree.transplant(state, 1))
	assert(state.tree.a == root and state.tree.b == a and state.tree.axis == "v")
	assert(state.tree.ratio == 0.5 and root.a == b and a.n == 5 and a.presel.dir == "r")
	assert(not tree.transplant(state, 99))
	state.tree = a
	assert(tree.transplant(state, 1) and state.tree == a)
end

function tests.split_rounding_and_monitor_fallback_are_shared()
	local box = { x = -10, y = 20, w = 101, h = 99 }
	local first, second = geometry.split_box(box, "h", 0.5)
	assert(first.w == 50 and second.w == 51 and second.x == 40)
	first, second = geometry.split_box(box, "v", 0.5)
	assert(first.h == 49 and second.h == 50 and second.y == 69)
	assert(geometry.monitor_box(nil, box) == box)
	assert(geometry.monitor_box({ width = 100 }, box) == box)
	local monitor = geometry.monitor_box({
		width = 1920, height = 1080, scale = 1.5, transform = 1, position = { x = -720, y = 5 },
	})
	assert(monitor.x == -720 and monitor.y == 5 and monitor.w == 720 and monitor.h == 1280)
end

local names = {}
for name in pairs(tests) do names[#names + 1] = name end
table.sort(names)
for _, name in ipairs(names) do
	tests[name]()
	print("PASS " .. name)
end
print(string.format("%d/%d tests passed", #names, #names))
