# Monocle display

`Super+v` still toggles the workspace's stored tiled/monocle mode. In monocle,
`bspwm.lua` places **all** tiled targets over the full logical monitor rectangle
(including the normally reserved panel strip). `bspwm_monocle.lua` supplies:

- Zero inner/outer gaps via a workspace-scoped rule.
- No border, rounding, shadow or other compositor decoration for tiled windows
  on that workspace. Floating windows retain their usual decoration.
- Explicit raising of the focused tile on entry, focus changes and after reload.

This does **not** set Hyprland/client fullscreen, hide other windows or change
opacity. A monocle-only `xray = false` window rule selects **live blur** over the
windows underneath instead of the cached wallpaper blur normally used for tiles
by `decoration.blur.new_optimizations`. Merely leaving global `blur.xray` off is
not sufficient in this Hyprland version. Blur stays enabled, and its usual path
is restored in tiled mode. Transparent surfaces can therefore composite over
the rest of the stack. Layer-shell panels are not automatically hidden as in
actual fullscreen.

Rules are disabled again in tiled mode, restoring the normal rules rather than
hard-coding replacement gap or border sizes. The original binary tree is retained.
Monitor geometry accounts for scale, rotation and nonzero/negative origins.
The normal numbered-workspace rules use `"N"`; monocle uses `"r[N-N]"` to avoid
merging into and then disabling the monitor/persistence rules. Keep those
range selectors reserved for this module (named workspaces use `"name:NAME"`).

Checks:

```
lua tests/bspwm_monocle_test.lua
luajit tests/bspwm_monocle_test.lua
lua tests/bspwm_state_test.lua
Hyprland --verify-config -c ~/.config/hypr/hyprland.lua
```

The fixtures model layout/rule calls, not GPU rendering. On the desktop, check a
transparent terminal over another window, cycle focus, open/close a window, then
toggle back to tiled mode and reload while in monocle. Ordinary app fullscreen
remains separate from this layout mode.
