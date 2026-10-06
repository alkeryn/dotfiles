-- lua tests/helpers_test.lua [lua/helpers.lua]
-- No host machine detection, compositor, or session checkpoint is used.
local helpers_path = arg[1] or "lua/helpers.lua"
local tests = {}

local function fixture(pc)
	local f = { windows = {}, monitors = {}, workspaces = {}, dispatches = {}, configs = {}, rules = {} }
	local vars = { PC = pc or "laptop", GAPS = 4, GAPS_OUT = 8, M1 = "first", M2 = "second" }
	package.loaded["lua/vars"] = vars
	package.loaded["lua/extensions/bspwm"] = {
		has_neighbor = function(direction) f.direction = direction; return f.neighbor end,
		move_to_workspace = function(workspace) f.moved = workspace; return true end,
		swap_workspaces = function() return true end,
	}
	_G.hl = {
		get_windows = function() return f.windows end,
		get_monitors = function() return f.monitors end,
		get_workspaces = function() return f.workspaces end,
		get_active_window = function() return f.active end,
		get_last_window = function() return f.last end,
		get_active_workspace = function() return f.workspace end,
		get_workspace = function() return f.target_workspace end,
		get_monitor = function(direction) f.direction = direction; return f.monitor end,
		dsp = {
			focus = function(options) return options end,
			layout = function(message) return { message = message } end,
		},
		dispatch = function(command) f.dispatches[#f.dispatches + 1] = command end,
		config = function(config) f.configs[#f.configs + 1] = config.general end,
		workspace_rule = function(rule) f.rules[#f.rules + 1] = rule end,
	}
	f.helpers = dofile(helpers_path)
	return f
end

function tests.focus_history_wraps_and_matches_address_not_object()
	local f = fixture()
	local oldest = { address = "oldest", focus_history_id = 8 }
	local current = { address = "current", focus_history_id = 2 }
	local newest = { address = "newest", focus_history_id = 0 }
	f.windows = { oldest, current, newest }
	f.active = { address = "current" }
	f.helpers.focus_history(1)
	assert(f.dispatches[1].window == oldest)
	f.helpers.focus_history(-1)
	assert(f.dispatches[2].window == newest)
	f.active = newest
	f.helpers.focus_history(-1)
	assert(f.dispatches[3].window == oldest)
	f.active = oldest
	f.helpers.focus_history(1)
	assert(f.dispatches[4].window == newest)
end

function tests.focus_history_missing_rank_and_missing_focus()
	local f = fixture()
	local first, second = { address = "first" }, { address = "second", focus_history_id = 1 }
	f.windows, f.active = { second, first }, first
	f.helpers.focus_history(1)
	assert(f.dispatches[1].window == second)
	for _, active in ipairs({ false, { address = "absent" } }) do
		f.active = active
		f.helpers.focus_history(1)
	end
	f.windows = nil
	f.helpers.focus_history(1)
	f.windows = { first }
	f.helpers.focus_history(1)
	assert(#f.dispatches == 1)
end

function tests.focus_last_only_dispatches_when_available()
	local f = fixture()
	f.helpers.focus_last()
	assert(#f.dispatches == 0)
	f.last = { address = "last" }
	f.helpers.focus_last()
	assert(f.dispatches[1].window == f.last)
end

function tests.swap_queries_layout_before_monitor_fallback()
	local f = fixture()
	f.neighbor = true
	f.helpers.swap_dir("l")
	assert(f.direction == "l" and f.dispatches[1].message == "swap l")
	assert(not f.moved)
	f.neighbor = false
	f.monitor = { active_workspace = { id = 7 } }
	f.helpers.swap_dir("r")
	assert(f.direction == "r" and f.moved == f.monitor.active_workspace)
	f.monitor, f.moved = nil, nil
	f.helpers.swap_dir("u")
	assert(not f.moved and #f.dispatches == 1)
end

function tests.workspace_swap_preserves_focus_result_fallback_conventions()
	for _, case in ipairs({
		{ fallback = true },
		{ result = false, fallback = true },
		{ result = { ok = false }, fallback = true },
		{ result = {}, fallback = false },
		{ result = { ok = true }, fallback = false },
	}) do
		local f = fixture()
		f.workspace = { id = 1 }
		f.target_workspace = { id = -7, name = "special:test" }
		f.active = { workspace = f.target_workspace }
		hl.dispatch = function(command)
			f.dispatches[#f.dispatches + 1] = command
			return case.result
		end
		f.helpers.swap_with_workspace("name:special:test")
		assert(f.dispatches[1].window == f.active)
		assert(#f.dispatches == (case.fallback and 2 or 1))
		if case.fallback then assert(f.dispatches[2].workspace == "name:special:test") end
	end
end

function tests.gaps_clamp_independently_and_reset_to_defaults()
	local f = fixture()
	f.helpers.adjust_gaps(-6)
	assert(f.configs[1].gaps_in == 0 and f.configs[1].gaps_out == 2)
	f.helpers.adjust_gaps(5)
	assert(f.configs[2].gaps_in == 5 and f.configs[2].gaps_out == 7)
	f.helpers.zero_gaps()
	assert(f.configs[3].gaps_in == 0 and f.configs[3].gaps_out == 0)
	f.helpers.reset_gaps()
	assert(f.configs[4].gaps_in == 4 and f.configs[4].gaps_out == 8)
end

function tests.reload_resets_tracked_gaps()
	local f = fixture()
	f.helpers.adjust_gaps(30)
	local reloaded = dofile(helpers_path)
	reloaded.adjust_gaps(0)
	assert(f.configs[2].gaps_in == 4 and f.configs[2].gaps_out == 8)
end

function tests.docking_uses_connected_outputs_except_removed_monitor()
	local f = fixture()
	assert(not f.helpers.is_docked())
	f.monitors = { { name = "first" }, { name = "second" } }
	assert(f.helpers.is_docked())
	assert(not f.helpers.is_docked({ name = "second" }))
	assert(f.helpers.is_docked({ name = "unknown" }))
	f = fixture("mainpc")
	assert(f.helpers.is_docked())
end

function tests.laptop_layout_waits_for_outputs_and_excludes_removed_monitor()
	local f = fixture()
	f.helpers.apply_monitor_layout()
	assert(#f.rules == 0)
	f.monitors = { { name = "first" }, { name = "second" }, { name = "third" } }
	f.helpers.apply_monitor_layout({ name = "first" })
	for i, rule in ipairs(f.rules) do
		assert(rule.workspace == tostring(i) and rule.persistent == true)
		assert(rule.monitor == (i <= 4 and "second" or "third"))
	end
	assert(#f.rules == 10)
	f.rules, f.monitors = {}, { { name = "only" } }
	f.helpers.apply_monitor_layout()
	assert(#f.rules == 10)
	for _, rule in ipairs(f.rules) do assert(rule.monitor == "only") end
end

function tests.mainpc_layout_is_pinned_even_before_outputs_exist()
	local f = fixture("mainpc")
	f.helpers.apply_monitor_layout({ name = "first" })
	assert(#f.rules == 10)
	for i, rule in ipairs(f.rules) do
		assert(rule.workspace == tostring(i) and rule.monitor == (i <= 4 and "first" or "second"))
	end
end

local names = {}
for name in pairs(tests) do names[#names + 1] = name end
table.sort(names)
for _, name in ipairs(names) do
	tests[name]()
	print("PASS " .. name)
end
print(string.format("%d/%d tests passed", #names, #names))
