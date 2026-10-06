-- lua tests/bspwm_monocle_test.lua -- real provider, mocked rule/placement API.
-- Models Space's outer padding and WindowTarget's inner gaps + border insets.
-- Does not test compositor rendering; visual transparency still needs a desktop.
package.loaded["lua/extensions/bspwm_state"] = { open_session = function() return nil end }
local display = require("lua/extensions/bspwm_monocle")
local tests = {}

local function fixture()
	local f = { events = {}, workspace_rules = {}, window_rules = {}, raises = {}, windows = {} }
	local provider
	local mon = { position = { x = 3840, y = 0 }, width = 3840, height = 2160, scale = 1,
		reserved = { top = 40 } }
	local ws = { id = 1, name = "1", monitor = mon }
	local ctx = { targets = {} }
	f.mon, f.ws, f.ctx = mon, ws, ctx
	local function handle(spec)
		spec.enabled = spec.enabled ~= false
		function spec:set_enabled(enabled) self.enabled = enabled end
		return spec
	end
	local function matches(selector, workspace)
		return selector == tostring(workspace.id) or selector == "name:" .. workspace.name
			or selector == string.format("r[%d-%d]", workspace.id, workspace.id)
	end
	function f.emit(event, ...)
		for _, callback in ipairs(f.events[event] or {}) do callback(...) end
	end
	function f.gaps(workspace)
		local inner, outer = 9, 23
		for _, rule in ipairs(f.workspace_rules) do
			if rule.enabled and matches(rule.workspace, workspace) then
				inner, outer = rule.gaps_in or inner, rule.gaps_out or outer
			end
		end
		return inner, outer
	end
	function f.effect(window, key, default)
		local value = default
		for _, rule in ipairs(f.window_rules) do
			if rule.enabled and rule.match.workspace and matches(rule.match.workspace, window.workspace)
				and rule.match.float == window.floating and rule[key] ~= nil then value = rule[key] end
		end
		return value
	end
	function f.border(window) return f.effect(window, "border_size", 7) end
	_G.hl = {
		layout = { register = function(name, impl) if name == "bspwm" then provider = impl end end },
		on = function(event, callback)
			f.events[event] = f.events[event] or {}
			table.insert(f.events[event], callback)
		end,
		workspace_rule = function(spec)
			-- Like Hyprland: exact selector collisions merge, not independent handles.
			for _, rule in ipairs(f.workspace_rules) do
				if rule.enabled and rule.workspace == spec.workspace then
					for key, value in pairs(spec) do rule[key] = value end
					return rule
				end
			end
			table.insert(f.workspace_rules, handle(spec)); return spec
		end,
		window_rule = function(spec) table.insert(f.window_rules, handle(spec)); return spec end,
		get_windows = function()
			local windows = {}
			for _, w in pairs(f.windows) do windows[#windows + 1] = w end
			return windows
		end,
		dispatch = function(dispatcher) return dispatcher() end,
		dsp = { window = {
			alter_zorder = function(opts)
				assert(opts.mode == "top")
				return function()
					f.raises[#f.raises + 1] = opts.window.stable_id
					if f.reenter_raise then f.emit("window.active", opts.window) end
				end
			end,
			tag = function() return function() end end,
		} }, -- Deliberately NO fullscreen/hide/opacity dispatchers.
	}
	f.base_rule = hl.workspace_rule({ workspace = "1", monitor = "fixture-monitor", persistent = true })
	dofile("lua/extensions/bspwm.lua")
	function f.recalculate()
		local _, outer = f.gaps(ws)
		local bounds = display.monitor_box({ monitor = mon })
		local top = mon.reserved.top
		ctx.area = { x = bounds.x + outer, y = bounds.y + top + outer,
			w = bounds.w - 2 * outer, h = bounds.h - top - 2 * outer }
		provider.recalculate(ctx)
	end
	function f.focus(id)
		for _, window in pairs(f.windows) do window.active = window.stable_id == id end
		f.emit("window.active", f.windows[id])
	end
	function f.open(id)
		local window = { stable_id = id, workspace = ws, monitor = mon, mapped = true,
			active = false, floating = false, fullscreen = 0, hidden = false, opacity = 0.7 }
		local target = { window = window }
		function target:place(box)
			self.box = box
			local gap = f.gaps(window.workspace)
			local border = f.border(window)
			local area = ctx.area
			local left = (math.abs(box.x - area.x) < 2 and 0 or gap) + border
			local top = (math.abs(box.y - area.y) < 2 and 0 or gap) + border
			local right = (math.abs(box.x + box.w - area.x - area.w) < 2 and 0 or gap) + border
			local bottom = (math.abs(box.y + box.h - area.y - area.h) < 2 and 0 or gap) + border
			self.visual = { x = box.x + left, y = box.y + top,
				w = box.w - left - right, h = box.h - top - bottom }
		end
		f.windows[id] = window
		ctx.targets[#ctx.targets + 1] = target
		f.recalculate(); f.focus(id)
		return target
	end
	function f.message(message)
		assert(provider.layout_msg(ctx, message) == true)
		f.recalculate()
		f.recalculate() -- scheduled workspace-rule refresh updates ctx.area
	end
	f.open(1); f.open(2); f.open(3)
	return f
end

local function expect_box(box, x, y, w, h)
	assert(box.x == x and box.y == y and box.w == w and box.h == h,
		string.format("unexpected box: %g,%g %gx%g", box.x, box.y, box.w, box.h))
end

function tests.full_monitor_stack_without_gaps_borders_or_fullscreen()
	local f = fixture()
	f.message("monocle")
	assert(f.gaps(f.ws) == 0)
	for _, target in ipairs(f.ctx.targets) do
		expect_box(target.visual, 3840, 0, 3840, 2160) -- includes the reserved strip
		local w = target.window
		assert(f.border(w) == 0 and w.fullscreen == 0 and not w.hidden and w.opacity == 0.7)
	end
	assert(f.raises[#f.raises] == 3)
	assert(f.border({workspace = f.ws, floating = true}) == 7)
	local rule = f.window_rules[#f.window_rules]
	assert(rule.decorate == false and rule.no_shadow and rule.rounding == 0)
end

function tests.live_blur_is_scoped_to_monocle_tiles()
	local f = fixture()
	assert(f.effect(f.windows[1], "xray") == nil)
	f.message("monocle")
	for _, window in pairs(f.windows) do
		-- Explicit false opts out of cached wallpaper blur even with global
		-- new_optimizations enabled; absence of the property does not.
		assert(f.effect(window, "xray") == false)
		assert(f.effect(window, "no_blur") == nil, "keep blur enabled")
	end
	assert(f.effect({ workspace = f.ws, floating = true }, "xray") == nil)
	assert(f.effect({ workspace = { id = 2, name = "2" }, floating = false }, "xray") == nil)
	f.windows[1].floating = true
	assert(f.effect(f.windows[1], "xray") == nil)
	f.windows[1].floating = false
	f.message("tiled")
	for _, window in pairs(f.windows) do assert(f.effect(window, "xray") == nil) end
end

function tests.tiled_restores_original_geometry_and_rules()
	local f = fixture()
	local previous = {}
	for i, target in ipairs(f.ctx.targets) do previous[i] = target.visual end
	for _ = 1, 3 do f.message("mode"); f.message("mode") end
	for i, target in ipairs(f.ctx.targets) do
		local b = previous[i]
		expect_box(target.visual, b.x, b.y, b.w, b.h)
		assert(f.border(target.window) == 7)
	end
	local inner, outer = f.gaps(f.ws)
	assert(inner == 9 and outer == 23)
	assert(f.base_rule.enabled and f.base_rule.monitor == "fixture-monitor" and f.base_rule.persistent)
	assert(#f.workspace_rules == 2 and #f.window_rules == 2, "rules accumulated on mode toggles")
end

function tests.focus_changes_raise_without_relayout_and_guard_reentry()
	local f = fixture()
	f.message("monocle")
	f.reenter_raise = true
	local count = #f.raises
	f.focus(1)
	assert(#f.raises == count + 1 and f.raises[#f.raises] == 1)
	f.focus(2)
	assert(f.raises[#f.raises] == 2)
	f.message("tiled")
	count = #f.raises
	f.focus(3)
	assert(#f.raises == count, "tiled focus should not change stacking")
end

function tests.floats_and_real_fullscreen_are_not_raised_by_monocle()
	local f = fixture()
	f.message("monocle")
	local count = #f.raises
	f.windows[1].floating = true
	f.focus(1)
	f.windows[2].fullscreen = 2
	f.focus(2)
	f.ws.has_fullscreen = true
	f.focus(3)
	assert(#f.raises == count)
	assert(f.border(f.windows[1]) == 7)
end

function tests.other_workspace_and_moved_windows_keep_normal_rules()
	local f = fixture()
	f.message("monocle")
	local other = { id = 2, name = "2", monitor = f.mon }
	assert(f.gaps(other) == 9)
	f.windows[1].workspace = other
	f.emit("window.move_to_workspace", f.windows[1])
	assert(f.border(f.windows[1]) == 7)
	local count = #f.raises
	f.focus(1)
	assert(#f.raises == count)
end

function tests.new_windows_and_monitor_changes_fill_the_stack()
	local f = fixture()
	f.message("monocle")
	f.mon.position = { x = -1440, y = -100 }
	f.mon.width, f.mon.height, f.mon.scale, f.mon.transform = 3840, 2160, 1.5, 1
	f.open(4)
	for _, target in ipairs(f.ctx.targets) do expect_box(target.visual, -1440, -100, 1440, 2560) end
	assert(f.raises[#f.raises] == 4)
end

function tests.workspace_removal_disables_overrides()
	local f = fixture()
	f.message("monocle")
	f.emit("workspace.removed", f.ws)
	assert(not f.workspace_rules[2].enabled and not f.window_rules[2].enabled)
	assert(f.base_rule.enabled and f.gaps(f.ws) == 9)
end

function tests.named_workspaces_do_not_use_invalid_negative_ranges()
	local f = fixture()
	f.ws.id, f.ws.name = -1337, "named-fixture"
	f.recalculate(); f.message("monocle")
	assert(f.workspace_rules[2].workspace == "name:named-fixture")
	assert(f.window_rules[2].match.workspace == "name:named-fixture")
	f.message("tiled")
	assert(not f.workspace_rules[2].enabled)
end

local names = {}
for name in pairs(tests) do names[#names + 1] = name end
table.sort(names)
local failures = 0
for _, name in ipairs(names) do
	local ok, err = pcall(tests[name])
	if ok then print("PASS " .. name)
	else failures = failures + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
print(string.format("%d/%d tests passed", #names - failures, #names))
os.exit(failures == 0 and 0 or 1)
