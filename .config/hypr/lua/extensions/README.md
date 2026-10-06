# Lua extensions

## Module boundaries

- `bspwm.lua`: per-workspace state, layout commands, focus/selection events,
  guarded workspace transfers, checkpoint and feedback coordination.
- `bspwm_tree.lua`: compositor-independent tree traversal, insertion/removal,
  swaps, resizing, transforms and placement. Operations preserve node identity
  and metadata rather than rebuilding subtrees.
- `bspwm_geometry.lua`: shared logical monitor bounds and split rounding for
  tree placement, monocle and preselection previews.
- `bspwm_state.lua`: bounded data-only checkpoint codec and atomic session
  storage. V1 checkpoints remain readable; writes retain the V2 format.
- `bspwm_monocle.lua`: reversible workspace/window rules and guarded raising.
- `bspwm_drag.lua`: held-button pointer sampling and native floating fallback.
- `presel_feedback.lua`: preview geometry and atomic V3 JSON publication to the
  existing renderer, including retirement of legacy protocol files.
- `close_refocus.lua`: empty-workspace focus correction and bounded rechecks.

`../helpers.lua` provides the public window/focus/workspace/gap/monitor helpers
used by bindings and rules. All `require` paths are relative to the main config
root, not this directory.

## Behavior-sensitive details

- A split ratio is always the **first** child's share. Only that share is
  rounded down; the second child gets the remainder.
- A selected node can be an entire subtree. Detaching, swapping and transferring
  it must retain its identity, ages, ratios and preselection metadata.
- Native moves and rule changes can reenter layout callbacks synchronously.
  Transfer guards, reconciliation, final placement and focus ordering matter.
- Reload reattachment supplies partial target lists. Do not prune saved windows
  or checkpoint intermediate state before the property-refresh barrier.
- Dispatcher return conventions differ between call sites. In particular, the
  workspace-swap helper falls back to workspace focus on a missing result.

The adjacent feature documents describe the user-visible behavior in detail.

## Checks

From the config root:

```sh
for test in tests/*_test.lua; do lua "$test" || break; done
python3 -m unittest discover -s tests -p '*_test.py'
Hyprland --verify-config -c "$PWD/hyprland.lua"
```

The Lua suites also run with `lua5.4` and `luajit`. Tests mock compositor calls;
several binding tests still load `lua/vars.lua` and need `~/bin/wpc`. In a sandbox,
use an isolated `HOME` with a test `bin/wpc` exporting `PC=mainpc` rather than
altering machine detection or accessing a running compositor's checkpoint.
