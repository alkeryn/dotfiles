# Fullscreen across reloads — Lua only

`bspwm_fullscreen.lua` keeps tiled fullscreen/maximized windows working across
`hyprctl reload`, the reload shortcut, and automatic file-edit reloads. There is
no new native hook, timer, daemon, command wrapper or disk checkpoint.

## Why a reload breaks fullscreen

In Hyprland v0.56.2, fullscreen tracking belongs to the layout instance. Lua
provider teardown and the bspwm alias flip replace that instance without
transferring its fullscreen records. The Wayland toplevel can still advertise
FULLSCREEN even though Hyprland now reports internal/client modes of zero.
Clearing an already-zero mode is a no-op; a later node operation resends the
cached protocol fullscreen flag along with its geometry.

Lua's `config.reloaded` event happens **after** provider teardown. Saving the
window's fullscreen fields in that callback would therefore be too late.

## Window-tag checkpoint

A private **static** window tag, `bspwm_fullscreen_<internal>_<client>`, records
the two modes while the window is healthy. Values are `0` (none), `1`
(maximized), and `2` (fullscreen); zero/zero has no marker. Static tags stay on
the native window when Lua/layout instances are replaced. They are distinct
from dynamic window-rule tags (which end in `*`). Other tags, including the
subtree selection marker, are not modified by this module.

- `window.fullscreen` records internal transitions.
- `window.update_rules` also records client-only changes, which do not emit a
  fullscreen event when the internal mode is unchanged.
- Open, close, floating and workspace changes retire stale markers. Only mapped,
  nonhidden tiles in `lua:bspwm` / `lua:bspwm_b` are eligible. Inactive desktops
  are included; floating windows retain their native handler and need no replay.
- Tag writes are idempotent and guarded against recursive rule notifications.

The module is registered before the tree provider's event handlers. After
`config.reloaded`, the first `config.props_refreshed` restores each unambiguous
marker **only if both live modes were lost**, using an explicitly targeted
`fullscreen_state` **set**, not a toggle. It does not unset fullscreen first.
New nonzero live states take precedence. Another fullscreen window in the same
workspace, such as a surviving fullscreen float, is never evicted to replay a
marker. Ordinary property refreshes do not replay anything.

The v0.56.2 reload sequence clears user entries in `package.loaded` before
unregistering providers, while the old Lua event subscriptions can still fire.
The module checks its cache identity to ignore those teardown notifications;
otherwise their zero-mode queries could erase the very marker being restored.
A syntax-failed reload retains the old Lua callbacks, so `config.reloaded`
re-arms that instance before the alias flip. **Recheck this ordering when
upgrading Hyprland.**

## Activation and limitations

For the first reload installing this feature, leave fullscreen first: the old
config has not recorded any markers yet. Once loaded, both manual and automatic
reloads should retain fullscreen until you explicitly exit it. A window whose
tracking was already lost cannot be inferred from its zero-mode fields; recover
it once with `Super+f`, then `Super+s`.

The tags are visible in `hyprctl -j clients`; do not clear or manually edit these
reserved markers while a window is fullscreen. This is session-local, not a way
to launch applications fullscreen or restore them after a compositor restart.
The existing tree checkpoint format is unchanged, and fullscreen recovery does
not depend on its file being writable. Dispatcher failures are logged with
`bspwm fullscreen:` and are not retried in a loop.

## Checks

```sh
lua tests/bspwm_fullscreen_test.lua
luajit tests/bspwm_fullscreen_test.lua
```

The tests run the real Lua modules against mocked native event/dispatcher
semantics. An unpatched control reproduces the stale-fullscreen recurrence.
Coverage includes all nine mode pairs, teardown callbacks, provider registration,
repeated alias flips, failed syntax reloads, client-only changes, inactive
workspaces, floats/hidden windows, close/remap, conflicting tags, live-state
precedence, reentrant notifications and failed dispatches.

Live check: fullscreen a tiled window, reload, exit fullscreen, then preselect,
resize or swap a neighboring node. It must stay tiled. Repeat via a file edit
and with a fullscreen window on an inactive workspace. The sandbox cannot reach
the running compositor; mocked tests and config verification are not a live
Wayland round trip.
