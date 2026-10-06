-- Route config-owned pseudo tiles to native resizing, not BSP split resizing.
-- v0.56.2 exposes neither isPseudo nor pseudoSize on HL.Window/LayoutTarget.
-- A native window tag survives Lua reloads alongside the native pseudo state;
-- no geometry cache, window-ID table, IPC query or resize-time toggle is needed.
local M = {}
local tag = "bspwm_pseudo_tiled"

function M.is_pseudo(window)
	for _, value in ipairs(window and window.tags or {}) do
		if value == tag then return true end
	end
	return false
end

function M.set(window, enabled)
	local result = hl.dispatch(hl.dsp.window.pseudo({ action = enabled and "on" or "off", window = window }))
	if result and result.ok == false then return false end
	if M.is_pseudo(window) ~= enabled then
		result = hl.dispatch(hl.dsp.window.tag({ tag = (enabled and "+" or "-") .. tag, window = window }))
		if result and result.ok == false then return false end
	end
	return true
end

return M
