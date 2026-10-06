-- hyprland.lua -- alkeryn's bspwm-style rice, ported to Hyprland v0.56.2
-- ============================================================================
-- Entry point: config, monitors, env, autostart.
--   require("lua/vars")     -- machine detection + shared constants
--   require("lua/animations") -- animation settings + curves
--   require("lua/autostart") -- startup commands
--   require("lua/rules")    -- window/workspace rules + monitor assignment
--   require("lua/bindings") -- keybindings
--   require("lua/helpers")  -- focus/swap/gap/monitor helpers (used by the two above)
--   require("lua/extensions/bspwm")    -- the bspwm-style tree layout
--
-- Migration from ~/.config/bspwm/bspwmrc + sxhkd.
--
-- Requirements (replaces the X11 stack):
--   hyprpaper hypridle hyprlock waybar dunst grim slurp wl-clipboard cliphist
--   rofi (wayland build) alacritty brightnessctl playerctl pactl ckb-next
--   conky (XWayland) megasync signal-desktop mpd mpDris2
--   python3 python-gobject python-cairo gtk-layer-shell (script-only feedback)
-- ============================================================================

local bspwm = require("lua/extensions/bspwm") -- registers the "lua:bspwm" layout
require("lua/extensions/presel_feedback").setup(bspwm)
hl.layer_rule({
	name = "bspwm-preselection-feedback",
	match = { namespace = "^bspwm-presel-feedback$" },
	no_anim = true,
	blur = false,
})

local vars = require("lua/vars")

local PC       = vars.PC
local GAPS     = vars.GAPS
local GAPS_OUT = vars.GAPS_OUT
local BORDER   = vars.BORDER
local M1       = vars.M1
local M2       = vars.M2

-- ---------------------------------------------------------------------------
-- monitors + HDR (tuned on the previous attempt)
-- ---------------------------------------------------------------------------
-- Previous attempt kept the output SDR by default and relied on
-- render:cm_auto_hdr to flip HDR when a fullscreen app requests it -- so the
-- SDR desktop never pays an HDR penalty. supports_hdr/supports_wide_color=1
-- force-enables the EDID capability claims (use -1 = trust EDID if unsure).
-- Fractional scales were rejected on that attempt ("blurry mess"): scale stays
-- 1, xwayland force_zero_scaling + QT_FONT_DPI compensate instead.

-- monitor=,preferred,auto,auto -- fallback for any output (laptop, docks, ...)
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

if PC == "mainpc" then
	hl.monitor({
		output   = M1,
		mode     = "3840x2160",
		position = "0x0",
		scale    = "1",
	})
	hl.monitor({
		output              = M2,
		mode                = "3840x2160@244",
		position            = "3840x0",
		scale               = "1",
		bitdepth            = 10,
		supports_wide_color = 1,
		supports_hdr        = 1,
		-- sdrbrightness = 1.2, -- raise if SDR looks dim under HDR output
	})
end

hl.config({
	render = {
		cm_enabled = true,
		cm_auto_hdr = 1,      -- auto HDR when a fullscreen app requests it
		-- Workaround for stale frames after closing fullscreen mpv: keep compositing.
		direct_scanout = 0,
		-- cm_fs_passthrough: existed on the old build, gone in v0.56.2 --
		-- cm_auto_hdr + surface-driven metadata cover it.
	},
	xwayland = {
		force_zero_scaling = true, -- with scale 1 + QT_FONT_DPI below
	},
})

-- ---------------------------------------------------------------------------
-- look and feel (bspwmrc parity)
-- ---------------------------------------------------------------------------

hl.config({
	general = {
		gaps_in     = GAPS,
		gaps_out    = GAPS_OUT,
		border_size = BORDER,
		layout      = "lua:bspwm",

		col = {
			-- focused_border_color #bb0000 / normal_border_color #500000
			active_border   = "rgb(bb0000)",
			inactive_border = "rgb(500000)",
		},
		resize_on_border  = false,          -- previous attempt tuning
		allow_tearing     = false,
		no_focus_fallback = true,           -- like bspwm: no focus jump when nothing in direction
	},

	decoration = {
		rounding = 0, -- bspwm look: square corners
		active_opacity   = 1.0,
		inactive_opacity = 1.0,
		-- previous attempt kept picom-like depth: shadow + blur on
		shadow = {
			enabled      = true,
			range        = 4,
			render_power = 3,
			color        = "rgba(1a1a1aee)",
		},
		blur = {
			enabled  = true,
			size     = 3,
			passes   = 1,
			vibrancy = 0.1696,
		},
	},

	input = {
		kb_layout  = "fr",                  -- setxkbmap fr
		kb_options = "lv3:caps_switch",     -- setxkbmap -option lv3:caps_switch
		-- NOTE: the previous attempt had these inverted (75/250); sxhkd used
		-- xset r rate 250 75 = 250 ms delay, 75 repeats/s
		repeat_rate  = 75,
		repeat_delay = 250,
		numlock_by_default = true,          -- numlockx on
		follow_mouse = 2,                   -- previous attempt tuning (was 0 here)
		float_switch_override_focus = 0,
		-- what to focus when the focused window closes:
		--   1 = window under the cursor (the wrong-monitor trap),
		--   2 = most recently focused window of the workspace (bspwm-like).
		-- Empty-workspace closes are handled by lua/extensions/close_refocus.lua.
		focus_on_close = 2,
		sensitivity = 0,
		touchpad = { natural_scroll = false },
	},

	cursor = {
		no_warps = true,                    -- previous attempt
		default_monitor = PC == "mainpc" and M2 or "",
	},

	misc = {
		force_default_wallpaper = -1,
		disable_hyprland_logo = false,
		mouse_move_focuses_monitor = false, -- previous attempt
		key_press_enables_dpms = true,      -- wake on key press with dpms off
	},
})

-- hide cursor after 3s on laptop (unclutter -t 3); lives under cursor:,
-- not misc:, in v0.56.2
hl.config({ cursor = { inactive_timeout = PC == "laptop" and 3 or 0 } })

-- Config reload workaround (Hyprland v0.56.2): a reload closes the Lua state and
-- re-registers the layout, but workspaces keep their old layout instance when the
-- layout name is unchanged -- that instance is bound to the dead provider and
-- falls back to a plain grid (windows side by side). See lua/extensions/bspwm.lua: the layout
-- is registered under two names; flip to the one the workspaces are NOT using so
-- they all get a fresh instance. lua/extensions/bspwm.lua restores the session checkpoint
-- before registration, preserving the tree/ratios while targets are reattached.
hl.on("config.reloaded", function()
	local ws  = hl.get_active_workspace()
	local cur = ws and ws.tiled_layout or nil
	if cur == "lua:bspwm" then
		hl.config({ general = { layout = "lua:bspwm_b" } })
	elseif cur == "lua:bspwm_b" then
		hl.config({ general = { layout = "lua:bspwm" } })
	end -- anything else (first start: no workspace yet): keep the configured layout
end)

require("lua/animations") -- animation settings + curves

-- env (from the previous attempt)
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("XCURSOR_THEME", "capitaine-cursors")
hl.env("QT_FONT_DPI", "120")

require("lua/autostart") -- startup commands

-- hyprctl setcursor is superseded by XCURSOR_THEME/XCURSOR_SIZE env above

-- wallpaper: ~/.wall lock -> hyprpaper config (~/.config/hypr/hyprpaper.conf):
--   splash = false
--   ipc = on
--   preload = /path/to/wall.jpg
--   wallpaper = ,/path/to/wall.jpg

-- lock: ~/bin/lock + ~/bin/blurlock -> hyprlock, driven by hypridle:
--   ~/.config/hypr/hypridle.conf:
--     general { after_resume_cmd = ... ; }
--     listener { timeout = 900; on-timeout = hyprlock; }

-- ---------------------------------------------------------------------------
-- rules + bindings (each in its own module)
-- ---------------------------------------------------------------------------

require("lua/rules")           -- window/workspace rules + monitor->tag assignment
require("lua/bindings")        -- keybindings
require("lua/extensions/close_refocus")   -- keep the right monitor focused when a workspace empties
