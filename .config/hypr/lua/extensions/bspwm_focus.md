# bspwm directional focus (Super+h/j/k/l)

References from the original rice:

- `~/tmp/dotfiles/.config/bspwm/sxhkd/sxhkdrc:115-116`:
  `bspc node -f "$A" || bspc monitor -f "$A"`, with west/south/north/east.
- `~/tmp/dotfiles/.config/bspwm/bspwmrc:46`:
  `bspc config directional_focus_tightness low`.
- `~/tmp/bspwm/src/tree.c`: `find_nearest_neighbor`, `get_rectangle`.
- `~/tmp/bspwm/src/geometry.c`: `on_dir_side`, `boundary_distance`.
- `~/tmp/bspwm/src/monitor.c`: `nearest_monitor`.

`../bindings.lua` now calls `helpers.focus_dir`, through the layout module's
reload/transfer guard, into `bspwm_focus.lua`. It does **not** call Hyprland's
native directional-focus dispatcher. Key repeat is retained. Shift+hjkl swaps
are unchanged.

## Search rules

1. Search every monitor's current desktop, not just the focused desktop.
2. Include tiled **and** floating clients in one search. There is no tiled-first,
   floating-first, local-monitor-first or stacking-order preference.
3. Use the source and candidate rectangles, with **inclusive pixel endpoints**.
   Low tightness permits overlapping and contained rectangles; perpendicular
   ranges must overlap. A float inside a tile can therefore be reached from it
   (and vice versa), even when their centres coincide.
4. Rank by absolute distance between the source's requested edge and the
   candidate's opposite edge. Break ties by most recent focus; unrecorded
   history comes last. This is not Euclidean/centre distance.
5. Exclude the source, its selected subtree's descendants, hidden/unmapped
   clients and inactive desktops. Fullscreen/monocle does not change the search
   into native focus cycling, nor does opacity alone hide a candidate.
6. If there is no matching client (or its focus dispatch fails), search monitors
   using the same geometry from the **monitor** rectangle. This also reaches an
   empty monitor. No matching monitor means no-op, not wraparound.

Native window handles supply goal `at`/`size`, including floating, pseudo-tiled,
monocle and fullscreen geometry. Allocation boxes alone would wrongly treat
pseudo-tiled clients as full-size tiles and omit floats entirely. Internal-node
selection uses the existing port's whole-node allocation rectangle, excluding
all its leaves; in monocle it uses the representative's full-screen rectangle.
Normal native focus events clear the old selection/highlights.

## Compositor-specific boundaries

This ports the bspwm search, not X11 geometry management: positions, gaps,
decorations and internal-node allocation rectangles remain those of this
Hyprland port. Equal-distance **and** equal-history ties retain tree leaf order
for tiles. Floats are not stored in the tiled tree, so otherwise indistinguishable
unranked floats use native enumeration order rather than an unavailable bspwm
float-leaf order.

Hyprland-only special workspaces are treated as the monitor's current desktop
while open; normal windows behind them are not searched. Pinned floats remain
eligible on their current monitor. Mirrored monitor copies are not separate
focus destinations. Native focus/fullscreen policy still applies when the chosen
window is focused; no window state is changed by this module.

## Checks

```sh
lua tests/bspwm_focus_test.lua
lua5.4 tests/bspwm_focus_test.lua
luajit tests/bspwm_focus_test.lua
BSPWM_SOURCE="$HOME/tmp/bspwm" python3 tests/bspwm_focus_reference_test.py
```

The binding tests load the real layout and bindings with mocked compositor
handles, covering both directions of tiled/floating focus, containment, all four
keys, repeat, history, monitor fallback, selected nodes and monocle/fullscreen.
The optional reference test compiles the **unmodified original `geometry.c`**
and compares 82,500 directional cases against Lua and LuaJIT. No display server
is involved; absent source/compiler/interpreter skips that reference test.

For a live check, reload with Super+Escape, open a floating terminal, then use
Super+hjkl to enter/leave it from an overlapping tile and between monitors.
