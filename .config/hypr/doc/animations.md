# Picom animation parity

`lua/animations.lua` translates the fading settings from
`~/tmp/dotfiles/.config/picom.conf`:

```conf
fading = true;
fade-delta = 3;
fade-in-step = 0.03;
fade-out-step = 0.03;
fade-exclude = [ ];
```

`no-fading-openclose` is commented out, so the original fades opening and closing.
The port now makes window closing an exception (see below).
Active, inactive and frame opacity are all 1: focus does not dim windows.
There are no geometry animations in the original config.

## Translation

- **Linear, 100 ms full-opacity fades, except window closing.** Picom changes
  opacity by 0.03 every 3 ms: `3 / 0.03 = 100 ms`. Hyprland measures animation
  speed in 100 ms units, so this is `speed = 1` with the linear Bézier curve.
- Enable window opening and opacity fades, layer-shell fades (panels,
  launchers, notifications), and native popup fades (menus/tooltips).
  Window closing is immediate; layers and popups still fade in both directions.
- Disable position/size, border-colour, zoom, monitor-entry, DPMS and independent
  shadow/glow/dim animations. Shadows still follow overall window opacity.
- Use `popin 100%` for the disabled window geometry branch. Hyprland 0.56.2
  still computes its style endpoints before warping disabled animations;
  the old `popin 87%` would shrink the closing snapshot during its fade.
- Fade both incoming and outgoing workspaces **in place**, including special
  workspaces. In bspwm, `show_node`/`hide_node` map/unmap each desktop's windows,
  which Picom fades. This supersedes the port's incoming-only transition.

## Window-close border-fragment workaround

Commit `20d4214e68d596bdfe4a9e12aff03ac8698b7250` enabled `fadeOut`, retaining
closing windows for 100 ms. Border-coloured fragments were reported while
closing tiled terminals after that change.

In Hyprland 0.56.2 (`efb50993780079460b0cbed1363e2166a2de1d9f`),
`CWindow::unmapWindow()` captures a decorated snapshot before removing the
layout target. Surviving tiles reflow immediately; `renderFadeouts()` then draws
the old snapshot above the live tiles. `CWindowFadeout::effects()` also blurs the
live background behind translucent snapshots. This is a plausible source of
border fragments with the original terminal's `opacity = 0.6`, not an animated
border colour. The rendered cause has not been confirmed in the sandbox.

The narrow configuration workaround is an explicit `fadeOut.enabled = false`.
Disabling `windowsOut` is insufficient: it controls geometry, not opacity.
Keep `popin 100%` as well so disabled geometry never shrinks the snapshot.
No border, blur, terminal-opacity, layout, or other fade settings are changed.
This intentionally gives up Picom-style **window-close** fades rather than
patching Hyprland's renderer or disabling all animations.

For a visual A/B check, change only the `fadeOut` entry in `lua/animations.lua`
back to `enabled = true`, reload, and close several tiled terminals. Restore
`false` and repeat. If fragments persist with the close fade off, this workaround
is insufficient; capture a recording for further diagnosis.

## Limits of a configuration-only match

Apart from the close-fade workaround, this matches the original fade rate and
effects, not every rendered frame:

- Picom's steps are discrete: an opaque window reaches its endpoint after
  34 steps (nominally 102 ms). Hyprland interpolates over 100 ms and presents
  on compositor frames; it cannot reproduce the 3 ms cadence or Picom's
  `vsync = false` presentation through animation settings.
- Picom's absolute opacity step means smaller opacity changes finish sooner.
  Hyprland uses fixed-duration interpolation, including interrupted fades and
  surfaces whose opacity is below 1. Client-rendered Wayland transparency and
  tooltips are not equivalent to X11 window-type opacity rules.
- Hyprland fades a **live workspace**, not retained unmapped X11 window pixmaps.
  Moving a tile to another workspace can expose the source layout's immediate
  reflow during fade-out. The previous config avoided that by disabling the
  outgoing fade; restoring that workaround would sacrifice fade-out parity.
- Preselection remains an exception: the existing `bspwm-presel-feedback`
  layer rule keeps `no_anim = true`. Its script draws rectangles into one
  persistent surface per output; rectangles are buffer updates, not separate
  windows whose appearance/disappearance Hyprland can fade. Exact Picom-style
  feedback fades would require changes to that renderer.

Static blur, shadows, opacity rules and the preselection renderer are unchanged
by this animation-only port. Exact parity in the cases above requires more than
Hyprland animation configuration.

## Check

From `~/.config/hypr`:

```sh
lua tests/animations_test.lua
```

The test covers effective animation-tree inheritance, timing, linearity,
full-size window endpoints, stationary layer/workspace fades, explicit exclusion
of window-close fading, and exclusion of unrelated effects. It does not validate
rendered frames.
