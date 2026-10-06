-- bindings.lua -- keybindings
-- ============================================================================
-- Module: registers all binds. Requires lua/vars + lua/helpers.
-- (sxhkdrc translation; French azerty keysyms are unchanged; every bind
-- carries a comment with the bspwm original it replaces)
-- Keep ALL keyboard bindings repeating, as they were under sxhkd, including
-- toggles and launchers. The old Hyprland branch also used binde/bindel for
-- focus/swap/resize and media keys. Do not silently make them single-shot.
-- { repeating = true } uses input.repeat_delay / input.repeat_rate; mouse
-- drag and wheel bindings keep their separate, non-repeating behavior.
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
hl.bind("SUPER + Print",          hl.dsp.exec_cmd("grim -g \"$(slurp -b 50000055 -c bb0000)\" - | wl-copy"), { repeating = true })
hl.bind("SUPER + SHIFT + Print",  hl.dsp.exec_cmd("grim -g \"$(slurp -b 50000055 -c bb0000)\" ~/Images/scrot/$(date +%Y%m%d_%H%M%S).png"), { repeating = true })
hl.bind("SUPER + CTRL + Print",   hl.dsp.exec_cmd("grim ~/Images/scrot/$(date +%Y%m%d_%H%M%S).png"), { repeating = true })

-- pipe clipboard (xclip socket -> cliphist; adapted)
hl.bind("SUPER + z",              hl.dsp.exec_cmd("wl-paste | cliphist store"), { repeating = true })
hl.bind("SUPER + SHIFT + z",      hl.dsp.exec_cmd("cliphist decode | wl-copy"), { repeating = true })

-- Lock
hl.bind("SUPER + a",              hl.dsp.exec_cmd("hyprlock"), { repeating = true })  -- was: sh ~/bin/lock (scrot+i3lock, X11 only)

-- Terminal
hl.bind("SUPER + space",          hl.dsp.exec_cmd(terminal), { repeating = true })
hl.bind("SUPER + ALT + space",    hl.dsp.exec_cmd(terminal .. " --class floating"), { repeating = true })

-- Music
hl.bind("SUPER + p",              hl.dsp.exec_cmd(terminal .. " -e ncmpcpp"), { repeating = true })

-- Rofi
hl.bind("SUPER + Return",         hl.dsp.exec_cmd("rofi -terminal alacritty -show drun"), { repeating = true })
hl.bind("SUPER + CTRL + Return",  hl.dsp.exec_cmd("rofi -terminal alacritty -show run"), { repeating = true })
hl.bind("SUPER + ALT + Return",   hl.dsp.exec_cmd("rofi -terminal alacritty -modi emoji -show emoji"), { repeating = true })
hl.bind("SUPER + SHIFT + Return", hl.dsp.exec_cmd("rofi -terminal alacritty -modi calc -show calc -no-show-match -no-sort"), { repeating = true })
hl.bind("SUPER + Tab",            hl.dsp.exec_cmd("rofi -show window"), { repeating = true })

-- Ranger
hl.bind("SUPER + e",              hl.dsp.exec_cmd("bash -c 'source ~/bin/shell/env; " .. terminal .. " -e ranger'"), { repeating = true })

-- Sound / media
hl.bind("XF86AudioStop",          hl.dsp.exec_cmd("playerctl -p playerctld pause"), { locked = true, repeating = true })
hl.bind("XF86AudioPrev",          hl.dsp.exec_cmd("playerctl -p playerctld previous"), { locked = true, repeating = true })
hl.bind("XF86AudioPlay",          hl.dsp.exec_cmd("playerctl -p playerctld play-pause"), { locked = true, repeating = true })
hl.bind("XF86AudioNext",          hl.dsp.exec_cmd("playerctl -p playerctld next"), { locked = true, repeating = true })
hl.bind("SHIFT + XF86AudioPlay",  hl.dsp.exec_cmd("playerctl -a pause"), { locked = true, repeating = true })
hl.bind("XF86AudioRaiseVolume",   hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ +4%"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",   hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ -4%"), { locked = true, repeating = true })
hl.bind("XF86AudioMute",          hl.dsp.exec_cmd("pactl set-sink-mute @DEFAULT_SINK@ toggle"), { locked = true, repeating = true })
hl.bind("SUPER + XF86AudioMute",  hl.dsp.exec_cmd("pactl set-sink-volume @DEFAULT_SINK@ 100%"), { locked = true, repeating = true })

-- Backlight (light kept; swap to brightnessctl if udev perms annoy you)
hl.bind("XF86MonBrightnessDown",  hl.dsp.exec_cmd("light -U 10"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp",    hl.dsp.exec_cmd("light -A 10"), { locked = true, repeating = true })

-- wifi toggle
hl.bind("SUPER + F12",            hl.dsp.exec_cmd("~/bin/wifitoggle"), { repeating = true })

-- Reload without discarding the tree. Mutations are also checkpointed for
-- automatic file reloads; the shortcut flushes once more before hyprctl reload.
hl.bind("SUPER + Escape",         require("lua/extensions/bspwm").reload, { repeating = true })

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
	end, { repeating = true })
end

-- quit bspwm / close and kill
-- Super+x closes the selected subtree, or just the focused window otherwise.
-- Plain Ctrl+x is left to applications; Super+Ctrl+x below still pins.
hl.bind("SUPER + CTRL + ALT + Escape", hl.dsp.exit(), { repeating = true })
hl.bind("SUPER + x",                   require("lua/extensions/bspwm").close, { repeating = true })
hl.bind("SUPER + SHIFT + x",           hl.dsp.window.kill(), { repeating = true })

-- alternate between the tiled and monocle layout (bspc desktop -l next)
hl.bind("SUPER + v",                   hl.dsp.layout("mode"), { repeating = true })

-- Send the selected node to last preselection; otherwise pull the last logical
-- node (a remembered Super+b subtree, or an ordinary window) beside this node.
-- Across desktops/monitors; reflow first, then focus/select the inserted node.
hl.bind("SUPER + y",                   hl.dsp.layout("pull"), { repeating = true })

-- Rotate (bspc node -R {90,270})
hl.bind("SUPER + r",                   hl.dsp.layout("rotate 90"), { repeating = true })
hl.bind("SUPER + SHIFT + r",           hl.dsp.layout("rotate 270"), { repeating = true })

-- Flip (bspc node -F {horizontal,vertical})
hl.bind("SUPER + u",                   hl.dsp.layout("flip h"), { repeating = true })
hl.bind("SUPER + i",                   hl.dsp.layout("flip v"), { repeating = true })

-- Balance Tree (bspc node @/ {-B,-E})
hl.bind("SUPER + ALT + b",             hl.dsp.layout("balance"), { repeating = true })
hl.bind("SUPER + CTRL + b",            hl.dsp.layout("equalize"), { repeating = true })

-- Set mutually exclusive states, overriding fullscreen/float/pseudo rather than toggling.
hl.bind("SUPER + s",                   function() helpers.set_window_state("tiled") end, { repeating = true })
hl.bind("SUPER + d",                   function() helpers.set_window_state("floating") end, { repeating = true })
hl.bind("SUPER + f",                   function() helpers.set_window_state("fullscreen") end, { repeating = true })
hl.bind("SUPER + t",                   function() helpers.set_window_state("pseudo_tiled") end, { repeating = true })

-- set the node flags
-- bspc node -g locked  -> no equivalent (unavailable)
hl.bind("SUPER + CTRL + x",            hl.dsp.window.pin(), { repeating = true })          -- -g sticky
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
hl.bind("SUPER + q",                   helpers.focus_last, { repeating = true })
hl.bind("ALT + twosuperior",           helpers.focus_last, { repeating = true })
hl.bind("ALT + Tab",                   hl.dsp.focus({ workspace = "previous_per_monitor" }), { repeating = true })

-- focus the next/previous node in the current desktop
hl.bind("SUPER + c",                   hl.dsp.window.cycle_next(), { repeating = true })
hl.bind("SUPER + ALT + c",             hl.dsp.window.cycle_next({ next = false }), { repeating = true })

-- focus/send/swap next/prev desktop (dead_circumflex / dollar)
-- Sends transfer the selected subtree (Super+b), then follow it once.
hl.bind("SUPER + dead_circumflex",              hl.dsp.focus({ workspace = "m-1" }), { repeating = true })
hl.bind("SUPER + dollar",                       hl.dsp.focus({ workspace = "m+1" }), { repeating = true })
hl.bind("SUPER + SHIFT + dead_circumflex",      function() helpers.move_workspace_rel(-1) end, { repeating = true })
hl.bind("SUPER + SHIFT + dollar",               function() helpers.move_workspace_rel(1) end, { repeating = true })
hl.bind("SUPER + ALT + dead_circumflex",        function() helpers.swap_workspace_rel(-1) end, { repeating = true })
hl.bind("SUPER + ALT + dollar",                 function() helpers.swap_workspace_rel(1) end, { repeating = true })

-- focus the older or newer node in the focus history
hl.bind("SUPER + parenright",          function() helpers.focus_history(-1) end, { repeating = true }) -- older
hl.bind("SUPER + equal",               function() helpers.focus_history(1) end, { repeating = true })  -- newer

-- focus or send to the given desktop (super + number row, azerty)
local NUM_KEYS = { "ampersand", "eacute", "quotedbl", "apostrophe", "parenleft",
	"minus", "egrave", "underscore", "ccedilla", "agrave" }
for i, key in ipairs(NUM_KEYS) do
	local ws = tostring(i == 10 and 10 or i)
	hl.bind("SUPER + " .. key,            hl.dsp.focus({ workspace = ws }), { repeating = true })
	hl.bind("SUPER + SHIFT + " .. key,    function() helpers.move_to_workspace(ws) end, { repeating = true })
	hl.bind("SUPER + ALT + " .. key,      function() helpers.swap_with_workspace(ws) end, { repeating = true })
end

-- Layer (bspc node -l {below,normal,above} -> above only)
hl.bind("SUPER + SHIFT + m",           hl.dsp.window.bring_to_top(), { repeating = true })

-- Preselect the direction (bspc node -p {west,south,north,east})
hl.bind("SUPER + CTRL + h",            hl.dsp.layout("preselect l"), { repeating = true })
hl.bind("SUPER + CTRL + j",            hl.dsp.layout("preselect d"), { repeating = true })
hl.bind("SUPER + CTRL + k",            hl.dsp.layout("preselect u"), { repeating = true })
hl.bind("SUPER + CTRL + l",            hl.dsp.layout("preselect r"), { repeating = true })

-- preselect the ratio (bspc node -o 0.{1-9})
local RATIO_KEYS = { "ampersand", "eacute", "quotedbl", "apostrophe", "parenleft",
	"minus", "egrave", "underscore", "ccedilla" }
for i, key in ipairs(RATIO_KEYS) do
	hl.bind("SUPER + CTRL + " .. key,     hl.dsp.layout("pratio 0." .. i), { repeating = true })
end

-- cancel preselection (node / desktop)
hl.bind("SUPER + CTRL + space",              hl.dsp.layout("preselect cancel"), { repeating = true })
hl.bind("SUPER + CTRL + SHIFT + space",      hl.dsp.layout("preselect clear"), { repeating = true })

-- Move/resize (bspc node -z / -v)
-- The key specifies the direction the edge MOVES: h grows the left edge
-- outward, Ctrl+h shrinks the RIGHT edge inward. Match sxhkd on tiles AND floats.
local resize_keys = { h = { "l", "r" }, j = { "d", "u" }, k = { "u", "d" }, l = { "r", "l" } }
for key, edges in pairs(resize_keys) do
	hl.bind("SUPER + ALT + " .. key,          function() helpers.resize_edge(edges[1], 20) end, { repeating = true })
	hl.bind("SUPER + ALT + CTRL + " .. key,   function() helpers.resize_edge(edges[2], -20) end, { repeating = true })
end

-- move a floating window
hl.bind("SUPER + left",          hl.dsp.window.move({ x = -FLOAT_STEP, y = 0, relative = true }), { repeating = true })
hl.bind("SUPER + right",         hl.dsp.window.move({ x = FLOAT_STEP, y = 0, relative = true }), { repeating = true })
hl.bind("SUPER + up",            hl.dsp.window.move({ x = 0, y = -FLOAT_STEP, relative = true }), { repeating = true })
hl.bind("SUPER + down",          hl.dsp.window.move({ x = 0, y = FLOAT_STEP, relative = true }), { repeating = true })

-- gaps (per-desktop in bspwm; global here, see helpers.lua)
hl.bind("SUPER + Next",              function() helpers.adjust_gaps(5) end, { repeating = true })
hl.bind("SUPER + Prior",             function() helpers.adjust_gaps(-5) end, { repeating = true })
hl.bind("SUPER + BackSpace",         helpers.reset_gaps, { repeating = true })
hl.bind("SUPER + SHIFT + BackSpace", helpers.zero_gaps, { repeating = true })

-- Transplant (bspc node -n @/)
hl.bind("SUPER + SHIFT + t",     hl.dsp.layout("transplant"), { repeating = true })

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
			hl.dsp.exec_cmd("paplay ~/Cloud/Mega/zPC/Sounds/" .. s[2] .. ".wav &"), { repeating = true })
	end
end
hl.bind("SUPER + KP_Insert",     hl.dsp.exec_cmd("pkill paplay"), { repeating = true })

-- bspwm pointer move: tiles swap on hover while held; floats move normally.
-- Do NOT use native window.drag for tiles: it floats/removes them until drop.
local pointer_drag = require("lua/extensions/bspwm_drag").new(require("lua/extensions/bspwm"))
hl.bind("SUPER + mouse:272", pointer_drag.begin)
-- A release must end the grab even if Super went up first, another modifier
-- was pressed, an inhibitor appeared, or the submap/lock state changed. This
-- observer does not consume ordinary clicks or interfere with native drags.
hl.bind("mouse:272", pointer_drag.stop, {
	release = true, ignore_mods = true, non_consuming = true, transparent = true,
	locked = true, dont_inhibit = true, submap_universal = true,
})
-- Explicit native move override and resize retain their previous behavior.
hl.bind("SUPER + CTRL + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273",     hl.dsp.window.resize(), { mouse = true })

-- mouse scroll workspace nav (from previous attempt)
hl.bind("SUPER + mouse_down",    hl.dsp.focus({ workspace = "e+1" }))
hl.bind("SUPER + mouse_up",      hl.dsp.focus({ workspace = "e-1" }))
