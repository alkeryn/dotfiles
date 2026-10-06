-- Run from ~/.config/hypr: lua tests/resize_bindings_test.lua
-- Loads the actual bindings, helpers and layout. The floating dispatcher mock
-- models v0.56.2's center-based resize and exposes updated goal geometry.
local tests = {}
package.loaded["lua/extensions/bspwm_state"] = { open_session = function() return nil end }
package.loaded["lua/vars"] = { GAPS = 4, GAPS_OUT = 8, FLOAT_STEP = 20, terminal = "alacritty" }

local function fixture()
	local f = { binds = {}, messages = {}, resize_calls = 0, move_calls = 0, native_targets = {} }
	local provider
	local ctx = { area = { x = 0, y = 0, w = 1000, h = 800 }, targets = {} }
	f.ctx = ctx
	local function ignored_dispatcher() return function() end end
	local window_dsp = setmetatable({}, { __index = function() return ignored_dispatcher end })

	function window_dsp.tag(opts)
		return function()
			local tags, value = opts.window.tags, opts.tag:sub(2)
			for i, tag in ipairs(tags) do
				if tag == value then
					if opts.tag:sub(1, 1) == "-" then table.remove(tags, i) end
					return { ok = true }
				end
			end
			if opts.tag:sub(1, 1) == "+" then tags[#tags + 1] = value end
			return { ok = true }
		end
	end

	function window_dsp.pseudo(opts)
		return function()
			local target = assert(f.native_targets[opts.window])
			target.pseudo = opts.action == "on"
			target:place(target.box)
			return { ok = true }
		end
	end

	function window_dsp.resize(opts)
		if not opts then return ignored_dispatcher() end -- mouse binding
		return function()
			f.resize_calls = f.resize_calls + 1
			if f.reject_resize then return { ok = false } end
			local w = assert(opts.window, "resize must explicitly target the focused window")
			local target = f.native_targets[w]
			if target and target.pseudo then
				-- Native LayoutManager::resizeTarget consumes pseudo deltas before
				-- the Lua provider, clamps its stored size, then recenters in place.
				assert(opts.relative, "pseudo resize must use native size deltas")
				target.pseudo_size.x = math.min(target.box.w, math.max(20, target.pseudo_size.x + opts.x))
				target.pseudo_size.y = math.min(target.box.h, math.max(20, target.pseudo_size.y + opts.y))
				target:place(target.box)
				return { ok = true }
			end
			local sx = opts.relative and w.size.x + opts.x or opts.x
			local sy = opts.relative and w.size.y + opts.y or opts.y
			assert(sx >= 1 and sy >= 1, "non-positive requested size")
			-- A resize can be constrained; position correction must use the
			-- resulting size, not assume the whole requested step was applied.
			local min_size = f.min_size or { x = 1, y = 1 }
			local max_size = f.max_size or { x = math.huge, y = math.huge }
			local nx = math.min(max_size.x, math.max(min_size.x, sx))
			local ny = math.min(max_size.y, math.max(min_size.y, sy))
			w.at = { x = w.at.x - (sx - w.size.x) / 2, y = w.at.y - (sy - w.size.y) / 2 }
			w.size = { x = nx, y = ny }
			return { ok = true }
		end
	end

	function window_dsp.move(opts)
		return function()
			f.move_calls = f.move_calls + 1
			local w = assert(opts.window)
			w.at = {
				x = opts.relative and w.at.x + opts.x or opts.x,
				y = opts.relative and w.at.y + opts.y or opts.y,
			}
			return { ok = true }
		end
	end

	_G.hl = {
		on = function() end,
		window_rule = function() end,
		layout = { register = function(name, impl) if name == "bspwm" then provider = impl end end },
		get_active_window = function() return f.active end,
		get_windows = function()
			local windows = {}
			for _, t in ipairs(ctx.targets) do windows[#windows + 1] = t.window end
			return windows
		end,
		bind = function(keys, callback, opts) f.binds[keys] = { callback = callback, opts = opts } end,
		dispatch = function(callback) return callback() end,
		dsp = setmetatable({
			window = window_dsp,
			layout = function(msg)
				return function()
					f.messages[#f.messages + 1] = msg
					assert(provider.layout_msg(ctx, msg) == true)
					provider.recalculate(ctx)
					return { ok = true }
				end
			end,
		}, { __index = function() return ignored_dispatcher end }),
	}
	for _, name in ipairs({ "lua/extensions/bspwm", "lua/helpers", "lua/bindings" }) do package.loaded[name] = nil end
	require("lua/bindings")

	function f.press(key, shrink)
		local mods = shrink and "SUPER + ALT + CTRL + " or "SUPER + ALT + "
		local bind = assert(f.binds[mods .. key])
		assert(bind.opts.repeating, "resize should repeat while held")
		bind.callback()
	end

	function f.floating()
		f.active = { mapped = true, floating = true, fullscreen = 0,
			at = { x = 100, y = 200 }, size = { x = 800, y = 600 } }
		for _, t in ipairs(ctx.targets) do t.window.active = false end
		return f.active
	end

	function f.tiled(vertical, focused_id)
		ctx.area = vertical and { x = 0, y = 0, w = 800, h = 1000 } or ctx.area
		for id = 1, 2 do
			local t = { window = { stable_id = id, workspace = { id = 1 }, mapped = true, tags = {},
				floating = false, fullscreen = 0, active = id == focused_id }, pseudo_size = { x = 200, y = 150 } }
			-- Like HL.Window, the Lua window has no readable pseudo property.
			f.native_targets[t.window] = t
			function t:place(box)
				self.box = box
				local sx, sy = box.w, box.h
				if self.pseudo then
					local scale = math.min(1, sx / self.pseudo_size.x, sy / self.pseudo_size.y)
					sx, sy = self.pseudo_size.x * scale, self.pseudo_size.y * scale
				end
				self.window.size = { x = sx, y = sy }
				self.window.at = { x = box.x + (box.w - sx) / 2, y = box.y + (box.h - sy) / 2 }
			end
			ctx.targets[#ctx.targets + 1] = t
			if t.window.active then f.active = t.window end
		end
		provider.recalculate(ctx)
	end

	function f.expect_float(x, y, width, height)
		local w = f.active
		assert(w.at.x == x and w.at.y == y and w.size.x == width and w.size.y == height,
			string.format("expected (%g,%g %gx%g), got (%g,%g %gx%g)",
				x, y, width, height, w.at.x, w.at.y, w.size.x, w.size.y))
		assert(#f.messages == 0, "floating resize reached the tiled layout")
	end

	return f
end

local grow_cases = {
	h = { 80, 200, 820, 600 }, j = { 100, 200, 800, 620 },
	k = { 100, 180, 800, 620 }, l = { 100, 200, 820, 600 },
}
local shrink_cases = {
	h = { 100, 200, 780, 600 }, j = { 100, 220, 800, 580 },
	k = { 100, 200, 800, 580 }, l = { 120, 200, 780, 600 },
}
local unpack_values = table.unpack or unpack
for key, expected in pairs(grow_cases) do
	tests["floating_grow_" .. key] = function()
		local f = fixture()
		f.floating()
		f.press(key)
		f.expect_float(unpack_values(expected))
	end
end
for key, expected in pairs(shrink_cases) do
	tests["floating_shrink_" .. key] = function()
		local f = fixture()
		f.floating()
		f.press(key, true)
		f.expect_float(unpack_values(expected))
	end
end

local edge_for_key = { h = "l", j = "d", k = "u", l = "r" }
local opposite = { l = "r", r = "l", u = "d", d = "u" }
for key, edge in pairs(edge_for_key) do
	for _, shrink in ipairs({ false, true }) do
		local name = "tiled_" .. (shrink and "shrink_" or "grow_") .. key
		tests[name] = function()
			local f = fixture()
			local actual_edge = shrink and opposite[edge] or edge
			local vertical = actual_edge == "u" or actual_edge == "d"
			local id = (actual_edge == "r" or actual_edge == "d") and 1 or 2
			f.tiled(vertical, id)
			f.press(key, shrink)
			local box = f.ctx.targets[id].box
			local expected_size = shrink and 480 or 520
			assert((vertical and box.h or box.w) == expected_size, "wrong tiled resize amount or edge")
			assert(f.messages[1] == (shrink and "shrink " or "grow ") .. actual_edge .. " 20")
			assert(f.resize_calls == 0 and f.move_calls == 0, "tiled resize used floating API")
		end
	end
end

function tests.floating_does_not_resize_tiles()
	local f = fixture()
	f.tiled(false, 1)
	f.floating()
	f.press("l")
	f.expect_float(100, 200, 820, 600)
	assert(f.ctx.targets[1].box.w == 500 and f.ctx.targets[2].box.w == 500)
end

function tests.repeated_float_resize_is_reversible()
	local f = fixture()
	f.floating()
	for _ = 1, 10 do f.press("h") end -- move left edge outward
	f.expect_float(-100, 200, 1000, 600)
	for _ = 1, 10 do f.press("l", true) end -- move left edge inward
	f.expect_float(100, 200, 800, 600)
end

function tests.minimum_size_does_not_drift()
	local f = fixture()
	f.floating()
	f.min_size = { x = 795, y = 595 }
	for _ = 1, 3 do f.press("l", true); f.press("j", true) end
	f.expect_float(105, 205, 795, 595)
end

function tests.maximum_size_does_not_drift()
	local f = fixture()
	f.floating()
	f.max_size = { x = 805, y = 605 }
	for _ = 1, 3 do f.press("h"); f.press("k") end
	f.expect_float(95, 195, 805, 605)
end

function tests.positive_size_floor()
	local f = fixture()
	local w = f.floating()
	w.size = { x = 10, y = 10 }
	for _ = 1, 3 do f.press("l", true); f.press("j", true) end
	f.expect_float(109, 209, 1, 1)
end

function tests.failed_resize_does_not_move()
	local f = fixture()
	f.floating()
	f.reject_resize = true
	f.press("h")
	f.expect_float(100, 200, 800, 600)
	assert(f.move_calls == 0)
end

function tests.no_focus_fullscreen_and_unmapped_are_noops()
	local f = fixture()
	f.press("h")
	local w = f.floating()
	w.fullscreen = 2
	f.press("h")
	w.fullscreen = 0
	w.mapped = false
	f.press("h")
	assert(f.resize_calls == 0 and f.move_calls == 0 and #f.messages == 0)
end

function tests.tiled_outer_edge_is_noop()
	local f = fixture()
	f.tiled(false, 1)
	f.press("h")
	assert(f.ctx.targets[1].box.w == 500)
end

for key, edge in pairs(edge_for_key) do
	for _, shrink in ipairs({ false, true }) do
		tests["pseudo_" .. (shrink and "shrink_" or "grow_") .. key .. "_resizes_client_not_split"] = function()
			local f = fixture()
			f.tiled(false, 1)
			f.binds["SUPER + t"].callback()
			local delta = shrink and -20 or 20
			local horizontal = edge == "l" or edge == "r"
			for i = 1, 3 do
				f.press(key, shrink)
				local w = f.active
				assert(w.size.x == 200 + (horizontal and i * delta or 0))
				assert(w.size.y == 150 + (horizontal and 0 or i * delta))
				assert(w.at.x + w.size.x / 2 == 250 and w.at.y + w.size.y / 2 == 400, "pseudo lost centering")
				assert(f.ctx.targets[1].box.w == 500 and f.ctx.targets[2].box.x == 500, "pseudo changed BSP split")
			end
			assert(f.resize_calls == 3 and f.move_calls == 0 and #f.messages == 0)
		end
	end
end

function tests.pseudo_clamp_does_not_fall_through_to_split_resize()
	local f = fixture()
	f.tiled(false, 1)
	f.binds["SUPER + t"].callback()
	for _ = 1, 30 do f.press("l"); f.press("j") end
	assert(f.active.size.x == 500 and f.active.size.y == 750)
	for _ = 1, 50 do f.press("h", true); f.press("k", true) end
	assert(f.active.size.x == 20 and f.active.size.y == 20)
	assert(f.ctx.targets[1].box.w == 500 and #f.messages == 0 and f.move_calls == 0)
end

function tests.pseudo_resize_after_reload_and_return_to_tiled()
	local f = fixture()
	f.tiled(false, 1)
	f.binds["SUPER + t"].callback()
	for _, name in ipairs({ "lua/helpers", "lua/bindings", "lua/extensions/bspwm_pseudo" }) do package.loaded[name] = nil end
	require("lua/bindings")
	f.press("l")
	assert(f.active.size.x == 220 and #f.messages == 0)
	f.binds["SUPER + s"].callback()
	f.press("l")
	assert(f.ctx.targets[1].box.w == 520 and f.active.size.x == 520)
	assert(f.resize_calls == 1 and f.messages[1] == "grow r 20")
end

function tests.pseudo_resize_failure_and_fullscreen_do_not_touch_splits()
	local f = fixture()
	f.tiled(false, 1)
	f.binds["SUPER + t"].callback()
	f.reject_resize = true
	f.press("l")
	f.active.fullscreen = 2
	f.press("l")
	assert(f.active.size.x == 200 and f.resize_calls == 1 and #f.messages == 0 and f.move_calls == 0)
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
