-- Run from ~/.config/hypr: lua tests/presel_feedback_test.lua
local feedback = require("lua/presel_feedback")
local tests = {}
package.loaded["lua/bspwm_state"] = { open_session = function() return nil end }

-- These are synthetic outputs, never connector names from lua/vars or the host.
local function monitor_fixture(index, properties)
	local mon = { name = "fixture-output-" .. index, dpms_status = true }
	for key, value in pairs(properties or {}) do mon[key] = value end
	return mon
end

local function expect_box(b, x, y, w, h)
	assert(b and b.x == x and b.y == y and b.w == w and b.h == h,
		"unexpected preview geometry")
end

local function fixture(count)
	local f = { windows = {}, previews = {}, publishes = 0 }
	local provider
	local ws = { id = 1, visible = true, has_fullscreen = false, tiled_layout = "lua:bspwm",
		monitor = monitor_fixture(1, { position = { x = 3840, y = 0 } }) }
	local ctx = { area = { x = 3840, y = 40, w = 3840, h = 2160 }, targets = {} }
	f.ws, f.ctx = ws, ctx
	_G.hl = {
		layout = { register = function(name, impl) if name == "bspwm" then provider = impl end end },
		window_rule = function() end, on = function() end,
		dispatch = function(callback) return callback() end,
		dsp = { window = { tag = function() return function() end end } },
	}
	local layout = dofile("bspwm.lua")
	layout.set_feedback_sink(function(states)
		f.states = states
		f.previews = feedback.rectangles(states, {ws}, f.windows)
		f.publishes = f.publishes + 1
	end)
	function f.recalculate() provider.recalculate(ctx) end
	function f.focus(id)
		for _, w in ipairs(f.windows) do w.active = w.stable_id == id end
	end
	function f.open(id)
		local w = { stable_id = id, workspace = ws, mapped = true, active = false, floating = false }
		f.windows[#f.windows + 1] = w
		local target = { window = w }
		function target:place(box) self.box = box end
		ctx.targets[#ctx.targets + 1] = target
		f.recalculate(); f.focus(id)
		return target
	end
	function f.message(msg)
		assert(provider.layout_msg(ctx, msg) == true)
		f.recalculate()
	end
	for id = 1, count or 1 do f.open(id) end
	return f
end

function tests.directions_ratios_and_negative_origin()
	local box = { x = -1000, y = 40, w = 1000, h = 800 }
	expect_box(feedback.preview_box(box, { dir = "l", ratio = 0.3 }), -1000, 40, 300, 800)
	expect_box(feedback.preview_box(box, { dir = "r", ratio = 0.3 }), -700, 40, 700, 800)
	expect_box(feedback.preview_box(box, { dir = "u", ratio = 0.3 }), -1000, 40, 1000, 240)
	expect_box(feedback.preview_box(box, { dir = "d", ratio = 0.3 }), -1000, 280, 1000, 560)
end

function tests.rounding_matches_layout_split()
	local box = { x = 10, y = 20, w = 101, h = 99 }
	expect_box(feedback.preview_box(box, { dir = "east", ratio = 0.5 }), 60, 20, 51, 99)
	expect_box(feedback.preview_box(box, { dir = "south", ratio = 0.5 }), 10, 69, 101, 50)
end

function tests.no_preselection_means_no_overlay()
	local f = fixture(4)
	assert(#f.previews == 0)
end

for _, direction in ipairs({ "l", "r", "u", "d" }) do
	tests["preview_matches_inserted_window_" .. direction] = function()
		local f = fixture(4)
		f.message("focus parent"); f.message("focus parent")
		f.message("preselect " .. direction); f.message("pratio 0.3")
		assert(#f.previews == 1)
		local preview = f.previews[1]
		local new = f.open(5)
		expect_box(new.box, preview.x, preview.y, preview.w, preview.h)
		assert(#f.previews == 0, "consumed preselection remained visible")
	end
end

function tests.ratio_and_direction_changes_update_overlay()
	local f = fixture()
	f.message("preselect r")
	expect_box(f.previews[1], 5760, 40, 1920, 2160)
	f.message("pratio 0.25")
	expect_box(f.previews[1], 4800, 40, 2880, 2160)
	f.message("preselect u")
	expect_box(f.previews[1], 3840, 40, 3840, 540)
end

function tests.multiple_node_preselections_and_cancel()
	local f = fixture(4)
	f.message("preselect u")
	f.focus(1); f.message("preselect l")
	assert(#f.previews == 2)
	f.message("preselect cancel")
	assert(#f.previews == 1, "cancel should clear only the focused node")
	f.message("preselect clear")
	assert(#f.previews == 0)
end

function tests.hidden_fullscreen_monocle_dpms_and_other_layout()
	local f = fixture()
	f.message("preselect r")
	for _, property in ipairs({ "hidden", "fullscreen", "monocle", "dpms", "layout", "special" }) do
		f.ws.visible = property ~= "hidden"
		f.ws.has_fullscreen = property == "fullscreen"
		f.states[1].mode = property == "monocle" and "monocle" or "tiled"
		f.ws.monitor.dpms_status = property ~= "dpms"
		f.ws.tiled_layout = property == "layout" and "dwindle" or "lua:bspwm_b"
		f.ws.monitor.active_special_workspace = property == "special" and { id = 99 } or nil
		f.recalculate()
		assert(#f.previews == 0, "preview not hidden for " .. property)
	end
	f.ws.monitor.active_special_workspace = nil
	f.recalculate(); assert(#f.previews == 1, "returning to workspace should restore preview")
end

function tests.close_or_float_last_window_hides_feedback()
	for _, floating in ipairs({ false, true }) do
		local f = fixture()
		f.message("preselect r")
		f.windows[1].mapped = floating
		f.windows[1].floating = floating
		f.ctx.targets = {}
		f.recalculate()
		assert(#f.previews == 0, "empty workspace kept an old preview")
	end
end

function tests.monitor_geometry_change_repositions_feedback()
	local f = fixture()
	f.message("preselect d")
	f.ctx.area = { x = -1080, y = 100, w = 1080, h = 1820 }
	f.recalculate()
	expect_box(f.previews[1], -1080, 1010, 1080, 910)
end

function tests.moved_window_does_not_leave_feedback_on_old_workspace()
	local f = fixture()
	f.message("preselect r")
	f.windows[1].workspace = { id = 2 }
	assert(#feedback.rectangles(f.states, {f.ws}, f.windows) == 0)
end

function tests.multiple_visible_monitors_and_special_workspace()
	local windows, states, workspaces = {}, {}, {}
	for i = 1, 2 do
		workspaces[i] = { id = i, visible = true, tiled_layout = "lua:bspwm",
			monitor = monitor_fixture(i, { active_special_workspace = i == 2 and { id = i } or nil }) }
		windows[i] = { stable_id = i, mapped = true, workspace = workspaces[i] }
		states[i] = { mode = "tiled", tree = { t = "leaf", id = i,
			_box = { x = (i - 1) * 1920, y = 0, w = 1920, h = 1080 },
			presel = { dir = "r", ratio = 0.5 } } }
	end
	local previews = feedback.rectangles(states, workspaces, windows)
	assert(#previews == 2)
	expect_box(previews[1], 960, 0, 960, 1080)
	expect_box(previews[2], 2880, 0, 960, 1080)
end

function tests.state_uses_runtime_name_and_monitor_geometry()
	local mon = monitor_fixture(7)
	assert(feedback.encode({}) == '{"version":3,"rectangles":[]}\n')
	assert(feedback.encode({ {output=mon.name, x=-100, y=40, w=80, h=60,
		monitor_x=-1920, monitor_y=0, monitor_w=1920, monitor_h=1080} })
		== string.format('{"version":3,"rectangles":[{"output":"%s","box":[1820,40,80,60],"monitor":[-1920,0,1920,1080]}]}\n', mon.name))
end

function tests.output_names_are_escaped_not_restricted_to_hardware_patterns()
	local mon = monitor_fixture(1)
	mon.name = 'fixture "quoted"\\name\n'
	local encoded = feedback.encode({ {output=mon.name, x=0, y=0, w=10, h=10,
		monitor_x=0, monitor_y=0, monitor_w=100, monitor_h=100} })
	assert(encoded:find('fixture \\"quoted\\"\\\\name\\u000a', 1, true))
end

function tests.single_to_two_window_preview_includes_future_outer_and_inner_gaps()
	local f = fixture()
	f.ws.monitor.width, f.ws.monitor.height, f.ws.monitor.scale = 3840, 2160, 1
	f.ws.monitor.reserved = { top = 40 }
	f.message("preselect r")
	-- Old root covers the gapless workarea. On opening a second tile, outer
	-- gaps become 8; the shared boundary also gets a 4px gap on each side.
	local previews = feedback.rectangles(f.states, {f.ws}, f.windows, { gaps_in = 4, gaps_out = 8 })
	expect_box(previews[1], 5764, 48, 1908, 2104)
	-- Compare with the actual provider given the post-insertion Space workarea.
	f.ctx.area = { x = 3848, y = 48, w = 3824, h = 2104 }
	local new = f.open(2)
	expect_box(new.box, 5760, 48, 1912, 2104)
	-- WindowTarget reserves a 1px border *inside* the gap-adjusted tile.
	local client = { x = new.box.x + 4 + 1, y = new.box.y + 1,
		w = new.box.w - 4 - 2, h = new.box.h - 2 }
	expect_box(previews[1], client.x - 1, client.y - 1, client.w + 2, client.h + 2)
end

function tests.subtree_preview_reflows_from_future_workarea_then_applies_gaps()
	local f = fixture(4)
	f.ws.monitor.width, f.ws.monitor.height, f.ws.monitor.scale = 3840, 2160, 1
	f.ws.monitor.reserved = { top = 40 }
	f.message("focus parent"); f.message("focus parent")
	f.message("preselect d"); f.message("pratio 0.3")
	local previews = feedback.rectangles(f.states, {f.ws}, f.windows, { gaps_in = 4, gaps_out = 8 })
	-- Future subtree: x=5760,y=48,w=1912,h=2104. First child takes floor(.3*h)=631.
	expect_box(previews[1], 5764, 683, 1908, 1469)
	f.ctx.area = { x = 3848, y = 48, w = 3824, h = 2104 }
	local new = f.open(5)
	expect_box(new.box, 5760, 679, 1912, 1473)
end

function tests.asymmetric_gaps_and_rotated_scaled_output()
	local ws = { monitor = { width = 3840, height = 2160, scale = 1.5, transform = 1,
		position = { x = -1440, y = 0 }, reserved = { top = 30, bottom = 10 } } }
	local area = feedback.future_area({}, ws, { left=8, right=12, top=6, bottom=4 })
	expect_box(area, -1432, 36, 1420, 2510)
	local tile = feedback.preview_box(area, { dir="r", ratio=0.5 })
	expect_box(feedback.window_box(tile, area, { left=4, right=7, top=5, bottom=9 }), -718, 36, 706, 2510)
end

function tests.runtime_publisher_atomic_updates_startup_and_shutdown()
	local marker = os.tmpname()
	os.remove(marker)
	local runtime = marker:match("^(.*)/")
	local signature = "test-" .. marker:match("([^/]+)$")
	local base = runtime .. "/bspwm_presel_" .. signature
	local state_path = base .. ".v3.json"
	local old_hl, old_getenv, old_rename = _G.hl, os.getenv, os.rename
	local events, commands, renames, ready, tick, timer_enabled = {}, {}, 0, false, nil, true
	local ws = { id = 1, visible = true, tiled_layout = "lua:bspwm", monitor = monitor_fixture(3) }
	local windows = { { stable_id = 1, mapped = true, workspace = ws } }
	local states = { [1] = { mode = "tiled", tree = { t = "leaf", id = 1,
		_box = { x = 0, y = 0, w = 1000, h = 800 }, presel = { dir = "r", ratio = 0.5 } } } }
	local function read_state(path)
		local file = assert(io.open(path or state_path, "r"))
		local data = file:read("*a"); file:close(); return data
	end
	local ok, err = pcall(function()
		os.getenv = function(key)
			if key == "XDG_RUNTIME_DIR" then return runtime end
			if key == "HYPRLAND_INSTANCE_SIGNATURE" then return signature end
			if key == "HOME" then return "/home/test'user" end
			return old_getenv(key)
		end
		os.rename = function(from, to)
			if to == state_path then renames = renames + 1 end
			return old_rename(from, to)
		end
		_G.hl = {
			on = function(name, fn) events[name] = fn end,
			get_monitors = function() return ready and {{}} or {} end,
			get_workspaces = function() return {ws} end,
			get_windows = function() return windows end,
			get_config = function() return 0 end,
			timer = function(fn, opts)
				assert(opts.type == "repeat" and opts.timeout == 50)
				tick = fn
				return { set_enabled = function(_, value) timer_enabled = value end }
			end,
			exec_cmd = function(cmd) commands[#commands + 1] = cmd end,
		}
		local sink
		feedback.setup({ set_feedback_sink = function(fn) sink = fn; fn(states) end })
		events["config.reloaded"]()
		assert(#commands == 0 and renames == 0, "must wait for outputs on startup")
		ready = true
		events["hyprland.start"]()
		assert(#commands == 1 and renames == 1)
		assert(commands[1]:find("test'\\''user", 1, true), "helper path must be shell-quoted")
		assert(commands[1]:find("python3 ", 1, true) == 1)
		assert(commands[1]:find("presel_feedback.py", 1, true))
		assert(commands[1]:find(" --state '" .. state_path .. "'", 1, true))
		for _, suffix in ipairs({ ".state", ".json" }) do
			assert(commands[1]:find(" --legacy-state '" .. base .. suffix .. "'", 1, true))
		end
		assert(read_state(base .. ".state") == "BSPWM_PRESEL_V2\n")
		assert(read_state(base .. ".json") == '{"version":1,"rectangles":[]}\n')
		assert(read_state() == string.format('{"version":3,"rectangles":[{"output":"%s","box":[500,0,500,800],"monitor":[0,0,1000,800]}]}\n', ws.monitor.name))
		tick(); sink(states); events["config.reloaded"]()
		assert(renames == 1 and #commands == 1, "unchanged state rewrote file or duplicated timer/helper")
		ws.visible = false; tick()
		assert(read_state() == feedback.encode({}))
		ws.visible = true; tick()
		assert(renames == 3)
		assert(read_state(base .. ".state") == "BSPWM_PRESEL_V2\n", "new frames reached the old native reader")
		events["hyprland.shutdown"]()
		assert(not timer_enabled and read_state() == feedback.encode({}))
	end)
	_G.hl, os.getenv, os.rename = old_hl, old_getenv, old_rename
	os.remove(state_path); os.remove(state_path .. ".tmp")
	os.remove(base .. ".json"); os.remove(base .. ".json.tmp")
	os.remove(base .. ".state"); os.remove(base .. ".state.tmp")
	assert(ok, err)
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
