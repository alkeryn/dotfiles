# Keeping the bspwm layout across config reloads

Hyprland 0.56.2 destroys the Lua state on a successful reload. `lua/extensions/bspwm.lua` now
loads a checkpoint **before registering its layout providers** and checkpoints
layout commands, recalculations and selection events. `Super+Escape` flushes the
checkpoint and still runs the real `hyprctl reload`; automatic file reloads are
covered too.

Stored per workspace:

- Binary-tree topology, split directions and exact ratios.
- Window stable IDs and insertion ages/sequence.
- Last floating rectangle saved by the state shortcuts, with its monitor bounds.
- Tiled/monocle mode and per-node preselection.
- Selected node and pending insertion anchor, identified by tree paths.
- Remembered `Super+y` source groups and their representative window IDs,
  independent of which window currently has focus or selection borders.

Vacant floating leaves remain in the saved topology. Vacancy itself is derived
from live windows/targets on reload rather than serialized, so tiling again
restores the saved slot even after reloading while every window is floating.

Tiled placement geometry and Hyprland userdata are not serialized. The new
config's monitor workareas and gaps still apply; this preserves the tree, not overrides to other
configuration options. Selections are retained only if their focused window and
subtree still exist.

## Reload ordering

Registering/switching providers can synchronously recalculate after each window
is attached. Until `config.props_refreshed` follows `config.reloaded`, absent
layout targets are checked against all mapped windows for tree membership and
all live tiled windows for occupancy. Floating leaves are retained as vacant;
missing targets during partial reattachment are not mistaken for floating or
closed windows. Transient focus events and checkpoint writes are suppressed in
that phase. The final refresh prunes closed/moved leaves, refreshes vacancy,
restores selection borders and resumes normal checkpointing.

The existing two-provider workaround remains: it replaces stale provider
instances without throwing away the tree.

## Storage and safety

```
$XDG_RUNTIME_DIR/bspwm_layout_${HYPRLAND_INSTANCE_SIGNATURE}.state
```

The file belongs only to the current compositor session. It is atomically
replaced only when serialized state changes. The versioned, bounded parser reads
data tokens, **never executes Lua from a state file**, and rejects corruption,
invalid nodes, duplicate leaves, excessive depth or oversized input. Errors are
logged with `bspwm checkpoint:`; persistence failure does not disable tiling.

V3 adds an optional floating rectangle and monitor bounds to leaf records. V2
introduced an optional pull-source representative on splits. V1 and V2 files
are still accepted and upgraded on the next save without rebuilding their trees.
Floating coordinates are bounded integers and rectangle dimensions must be positive.
The decoder verifies each remembered representative belongs to its subtree and
reconstructs its member IDs. If membership changed while the config was reloading,
the layout drops that stale association during reconciliation.

The first reload installing this feature may rebuild once: the previous code
never checkpointed its in-memory tree. Arrangements made after installation are
preserved by later reloads. There is no new daemon or interpreter dependency.

## Tests

```
lua tests/bspwm_state_test.lua
luajit tests/bspwm_state_test.lua
```

Fixtures use temporary files and fake window IDs; other layout tests explicitly
disable session persistence so they cannot overwrite the running desktop's tree.
The reload tests replace the module, reattach windows incrementally and out of
order, simulate the provider flip and only then signal the refresh barrier.
