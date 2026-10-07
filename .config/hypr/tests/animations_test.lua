-- Run from ~/.config/hypr: lua tests/animations_test.lua
-- Guard the transition policy, not GPU rendering: the departing workspace is
-- live, so fading it out exposes its reflow after a window is moved away.
local animations, curves, enabled = {}, {}, false
_G.hl = {
	config = function(spec) enabled = spec.animations.enabled end,
	curve = function(name, spec) curves[name] = spec end,
	animation = function(spec)
		assert(not animations[spec.leaf], "duplicate animation: " .. spec.leaf)
		animations[spec.leaf] = spec
	end,
}
require("lua/animations")

assert(enabled, "incoming workspace fade requires animations enabled")
assert(animations.workspacesOut.enabled == false,
	"outgoing workspace must disappear immediately, hiding post-move reflow")
local incoming = animations.workspacesIn
assert(incoming.enabled and incoming.style == "fade" and incoming.speed == 1.21,
	"preserve the incoming workspace fade")
assert(curves[incoming.bezier], "incoming fade curve must exist")
for leaf, spec in pairs(animations) do
	if leaf ~= "workspaces" and leaf ~= "workspacesIn" then
		assert(not spec.enabled, "unexpected animation enabled: " .. leaf)
	end
end
print("PASS workspace transitions: immediate departure, preserved incoming fade")
