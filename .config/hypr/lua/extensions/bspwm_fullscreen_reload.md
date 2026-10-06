# Fullscreen across layout reloads — Lua only

`bspwm_fullscreen_reload.lua` is the Hyprland v0.56.2 reload workaround. It saves
and restores fullscreen mode records; it does not implement application/WM
fullscreen policy, set policy properties, or schedule timers.

## Why it is needed

Replacing a Lua layout loses its native fullscreen records while the Wayland
protocol flag can survive. `config.reloaded` happens after provider teardown,
so saving modes in that callback would be too late. Clearing an already-zero
mode is a no-op, and later geometry updates can resend the stale protocol flag.

## Checkpoint ownership

The module owns only static tags matching
`bspwm_fullscreen_<internal>_<client>`, with mode values `0` (none), `1`
(maximized), or `2` (fullscreen). Zero/zero has no mode tag. Other tags—including
`bspwm_fullscreen_independent`, owned by the separate behavior policy—are ignored.

Mode tags are maintained for mapped, nonhidden tiles in `lua:bspwm` and
`lua:bspwm_b`. Inactive workspaces are included. Floats retain their native
handler through a layout reload and do not need mode replay.

`window.fullscreen` records internal changes; `window.update_rules` also catches
client-only changes. Guarded tag writes prevent recursion. Open/close/workspace
events retire stale markers. A closing window is marked retired so later close
subscribers cannot recreate its mode tag while native `mapped` is still true.

## Restoration and integration

Register with `require("lua/extensions/bspwm_fullscreen_reload").setup()` before
layout providers. After `config.reloaded`, the first `config.props_refreshed`
restores each unambiguous tag only if **both live modes were lost** and no other
fullscreen window occupies that workspace. It uses targeted **set** requests,
never toggles or an initial fullscreen unset. New live states and surviving
fullscreen floats take precedence. Ordinary refreshes do not replay tags.

`is_ready()` stays false until replay completes, even during reentrant refreshes.
The module has no dependency on the behavior policy. When both are installed,
`bspwm.lua` wires them explicitly:

```lua
local reload = require("lua/extensions/bspwm_fullscreen_reload")
reload.setup()
require("lua/extensions/bspwm_fullscreen_policy").setup({ reload_ready = reload.is_ready })
```

This ordering lets the [policy](bspwm_fullscreen_policy.md) adopt restored modes
and reapply its sync setting after the native dispatcher has finished. Both run
before the tree provider resumes checkpointing and selection.

Each module guards its own `package.loaded` identity: v0.56.2 clears user modules
before provider teardown, while old callbacks can still execute. Syntax-failed
reloads retain callbacks, which re-arm their identities. Recheck this ordering
when upgrading Hyprland.

## Limits and checks

Tags are session-local and keep their existing names; no disk checkpoint or
plugin is involved. Do not manually edit the reserved mode tags. Already-lost
modes cannot be inferred from zero fields: recover with the application's own
fullscreen controls. Errors are logged with `bspwm fullscreen reload:` and are
not retried in a loop.

```sh
lua tests/bspwm_fullscreen_reload_test.lua
luajit tests/bspwm_fullscreen_reload_test.lua
lua tests/bspwm_fullscreen_integration_test.lua
```

The reload suite disables the behavior policy. It covers mode pairs, provider
teardown, syntax failures, conflicting tags, surviving windows, close/remap and
dispatch failures. Integration tests check replay ordering and policy adoption.

Live check: fullscreen a tiled window, reload manually and through a file edit,
then leave fullscreen using the application. Resize/swap/preselect neighboring
nodes; fullscreen must not return. Repeat on an inactive workspace and with a
surviving fullscreen float. Mocked tests do not replace this compositor check.
