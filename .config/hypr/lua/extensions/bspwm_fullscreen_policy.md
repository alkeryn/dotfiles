# Application/WM fullscreen policy — Lua only

`bspwm_fullscreen_policy.lua` implements the behavior policy, not a compositor
reload workaround. Applications entering fullscreen cover the monitor; WM
commands can then tile or float them without making them leave fullscreen.

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
control for that. `lua/helpers.lua` preserves the client mode across tiled/float
handler transfers, while the existing floating helper preserves geometry.
`misc.on_focus_under_fullscreen = 2` in `hyprland.lua` prevents new tiles from
inheriting fullscreen. Floating dialogs retain their usual overlay behavior.

The observer covers mapped, nonhidden tiles and floats in bspwm workspaces,
plus windows explicitly controlled with the state shortcuts. Other layouts are
not automatically enrolled. There are no application-specific rules or plugins.
Applications still receive necessary geometry notifications.

## Implementation and ownership

Hyprland's internal and client modes use `0` = none, `1` = maximized, `2` =
fullscreen. `set_wm_modes(window, internal, client)` performs targeted **set**
requests, not toggles. Native dispatch rewrites `sync_fullscreen` to
`internal == client`, so the setter reapplies this policy after each request:

- Outside application fullscreen, enable sync for managed windows so the next
  application request covers the monitor natively.
- While the client is fullscreen, disable sync before native WM demotion can
  clear its flag. A demotion or repeated assertion of client mode `2` must not
  inflate a `0/2` video tile again.
- When the application exits, re-enable sync. If internal fullscreen remains,
  clear it in a 1ms oneshot after native dispatch returns, never recursively
  inside its rule callback.

Explicit WM writes are adopted as a baseline, not interpreted as application
input. Deferred exits verify live modes, window lifetime and module identity;
entry, WM actions, close, destroy and reload invalidate their tokens. Invalidated
oneshots expire harmlessly so v0.56.2 releases their callback references.

The module owns only `bspwm_fullscreen_independent`, a stable policy-ownership
tag, and its `sync_fullscreen` override. Close/remap releases them. It neither
reads nor writes mode checkpoint tags, and cannot repair lost fullscreen records.

## Setup and reload lifecycle

Standalone: `require("lua/extensions/bspwm_fullscreen_policy").setup()`.
The module always discards pending exits and observer baselines on reload, then
adopts live modes on the subsequent property refresh. This is observer lifecycle,
not checkpoint restoration.

When the separate [reload workaround](bspwm_fullscreen_reload.md) is installed,
`bspwm.lua` registers that module first and passes its `is_ready` function as
`setup({ reload_ready = ... })`. The policy waits for complete replay, including
reentrant refreshes, before adopting modes and reapplying sync. There is no
import of the reload module or knowledge of its tag format here.

Errors are logged with `bspwm fullscreen policy:`. Session tags retain their
existing names so splitting the modules does not require restarting applications.

## Checks

```sh
lua tests/bspwm_fullscreen_policy_test.lua
luajit tests/bspwm_fullscreen_policy_test.lua
lua tests/window_state_bindings_test.lua
lua tests/bspwm_floating_test.lua
lua tests/bspwm_fullscreen_integration_test.lua
```

The policy suite disables the reload workaround and also exercises setup without
a readiness callback. The integration suite checks their interaction. Mocks are
not a substitute for a live Wayland/XWayland check:

1. With two tiles, enter fullscreen in Brave/mpv: expect internal/client `2/2`.
2. Open another tile: the video returns to its tile with presentation intact
   (`0/2`); the new window must not inherit fullscreen.
3. Try `Super+d/s/t/f` and resize/move. Application presentation stays unchanged.
4. Exit using the application: expect `0/0`. Enter again: expect `2/2`.
5. With the reload workaround installed, repeat through manual/file-edit reloads.
