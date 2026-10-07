-- Pure return-slot geometry and invalidation; no compositor/session state.
local tree = require("lua/extensions/bspwm_tree")
local slots = require("lua/extensions/bspwm_workspace_slots")
local tests = {}
local function split(a, b, axis, ratio)
	return { t = "split", a = a, b = b, axis = axis or "h", ratio = ratio or 0.5 }
end

function tests.all_sides_restore_nested_subtree_sibling_and_exact_ratio()
	for _, axis in ipairs({ "h", "v" }) do
		for _, first in ipairs({ false, true }) do
			local node = tree.leaf(1)
			local sibling = split(tree.leaf(2), tree.leaf(3), "v", 0.7)
			local parent = split(first and node or sibling, first and sibling or node, axis, 0.3)
			local st = { tree = split(tree.leaf(4), parent) }
			local slot = assert(slots.capture(st, node))
			assert(tree.detach(st, node) == node and st.tree.b == sibling)
			-- Return positions are structural, not cached monitor rectangles.
			tree.place(st.tree, { x = -300, y = 10, w = 901, h = 503 }, {})
			assert(slots.restore(st, node, slot))
			local restored = st.tree.b
			assert(restored.axis == axis and restored.ratio == 0.3)
			assert(restored.a == parent.a and restored.b == parent.b)
		end
	end
end

function tests.root_slot_requires_an_empty_destination()
	local node = split(tree.leaf(1), tree.leaf(2))
	local st = { tree = node }
	local slot = assert(slots.capture(st, node))
	tree.detach(st, node)
	st.tree = tree.leaf(3)
	assert(not slots.restore(st, node, slot) and st.tree.id == 3)
	st.tree = nil
	assert(slots.restore(st, node, slot) and st.tree == node)
	assert(not slots.capture(st, tree.leaf(9)))
	assert(not slots.restore(st, node, nil))
end

function tests.changed_layout_never_mutates_on_restore_attempt()
	for _, change in ipairs({ "ratio", "axis", "order", "id", "vacancy", "closed", "inserted" }) do
		local a, b, c = tree.leaf(1), tree.leaf(2), tree.leaf(3)
		local st = { tree = split(a, split(b, c)) }
		local slot = slots.capture(st, a)
		tree.detach(st, a)
		if change == "ratio" then st.tree.ratio = 0.6
		elseif change == "axis" then st.tree.axis = "v"
		elseif change == "order" then st.tree.a, st.tree.b = c, b
		elseif change == "id" then b.id = 4
		elseif change == "vacancy" then b.vacant = true
		elseif change == "closed" then tree.detach(st, b)
		else tree.insert_adjacent(st, 4, b, "r") end
		local root = st.tree
		assert(not slots.restore(st, a, slot), change)
		assert(st.tree == root and not tree.find_path(st.tree, a))
	end
end

function tests.preselection_metadata_and_display_boxes_are_not_topology()
	local a, b = tree.leaf(1), tree.leaf(2)
	local st = { tree = split(a, b) }
	local slot = slots.capture(st, a)
	tree.detach(st, a)
	b.presel, b._box, st.mode = { dir = "u", ratio = 0.7 }, { w = 300, h = 900 }, "monocle"
	-- The caller chooses whether to honor explicit insertion intent first.
	assert(slots.restore(st, a, slot) and b.presel.ratio == 0.7)
end

local names = {}
for name in pairs(tests) do names[#names + 1] = name end
table.sort(names)
for _, name in ipairs(names) do tests[name](); print("PASS " .. name) end
print(string.format("%d/%d tests passed", #names, #names))
