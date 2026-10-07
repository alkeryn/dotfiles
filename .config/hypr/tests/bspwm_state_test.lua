-- lua tests/bspwm_state_test.lua -- no host session or monitor dependencies.
local codec = require("lua/extensions/bspwm_state")
local tests = {}
local paths = {}
local function temporary_path()
	local path = os.tmpname()
	os.remove(path)
	paths[#paths + 1] = path
	return path
end
local function read_file(path)
	local file = assert(io.open(path, "r"))
	local text = file:read("*a"); file:close(); return text
end

local function fixture()
	local f = { path=temporary_path(), windows={}, contexts={}, providers={}, events={}, binds={}, commands={}, raises={} }
	local function context(id)
		if not f.contexts[id] then
			f.contexts[id] = { area={ x=(id-1)*1200, y=20, w=1200, h=800 }, targets={} }
		end
		return f.contexts[id]
	end
	local function windows()
		local result = {}
		for _, w in pairs(f.windows) do if w.mapped then result[#result+1] = w end end
		return result
	end
	function f.emit(name, ...)
		for _, fn in ipairs(f.events[name] or {}) do fn(...) end
	end
	function f.recalculate(id)
		f.providers.bspwm.recalculate(context(id or 1))
	end
	function f.replay(provider)
		for _, ctx in pairs(f.contexts) do
			local subset = { area=ctx.area, targets={} }
			-- Reverse reattachment order to prove we restore topology, not order.
			for i = #ctx.targets, 1, -1 do
				subset.targets[#subset.targets+1] = ctx.targets[i]
				provider.recalculate(subset)
				if f.before_reload then
					assert(read_file(f.path) == f.before_reload, "partial hydration overwrote checkpoint")
				end
			end
		end
	end
	function f.load()
		f.events, f.providers, f.workspace_rules, f.window_rules = {}, {}, {}, {}
		local function rule_handle(spec)
			spec.enabled = spec.enabled ~= false
			function spec:set_enabled(enabled) self.enabled = enabled end
			return spec
		end
		package.loaded["lua/extensions/bspwm_state"] = { open_session=function() return codec.open(f.path) end }
		local function ignored_dispatcher() return function() end end
		_G.hl = {
			layout = { register=function(name, provider)
				f.providers[name] = provider
				f.replay(provider) -- native registration can synchronously call Lua
			end },
			on = function(name, fn)
				f.events[name] = f.events[name] or {}; table.insert(f.events[name], fn)
			end,
			window_rule = function(spec)
				f.window_rules[spec.name] = rule_handle(spec)
				return spec
			end,
			workspace_rule = function(spec)
				f.workspace_rules[spec.workspace] = rule_handle(spec)
				return spec
			end,
			get_windows = windows,
			get_active_window = function() return f.active end,
			exec_cmd = function(command) f.commands[#f.commands+1] = command end,
			bind = function(keys, callback) f.binds[keys] = callback end,
			dispatch = function(fn) return fn() end,
			dsp = setmetatable({ window=setmetatable({
				tag=function(opts) return function()
					local tag = opts.tag:sub(2)
					opts.window.tags[tag] = opts.tag:sub(1,1) == "+" or nil
				end end,
				alter_zorder=function(opts) return function()
					f.raises[#f.raises+1] = opts.window.stable_id
				end end,
			}, {__index=function() return ignored_dispatcher end}) },
			{__index=function() return ignored_dispatcher end}),
		}
		f.api = dofile("lua/extensions/bspwm.lua")
		f.api.set_feedback_sink(function(states) f.states = states end)
	end
	function f.finish_reload()
		f.emit("config.reloaded")
		-- The config flips to the other registered provider; this triggers a
		-- second series of partial callbacks AFTER config.reloaded.
		f.replay(f.providers.bspwm_b)
		f.emit("monitor.focused", {})
		f.emit("window.active", f.active, 7)
		f.emit("config.props_refreshed", true)
		f.before_reload = nil
		for id in pairs(f.contexts) do f.recalculate(id) end
	end
	function f.focus(id)
		for _, w in pairs(f.windows) do w.active = w.stable_id == id end
		f.active = f.windows[id]
		f.emit("window.active", f.active)
	end
	function f.open(id, wsid)
		wsid = wsid or 1
		local w = { stable_id=id, workspace={id=wsid}, active=false, mapped=true, floating=false, tags={personal=true} }
		f.windows[id] = w
		local target = {window=w}
		function target:place(box) self.box = box end
		table.insert(context(wsid).targets, target)
		f.recalculate(wsid); f.focus(id)
	end
	function f.message(msg, wsid)
		assert(f.providers.bspwm.layout_msg(context(wsid or 1), msg) == true)
		f.recalculate(wsid)
	end
	function f.reload()
		f.before_reload = read_file(f.path)
		f.load(); f.finish_reload()
	end
	function f.geometry()
		local boxes = {}
		for _, ctx in pairs(f.contexts) do
			for _, target in ipairs(ctx.targets) do
				local b = target.box
				boxes[target.window.stable_id] = table.concat({b.x,b.y,b.w,b.h}, ",")
			end
		end
		return boxes
	end
	function f.expect_geometry(expected)
		local actual = f.geometry()
		for id, box in pairs(expected) do assert(actual[id] == box, "geometry changed for leaf " .. id) end
	end
	f.load(); f.finish_reload()
	return f
end

function tests.codec_round_trip_preserves_references_not_userdata()
	local a = {t="leaf", id=11, n=1, _box={x=1}, window="must not persist"}
	local b = {t="leaf", id=12, n=2}
	local tree = {t="split", axis="v", ratio=0.37, a=a, b=b, presel={dir="u", ratio=0.3}}
	local states = { [7]={tree=tree, seq=2, mode="monocle", selected=tree, selected_focus_id=12,
		insertion_anchor=a, insertion_window_id=13, boxes={junk=true}, highlighted={junk=true}} }
	local text = codec.encode(states, {dir="west", ratio=0.25})
	local decoded = assert(codec.decode(text))
	local st = decoded.states[7]
	assert(st.selected == st.tree and st.insertion_anchor == st.tree.a)
	assert(st.tree.ratio == tree.ratio and st.tree.presel.ratio == 0.3)
	assert(st.tree.a.n == 1 and st.seq == 2 and st.mode == "monocle")
	assert(not st.tree.a._box and not st.tree.a.window and not next(st.boxes) and not next(st.highlighted))
	assert(decoded.pending.dir == "west" and codec.encode(decoded.states, decoded.pending) == text)
end

function tests.rotated_resized_swapped_tree_survives_repeated_reload()
	local f = fixture()
	for id=1,4 do f.open(id) end
	f.message("focus parent"); f.message("grow u 80"); f.message("focus parent")
	f.message("rotate 90")
	f.focus(1); f.message("swap r")
	local expected, saved = f.geometry(), read_file(f.path)
	for _=1,3 do
		f.reload(); f.expect_geometry(expected)
		assert(read_file(f.path) == saved, "saved topology/ratios/ages changed")
	end
end

function tests.swapped_selected_subtree_and_metadata_survive_repeated_reload()
	local f = fixture()
	for id = 1, 3 do f.open(id) end
	f.message("focus parent"); f.message("grow u 40")
	f.message("preselect r"); f.message("pratio 0.3")
	f.message("swap l")
	local expected, saved = f.geometry(), read_file(f.path)
	for _ = 1, 3 do
		f.reload(); f.expect_geometry(expected)
		assert(read_file(f.path) == saved)
		local st = f.states[1]
		assert(st.selected == st.tree.a and st.tree.b.id == 1 and st.selected_focus_id == 3)
		assert(st.selected.presel.dir == "r" and st.selected.presel.ratio == 0.3)
		assert(st.selected.a.n == 2 and st.selected.b.n == 3)
		for id = 2, 3 do assert(f.windows[id].tags.bspwm_selected) end
		f.message("swap r"); f.message("swap l")
		f.expect_geometry(expected)
		assert(read_file(f.path) == saved, "inverse swaps altered the selected subtree")
	end
end

function tests.reload_event_without_replacing_lua_state_keeps_tree()
	-- Hyprland retains the old Lua state when the new config fails syntax
	-- validation, but still emits config.reloaded and runs the alias flip.
	local f = fixture()
	for id=1,4 do f.open(id) end
	f.message("focus parent"); f.message("focus parent"); f.message("rotate 90")
	local expected = f.geometry()
	f.before_reload = read_file(f.path)
	f.finish_reload()
	f.expect_geometry(expected)
end

function tests.selection_preselection_and_insertion_age_survive_reload()
	local f = fixture()
	for id=1,4 do f.open(id) end
	f.message("focus parent"); f.message("focus parent")
	f.message("preselect u"); f.message("pratio 0.3")
	local saved = read_file(f.path)
	f.reload()
	assert(read_file(f.path) == saved)
	for id=2,4 do assert(f.windows[id].tags.bspwm_selected) end
	assert(not f.windows[1].tags.bspwm_selected and f.windows[1].tags.personal)
	local selected = f.states[1].selected
	assert(selected and selected.presel.dir == "u" and selected.presel.ratio == 0.3)
	assert(f.states[1].seq == 4)
	f.open(5)
	assert(not selected.presel and f.states[1].seq == 5)
	f.message("focus parent")
	for id=2,5 do assert(f.windows[id].tags.bspwm_selected) end
end

function tests.monocle_keeps_its_underlying_tree()
	local f = fixture()
	for id=1,4 do f.open(id) end
	f.message("focus parent"); f.message("rotate 270")
	local tiled = f.geometry()
	f.message("monocle")
	local monocle = f.geometry()
	f.reload(); f.expect_geometry(monocle)
	assert(f.states[1].mode == "monocle")
	f.raises = {}
	f.before_reload = read_file(f.path)
	f.load(); f.emit("config.reloaded"); f.replay(f.providers.bspwm_b)
	assert(#f.raises == 0, "partial reload must not disturb focus/stacking")
	f.emit("config.props_refreshed", true)
	assert(#f.raises == 1 and f.raises[1] == f.active.stable_id)
	f.before_reload = nil
	assert(f.workspace_rules["r[1-1]"].enabled and f.window_rules["bspwm-monocle-1"].enabled)
	f.message("tiled"); f.expect_geometry(tiled)
	assert(not f.workspace_rules["r[1-1]"].enabled and not f.window_rules["bspwm-monocle-1"].enabled)
end

function tests.inactive_workspaces_restore_independently()
	local f = fixture()
	for id=1,3 do f.open(id, 1) end
	f.message("focus parent"); f.message("rotate 90")
	for id=4,6 do f.open(id, 2) end
	f.message("focus parent",2); f.message("grow u 40",2)
	local expected = f.geometry()
	f.reload(); f.expect_geometry(expected)
	assert(f.states[1].seq == 3 and f.states[2].seq == 3)
end

function tests.closed_between_checkpoint_and_reload_are_pruned_not_resurrected()
	local f = fixture()
	for id=1,3 do f.open(id) end
	f.windows[2].mapped = false
	table.remove(f.contexts[1].targets, 2)
	f.reload()
	assert(f.states[1].tree.a.id == 1 and f.states[1].tree.b.id == 3)
	assert(#f.contexts[1].targets == 2)
end

function tests.floating_between_checkpoint_and_reload_keeps_vacant_slot()
	local f = fixture()
	for id=1,3 do f.open(id) end
	local expected, saved = f.geometry(), read_file(f.path)
	f.windows[2].floating = true
	local target = table.remove(f.contexts[1].targets, 2)
	for _ = 1, 3 do
		f.reload()
		local st = f.states[1]
		assert(st.tree.a.id == 1 and st.tree.b.a.id == 2 and st.tree.b.b.id == 3)
		assert(st.tree.b.a.vacant and not st.tree.b.vacant and not st.boxes[2])
		assert(read_file(f.path) == saved, "float changed topology/ratios/ages")
	end
	f.windows[2].floating = false
	table.insert(f.contexts[1].targets, target)
	f.focus(1); f.recalculate()
	f.expect_geometry(expected)
	assert(f.states[1].seq == 3)
end

function tests.all_floating_reload_preserves_tree_and_restores_in_reverse_order()
	local f = fixture()
	for id = 1, 3 do f.open(id) end
	local expected, targets = f.geometry(), f.contexts[1].targets
	f.contexts[1].targets = {}
	for _, w in pairs(f.windows) do w.floating = true end
	f.emit("config.props_refreshed", true)
	f.reload()
	assert(f.states[1].tree.vacant and not next(f.states[1].boxes))
	for i = #targets, 1, -1 do
		targets[i].window.floating = false
		table.insert(f.contexts[1].targets, targets[i])
		f.recalculate()
	end
	f.expect_geometry(expected)
	assert(f.states[1].seq == 3)
end

function tests.reload_shortcut_checkpoints_then_invokes_real_reload()
	local f = fixture()
	f.open(1); f.open(2)
	package.loaded["lua/extensions/bspwm"] = f.api
	package.loaded["lua/bindings"], package.loaded["lua/helpers"] = nil, nil
	require("lua/bindings")
	local saved = read_file(f.path)
	assert(f.binds["SUPER + Escape"])
	f.binds["SUPER + Escape"]()
	assert(f.commands[1] == "hyprctl reload" and read_file(f.path) == saved)
end

function tests.empty_workspace_mode_and_pending_preselection_round_trip()
	local text = codec.encode({ [3]={seq=4, mode="monocle", boxes={}, highlighted={}} }, {dir="d",ratio=0.4})
	local result = assert(codec.decode(text))
	assert(not result.states[3].tree and result.states[3].mode == "monocle")
	assert(result.pending.dir == "d" and result.pending.ratio == 0.4)
end

function tests.remembered_pull_source_round_trips_without_visual_selection()
	local tree = { t="split", axis="h", ratio=0.37, pull_focus_id=2, pull_ids={ [1]=true, [2]=true },
		a={ t="leaf", id=1, n=1 }, b={ t="leaf", id=2, n=2 } }
	local text = codec.encode({ [1]={ tree=tree, seq=2, mode="tiled" } })
	assert(text:match("^BSPWM_LAYOUT_V2"))
	local decoded = assert(codec.decode(text))
	local st = decoded.states[1]
	assert(not st.selected and st.tree.pull_focus_id == 2)
	assert(st.tree.pull_ids[1] and st.tree.pull_ids[2])
	assert(codec.encode(decoded.states) == text)
end

function tests.legacy_v1_checkpoint_remains_readable()
	local text = "BSPWM_LAYOUT_V1\nP - -\nW 1 2 tiled . 2 - -\nS h 0.37 - -\nL 1 1 - -\nL 2 2 - -\n"
	local decoded = assert(codec.decode(text))
	local st = decoded.states[1]
	assert(st.selected == st.tree and st.selected_focus_id == 2 and st.tree.ratio == 0.37)
	assert(not st.tree.pull_focus_id)
	local upgraded = codec.encode(decoded.states)
	assert(upgraded:match("^BSPWM_LAYOUT_V2") and codec.decode(upgraded))
end

function tests.invalid_pull_source_representative_is_rejected()
	for _, representative in ipairs({ "3", "0", "-1", "nan", "1e100" }) do
		local text = "BSPWM_LAYOUT_V2\nP - -\nW 1 2 tiled - - - -\nS h 0.5 - - " .. representative
			.. "\nL 1 1 - -\nL 2 2 - -\n"
		local value, err = codec.decode(text)
		assert(not value and err, "accepted invalid pull representative " .. representative)
	end
end

function tests.corrupt_or_executable_checkpoint_is_rejected()
	local bad = {
		"return (function() _G.checkpoint_executed = true end)()",
		"BSPWM_LAYOUT_V0\nP - -\n", "BSPWM_LAYOUT_V1\nP - -\nW 1 0 tiled - - - -\nS h 0.5 - -\nN\nN\n",
		"BSPWM_LAYOUT_V1\nP - -\nW 1 0 tiled - - - -\nS h nan - -\n",
		"BSPWM_LAYOUT_V1\nP - -\nW 1 0 tiled .a 1 - -\nL 1 0 - -\n",
	}
	for _, text in ipairs(bad) do local result, err=codec.decode(text); assert(not result and err) end
	assert(not _G.checkpoint_executed)
	assert(not codec.decode(string.rep(" ", 1048577)))
end

function tests.decoder_rejects_duplicate_leaves_and_excessive_depth()
	local head = "BSPWM_LAYOUT_V1\nP - -\nW 1 0 tiled - - - -\n"
	assert(not codec.decode(head .. "S h 0.5 - -\nL 1 0 - -\nL 1 0 - -\n"))
	assert(not codec.decode(head .. string.rep("S h 0.5 - -\n", 130)))
end

function tests.store_does_not_rewrite_unchanged_state()
	local path = temporary_path()
	local store = codec.open(path)
	assert(store:save({}, nil))
	local rename = os.rename
	local count = 0
	os.rename = function(...) count=count+1; return rename(...) end
	local ok, err = store:save({}, nil)
	os.rename = rename
	assert(ok, err); assert(count == 0)
end

function tests.save_failure_keeps_last_checkpoint()
	local path = temporary_path()
	local store = codec.open(path)
	assert(store:save({}, nil))
	local previous = read_file(path)
	local rename = os.rename
	os.rename = function() return nil, "simulated rename failure" end
	local ok, err = store:save({}, {dir="r", ratio=0.2})
	os.rename = rename
	assert(not ok and err and read_file(path) == previous)
end

local names = {}
for name in pairs(tests) do names[#names+1]=name end
table.sort(names)
local failures=0
for _, name in ipairs(names) do
	local ok, err=pcall(tests[name])
	if ok then print("PASS " .. name)
	else failures=failures+1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
for _, path in ipairs(paths) do os.remove(path); os.remove(path .. ".tmp") end
print(string.format("%d/%d tests passed", #names-failures, #names))
os.exit(failures == 0 and 0 or 1)
