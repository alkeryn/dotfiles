-- rules.lua -- window/workspace rules
-- ============================================================================
-- Module: registers all rules. Requires lua/vars + lua/helpers.
-- (bspc rule translation + previous attempt's rules.conf)
--
-- Class matching: Hyprland matches with RE2 *full match*, and Wayland app_ids
-- differ from X11 classes in case/naming (pavucontrol -> org.pulseaudio.pavucontrol),
-- so app rules use `(?i).*name.*` (case-insensitive substring) via rx().
-- ============================================================================

-- NOTE: module paths are relative to the main config dir; modules in lua/
-- are required as "lua/<name>" (see bindings.lua)
local vars    = require("lua/vars")
local helpers = require("lua/helpers")

local function rx(name) return "(?i).*" .. name .. ".*" end

-- ---------------------------------------------------------------------------
-- monitor layout: workspace -> monitor assignment
-- ---------------------------------------------------------------------------
-- The config loads before any monitor exists; monitor.added re-applies it.

helpers.apply_monitor_layout()

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
	name     = "fix-xwayland-drags",
	match    = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
	no_focus = true,
})

-- bspc rule -a floating state=floating  (alacritty --class floating)
hl.window_rule({
	name  = "alacritty-floating",
	match = { class = "^floating$" },
	float = true,
})

-- ---------------------------------------------------------------------------
-- app rules (bspc rule translation)
-- ---------------------------------------------------------------------------
-- bspwm `desktop=N follow=on`  -> workspace = "N"        (switch to it)
-- bspwm `desktop='^N'`         -> workspace = "N silent" (stay where you are)

local function register(prefix, list, enabled)
	for i, r in ipairs(list) do
		hl.window_rule({
			name      = prefix .. "-" .. i .. "-" .. r.class,
			enabled   = enabled,
			match     = { class = rx(r.class) },
			float     = r.float,
			tile      = r.tile,
			pin       = r.pin,
			no_focus  = r.no_focus,
			workspace = r.workspace,
		})
	end
end

-- enabled state can be flipped later; re-registering would append effects
local function toggle(prefix, list, enabled)
	for i, r in ipairs(list) do
		hl.window_rule({ name = prefix .. "-" .. i .. "-" .. r.class, enabled = enabled })
	end
end

register("app", {
	{ class = "lxappearance",         float = true },
	{ class = "pavucontrol",          float = true },
	{ class = "megasync",             float = true },
	{ class = "vscode-color-ui",      float = true },
	{ class = "gimp",                 float = true, workspace = "8" },
	{ class = "VESC Tool",            workspace = "8" },
	{ class = "Ethereum ?Wallet",     float = true, workspace = "3" },
	{ class = "looking-glass-client", workspace = "8" },
	{ class = "zathura",              tile = true },
	-- bspc rule -a Screenkey manage=off: closest approximation
	{ class = "screenkey",            float = true, pin = true, no_focus = true },
}, true)

if vars.PC == "mainpc" then
	register("mainpc", {
		{ class = "discord",       workspace = "1 silent" },
		{ class = "signal",        workspace = "1 silent" },
		{ class = "skypeforlinux", workspace = "1 silent" },
		{ class = "qbittorrent",   workspace = "2" },
	}, true)
else
	-- laptop: bspwmrc picks the set from the number of connected monitors
	local docked = {
		{ class = "discord",       workspace = "1 silent" },
		{ class = "qbittorrent",   workspace = "2" },
		{ class = "skypeforlinux", workspace = "3 silent" },
	}
	local undocked = {
		{ class = "qbittorrent",   workspace = "9" },
		{ class = "discord",       workspace = "10 silent" },
		{ class = "skypeforlinux", workspace = "10 silent" },
	}
	-- no monitors are known at first load: start undocked, monitor events decide
	register("docked", docked, false)
	register("undocked", undocked, true)

	local function update(exclude)
		local d = helpers.is_docked(exclude)
		toggle("docked", docked, d)
		toggle("undocked", undocked, not d)
	end
	hl.on("monitor.added", function() update() end)
	hl.on("monitor.removed", function(mon) update(mon) end)
end

-- workspace -> monitor assignment follows monitors coming and going
hl.on("monitor.added", function() helpers.apply_monitor_layout() end)
hl.on("monitor.removed", function(mon) helpers.apply_monitor_layout(mon) end)
