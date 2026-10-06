-- Run from ~/.config/hypr: lua tests/bspwm_layout_test.lua
-- Exercises the real provider using the installed HL.LayoutContext API shape.
local tests = {}

local function fixture(width, height, x, y)
	local providers = {}
	_G.hl = {
		layout = { register = function(name, impl) providers[name] = impl end },
		on = function() end,
		window_rule = function() end,
	}
	dofile("bspwm.lua")
	local provider = assert(providers.bspwm)
	local ctx = { area = { x = x or 0, y = y or 0, w = width, h = height }, targets = {} }
	local f = { ctx = ctx }

	function f.add(id, workspace_id)
		local target = { window = {
			stable_id = id, workspace = { id = workspace_id or 1 },
			mapped = true, active = false, focus_history_id = -1,
		} }
		function target:place(box)
			self.box = { x = box.x, y = box.y, w = box.w, h = box.h }
		end
		ctx.targets[#ctx.targets + 1] = target
		return target
	end

	function f.focus(id)
		for _, target in ipairs(ctx.targets) do
			local w = target.window
			w.active = w.stable_id == id
			if w.active then
				w.focus_history_id = 0
			elseif w.focus_history_id >= 0 then
				w.focus_history_id = w.focus_history_id + 1
			end
		end
	end

	function f.recalculate()
		provider.recalculate(ctx)
	end

	function f.open(id)
		f.add(id)
		f.recalculate() -- mapping can happen before focus changes
		f.focus(id)
	end

	function f.message(msg)
		assert(provider.layout_msg(ctx, msg) == true)
		f.recalculate()
	end

	function f.expect(id, x0, y0, w0, h0)
		for _, target in ipairs(ctx.targets) do
			if target.window.stable_id == id then
				local b = assert(target.box, "window was not placed: " .. id)
				assert(b.x == x0 and b.y == y0 and b.w == w0 and b.h == h0,
					string.format("window %d: expected (%g,%g %gx%g), got (%g,%g %gx%g)",
						id, x0, y0, w0, h0, b.x, b.y, b.w, b.h))
				return
			end
		end
		error("missing window: " .. id)
	end

	return f
end

function tests.longest_side_sequential()
	local f = fixture(3840, 2160)
	f.open(1)
	f.expect(1, 0, 0, 3840, 2160)
	f.open(2)
	f.expect(1, 0, 0, 1920, 2160)
	f.expect(2, 1920, 0, 1920, 2160)
	f.open(3)
	f.expect(1, 0, 0, 1920, 2160)
	f.expect(2, 1920, 0, 1920, 1080)
	f.expect(3, 1920, 1080, 1920, 1080)
	f.open(4)
	f.expect(3, 1920, 1080, 960, 1080)
	f.expect(4, 2880, 1080, 960, 1080)
end

function tests.portrait_and_square()
	local f = fixture(1080, 1920)
	f.open(1)
	f.open(2)
	f.expect(1, 0, 0, 1080, 960)
	f.expect(2, 0, 960, 1080, 960)
	f.open(3)
	f.expect(3, 540, 960, 540, 960)
	f = fixture(1000, 1000)
	f.open(1)
	f.open(2)
	f.expect(2, 0, 500, 1000, 500) -- bspwm uses width > height, not >=
end

function tests.batch_rebuild()
	local f = fixture(3840, 2160)
	for id = 1, 4 do f.add(id) end
	f.focus(4)
	f.recalculate()
	f.expect(1, 0, 0, 1920, 2160)
	f.expect(2, 1920, 0, 1920, 1080)
	f.expect(3, 1920, 1080, 960, 1080)
	f.expect(4, 2880, 1080, 960, 1080)
end

function tests.split_existing_focus_not_last_leaf()
	local f = fixture(3840, 2160)
	for id = 1, 3 do f.open(id) end
	f.focus(1)
	f.open(4)
	f.expect(1, 0, 0, 1920, 1080)
	f.expect(4, 0, 1080, 1920, 1080)
	f.expect(3, 1920, 1080, 1920, 1080)
end

function tests.new_window_already_focused()
	-- The active target may already be the new window, not in the tree yet.
	-- Use the most recently focused surviving leaf, not the last tree leaf.
	local f = fixture(3840, 2160)
	for id = 1, 3 do f.open(id) end
	f.focus(1)
	f.add(4)
	f.focus(4)
	f.recalculate()
	f.expect(1, 0, 0, 1920, 1080)
	f.expect(4, 0, 1080, 1920, 1080)
end

function tests.inactive_workspace_uses_focus_history()
	local f = fixture(3840, 2160)
	for id = 1, 3 do f.open(id) end
	f.focus(1)
	for _, t in ipairs(f.ctx.targets) do t.window.active = false end
	f.add(4)
	f.recalculate()
	f.expect(4, 0, 1080, 1920, 1080)
end

function tests.current_area_used_after_resize()
	local f = fixture(3840, 2160)
	f.open(1)
	f.ctx.area = { x = 3840, y = 40, w = 1080, h = 1920 }
	f.open(2)
	f.expect(1, 3840, 40, 1080, 960)
	f.expect(2, 3840, 1000, 1080, 960)
end

function tests.prune_before_insertion()
	local f = fixture(3840, 2160)
	f.open(1)
	f.open(2)
	table.remove(f.ctx.targets, 1)
	f.open(3) -- survivor now covers the whole screen, not its old narrow box
	f.expect(2, 0, 0, 1920, 2160)
	f.expect(3, 1920, 0, 1920, 2160)
end

function tests.preselection_overrides_automatic_once()
	local directions = {
		{ "l", 0, 0, 1920, 2160 }, { "r", 1920, 0, 1920, 2160 },
		{ "u", 0, 0, 3840, 1080 }, { "d", 0, 1080, 3840, 1080 },
	}
	for _, d in ipairs(directions) do
		local f = fixture(3840, 2160)
		f.open(1)
		f.message("preselect " .. d[1])
		f.open(2)
		f.expect(2, d[2], d[3], d[4], d[5])
	end
	local f = fixture(3840, 2160)
	f.open(1)
	f.message("preselect u")
	f.open(2)
	f.open(3) -- top region is wide; do not repeat preselect u
	f.expect(3, 1920, 0, 1920, 1080)
end

function tests.cancel_preselection()
	local f = fixture(1080, 1920)
	f.open(1)
	f.message("preselect l")
	f.message("preselect cancel")
	f.open(2)
	f.expect(2, 0, 960, 1080, 960)
end

function tests.monocle_restores_tree()
	local f = fixture(3840, 2160, 3840, 20)
	for id = 1, 3 do f.open(id) end
	f.message("monocle")
	for id = 1, 3 do f.expect(id, 3840, 20, 3840, 2160) end
	f.open(4)
	f.message("tiled")
	f.expect(1, 3840, 20, 1920, 2160)
	f.expect(4, 6720, 1100, 960, 1080)
end

function tests.workspace_isolation()
	local f = fixture(3840, 2160)
	f.open(1)
	f.open(2)
	local first_targets = f.ctx.targets
	f.ctx.targets = {}
	f.add(3, 2)
	f.recalculate()
	f.focus(3)
	f.add(4, 2)
	f.recalculate()
	f.expect(3, 0, 0, 1920, 2160)
	f.ctx.targets = first_targets
	f.open(5)
	f.expect(1, 0, 0, 1920, 2160)
	f.expect(5, 1920, 1080, 1920, 1080)
end

local names = {}
for name in pairs(tests) do names[#names + 1] = name end
table.sort(names)
local failures = 0
for _, name in ipairs(names) do
	local ok, err = pcall(tests[name])
	if ok then
		print("PASS " .. name)
	else
		failures = failures + 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
print(string.format("%d/%d tests passed", #names - failures, #names))
os.exit(failures == 0 and 0 or 1)
