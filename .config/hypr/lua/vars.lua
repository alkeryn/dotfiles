-- vars.lua -- machine detection + shared constants
-- ============================================================================
-- Module: returns the shared state table used by helpers/rules/bindings.
-- PC is auto-detected from /etc/hostname, like ~/bin/wpc did with $PC.
-- ============================================================================

local M = {}

M.PC = "mainpc"
do
	local f = io.open("/etc/hostname", "r")
	if f then
		local host = f:read("*l") or ""
		f:close()
		if host:find("laptop") or host:find("nomad") then M.PC = "laptop" end
	end
end

M.GAPS       = 4   -- previous attempt: gaps_in 4, gaps_out 8 (bspwm window_gap 8)
M.GAPS_OUT   = 8
M.BORDER     = M.PC == "mainpc" and 1 or 2    -- bspwm border_width
M.FLOAT_STEP = M.PC == "mainpc" and 20 or 40

-- monitor names from the hyprland-branch attempt (real hardware)
-- left: HDMI-A-2 (4K), main: DP-4 (4K@244, 10bit, HDR)
M.M1 = "HDMI-A-2"   -- left:      tags 1-4
M.M2 = "DP-4"       -- main:      tags 5-10

-- previous attempt: alacritty font bumped to 11 on hyprland to match bspwm's
-- 9pt physical size at scale 1 on 4K
M.terminal = "alacritty --option font.size=11"

return M
