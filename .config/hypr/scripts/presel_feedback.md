# Script-only preselection feedback

`lua/presel_feedback.lua` does all geometry prediction. The small display helper,
`scripts/presel_feedback.py`, runs through Python and GTK3/layer-shell. There is
**no compiler, build step, generated protocol code, custom binary or plugin**.

## Behavior

- `#100000` at **50% opacity**, no outline: matches the original bspwm color
  and the `presel_feedback` opacity rule in the old `picom.conf`.
- Correct direction/ratio for leaf or subtree preselection.
- Predicts the future work area, including monitor reservations and the removal
  of the single-window smart-gap rule when the second tile opens. Inner gaps are
  applied after splitting; the preview includes the future window border.
- Fully click-through, no keyboard focus and no reserved screen space.
- Hidden for inactive/fullscreen/monocle workspaces and powered-off outputs.

Lua exports runtime output names, full logical monitor bounds and local preview
coordinates. The renderer matches those bounds against GDK's current monitor
geometry; it does not assume connector names or monitor ordering. Ambiguous or
unmatched geometry is hidden and logged instead of guessing a display. Mirrored
outputs with identical geometry can therefore require extra handling.

Layer-shell's top layer is above floating windows too, unlike bspwm's exact
stacking order. Also, the preview predicts a normal tiled window: future
application-specific floating/size rules or additional workspace gap overrides
cannot be known in advance.

## Runtime and maintenance

Dependencies already available here: Python 3, PyGObject/GTK3 with Cairo bindings,
and gtk-layer-shell. A pure in-process Lua renderer isn't available in this
Hyprland API; Lua's optional GTK binding (`lgi`) is not installed either.

The helper starts on reload/startup. A per-session, per-protocol lock prevents
duplicates. Version 3 uses `.v3.json`, separate from the retired `.state` (native)
and `.json` (first Python version) protocols. Each old state file receives a valid
empty message in its own format, so a surviving reader hides instead of rejecting
new-format data.

Updated script versions restart on config reload. Legacy cleanup is best-effort:
only verified previous helpers for the exact session/state file are stopped using
pidfds. An unrecognized legacy process is left untouched and idle until session
end; it cannot hold the new renderer's lock or prevent startup. No process-safety
check is bypassed. The compiled helper/build files are no longer part of this
configuration.

State is written atomically only on changes. Visibility and state are refreshed
at 50 ms intervals. No window titles or content are exported.

Diagnostics:

```sh
state="$XDG_RUNTIME_DIR/bspwm_presel_${HYPRLAND_INSTANCE_SIGNATURE}.v3.json"
tail -n 50 "$state.log"
```

For a foreground run when no instance is running:

```sh
python3 ~/.config/hypr/scripts/presel_feedback.py --state "$state"
```

To disable feedback, comment out the `presel_feedback` setup call in
`hyprland.lua` and remove the session's state file. The helper then hides its
surfaces and exits with the Wayland session.

## Tests

From `~/.config/hypr`:

```sh
lua tests/presel_feedback_test.lua
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p '*_test.py'
```

Tests use synthetic output fixtures and injected geometry, not connected
monitors or the output names in `lua/vars.lua`. They cover smart gaps, scaling,
rotated outputs, subtree geometry, names/escaping, monitor reordering, ambiguity,
50% opacity (including repeated redraws), process-identity checks, and startup
with a refusing legacy lock.
Live placement and input pass-through
still need checking on the desktop.
