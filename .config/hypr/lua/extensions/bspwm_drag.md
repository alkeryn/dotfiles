# bspwm-style pointer move

`Super + left drag` now grabs the window **under the pointer**, keeps it tiled,
and swaps it with each tiled window entered while the button is held. Release
ends the gesture; it does not perform a native float/drop/reinsert operation.
Leaf identity, insertion age and preselection travel with the grabbed window;
the surrounding splits and ratios remain unchanged.

Reference: `~/tmp/bspwm/src/pointer.c:track_pointer`,
`src/window.c:move_client`, and `src/tree.c:swap_nodes`.
As in bspwm, crossing to another monitor **transfers** the node into that
monitor's displayed workspace rather than exchanging two windows across
monitors. Further motion swaps it with tiles there. Intermediate native
workspace-move layout callbacks are deferred until the tree transfer commits.

- Already-floating windows still use native dragging.
- `Super + Ctrl + left drag` remains an explicit native-move override.
- `Super + right drag` is unchanged.
- Gaps, floating-window occlusion and top/overlay layers do not swap tiles
  underneath them; the click-through preselection overlay is excluded.
- Fullscreen, grouped, hidden and monocle sources are not tiled-drag candidates.
- The non-consuming, modifier-independent release observer ends the grab even
  when Super is released first. It does not swallow ordinary clicks.
- Close, reload, submap change, monitor removal, focus loss and invalid source
  state cancel the gesture. Gesture state is not checkpointed across reloads.

## Implementation constraints

Hyprland 0.56.2 has no built-in Lua pointer-motion event. The input controller in
`bspwm_drag.lua` samples the cursor with a single reusable timer, **only during a
grab**, every 17 ms (bspwm's default `pointer_motion_interval`). No daemon, IPC
polling loop or binary plugin is needed. Stationary samples do not modify or
checkpoint the layout. Hover uses native goal geometry (`window.at/size`); this
config already disables window animations. Lua lacks a native surface hit-test,
so overlapping windows are resolved by fullscreen/floating priority and focus
history; arbitrary client popup/input regions are not modeled.

`bspwm.lua` implements the node swap in one layout message/recalculation. It
never calls native `window.drag` for this tiled gesture. Both final rectangles
are placed before the compositor returns to rendering.

## Checks

`lua tests/bspwm_pull_test.lua` covers the real input module/bindings with mocked
cursor, timers and native layout callbacks: ongoing repeated swaps, return
swaps, metadata and checkpoint preservation, native float fallback, occlusion,
release/cancellation, cross-monitor transfers and transfer failures.
`lua tests/repeat_bindings_test.lua` checks the release flags and retains keyboard
repeat and the other mouse bindings.

`Hyprland --verify-config -c ~/.config/hypr/hyprland.lua` checks API/config parsing.
In this sandbox the host's `~/bin/wpc` and compositor socket are unavailable;
verification used an isolated HOME containing a `PC=mainpc` machine-detection
fixture. Live mouse behavior still needs checking in the running session after
`hyprctl reload` (or Super + Escape).
