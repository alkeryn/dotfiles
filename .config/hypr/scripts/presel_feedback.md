# Native preselection feedback

`hyprland.lua` enables `lua/presel_feedback.lua`. It predicts the next tile's
bordered footprint and exports connector names and monitor-local logical
coordinates to `scripts/presel_feedback`, a native Wayland client.

## Appearance and geometry

- **Opaque `#100000`, no outline**: the original bspwm `presel_feedback_color`.
- Supports preselection on leaves and whole subtrees, including unequal ratios.
- Reflows the tree using the **future** work area: opening a second tile removes
  this config's single-window gap override. Monitor reservations and outer gaps
  are applied before splitting; inner gaps are applied after splitting.
- The rectangle includes the future window border, not the surrounding gaps.
  Border width is reserved *inside* that footprint by Hyprland; it is not
  subtracted twice.
- Uses connector identity (`DP-4`, etc.) rather than GTK's monitor coordinates.
  Positions account for output transforms and logical scale. Viewporter scales
  one solid pixel to the exact logical surface size, including fractional scale.
- Empty input region, no keyboard interactivity, no reserved screen space.
- Hidden on inactive/fullscreen/monocle workspaces and powered-off outputs.
- Layer-shell's top layer is above application windows, including floating ones;
  this stacking order differs from bspwm. The preview is always click-through.

Prediction matches the **normal tiled-window rules in this config**. A future
application's floating rule, custom size constraints, grouping decorations, or
new workspace-specific gap rules cannot be inferred before the application
exists. If adding such rules, update the predictor as needed.

## Build and runtime

Runtime: **libwayland-client only**, plus standard C libraries. No Python, GTK,
Cairo, JSON library, or compositor plugin.

Build tools (already installed): C compiler, pkg-config, wayland-scanner,
wayland-protocols. `scripts/presel_feedback` builds on first use and when its C
source/protocols change. The binary lives in:

```
${XDG_CACHE_HOME:-$HOME/.cache}/hypr/presel_feedback/presel_feedback
```

A session-specific lock prevents duplicates. After rebuilding, a config reload
replaces an outdated helper, checking its executable, owner, exact state argument
and held lock before using a pidfd to stop it. The same identity checks retire
the previous Python helper during migration; no broad process-name kill is used.
The Lua publisher also clears the legacy JSON overlay immediately.

Geometry is written atomically only when changed. Both processes check visibility
or state changes at 50 ms intervals. No window titles or content are exported.

Diagnostics:

```sh
state="$XDG_RUNTIME_DIR/bspwm_presel_${HYPRLAND_INSTANCE_SIGNATURE}.state"
tail -n 50 "$state.log"
```

For a foreground run when no instance is running:

```sh
~/.config/hypr/scripts/presel_feedback --state "$state"
```

The helper exits with the Wayland session. To disable feedback, comment out the
`require("lua/presel_feedback").setup(bspwm)` call and remove the session's state
file; the existing helper hides its surfaces.

## Checks

From `~/.config/hypr`:

```sh
lua tests/presel_feedback_test.lua
scripts/presel_feedback --self-test
tests/presel_feedback_native_test.sh
```

The last test runs the real helper against a headless Wayland protocol server.
It verifies the opaque SHM pixel, empty input region, keyboard mode, viewport
sizes, margins, resizing and dismissal. It requires libwayland-server for the
test server, not for the actual helper. Lua tests cover smart gaps, reservations,
rotated/scaled outputs, subtree geometry, ratios and visibility.

`protocols/wlr-layer-shell-unstable-v1.xml` is vendored from Hyprland commit
`efb50993780079460b0cbed1363e2166a2de1d9f`; its upstream copyright/license is retained
inside the file. Other protocol definitions come from system wayland-protocols.
