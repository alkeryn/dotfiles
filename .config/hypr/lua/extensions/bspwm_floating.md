# Floating without losing the tiled slot

Changing an existing tile to floating must not delete its tree node. In bspwm's
`src/tree.c`, `set_floating` calls `set_vacant`, not `remove_node`. Ancestors become
vacant only when both children are vacant. `apply_layout` gives both children the
parent's rectangle if either is vacant; the floating client's actual rectangle
is managed separately. Returning to tiled clears vacancy without reinsertion.

The Lua layout now follows that model:

- Tree membership uses mapped windows on the workspace, independently of the
  native tiled target list. Closed/moved leaves are pruned; floating leaves stay.
- Tiled targets determine occupancy. Floating nodes receive no tile placement,
  while their siblings fill the available area. Node identity, insertion age,
  split direction and ratio survive the round trip.
- Vacancy cancels preselection on that node and on fully vacant ancestors, as
  in bspwm. Tiling again does not consume another node's preselection.
- Resizing skips invisible split boundaries; balance counts only tiled leaves.
  Preselection previews use the same vacancy-aware geometry.
- Checkpoints retain the complete topology. Vacancy is rebuilt from current
  windows, including when reloading a float-only workspace.

## Hyprland ordering traps (v0.56.2)

`CAlgorithm::setFloating` calls `removeTarget` **before** changing the window's
floating flag. `CLuaTiledAlgorithm::removeTarget` immediately recalculates, unless
there are no remaining targets. Checking only `window.floating` during that first
callback is therefore insufficient: a missing but still-mapped leaf must survive.

`window.update_rules` observes the new floating flag and handles the last tile,
where there was no Lua layout callback. It does not revive a returning tile before
its target has been added. The property-refresh barrier also reconciles desktops
without targets. Lua does not expose the native `window.floating` event here.

`window.close` occurs before `mapped` becomes false. Closing IDs are excluded
through reentrant callbacks, then released on destroy/remap. Close and workspace
move events remove stale slots even when no tiled callback follows. Guarded
workspace transfers retain unrelated floating leaves during reconciliation.

## Tests

`tests/bspwm_floating_test.lua` models native callback ordering, repeated toggles,
all-floating trees, reversed restoration order, changing focus, inserting/closing
other windows, remapping, workspace moves and monocle. The tree, checkpoint,
workspace-transfer and feedback suites cover the corresponding lower-level paths.

Reload the config to activate changes. Slots already deleted by the old code
cannot be recovered; this preserves slots on subsequent floating transitions.
