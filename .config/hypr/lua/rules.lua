-- rules.lua -- window/workspace rules
-- ============================================================================
-- Module: registers all rules. Requires lua/vars + lua/helpers.
-- (bspc rule translation + previous attempt's rules.conf)
-- ============================================================================

-- NOTE: module paths are relative to the main config dir; modules in lua/
-- are required as "lua/<name>" (see bindings.lua)
local vars    = require("lua/vars")
local helpers = require("lua/helpers")

-- ---------------------------------------------------------------------------
-- monitor layout: workspace -> monitor assignment
-- ---------------------------------------------------------------------------

helpers.apply_monitor_layout() -- static registration at startup (mainpc / docked)
hl.on("monitor.added", function() helpers.apply_monitor_layout() end)
hl.on("monitor.removed", function() helpers.apply_monitor_layout() end)

-- ---------------------------------------------------------------------------
-- smart gaps / no gaps when only (from the previous attempt's rules.conf)
-- ---------------------------------------------------------------------------

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

-- ---------------------------------------------------------------------------
-- app rules (bspc rule translation)
-- ---------------------------------------------------------------------------

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

if vars.PC == "mainpc" then
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
