-- lua tests/ueberzug_overlay_test.lua -- no compositor required.
-- Checks that previews are lowered under internal and client fullscreen and
-- raised again, without touching overlays on other workspaces.
local events, dispatched, windows = {}, {}, {}

local function window(fields)
	local w = { mapped = true, hidden = false, fullscreen = 0, fullscreen_client = 0,
		allowed_over_fullscreen = true }
	for key, value in pairs(fields) do w[key] = value end
	return w
end

_G.hl = {
	get_windows = function() return windows end,
	on = function(name, callback) events[name] = callback end,
	dispatch = function(dispatcher)
		-- Emulate the z-order dispatcher: lower clears allowed_over_fullscreen.
		dispatcher.window.allowed_over_fullscreen = dispatcher.mode == "top"
		dispatched[#dispatched + 1] = dispatcher
	end,
	dsp = {
		window = {
			alter_zorder = function(opts) return opts end,
		},
	},
}

local overlay = require("lua/extensions/ueberzug_overlay")
overlay.setup()

for _, name in ipairs({ "window.open", "window.fullscreen", "window.close", "window.destroy" }) do
	assert(events[name], "subscribed to " .. name)
end

local ws1 = { name = "1" }
local ws2 = { name = "2" }
local preview = window({ class = "ueberzugpp_abcdefghij", workspace = ws1 })
local terminal = window({ class = "Alacritty", workspace = ws1 })
local viewer = window({ class = "imv", workspace = ws1 })
local other = window({ class = "ueberzugpp_klmnopqrst", workspace = ws2 })
windows = { preview, terminal, viewer, other }

-- No fullscreen: nothing to do.
overlay.sync()
assert(#dispatched == 0, "leave overlays alone without fullscreen")

-- Internal fullscreen on ws1 lowers only the overlay on ws1.
viewer.fullscreen = 1
events["window.fullscreen"](viewer)
assert(#dispatched == 1, "lower the overlay on fullscreen")
assert(dispatched[1].window == preview and dispatched[1].mode == "bottom", "lower only ws1 overlay")
assert(not preview.allowed_over_fullscreen, "rule-dispatched lower clears allowed_over_fullscreen")
assert(other.allowed_over_fullscreen, "do not touch other workspaces")

-- Exiting fullscreen raises it again.
viewer.fullscreen = 0
events["window.fullscreen"](viewer)
assert(#dispatched == 2 and dispatched[2].window == preview and dispatched[2].mode == "top", "raise after unfullscreen")
assert(preview.allowed_over_fullscreen, "raised overlay is allowed over fullscreen again")

-- Client-side fullscreen behaves the same.
viewer.fullscreen_client = 1
events["window.fullscreen"](viewer)
assert(#dispatched == 3 and dispatched[3].window == preview and dispatched[3].mode == "bottom", "hide under client fullscreen")

-- A new overlay opened while the viewer is fullscreen is lowered too.
local late = window({ class = "ueberzugpp_latepreview", workspace = ws1 })
windows[#windows + 1] = late
events["window.open"](late)
assert(#dispatched == 4 and dispatched[4].window == late and dispatched[4].mode == "bottom", "lower late overlay")

-- Closing the fullscreen window raises the remaining overlays.
viewer.fullscreen_client = 0
windows = { preview, terminal, late, other }
events["window.close"](viewer)
assert(late.allowed_over_fullscreen and preview.allowed_over_fullscreen, "raise overlays after close")

print("PASS ueberzug overlays stay behind fullscreen windows")
