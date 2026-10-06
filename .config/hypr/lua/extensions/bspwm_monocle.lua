-- Full-monitor monocle without Hyprland fullscreen (which hides other tiles).
-- Scoped, reversible rules leave floating windows and other workspaces alone.
local geometry = require("lua/extensions/bspwm_geometry")
local M = {}

function M.monitor_box(window, fallback)
	local monitor = window.monitor or (window.workspace and window.workspace.monitor)
	return geometry.monitor_box(monitor, fallback)
end

function M.new()
	local rules = {}
	local raising = false
	local instance = {}

	function instance.sync(ws, enabled)
		local entry = rules[ws.id]
		if not entry then
			if not enabled then return end
			-- Numeric monitor/persistence rules use "N" in helpers.lua. Use an
			-- equivalent but distinct selector: workspace_rule merges identical
			-- selectors, and disabling such a merged rule would disable theirs too.
			-- Named/special workspaces have negative IDs; ranges only accept >0.
			local selector = ws.id > 0 and string.format("r[%d-%d]", ws.id, ws.id)
				or "name:" .. ws.name
			entry = { enabled = true }
			rules[ws.id] = entry -- publish before rule updates can recalculate
			entry.gaps = hl.workspace_rule({ workspace = selector, gaps_in = 0, gaps_out = 0 })
			entry.windows = hl.window_rule({
				name = "bspwm-monocle-" .. ws.id,
				match = { workspace = selector, float = false },
				border_size = 0,
				rounding = 0,
				decorate = false,
				no_shadow = true,
				-- Renderer::shouldUseNewBlurOptimizations otherwise uses the
				-- cached wallpaper for tiles, covering the windows underneath.
				-- Explicit false selects live blur without disabling blur globally.
				xray = false,
			})
		elseif entry.enabled ~= enabled then
			entry.enabled = enabled
			entry.gaps:set_enabled(enabled)
			entry.windows:set_enabled(enabled)
		end
	end

	function instance.remove(ws)
		instance.sync(ws, false)
		rules[ws.id] = nil
	end

	function instance.raise(window)
		if raising or not window or not window.mapped or window.floating
			or (window.fullscreen or 0) ~= 0
			or (window.workspace and window.workspace.has_fullscreen) then
			return
		end
		-- Focus alone doesn't raise a tiled target in the Lua layout provider.
		-- alter_zorder also simulates pointer movement, so guard re-entry.
		raising = true
		hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = window }))
		raising = false
	end

	return instance
end

return M
