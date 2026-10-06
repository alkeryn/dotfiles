-- bindings.lua -- keybindings
-- ============================================================================
-- Module: registers all binds. Requires lua/vars + lua/helpers.
-- (sxhkdrc translation; French azerty keysyms are unchanged; every bind
-- carries a comment with the bspwm original it replaces)
-- ============================================================================

-- NOTE: require paths resolve against the MAIN config dir (~/.config/hypr),
-- not this file's location (package.path is prepended with <mainconfigdir>/?.lua
-- by the Lua config manager). Modules living in lua/ must therefore be
-- required as "lua/<name>" everywhere, including between themselves.
local vars    = require("lua/vars")
local helpers = require("lua/helpers")

local FLOAT_STEP = vars.FLOAT_STEP
local terminal   = vars.terminal

-- Screenshot (maim/scrot -> grim/slurp)
hl.bind("SUPER + Print",          hl.dsp.exec_cmd("grim -g \"$(slurp -b 50000055 -c bb0000)\" - | wl-copy"))
hl.bind("SUPER + SHIFT + Print",  hl.dsp.exec_cmd("grim -g \"$(slurp -b 50000055 -c bb0000)\" ~/Images/scrot/$(date +%Y%m%d_%H%M%S).png"))
hl.bind("SUPER + CTRL + Print",   hl.dsp.exec_cmd("grim ~/Images/scrot/$(date +%Y%m%d_%H%M%S).png"))

-- pipe clipboard (xclip socket -> cliphist; adapted)
hl.bind("SUPER + z",              hl.dsp.exec_cmd("wl-paste | cliphist store"))
hl.bind("SUPER + SHIFT + z",      hl.dsp.exec_cmd("cliphist decode | wl-copy"))

-- Lock
hl.bind("SUPER + a",              hl.dsp.exec_cmd("hyprlock"))  -- was: sh ~/bin/lock (scrot+i3lock, X11 only)

-- Binds marked { repeating = true } fire again while held (keyboard repeat:
-- input.repeat_delay / input.repeat_rate). sxhkd did this for every key; the
-- previous attempt kept it (binde) on the terminal/file manager, focus, swap,
-- preselect, workspace move, close/kill and resize binds -- same set here.

-- Terminal
hl.bind("SUPER + space",          hl.dsp.exec_cmd(terminal), { repeating = true })
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
hl.bind("SUPER + e",              hl.dsp.exec_cmd("bash -c 'source ~/bin/shell/env; " .. terminal .. " -e ranger'"), { repeating = true })

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

-- Reload without discarding the tree. Mutations are also checkpointed for
-- automatic file reloads; the shortcut flushes once more before hyprctl reload.
hl.bind("SUPER + Escape",         require("lua/bspwm").reload)

-- keyboard layouts (setxkbmap {fr, us altgr-intl, ru, us colemak})
local layouts = {
	{ key = "F1", layout = "fr", variant = "" },
	{ key = "F2", layout = "us", variant = "altgr-intl" },
	{ key = "F3", layout = "ru", variant = "" },
	{ key = "F4", layout = "us", variant = "colemak" },
}
for _, l in ipairs(layouts) do
	hl.bind("SUPER + " .. l.key, function()
		hl.config({ input = { kb_layout = l.layout, kb_variant = l.variant, repeat_rate = 75, repeat_delay = 250 } })
	end)
end

-- quit bspwm / close and kill
-- Super+x closes the selected subtree, or just the focused window otherwise.
-- Plain Ctrl+x is left to applications; Super+Ctrl+x below still pins.
hl.bind("SUPER + CTRL + ALT + Escape", hl.dsp.exit())
hl.bind("SUPER + x",                   require("lua/bspwm").close, { repeating = true })
hl.bind("SUPER + SHIFT + x",           hl.dsp.window.kill(), { repeating = true })

-- alternate between the tiled and monocle layout (bspc desktop -l next)
hl.bind("SUPER + v",                   hl.dsp.layout("mode"))

-- send to last preselection, otherwise pull last focused leaf (global history)
-- Across desktops/monitors; focus the inserted node after the move completes.
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
local DIRS = { h = { "left", "l" }, j = { "down", "d" }, k = { "up", "u" }, l = { "right", "r" } }
for key, dir in pairs(DIRS) do
	hl.bind("SUPER + " .. key,           hl.dsp.focus({ direction = dir[1] }), { repeating = true })
	hl.bind("SUPER + SHIFT + " .. key,   function() helpers.swap_dir(dir[2]) end, { repeating = true })
end

-- focus the node for the given path jump (bspc node -f @{parent,brother,first,second})
hl.bind("SUPER + b",                   hl.dsp.layout("focus parent"), { repeating = true })
hl.bind("SUPER + n",                   hl.dsp.layout("focus brother"), { repeating = true })
hl.bind("SUPER + colon",               hl.dsp.layout("focus first"), { repeating = true })
hl.bind("SUPER + exclam",              hl.dsp.layout("focus second"), { repeating = true })

-- focus last (bspc node -f last / bspc {node,desktop} -f last)
hl.bind("SUPER + q",                   helpers.focus_last)
hl.bind("ALT + twosuperior",           helpers.focus_last)
hl.bind("ALT + Tab",                   hl.dsp.focus({ workspace = "previous_per_monitor" }))

-- focus the next/previous node in the current desktop
hl.bind("SUPER + c",                   hl.dsp.window.cycle_next())
hl.bind("SUPER + ALT + c",             hl.dsp.window.cycle_next({ next = false }))

-- focus/send/swap next/prev desktop (dead_circumflex / dollar)
hl.bind("SUPER + dead_circumflex",              hl.dsp.focus({ workspace = "m-1" }), { repeating = true })
hl.bind("SUPER + dollar",                       hl.dsp.focus({ workspace = "m+1" }), { repeating = true })
hl.bind("SUPER + SHIFT + dead_circumflex",      hl.dsp.window.move({ workspace = "m-1", follow = true }), { repeating = true })
hl.bind("SUPER + SHIFT + dollar",               hl.dsp.window.move({ workspace = "m+1", follow = true }), { repeating = true })
hl.bind("SUPER + ALT + dead_circumflex",        function() helpers.swap_workspace_rel(-1) end)
hl.bind("SUPER + ALT + dollar",                 function() helpers.swap_workspace_rel(1) end)

-- focus the older or newer node in the focus history
hl.bind("SUPER + parenright",          function() helpers.focus_history(-1) end) -- older
hl.bind("SUPER + equal",               function() helpers.focus_history(1) end)  -- newer

-- focus or send to the given desktop (super + number row, azerty)
local NUM_KEYS = { "ampersand", "eacute", "quotedbl", "apostrophe", "parenleft",
	"minus", "egrave", "underscore", "ccedilla", "agrave" }
for i, key in ipairs(NUM_KEYS) do
	local ws = tostring(i == 10 and 10 or i)
	hl.bind("SUPER + " .. key,            hl.dsp.focus({ workspace = ws }))
	hl.bind("SUPER + SHIFT + " .. key,    hl.dsp.window.move({ workspace = ws, follow = true }))
	hl.bind("SUPER + ALT + " .. key,      function() helpers.swap_with_workspace(ws) end)
end

-- Layer (bspc node -l {below,normal,above} -> above only)
hl.bind("SUPER + SHIFT + m",           hl.dsp.window.bring_to_top())

-- Preselect the direction (bspc node -p {west,south,north,east})
hl.bind("SUPER + CTRL + h",            hl.dsp.layout("preselect l"), { repeating = true })
hl.bind("SUPER + CTRL + j",            hl.dsp.layout("preselect d"), { repeating = true })
hl.bind("SUPER + CTRL + k",            hl.dsp.layout("preselect u"), { repeating = true })
hl.bind("SUPER + CTRL + l",            hl.dsp.layout("preselect r"), { repeating = true })

-- preselect the ratio (bspc node -o 0.{1-9})
local RATIO_KEYS = { "ampersand", "eacute", "quotedbl", "apostrophe", "parenleft",
	"minus", "egrave", "underscore", "ccedilla" }
for i, key in ipairs(RATIO_KEYS) do
	hl.bind("SUPER + CTRL + " .. key,     hl.dsp.layout("pratio 0." .. i))
end

-- cancel preselection (node / desktop)
hl.bind("SUPER + CTRL + space",              hl.dsp.layout("preselect cancel"), { repeating = true })
hl.bind("SUPER + CTRL + SHIFT + space",      hl.dsp.layout("preselect clear"))

-- Move/resize (bspc node -z / -v)
-- The key specifies the direction the edge MOVES: h grows the left edge
-- outward, Ctrl+h shrinks the RIGHT edge inward. Match sxhkd on tiles AND floats.
local resize_keys = { h = { "l", "r" }, j = { "d", "u" }, k = { "u", "d" }, l = { "r", "l" } }
for key, edges in pairs(resize_keys) do
	hl.bind("SUPER + ALT + " .. key,          function() helpers.resize_edge(edges[1], 20) end, { repeating = true })
	hl.bind("SUPER + ALT + CTRL + " .. key,   function() helpers.resize_edge(edges[2], -20) end, { repeating = true })
end

-- move a floating window
hl.bind("SUPER + left",          hl.dsp.window.move({ x = -FLOAT_STEP, y = 0, relative = true }))
hl.bind("SUPER + right",         hl.dsp.window.move({ x = FLOAT_STEP, y = 0, relative = true }))
hl.bind("SUPER + up",            hl.dsp.window.move({ x = 0, y = -FLOAT_STEP, relative = true }))
hl.bind("SUPER + down",          hl.dsp.window.move({ x = 0, y = FLOAT_STEP, relative = true }))

-- gaps (per-desktop in bspwm; global here, see helpers.lua)
hl.bind("SUPER + Next",              function() helpers.adjust_gaps(5) end)
hl.bind("SUPER + Prior",             function() helpers.adjust_gaps(-5) end)
hl.bind("SUPER + BackSpace",         helpers.reset_gaps)
hl.bind("SUPER + SHIFT + BackSpace", helpers.zero_gaps)

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
