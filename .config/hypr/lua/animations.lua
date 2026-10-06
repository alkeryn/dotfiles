-- Picom-style opacity fades, except window open/close; geometry/borders are immediate.
-- Reference: ~/tmp/dotfiles/.config/picom.conf
--   fading = true; fade-delta = 3; fade-in-step = fade-out-step = 0.03;
-- 3 ms / 0.03 = 100 ms for a full-opacity fade. Hyprland speed is in 100 ms
-- units, so speed = 1 with a linear curve matches the opacity-change rate.
-- Picom's discrete steps (34 steps = 102 ms) and partial/interrupted fades
-- cannot be reproduced exactly by Hyprland's fixed-duration interpolation.
-- See doc/animations.md for the workspace and preselection limitations.
local fade_delta_ms = 3
local fade_in_step, fade_out_step = 0.03, 0.03
local fade_in_speed = fade_delta_ms / fade_in_step / 100
local fade_out_speed = fade_delta_ms / fade_out_step / 100

hl.config({ animations = { enabled = true } })
hl.curve("linear", { type = "bezier", points = { {0, 0}, {1, 1} } })

-- Opt in only to Picom's opacity effects. Unlisted children inherit their
-- parent: no animated moves/resizes, borders, zoom, monitor entry, or DPMS.
hl.animation({ leaf = "global",     enabled = false, speed = 1, bezier = "linear" })
-- Even disabled geometry animations need full-size endpoints: Hyprland 0.56.2
-- applies the window style before warping the closing snapshot to its goal.
-- Leaving the default popin (or the old 87%) would shrink a fading window.
hl.animation({ leaf = "windows",    enabled = false, speed = 1, bezier = "linear", style = "popin 100%" })
hl.animation({ leaf = "layers",     enabled = false, speed = 1, bezier = "linear", style = "fade" })
hl.animation({ leaf = "fade",       enabled = false, speed = 1, bezier = "linear" })

-- Opacity changes; active/inactive opacity remains 1.
-- Keep fade's other children off: no extra dim, shadow-colour, glow or DPMS
-- transitions. A window's shadow already follows its overall opacity.
-- Open windows immediately, without a fade-in.
hl.animation({ leaf = "fadeIn",     enabled = false, speed = fade_in_speed,  bezier = "linear" })
-- Close-fade workaround: Hyprland snapshots the border, then retiles surviving
-- windows underneath it. Do not retain that snapshot over the new layout:
-- translucent terminals can expose border fragments during the fade. Disabling
-- windowsOut alone only stops geometry animation, not this opacity fade.
hl.animation({ leaf = "fadeOut",    enabled = false, speed = fade_out_speed, bezier = "linear" })
hl.animation({ leaf = "fadeSwitch", enabled = true,  speed = fade_in_speed,  bezier = "linear" })

-- Picom's fade-exclude is empty: panels, launchers, notifications and popups
-- fade as well. The script-rendered preselection overlay retains its no_anim
-- rule; its rectangles are buffer updates, not individual mapped windows.
hl.animation({ leaf = "fadeLayers",    enabled = true, speed = fade_in_speed,  bezier = "linear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = fade_out_speed, bezier = "linear" })
hl.animation({ leaf = "fadePopups",    enabled = true, speed = fade_in_speed,  bezier = "linear" })
hl.animation({ leaf = "fadePopupsOut", enabled = true, speed = fade_out_speed, bezier = "linear" })

-- bspwm maps/unmaps windows when switching desktops, so Picom fades BOTH
-- directions. This intentionally replaces the old immediate-departure policy.
-- Hyprland fades a live workspace, not Picom's retained unmapped pixmaps:
-- moving a tile away can expose the source workspace's reflow during fade-out.
-- Special workspaces inherit this same stationary fade (no slide or zoom).
hl.animation({ leaf = "workspaces",    enabled = true, speed = fade_in_speed,  bezier = "linear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = fade_out_speed, bezier = "linear", style = "fade" })
