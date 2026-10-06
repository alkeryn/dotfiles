-- Run from ~/.config/hypr: lua tests/repeat_bindings_test.lua
-- sxhkd repeated every ported keyboard shortcut. Keep that behavior, including
-- media/mute keys that were also bindel on dotfiles' origin/hyprland branch.
-- Register the real bindings without loading the layout or executing actions.
local binds = {}
local function ignored_dispatcher() return function() end end
local dispatchers = setmetatable({}, { __index = function() return ignored_dispatcher end })
package.loaded["lua/vars"] = { FLOAT_STEP = 20, terminal = "alacritty" }
package.loaded["lua/helpers"] = setmetatable({}, { __index = function() return function() end end })
package.loaded["lua/extensions/bspwm"] = { close = function() end, reload = function() end }
_G.hl = {
	bind = function(keys, callback, opts)
		assert(not binds[keys], "duplicate binding: " .. keys)
		assert(type(callback) == "function", "missing action: " .. keys)
		binds[keys] = opts or {}
	end,
	dsp = setmetatable({ window = dispatchers }, { __index = function() return ignored_dispatcher end }),
}
require("lua/bindings")

local mouse_binds = {
	["SUPER + mouse:272"] = true,
	["SUPER + CTRL + mouse:272"] = true,
	["SUPER + mouse:273"] = true,
	["SUPER + mouse_down"] = false,
	["SUPER + mouse_up"] = false,
}
local missing_repeat = {}
local keyboard_count, mouse_count = 0, 0
for keys, opts in pairs(binds) do
	if keys:find("mouse", 1, true) then
		mouse_count = mouse_count + 1
		assert(mouse_binds[keys] ~= nil, "unexpected mouse binding: " .. keys)
		assert(not opts.repeating, "mouse binding must not gain keyboard repeat: " .. keys)
		assert((opts.mouse == true) == mouse_binds[keys], "changed mouse drag/scroll flags: " .. keys)
	else
		keyboard_count = keyboard_count + 1
		if opts.repeating ~= true then missing_repeat[#missing_repeat + 1] = keys end
	end
end
assert(mouse_count == 5, "lost a mouse binding")
assert(keyboard_count > 100, "did not load all keyboard bindings")
table.sort(missing_repeat)
assert(#missing_repeat == 0, "keyboard bindings missing repeat:\n" .. table.concat(missing_repeat, "\n"))

-- Adding repeat must preserve use of audio/backlight keys while locked.
for _, keys in ipairs({
	"XF86AudioStop", "XF86AudioPrev", "XF86AudioPlay", "XF86AudioNext",
	"SHIFT + XF86AudioPlay", "XF86AudioRaiseVolume", "XF86AudioLowerVolume",
	"XF86AudioMute", "SUPER + XF86AudioMute", "XF86MonBrightnessDown", "XF86MonBrightnessUp",
}) do
	assert(binds[keys] and binds[keys].locked == true, "lost locked flag: " .. keys)
end
print(string.format("PASS: all %d keyboard bindings repeat; %d mouse bindings and media locked flags preserved",
	keyboard_count, mouse_count))
