-- Floating rectangles for explicit state shortcuts. Native v0.56.2 remembers
-- only size, then movedTarget() centres it on the tile (and can add 10px).
-- Restore AFTER float dispatch returns: a window.update_rules callback is too
-- early, before the native floating algorithm has applied that placement.
local geometry = require("lua/extensions/bspwm_geometry")
local M = {}

local function usable(window)
	return window and window.mapped and window.floating and not window.group
		and (window.fullscreen or 0) == 0
end

function M.capture(window)
	if not usable(window) then return nil end
	local at, size = window.at, window.size
	if not at or not size or not at.x or not at.y or not size.x or not size.y
		or size.x <= 0 or size.y <= 0 then return nil end
	-- Copy goal coordinates, not animated/intermediate positions or userdata.
	local monitor = geometry.monitor_box(window.monitor)
	if monitor then monitor.x, monitor.y = geometry.round(monitor.x), geometry.round(monitor.y) end
	return { x = at.x, y = at.y, w = size.x, h = size.y, monitor = monitor }
end

function M.restore(window, saved)
	if not saved or not usable(window) then return end
	local size = window.size
	if size.x ~= saved.w or size.y ~= saved.h then
		local result = hl.dispatch(hl.dsp.window.resize({
			x = saved.w, y = saved.h, relative = false, window = window,
		}))
		if result and result.ok == false then return end
	end
	if not usable(window) then return end

	local x, y = saved.x, saved.y
	local old, current = saved.monitor, geometry.monitor_box(window.monitor)
	if old and current and (old.x ~= current.x or old.y ~= current.y
		or old.w ~= current.w or old.h ~= current.h) then
		-- Keep monitor-local placement when a tile changed monitors. Fit only
		-- after a monitor change; ordinary toggles preserve even edge overlaps.
		x, y = x - old.x + current.x, y - old.y + current.y
		size = window.size -- resizing may have been constrained by the client
		x = math.max(current.x, math.min(x, current.x + current.w - size.x))
		y = math.max(current.y, math.min(y, current.y + current.h - size.y))
	end
	-- Resize is centre-based, so position must always be restored LAST.
	hl.dispatch(hl.dsp.window.move({ x = x, y = y, relative = false, window = window }))
end

return M
