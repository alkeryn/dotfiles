-- ueberzug_overlay.lua -- keep ueberzugpp previews behind fullscreen windows
--
-- Hyprland only demotes windows under *internal* fullscreen
-- (IFullscreenHandler::setNoMembersAboveFullscreen()). A client-side fullscreen
-- (imv, mpv, most SDL apps) leaves floating overlays rendering on top of the
-- fullscreen surface. Lower the overlay while any fullscreen window shares its
-- workspace, then raise it again once none is left.
--
-- lower() also clears fullscreenPolicy().allowedOverFullscreen(), so internal
-- fullscreen hides the overlay natively; raise() restores it above the
-- terminal. Overlays keep `no_focus`, so z-order changes do not affect input.
local M = {}

local function is_overlay(window)
	return window and window.class and window.class:match("^ueberzug")
end

local function is_fullscreen(window)
	return (window.fullscreen or 0) ~= 0 or (window.fullscreen_client or 0) ~= 0
end

local function workspace_has_fullscreen(workspace)
	if not workspace then return false end
	for _, window in ipairs(hl.get_windows() or {}) do
		local other = window.workspace
		if other and other.name == workspace.name and window.mapped and not window.hidden and is_fullscreen(window) then
			return true
		end
	end
	return false
end

function M.sync()
	for _, window in ipairs(hl.get_windows() or {}) do
		if is_overlay(window) and window.workspace then
			local allowed = not workspace_has_fullscreen(window.workspace)
			-- allowed_over_fullscreen is what internal fullscreen consults.
			if allowed ~= window.allowed_over_fullscreen then
				hl.dispatch(hl.dsp.window.alter_zorder({
					mode   = allowed and "top" or "bottom",
					window = window,
				}))
			end
		end
	end
end

function M.setup()
	hl.on("window.open", M.sync)
	hl.on("window.fullscreen", M.sync)
	hl.on("window.close", M.sync)
	hl.on("window.destroy", M.sync)
end

return M
