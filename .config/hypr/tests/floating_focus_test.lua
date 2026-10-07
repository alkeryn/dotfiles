-- lua tests/floating_focus_test.lua -- no running compositor needed.
local events, raised = {}, {}
local active, reenter, fail
hl = {
	on = function(event, callback)
		assert(not events[event], "duplicate callback")
		events[event] = callback
	end,
	get_active_window = function() return active end,
	dsp = { window = { alter_zorder = function(opts)
		assert(opts.mode == "top" and opts.window == active)
		return opts
	end } }, -- No focus, fullscreen or floating-state dispatchers allowed.
	dispatch = function(opts)
		if fail then error("test dispatch failure") end
		raised[#raised + 1] = opts.window
		if reenter then events["window.active"](opts.window) end
		return { ok = true }
	end,
}
dofile("lua/extensions/floating_focus.lua")
assert(#raised == 0, "wait for focus/reload instead of dispatching during config load")

local first = { mapped = true, floating = true, hidden = false, active = false }
local second = { mapped = true, floating = true, hidden = false, active = false }
local function focus(window, reason)
	if active then active.active = false end
	active = window
	if window then window.active = true end
	events["window.active"](window, reason)
end

-- Keyboard focus/history/cycling must raise without a click, repeatedly.
focus(first, 1)
focus(second, 1)
focus(first, 1)
assert(#raised == 3 and raised[1] == first and raised[2] == second and raised[3] == first)
assert(active == first and first.floating and second.floating)

-- Click focus remains harmless; nested simulated mouse motion cannot loop.
reenter = true
focus(second, 5)
assert(#raised == 4 and raised[4] == second)
reenter = false

-- No keyboard focus, tiles, hidden/closed/expired windows or stale events.
local count = #raised
focus(nil)
focus({ mapped = true, floating = false })
focus({ mapped = true, floating = true, hidden = true })
focus({ mapped = false, floating = true })
focus({})
events["window.active"](first)
assert(#raised == count)

-- Reload raises the current float too, but never a tile or absent window.
focus(first)
count = #raised
events["config.reloaded"]()
assert(#raised == count + 1 and raised[#raised] == first)
focus(nil)
events["config.reloaded"]()
focus({ mapped = true, floating = false })
events["config.reloaded"]()
assert(#raised == count + 1)

-- Native z-order dispatch alone leaves pinning/fullscreen/layer policy intact.
first.pinned, first.fullscreen, first.fullscreen_client = true, 2, 2
focus(first)
assert(raised[#raised] == first and first.pinned and first.fullscreen == 2 and first.fullscreen_client == 2)

-- A failed dispatch must not permanently disable future raising.
fail = true
local ok, err = pcall(focus, second)
assert(not ok and tostring(err):find("test dispatch failure", 1, true))
fail = false
count = #raised
focus(first)
assert(#raised == count + 1 and raised[#raised] == first)

print("PASS floating focus: keyboard/click/reload raising, exclusions, re-entry and error recovery")
