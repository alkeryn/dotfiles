-- lua tests/rules_test.lua -- no machine detection or compositor required.
-- This checks rule scope, not GPU rendering or RE2 implementation.
for _, pc in ipairs({ "mainpc", "laptop" }) do
	local rules, events = {}, {}
	package.loaded["lua/vars"] = { PC = pc }
	package.loaded["lua/helpers"] = {
		apply_monitor_layout = function() end,
		is_docked = function() return false end,
	}
	_G.hl = {
		workspace_rule = function() end,
		window_rule = function(rule) rules[#rules + 1] = rule end,
		on = function(name, callback) events[name] = callback end,
	}
	dofile("lua/rules.lua")

	local live_blur
	for _, rule in ipairs(rules) do
		if rule.name == "alacritty-live-blur" then
			assert(not live_blur, "register the workaround only once")
			live_blur = rule
		else
			assert(rule.xray == nil, "do not change other apps' blur paths")
		end
	end
	assert(live_blur and live_blur.xray == false, "explicit false bypasses the tiled blur cache")
	assert(live_blur.match.class == "(?i)^(alacritty|floating)$", "include both terminal classes only")
	assert(live_blur.match.float == false, "leave floating windows alone")
	for key in pairs(live_blur.match) do
		assert(key == "class" or key == "float", "work on every monitor/workspace")
	end
	for key in pairs(live_blur) do
		assert(key == "name" or key == "match" or key == "xray",
			"preserve opacity, blur, decoration and window placement")
	end
	assert(events["hyprland.start"] == nil and events["config.reloaded"] == nil,
		"the blur rule must not depend on a startup/reload repair")
	print("PASS tiled terminal live blur on " .. pc)
end
print("2/2 tests passed")
