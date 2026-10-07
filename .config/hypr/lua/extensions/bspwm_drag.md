# bspwm-style pointer move and resize

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
- `Super + right drag` resizes the hovered tile's nearest corner. See below.
- Gaps, floating-window occlusion and top/overlay layers do not swap tiles
  underneath them; the click-through preselection overlay is excluded.
- Fullscreen, grouped, hidden and monocle sources are not tiled-drag candidates.
- The non-consuming, modifier-independent release observer ends the grab even
  when Super is released first. It does not swallow ordinary clicks.
- Close, reload, submap change, monitor removal, focus loss and invalid source
  state cancel the gesture. Gesture state is not checkpointed across reloads.

## Tiled corner resizing

`Super + right drag` grabs the window under the pointer, focuses it, and changes
its horizontal/vertical split ratios without floating, swapping or reinserting
it. The nearest corner is chosen once at press time. A screen edge with no
owning split stays fixed; a shared edge moves its nearest visible ancestor split.
Vacant floating branches are skipped. Keyboard subtree selection does not expand
the gesture to a whole subtree. Existing preselection and leaf metadata survive.

Both axes use displacement from the original pointer position, with the existing
10–90% ratio limits. This avoids fractional-motion drift and changing corners
mid-drag. Crossing monitors during **resize** does not transfer the window.
The right-button release observer commits any motion since the last timer tick,
then stops even if Super was released first. Resize and move grabs are mutually
exclusive. Floating windows and non-bspwm layouts retain native mouse resizing.
Reloads, focus loss, workspace/geometry changes or invalidated split ownership
cancel the tiled resize rather than modifying a different window or split.

Why the custom path is necessary: in Hyprland **v0.56.2**,
`src/config/lua/layout/LuaLayoutProvider.cpp:CLuaTiledAlgorithm::resizeTarget`
ignores its delta, target and corner arguments and only calls `recalculate()`.
The Lua provider API exposes `recalculate` and `layout_msg`, but no resize
callback. Merely binding `hl.dsp.window.resize()` therefore works on floats but
cannot change this Lua tree. `bspwm.lua` snapshots the owning splits, then sends
both updated ratios through one `pointer_resize` layout message per motion.

Unmodified border dragging remains disabled (`general.resize_on_border = false`);
this fix is for the configured **Super + right-button** gesture.

## Implementation constraints

Hyprland 0.56.2 has no built-in Lua pointer-motion event. The input controller in
`bspwm_drag.lua` samples the cursor with a reusable timer per gesture, **only
during a grab** (only one enabled at a time), every 17 ms (bspwm's default `pointer_motion_interval`). No daemon, IPC
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
release/cancellation, cross-monitor transfers and transfer failures. Resize cases
cover all four corners, ancestor/outer/vacant edges, both axes, ratio limits,
fractional motion, selected-subtree isolation, quick releases, checkpoint reload,
native fallback, timer reuse, invalidated grabs and cross-monitor non-transfer.
`lua tests/repeat_bindings_test.lua` checks the release flags and retains keyboard
repeat and the other mouse bindings.

`Hyprland --verify-config -c ~/.config/hypr/hyprland.lua` checks API/config parsing.
In this sandbox the host's `~/bin/wpc` and compositor socket are unavailable;
verification used an isolated HOME containing a `PC=mainpc` machine-detection
fixture. Live mouse behavior still needs checking in the running session after
`hyprctl reload` (or Super + Escape).
