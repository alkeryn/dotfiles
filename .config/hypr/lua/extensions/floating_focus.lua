-- Keep floating stacking order in sync with keyboard focus, in every layout.
-- Do not change follow_mouse: pointer hover alone must not gain keyboard focus.
local raising = false

local function raise_focused(window)
	if raising or not window or not window.mapped or not window.active
		or not window.floating or window.hidden then return end

	-- Explicit target: never raise an unrelated window if focus changes.
	-- alter_zorder simulates pointer motion and can re-enter focus callbacks.
	raising = true
	local ok, err = pcall(function()
		hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = window }))
	end)
	raising = false
	if not ok then error(err, 0) end
end

hl.on("window.active", raise_focused)
hl.on("config.reloaded", function()
	raise_focused(hl.get_active_window())
end)
