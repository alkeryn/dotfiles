-- Run from ~/.config/hypr: lua tests/animations_test.lua
-- Configuration/inheritance regression test, not a GPU rendering test.
local animations, curves, enabled = {}, {}, false
_G.hl = {
	config = function(spec) enabled = spec.animations.enabled end,
	curve = function(name, spec)
		assert(not curves[name], "duplicate curve: " .. name)
		curves[name] = spec
	end,
	animation = function(spec)
		assert(not animations[spec.leaf], "duplicate animation: " .. spec.leaf)
		animations[spec.leaf] = spec
	end,
}
require("lua/animations")

-- Hyprland 0.56.2's AnimationTree.cpp. Children inherit their nearest explicit
-- parent, so test the effective settings, not just the registered leaf names.
local parents = {
	windows = "global", windowsIn = "windows", windowsOut = "windows", windowsMove = "windows",
	layers = "global", layersIn = "layers", layersOut = "layers",
	fade = "global", fadeIn = "fade", fadeOut = "fade", fadeSwitch = "fade",
	fadeShadow = "fade", fadeGlow = "fade", fadeDim = "fade", fadeDpms = "fade",
	fadeLayers = "fade", fadeLayersIn = "fadeLayers", fadeLayersOut = "fadeLayers",
	fadePopups = "fade", fadePopupsIn = "fadePopups", fadePopupsOut = "fadePopups",
	workspaces = "global", workspacesIn = "workspaces", workspacesOut = "workspaces",
	specialWorkspace = "workspaces", specialWorkspaceIn = "specialWorkspace", specialWorkspaceOut = "specialWorkspace",
	border = "global", borderangle = "global", shadowangle = "global", glowangle = "global",
	zoomFactor = "global", monitorAdded = "global",
}
local function effective(leaf)
	if animations[leaf] then return animations[leaf] end
	return effective(assert(parents[leaf], "unknown animation: " .. leaf))
end
local fade_leaves = {
	fadeIn = true, fadeSwitch = true,
	fadeLayers = true, fadeLayersIn = true, fadeLayersOut = true,
	fadePopups = true, fadePopupsIn = true, fadePopupsOut = true,
	workspaces = true, workspacesIn = true, workspacesOut = true,
	specialWorkspace = true, specialWorkspaceIn = true, specialWorkspaceOut = true,
}

assert(enabled, "Picom fading=true requires animations enabled")
assert(not animations.global.enabled, "unrelated compositor animations must stay off")
for leaf in pairs(animations) do
	assert(leaf == "global" or parents[leaf], "unknown configured animation: " .. leaf)
end
for leaf in pairs(parents) do
	local spec = effective(leaf)
	assert(spec.enabled == (fade_leaves[leaf] == true), "wrong enabled state: " .. leaf)
	if spec.enabled then
		-- Original Picom: 3 ms per 0.03 opacity, in AND out. Hyprland: speed * 100 ms.
		assert(math.abs(spec.speed * 100 - 3 / 0.03) < 1e-9, "wrong Picom fade rate: " .. leaf)
		assert(spec.bezier == "linear" and not spec.spring, "fade must be linear: " .. leaf)
	end
end
local curve = assert(curves.linear, "missing linear curve")
assert(curve.type == "bezier" and #curve.points == 2, "expected cubic bezier")
assert(curve.points[1][1] == 0 and curve.points[1][2] == 0
	and curve.points[2][1] == 1 and curve.points[2][2] == 1, "curve must be exactly linear")
print("PASS Picom fades: window opening, opacity changes, layers and popups at 100 ms linear")

-- Close snapshots include borders while surviving tiles reflow immediately.
-- windowsOut=false only disables movement: explicitly keep fadeOut off without
-- disabling fadeIn/fadeSwitch or the separate layer/popup/workspace branches.
assert(animations.fadeOut and not animations.fadeOut.enabled,
	"window close fade must stay explicitly disabled to avoid retained border fragments")
print("PASS close workaround: immediate window removal, other opacity fades preserved")

-- Disabled movement still warps to the style's endpoints. A default/87% popin
-- would shrink a closing snapshot even though the movement animation is off.
for _, leaf in ipairs({ "windows", "windowsIn", "windowsOut" }) do
	local spec = effective(leaf)
	assert(not spec.enabled and spec.style == "popin 100%", "window must remain full size: " .. leaf)
end
for _, leaf in ipairs({ "layers", "layersIn", "layersOut" }) do
	local spec = effective(leaf)
	assert(not spec.enabled and spec.style == "fade", "layer must remain stationary: " .. leaf)
end
print("PASS geometry: no popin, slides, animated resizing, borders or zoom")

for _, leaf in ipairs({ "workspaces", "workspacesIn", "workspacesOut",
	"specialWorkspace", "specialWorkspaceIn", "specialWorkspaceOut" }) do
	local spec = effective(leaf)
	assert(spec.enabled and spec.style == "fade", "workspace must fade in place: " .. leaf)
end
assert(effective("workspacesIn").speed == effective("workspacesOut").speed,
	"both workspace directions must match Picom (replaces the immediate-departure workaround)")
print("PASS workspaces: symmetric stationary fades, including special workspaces")
