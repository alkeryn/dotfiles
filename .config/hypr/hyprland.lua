-- hyprland.lua -- alkeryn's bspwm-style rice, ported to Hyprland v0.56.2
-- ============================================================================
-- Migration from ~/.config/bspwm/bspwmrc + sxhkd. Every bind carries a comment
-- with the bspwm original it replaces.
--
-- Requirements (replaces the X11 stack):
--   hyprpaper hypridle hyprlock waybar dunst grim slurp wl-clipboard cliphist
--   rofi (wayland build) alacritty brightnessctl playerctl pactl ckb-next
--   conky (XWayland) megasync signal-desktop mpd mpDris2
--
-- Fill M1/M2 below with your real output names (hyprctl monitors all -j).
-- PC is auto-detected from /etc/hostname, like ~/bin/wpc did with $PC.
-- ============================================================================

require("bspwm") -- registers the "lua:bspwm" layout

-- ---------------------------------------------------------------------------
-- machine detection (replaces ~/bin/wpc + $PC)
-- ---------------------------------------------------------------------------

local PC = "mainpc"
do
	local f = io.open("/etc/hostname", "r")
	if f then
		local host = f:read("*l") or ""
		f:close()
		if host:find("laptop") or host:find("nomad") then PC = "laptop" end
	end
end

local GAPS   = 4   -- previous attempt: gaps_in 4, gaps_out 8 (bspwm window_gap 8)
local GAPS_OUT = 8
local BORDER = PC == "mainpc" and 1 or 2    -- bspwm border_width
local FLOAT_STEP = PC == "mainpc" and 20 or 40

-- monitor names from the hyprland-branch attempt (real hardware)
-- left: HDMI-A-2 (4K), main: DP-4 (4K@244, 10bit, HDR)
local M1 = "HDMI-A-2"   -- left:      tags 1-4
local M2 = "DP-4"       -- main:      tags 5-10

-- ---------------------------------------------------------------------------
-- monitors + HDR (tuned on the previous attempt)
-- ---------------------------------------------------------------------------
-- Previous attempt kept the output SDR by default and relied on
-- render:cm_auto_hdr to flip HDR when a fullscreen app requests it -- so the
-- SDR desktop never pays an HDR penalty. supports_hdr/supports_wide_color=1
-- force-enables the EDID capability claims (use -1 = trust EDID if unsure).
-- Fractional scales were rejected on that attempt ("blurry mess"): scale stays
-- 1, xwayland force_zero_scaling + QT_FONT_DPI compensate instead.

local function add_monitor(opts)
	if PC == "mainpc" then
		hl.monitor({
			output             = M1,
			mode               = "3840x2160",
			position           = "0x0",
			scale              = 1,
		})
		hl.monitor({
			output             = M2,
			mode               = "3840x2160@244",
			position           = "3840x0",
			scale              = 1,
			bitdepth           = 10,
			supports_wide_color = 1,
			supports_hdr       = 1,
			-- sdrbrightness = 1.2, -- raise if SDR looks dim under HDR output
		})
	else
		hl.monitor(opts)
	end
end

add_monitor({ output = M1, mode = "preferred", position = "auto", scale = 1 })
add_monitor({ output = M2, mode = "preferred", position = "auto-left", scale = 1 })

hl.config({
	render = {
		cm_enabled = true,
		cm_auto_hdr = 1,      -- auto HDR when a fullscreen app requests it
		direct_scanout = 1,   -- previous attempt: direct_scanout = true
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

	-- previous attempt: animations off except workspace fade
	animations = {
		enabled = true,
	},

	input = {
		kb_layout  = "fr",                  -- setxkbmap fr
		kb_options = "lv3:caps_switch",     -- setxkbmap -option lv3:caps_switch
		-- NOTE: the previous attempt had these inverted (75/250); sxhkd used
		-- xset r rate 250 75 = 250 cps, 75 ms delay
		repeat_rate  = 250,
		repeat_delay = 75,
		numlock_by_default = true,          -- numlockx on
		follow_mouse = 2,                   -- previous attempt tuning (was 0 here)
		float_switch_override_focus = 0,
		sensitivity = 0,
		touchpad = { natural_scroll = false },
	},

	cursor = {
		no_warps = true,                    -- previous attempt
		default_monitor = M2,
	},

	misc = {
		force_default_wallpaper = -1,
		disable_hyprland_logo = false,
		mouse_move_focuses_monitor = false, -- previous attempt
		key_press_enables_dpms = true,      -- wake on key press with dpms off
		cursor_inactive_timeout = PC == "laptop" and 3 or 0, -- unclutter -t 3
	},
})

-- env (from the previous attempt)
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("XCURSOR_THEME", "capitaine-cursors")
hl.env("QT_FONT_DPI", "120")

-- ---------------------------------------------------------------------------
-- autostart (replaces ~/.config/bspwm/scripts/autostart)
-- ---------------------------------------------------------------------------

hl.on("hyprland.start", function()
	hl.exec_cmd("hypridle")                                   -- xss-lock/dpms
	-- hl.exec_cmd("hyprpaper")                                  -- ~/.fehbg
	-- hl.exec_cmd("waybar")                                     -- polybar/launch.sh
	-- hl.exec_cmd("dunst")                                      -- notification daemon
	-- hl.exec_cmd("wl-paste --watch cliphist store")            -- clipboard history

	-- from the previous attempt's autorun.conf
	if PC == "mainpc" then
		hl.exec_cmd("ckb-next -b")
		-- hl.exec_cmd("conky -q")                               -- XWayland
		hl.exec_cmd("signal-desktop")
		-- last-window-close refocus bug workaround (socket2 watcher).
		-- Still relevant in v0.56.2: when a workspace empties, focus falls
		-- back to cursor position (InputManager::refocus), which can land on
		-- the wrong monitor. Drop this script if the bug proves fixed.

		-- hl.exec_cmd("$HOME/.config/hypr/scripts/close_refocus_fix")
	else
		hl.exec_cmd("signal-desktop")
	end
	hl.exec_cmd("xrdb -merge ~/.Xresources")                  -- XWayland resources
	hl.exec_cmd("sh -c 'pkill -x mpd; mpd; mpDris2'")
	-- hl.exec_cmd("nm-applet")
	-- hl.exec_cmd("megasync")
end)

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
-- focus history (super + {parenright,equal} -> older/newer)
-- ---------------------------------------------------------------------------

local function focus_history(step)
	local wins = hl.query.get_windows() or {}
	if #wins < 2 then return end
	table.sort(wins, function(a, b)
		return (a.focus_history_id or 0) < (b.focus_history_id or 0)
	end)
	local cur = hl.query.get_active_window()
	local idx
	for i, w in ipairs(wins) do
		if cur and w.address == cur.address then idx = i break end
	end
	if not idx then return end
	local t = wins[((idx - 1 + step) % #wins) + 1]
	if t then hl.dsp.focus({ window = "address:" .. t.address })() end
end

local function focus_last()
	local w = hl.query.get_last_window()
	if w then hl.dsp.focus({ window = "address:" .. w.address })() end
end

-- ---------------------------------------------------------------------------
-- focus / swap helpers with bspwm-style fallbacks
-- ---------------------------------------------------------------------------

local DIRFULL = { l = "left", r = "right", u = "up", d = "down" }

local function focus_dir(d)
	local ok = hl.dsp.focus({ direction = DIRFULL[d] })()
	if not ok then hl.dsp.focus({ monitor = d })() end
end

local function swap_dir(d)
	-- bspc node -s "$A" --follow (tree-aware swap in the bspwm layout);
	-- fallback: bspc node -d "$A":focused --follow
	local ok = hl.dsp.layout("swap " .. d)()
	if not ok then
		if d == "l" then hl.dsp.window.move({ workspace = "m-1" })()
		elseif d == "r" then hl.dsp.window.move({ workspace = "m+1" })() end
	end
end

-- ---------------------------------------------------------------------------
-- workspace swap helpers (bspc desktop -s)
-- ---------------------------------------------------------------------------

local function swap_with_workspace(sel)
	local cur = hl.query.get_active_workspace()
	local tgt = hl.query.get_workspace(sel)
	if not cur or not tgt or cur.id == tgt.id then return end
	for _, w in ipairs(tgt.windows or {}) do
		hl.dsp.window.move({ workspace = cur.id, follow = false, window = "address:" .. w.address })()
	end
	for _, w in ipairs(cur.windows or {}) do
		hl.dsp.window.move({ workspace = tgt.id, follow = false, window = "address:" .. w.address })()
	end
end

local function swap_workspace_rel(rel)
	local cur = hl.query.get_active_workspace()
	if cur then swap_with_workspace(cur.id + rel) end
end

-- ---------------------------------------------------------------------------
-- per-desktop gap presets (bspc config -d focused window_gap)
-- ---------------------------------------------------------------------------
-- Hyprland gaps are global here (Next/Prior adjust, BackSpace resets to 0,
-- shift+BackSpace restores the default). Per-workspace gaps are possible via
-- hl.workspace_rule({ workspace = "N", gaps_in = X }) at runtime, at the cost
-- of rule churn; global was chosen for predictability.

local function set_gaps(v)
	hl.config({ general = { gaps_in = v, gaps_out = v } })
end

-- ---------------------------------------------------------------------------
-- monitor layout (docked laptop detection, replaces the xrandr branch)
-- ---------------------------------------------------------------------------

local function apply_monitor_layout()
	local mons = hl.query.get_monitors() or {}
	if PC == "mainpc" or #mons > 1 then
		-- docked: 1-4 on primary, 5-10 on secondary
		for i = 1, 4 do
			hl.workspace_rule({ workspace = tostring(i), monitor = M1, persistent = true })
		end
		for i = 5, 10 do
			hl.workspace_rule({ workspace = tostring(i), monitor = M2, persistent = true })
		end
	elseif PC == "laptop" then
		for i = 1, 10 do
			hl.workspace_rule({ workspace = tostring(i), monitor = #mons > 0 and mons[1].name or "", persistent = true })
		end
	end
end

apply_monitor_layout() -- static registration at startup (mainpc / docked)
hl.on("monitor.added", function() apply_monitor_layout() end)
hl.on("monitor.removed", function() apply_monitor_layout() end)

-- ---------------------------------------------------------------------------
-- window rules (bspc rule translation + previous attempt's rules.conf)
-- ---------------------------------------------------------------------------

-- smart gaps / no gaps when only (from the previous attempt's rules.conf)
hl.workspace_rule({ workspace = "w[tv1]", gaps_in = 0, gaps_out = 0 })
hl.workspace_rule({ workspace = "f[1]",   gaps_in = 0, gaps_out = 0 })
hl.window_rule({
	name        = "no-gaps-wtv1",
	match       = { float = false, workspace = "w[tv1]" },
	border_size = 0,
	rounding    = 0,
})
hl.window_rule({
	name        = "no-gaps-f1",
	match       = { float = false, workspace = "f[1]" },
	border_size = 0,
	rounding    = 0,
})

-- ignore maximize requests from all apps (previous attempt kept this)
hl.window_rule({
	name           = "suppress-maximize-events",
	match          = { class = ".*" },
	suppress_event = "maximize",
})

hl.window_rule({
	name  = "fix-xwayland-drags",
	match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
	no_focus = true,
})

-- alacritty --class=floating
hl.window_rule({
	name  = "alacritty-floating",
	match = { class = "^floating$" },
	float = true,
})

local rules_app = {
	{ class = "Lxappearance",       float = true },
	{ class = "Pavucontrol",        float = true },
	{ class = "MEGAsync",           float = true },
	{ class = "vscode-color-ui",    float = true },
	{ class = "Gimp%-2%.8",         float = true, workspace = "8" },
	{ class = "VESC Tool",          workspace = "8" },
	{ class = "Ethereum Wallet",    float = true, workspace = "3" },
	{ class = "Ethereumwallet",     float = true, workspace = "3" },
	{ class = "looking%-glass%-client", workspace = "8" },
	{ class = "Zathura",            tile = true },
	-- bspc rule -a Screenkey manage=off: closest approximation
	{ class = "Screenkey",          float = true, pin = true, no_focus = true },
}

local function register_app_rules()
	-- per-PC workspace assignments
	if PC == "mainpc" then
		table.insert(rules_app, { class = "discord",       workspace = "1" })
		table.insert(rules_app, { class = "Signal",        workspace = "1" })
		table.insert(rules_app, { class = "skypeforlinux", workspace = "1" })
		table.insert(rules_app, { class = "qBittorrent",   workspace = "2" })
	else
		table.insert(rules_app, { class = "discord",       workspace = "10" })
		table.insert(rules_app, { class = "skypeforlinux", workspace = "10" })
		table.insert(rules_app, { class = "qBittorrent",   workspace = "9" })
	end
	for i, r in ipairs(rules_app) do
		hl.window_rule({
			name      = "app-" .. i .. "-" .. (r.class or ""),
			match     = { class = r.class },
			float     = r.float,
			tile      = r.tile,
			pin       = r.pin,
			no_focus  = r.no_focus,
			workspace = r.workspace,
		})
	end
end

register_app_rules()

-- ---------------------------------------------------------------------------
-- keybindings (sxhkdrc translation; French azerty keysyms are unchanged)
-- ---------------------------------------------------------------------------

-- Screenshot (maim/scrot -> grim/slurp)
hl.bind("SUPER + Print",          hl.dsp.exec_cmd("grim -g \"$(slurp -b 50000055 -c bb0000)\" - | wl-copy"))
hl.bind("SUPER + SHIFT + Print",  hl.dsp.exec_cmd("grim -g \"$(slurp -b 50000055 -c bb0000)\" ~/Images/scrot/$(date +%Y%m%d_%H%M%S).png"))
hl.bind("SUPER + CTRL + Print",   hl.dsp.exec_cmd("grim ~/Images/scrot/$(date +%Y%m%d_%H%M%S).png"))

-- pipe clipboard (xclip socket -> cliphist; adapted)
hl.bind("SUPER + z",              hl.dsp.exec_cmd("wl-paste | cliphist store"))
hl.bind("SUPER + SHIFT + z",      hl.dsp.exec_cmd("cliphist decode | wl-copy"))

-- Lock
hl.bind("SUPER + a",              hl.dsp.exec_cmd("sh ~/bin/lock"))

-- Terminal (previous attempt: alacritty font bumped to 11 on hyprland to
-- match bspwm's 9pt physical size at scale 1 on 4K)
local terminal = "alacritty --option font.size=11"
hl.bind("SUPER + space",          hl.dsp.exec_cmd(terminal))
hl.bind("SUPER + ALT + space",    hl.dsp.exec_cmd(terminal .. " --class floating"))

-- Music
hl.bind("SUPER + p",              hl.dsp.exec_cmd(terminal .. " -e ncmpcpp"))

-- Rofi
hl.bind("SUPER + Return",         hl.dsp.exec_cmd("rofi -terminal alacritty -show drun"))
hl.bind("SUPER + CTRL + Return",  hl.dsp.exec_cmd("rofi -terminal alacritty -show run"))
hl.bind("SUPER + ALT + Return",   hl.dsp.exec_cmd("rofi -terminal alacritty -modi emoji -show emoji"))
hl.bind("SUPER + SHIFT + Return", hl.dsp.exec_cmd("rofi -terminal alacritty -modi calc -show calc -no-show-match -no-sort"))
hl.bind("SUPER + Tab",            hl.dsp.exec_cmd("rofi -show window"))

-- Ranger
hl.bind("SUPER + e",              hl.dsp.exec_cmd("bash -c 'source ~/bin/shell/env; " .. terminal .. " -e ranger'"))

-- Sound / media
hl.bind("XF86AudioStop",          hl.dsp.exec_cmd("playerctl -p playerctld pause"), { locked = true })
hl.bind("XF86AudioPrev",          hl.dsp.exec_cmd("playerctl -p playerctld previous"), { locked = true })
hl.bind("XF86AudioPlay",          hl.dsp.exec_cmd("playerctl -p playerctld play-pause"), { locked = true })
hl.bind("XF86AudioNext",          hl.dsp.exec_cmd("playerctl -p playerctld next"), { locked = true })
hl.bind("SHIFT + XF86AudioPlay",  hl.dsp.exec_cmd("playerctl -a pause"), { locked = true })
hl.bind("XF86AudioRaiseVolume",   hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ +4%"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",   hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ -4%"), { locked = true, repeating = true })
hl.bind("XF86AudioMute",          hl.dsp.exec_cmd("pactl set-sink-mute @DEFAULT_SINK@ toggle"), { locked = true })
hl.bind("SUPER + XF86AudioMute",  hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ 100%"), { locked = true })

-- Backlight (light kept; swap to brightnessctl if udev perms annoy you)
hl.bind("XF86MonBrightnessDown",  hl.dsp.exec_cmd("light -U 10"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp",    hl.dsp.exec_cmd("light -A 10"), { locked = true, repeating = true })

-- wifi toggle
hl.bind("SUPER + F12",            hl.dsp.exec_cmd("~/bin/wifitoggle"))

-- reload config (sxhkd super+Escape dance; Hyprland hot-reloads lua anyway)
hl.bind("SUPER + Escape",         hl.dsp.reload_config())

-- keyboard layouts (setxkbmap {fr, us altgr-intl, ru, us colemak})
local layouts = {
	{ key = "F1", layout = "fr", variant = "" },
	{ key = "F2", layout = "us", variant = "altgr-intl" },
	{ key = "F3", layout = "ru", variant = "" },
	{ key = "F4", layout = "us", variant = "colemak" },
}
for _, l in ipairs(layouts) do
	hl.bind("SUPER + " .. l.key, function()
		hl.config({ input = { kb_layout = l.layout, kb_variant = l.variant, repeat_rate = 250, repeat_delay = 75 } })
	end)
end

-- quit bspwm / close and kill
hl.bind("SUPER + CTRL + ALT + Escape", hl.dsp.exit())
hl.bind("SUPER + x",                   hl.dsp.window.close())
hl.bind("SUPER + SHIFT + x",           hl.dsp.window.kill())

-- alternate between the tiled and monocle layout (bspc desktop -l next)
hl.bind("SUPER + v",                   hl.dsp.layout("mode"))

-- automatic <-> last manual / pull last leaf (super+y)
hl.bind("SUPER + y",                   hl.dsp.layout("pull"))

-- Rotate (bspc node -R {90,270})
hl.bind("SUPER + r",                   hl.dsp.layout("rotate 90"))
hl.bind("SUPER + SHIFT + r",           hl.dsp.layout("rotate 270"))

-- Flip (bspc node -F {horizontal,vertical})
hl.bind("SUPER + u",                   hl.dsp.layout("flip h"))
hl.bind("SUPER + i",                   hl.dsp.layout("flip v"))

-- Balance Tree (bspc node @/ {-B,-E})
hl.bind("SUPER + ALT + b",             hl.dsp.layout("balance"))
hl.bind("SUPER + CTRL + b",            hl.dsp.layout("equalize"))

-- set the window state (bspc node -t {tiled,floating,fullscreen,pseudo_tiled})
hl.bind("SUPER + s",                   hl.dsp.window.float({ action = "off" }))
hl.bind("SUPER + d",                   hl.dsp.window.float({ action = "toggle" }))
hl.bind("SUPER + f",                   hl.dsp.window.fullscreen())
hl.bind("SUPER + t",                   hl.dsp.window.pseudo())

-- set the node flags
-- bspc node -g locked  -> no equivalent (unavailable)
hl.bind("SUPER + CTRL + x",            hl.dsp.window.pin())          -- -g sticky
-- bspc node -g private -> no equivalent (unavailable)
-- bspc node -g urgent  -> no equivalent (client-driven only)

-- Focus/swap (bspc node -f/-s west|south|north|east + monitor fallback)
-- previous attempt used binde (hold-to-repeat) on these
for d, key in pairs({ h = "h", j = "j", k = "k", l = "l" }) do
	hl.bind("SUPER + " .. key, function() focus_dir(d) end, { repeating = true })
	hl.bind("SUPER + SHIFT + " .. key, function() swap_dir(d) end, { repeating = true })
end

-- focus the node for the given path jump (bspc node -f @{parent,brother,first,second})
hl.bind("SUPER + b",                   hl.dsp.layout("focus parent"))
hl.bind("SUPER + n",                   hl.dsp.layout("focus brother"))
hl.bind("SUPER + colon",               hl.dsp.layout("focus first"))
hl.bind("SUPER + exclam",              hl.dsp.layout("focus second"))

-- focus last (bspc node -f last / bspc {node,desktop} -f last)
hl.bind("SUPER + q",                   focus_last)
hl.bind("ALT + twosuperior",           focus_last)
hl.bind("ALT + Tab",                   hl.dsp.focus({ workspace = "previous_per_monitor" }))

-- focus the next/previous node in the current desktop
hl.bind("SUPER + c",                   hl.dsp.window.cycle_next())
hl.bind("SUPER + ALT + c",             hl.dsp.window.cycle_next({ next = false }))

-- focus/send/swap next/prev desktop (dead_circumflex / dollar)
hl.bind("SUPER + dead_circumflex",              hl.dsp.focus({ workspace = "m-1" }))
hl.bind("SUPER + dollar",                       hl.dsp.focus({ workspace = "m+1" }))
hl.bind("SUPER + SHIFT + dead_circumflex",      hl.dsp.window.move({ workspace = "m-1", follow = true }))
hl.bind("SUPER + SHIFT + dollar",               hl.dsp.window.move({ workspace = "m+1", follow = true }))
hl.bind("SUPER + ALT + dead_circumflex",        function() swap_workspace_rel(-1) end)
hl.bind("SUPER + ALT + dollar",                 function() swap_workspace_rel(1) end)

-- focus the older or newer node in the focus history
hl.bind("SUPER + parenright",          function() focus_history(-1) end) -- older
hl.bind("SUPER + equal",               function() focus_history(1) end)  -- newer

-- focus or send to the given desktop (super + number row, azerty)
local NUM_KEYS = { "ampersand", "eacute", "quotedbl", "apostrophe", "parenleft",
	"minus", "egrave", "underscore", "ccedilla", "agrave" }
for i, key in ipairs(NUM_KEYS) do
	local ws = tostring(i == 10 and 10 or i)
	hl.bind("SUPER + " .. key,            hl.dsp.focus({ workspace = ws }))
	hl.bind("SUPER + SHIFT + " .. key,    hl.dsp.window.move({ workspace = ws, follow = true }))
	hl.bind("SUPER + ALT + " .. key,      function() swap_with_workspace(ws) end)
end

-- Layer (bspc node -l {below,normal,above} -> above only)
hl.bind("SUPER + SHIFT + m",           hl.dsp.window.bring_to_top())

-- Preselect the direction (bspc node -p {west,south,north,east})
hl.bind("SUPER + CTRL + h",            hl.dsp.layout("preselect l"))
hl.bind("SUPER + CTRL + j",            hl.dsp.layout("preselect d"))
hl.bind("SUPER + CTRL + k",            hl.dsp.layout("preselect u"))
hl.bind("SUPER + CTRL + l",            hl.dsp.layout("preselect r"))

-- preselect the ratio (bspc node -o 0.{1-9})
local RATIO_KEYS = { "ampersand", "eacute", "quotedbl", "apostrophe", "parenleft",
	"minus", "egrave", "underscore", "ccedilla" }
for i, key in ipairs(RATIO_KEYS) do
	hl.bind("SUPER + CTRL + " .. key,     hl.dsp.layout("pratio 0." .. i))
end

-- cancel preselection (node / desktop)
hl.bind("SUPER + CTRL + space",              hl.dsp.layout("preselect cancel"))
hl.bind("SUPER + CTRL + SHIFT + space",      hl.dsp.layout("preselect clear"))

-- Move/resize (bspc node -z / -v)
-- previous attempt used resizeactiveedge (removed in v0.56.2); the bspwm
-- layout's grow/shrink adjusts the owning ancestor split instead
local RESIZE_KEYS = { h = "l", j = "d", k = "u", l = "r" }
for key, d in pairs(RESIZE_KEYS) do
	hl.bind("SUPER + ALT + " .. key,            hl.dsp.layout("grow " .. d .. " 20"), { repeating = true })
	hl.bind("SUPER + ALT + CTRL + " .. key,     hl.dsp.layout("shrink " .. d .. " 20"), { repeating = true })
end

-- move a floating window
hl.bind("SUPER + left",          hl.dsp.window.move({ x = -FLOAT_STEP, y = 0, relative = true }))
hl.bind("SUPER + right",         hl.dsp.window.move({ x = FLOAT_STEP, y = 0, relative = true }))
hl.bind("SUPER + up",            hl.dsp.window.move({ x = 0, y = -FLOAT_STEP, relative = true }))
hl.bind("SUPER + down",          hl.dsp.window.move({ x = 0, y = FLOAT_STEP, relative = true }))

-- gaps (per-desktop in bspwm; global here, see note above)
hl.bind("SUPER + Next",          function() set_gaps(math.max(0, GAPS + 5)) end)
hl.bind("SUPER + Prior",         function() set_gaps(math.max(0, GAPS - 5)) end)
hl.bind("SUPER + BackSpace",     function() set_gaps(GAPS) end)
hl.bind("SUPER + SHIFT + BackSpace", function() set_gaps(0) end)

-- Transplant (bspc node -n @/)
hl.bind("SUPER + SHIFT + t",     hl.dsp.layout("transplant"))

-- Sounds (unchanged)
local SOUNDS = {
	[""] = { { "KP_Prior", "NeinNein" }, { "KP_Up", "miaou" }, { "KP_Home", "Popopo" },
		{ "KP_Right", "YES" }, { "KP_Begin", "Issou" }, { "KP_Left", "Jeff" },
		{ "KP_Next", "PickleRick" }, { "KP_Down", "AH" }, { "KP_End", "Nils" } },
	["SHIFT + "] = { { "KP_Prior", "RickRoll" }, { "KP_Up", "Lol" }, { "KP_Home", "Jurassic" },
		{ "KP_Right", "Interject" }, { "KP_Begin", "Fuck" }, { "KP_Left", "FuckedUp" },
		{ "KP_Next", "Cena" }, { "KP_Down", "ShootingStars" }, { "KP_End", "Souffrir" },
		{ "KP_Insert", "Colere" } },
	["ALT + "] = { { "KP_Prior", "DAMN" }, { "KP_Up", "Malou" }, { "KP_Home", "Weee" },
		{ "KP_Right", "Skrattar" } },
}
for mods, list in pairs(SOUNDS) do
	for _, s in ipairs(list) do
		hl.bind("SUPER + " .. mods .. s[1],
			hl.dsp.exec_cmd("paplay ~/Cloud/Mega/zPC/Sounds/" .. s[2] .. ".wav &"))
	end
end
hl.bind("SUPER + KP_Insert",     hl.dsp.exec_cmd("pkill paplay"))

-- mouse: move/resize. Previous attempt swapped windows by dragging
-- (bindm swapwindow) -- that mouse mode no longer exists in v0.56.2
-- (MBIND is move/resize only), so SUPER-drag now moves like stock.
hl.bind("SUPER + mouse:272",     hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + CTRL + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273",     hl.dsp.window.resize(), { mouse = true })

-- mouse scroll workspace nav (from previous attempt)
hl.bind("SUPER + mouse_down",    hl.dsp.focus({ workspace = "e+1" }))
hl.bind("SUPER + mouse_up",      hl.dsp.focus({ workspace = "e-1" }))
