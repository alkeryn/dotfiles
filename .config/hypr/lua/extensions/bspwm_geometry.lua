-- Shared logical geometry for tile placement, monocle and preselection feedback.
-- Keep rounding here consistent with Hyprland's integer layout rectangles.
local M = {}

function M.round(value)
	return math.floor(value + 0.5)
end

function M.monitor_box(monitor, fallback)
	if not monitor or not monitor.width or not monitor.height or not monitor.position then
		return fallback
	end
	local width, height = monitor.width, monitor.height
	if (monitor.transform or 0) % 2 == 1 then width, height = height, width end
	local scale = monitor.scale or 1
	return {
		x = monitor.position.x,
		y = monitor.position.y,
		w = M.round(width / scale),
		h = M.round(height / scale),
	}
end

-- The ratio always describes the first child's share, including east/south
-- preselection. Round only that share; the second child takes the remainder.
function M.split_box(box, axis, ratio)
	if axis == "h" then
		local width = math.floor(box.w * ratio)
		return { x = box.x, y = box.y, w = width, h = box.h },
			{ x = box.x + width, y = box.y, w = box.w - width, h = box.h }
	end
	local height = math.floor(box.h * ratio)
	return { x = box.x, y = box.y, w = box.w, h = height },
		{ x = box.x, y = box.y + height, w = box.w, h = box.h - height }
end

return M
