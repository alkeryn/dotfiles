-- autostart.lua -- replaces ~/.config/bspwm/scripts/autostart

local vars = require("lua/vars")
local PC = vars.PC
local M = {}
local signal_started = false

-- Called over IPC only after xrdb succeeds; Signal keeps its own exec.
function M.after_xresources()
	if signal_started then return end
	signal_started = true
	hl.exec_cmd("signal-desktop")
end

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
	end
	-- exec_cmd has no completion callback. Notify Lua over IPC after xrdb exits
	-- successfully, without blocking the compositor (XWayland needs it running).
	hl.exec_cmd([[xrdb -merge "$HOME/.Xresources" && hyprctl eval 'require("lua/autostart").after_xresources()']])
	hl.exec_cmd("sh -c 'pkill -x mpd; mpd; mpDris2'")
	hl.exec_cmd("nm-applet")
	-- hl.exec_cmd("megasync")
end)

return M
