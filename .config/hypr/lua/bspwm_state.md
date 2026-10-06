# Keeping the bspwm layout across config reloads

Hyprland 0.56.2 destroys the Lua state on a successful reload. `lua/bspwm.lua` now
loads a checkpoint **before registering its layout providers** and checkpoints
layout commands, recalculations and selection events. `Super+Escape` flushes the
checkpoint and still runs the real `hyprctl reload`; automatic file reloads are
covered too.

Stored per workspace:

- Binary-tree topology, split directions and exact ratios.
- Window stable IDs and insertion ages/sequence.
- Tiled/monocle mode and per-node preselection.
- Selected node and pending insertion anchor, identified by tree paths.

Geometry and Hyprland userdata are not serialized. The new config's monitor
workareas and gaps still apply; this preserves the tree, not overrides to other
configuration options. Selections are retained only if their focused window and
subtree still exist.

## Reload ordering

Registering/switching providers can synchronously recalculate after each window
is attached. Until `config.props_refreshed` follows `config.reloaded`, absent
layout targets are checked against all live tiled windows, not mistaken for
closed windows. Transient focus events and checkpoint writes are suppressed in
that phase. The final refresh reconciles closed/floating/moved windows, restores
selection borders and resumes normal checkpointing.

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
