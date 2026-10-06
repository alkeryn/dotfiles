# Directional swaps of selected subtrees

`Super+Shift+h/j/k/l` swaps the current `Super+b` selection with a neighbouring
window on the same desktop. Without a subtree selection, it swaps the focused
leaf as before. The existing monitor-edge fallback still sends the whole
selected node to the neighbouring monitor's active desktop.

Reference: `~/tmp/bspwm/src/tree.c`, `find_nearest_neighbor` and `swap_nodes`:

- Search from the selected node's full tiled rectangle, not the keyboard-focus
  representative's rectangle. Exclude all descendants of that node.
- Among directional leaves with an overlapping perpendicular range, prefer the
  closest boundary, breaking ties by recent focus history. Unranked ties use
  deterministic tree order. Hidden/unmapped/floating windows are not candidates.
- Exchange node references at their parents, including when they are siblings.
  Do not exchange window IDs or remove/reinsert individual leaves. Both nodes
  keep their own orientation, split ratios, insertion ages and preselections.
- Keep focus on the original representative and leave the moved subtree
  selected, so further swaps, rotates, closes and desktop sends act on it.
- `has_neighbor` uses the same selection-aware search as `swap`. Selecting the
  whole root has no local neighbour; an internal child cannot swallow the
  monitor fallback. Direct swaps with no target are no-ops.

Pointer swaps share the same tree-swap primitive, but still swap only the two
pointed-at leaves and clear the keyboard selection. Monocle and floating focus
do not cause a directional layout swap of unrelated tiles.

Regression tests:

```sh
lua tests/bspwm_selection_test.lua
lua tests/bspwm_pull_test.lua
lua -e 'package.loaded["lua/vars"] = { FLOAT_STEP=20, terminal="alacritty", GAPS=4, GAPS_OUT=8 }' tests/bspwm_state_test.lua
```

Also run with `luajit`. Coverage includes all four actual bindings, sibling and
non-sibling swaps, repeated inverse swaps, boundary/history targeting, intact
selection/metadata, monitor fallback, pointer swaps, and checkpoint reloads.
The fixtures mock Hyprland; live desktop testing is still needed.
