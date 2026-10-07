# One-way fullscreen policy — Lua only

Application fullscreen requests cover the monitor. Window-manager actions can
then tile or float the window without making the application leave fullscreen.

## Behavior

| Action | Hyprland layout | Application presentation |
| --- | --- | --- |
| Application enters fullscreen | Covers the monitor | Fullscreen |
| Open/focus another tile | Covering window returns to its tile | Still fullscreen |
| `Super+d` | Floating | Unchanged |
| `Super+s` / `Super+t` | Tiled / pseudo-tiled | Unchanged |
| `Super+f` | Tiled, covering the monitor | Unchanged |
| Application exits fullscreen | Leaves monitor fullscreen | Normal |

`Super+f` does not itself hide browser UI; use the application's fullscreen
control for that. Saved floating geometry and BSP placement are preserved.
`misc.on_focus_under_fullscreen = 2` prevents new tiles from inheriting the old
window's fullscreen layout. Floating dialogs retain the usual overlay behavior.

The observer covers mapped, nonhidden tiles and floats in bspwm workspaces,
plus windows explicitly controlled with the state shortcuts. Other layouts are
not automatically enrolled. There are no application-specific rules or native
plugin changes. Applications still receive necessary geometry notifications.

## Implementation

Hyprland tracks **internal** (compositor) and **client** (application) modes:
`0` = none, `1` = maximized, `2` = fullscreen. `lua/helpers.lua` snapshots the
client mode before switching tiled/floating handlers, which have separate mode
records in v0.56.2. It clears only internal fullscreen before the transition,
then restores the saved client mode in the destination handler. No intermediate
request unsets the application's fullscreen flag.

`bspwm_fullscreen.set_wm_modes` uses targeted `fullscreen_state` **set** requests,
not toggles. The native dispatcher temporarily bypasses synchronization, then
rewrites `sync_fullscreen` to `internal == client`. The Lua setter therefore
applies this policy after each request, including no-ops:

- **Client not fullscreen:** enable synchronization for managed windows, so the
  next application fullscreen request covers the monitor natively.
- **Client fullscreen:** disable synchronization on the fullscreen/rule event,
  before a native focus/new-window demotion can clear its client flag.
- **Client exits fullscreen:** re-enable synchronization. If internal mode is
  still fullscreen, clear it with a 1ms Lua oneshot after the native request
  returns; do not recursively change fullscreen inside its rule callback.

A demotion that leaves client mode `2` is not a new application request.
Ordinary updates and repeated assertions of that mode do not inflate a `0/2`
video tile again. Explicit WM writes are guarded and adopted as a baseline,
not interpreted as application input.

Deferred exits check window lifetime, module identity and live modes. New
client entry, WM actions, close, destroy and reload invalidate pending tokens.
Invalidated oneshots expire harmlessly: disabling them would retain their Lua
callback references in v0.56.2. There is no polling or background daemon.

## Reload checkpoints

In v0.56.2, replacing a Lua layout loses its fullscreen records while the
Wayland protocol flag can survive. `config.reloaded` happens after provider
teardown, so saving modes in that callback would be too late.

Two static window tags survive layout/Lua replacement:

- `bspwm_fullscreen_<internal>_<client>` records live modes for mapped, nonhidden
  bspwm tiles. Zero/zero has no mode tag; floats retain their native handler.
- `bspwm_fullscreen_independent` records policy ownership, **not** a fixed sync
  value. Its name stays stable across reloads. It can exist without a mode tag
  and is never authority to restore fullscreen.

`window.fullscreen` and `window.update_rules` maintain mode tags; the latter
also catches client-only changes. Open/close/workspace events retire stale
records, and guarded tag writes prevent recursive observation. Close/remap
also releases the policy override back to normal rules/defaults.

The module registers before the tree provider. On the first
`config.props_refreshed` after reload, it restores an unambiguous mode tag only
if **both live modes were lost** and no other fullscreen window occupies the
workspace. New live requests and surviving fullscreen floats take precedence.
It then reapplies policy from the restored client mode and adopts the result.
Ordinary property refreshes never replay mode tags.

Old callbacks check their `package.loaded` identity because v0.56.2 clears user
modules before provider teardown. A syntax-failed reload retains the old Lua
callbacks, which re-arm their module identity. **Recheck this ordering when
upgrading Hyprland.**

Tags are session-local, do not change the tree checkpoint format, and need no
disk checkpoint. Do not manually edit these reserved tags. Already-lost modes
cannot be inferred from zero fields: recover with the application's fullscreen
controls. A valid `0/2` video tile remains tiled through reload; use `Super+f`
or a fresh application exit/entry to cover the monitor. Dispatcher failures are
logged with `bspwm fullscreen:` and are not retried in a loop.

## Validation

From `~/.config/hypr`:

```sh
for runtime in lua luajit; do
    "$runtime" tests/window_state_bindings_test.lua
    "$runtime" tests/bspwm_floating_test.lua
    "$runtime" tests/bspwm_fullscreen_test.lua
done
```

The mocks cover mode pairs, intermediate client flags, handler transfers,
repeats, focus changes, floating geometry, native new-window demotion, reloads,
policy cleanup, deferred-exit races and dispatch failures. They reject recursive
fullscreen dispatches; they do not replace a live Wayland/XWayland check.

Live check with Brave and mpv:

1. With two tiles open, enter fullscreen using the application: expect `2/2`.
2. Open another tile: the video returns to its tile but keeps its presentation
   (`0/2`); the new window must not inherit fullscreen.
3. Try `Super+d/s/t/f`, resize/move, and reload while floating and tiled. The
   application must keep its fullscreen presentation.
4. Exit using the application: expect `0/0`. Enter again: expect `2/2`.
5. Repeat on an inactive workspace and after a file-edit reload. Preselect,
   resize or swap neighboring nodes after exit; fullscreen must not resurrect.
