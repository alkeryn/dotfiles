-- autostart.lua -- replaces ~/.config/bspwm/scripts/autostart

local vars = require("lua/vars")
local PC = vars.PC

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
	else
		hl.exec_cmd("signal-desktop")
	end
	hl.exec_cmd("xrdb -merge ~/.Xresources")                  -- XWayland resources
	hl.exec_cmd("sh -c 'pkill -x mpd; mpd; mpDris2'")
	hl.exec_cmd("nm-applet")
	-- hl.exec_cmd("megasync")
end)
