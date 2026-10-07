-- lua tests/bspwm_fullscreen_test.lua (also LuaJIT); no live compositor/plugin.
-- Exercise the real bspwm module and Lua fullscreen checkpoint with v0.56.2's
-- module-cache clearing, provider teardown, alias flip and dispatcher semantics.
local module_name = "lua/extensions/bspwm_fullscreen"
local prefix = "bspwm_fullscreen_"
local tests = {}

local function has_tag(window, tag)
	for _, value in ipairs(window.tags) do if value == tag then return true end end
	return false
end

local function fixture(disabled)
	local f = { windows = {}, workspaces = {}, providers = {}, events = {}, active_callbacks = {},
		calls = {}, tag_writes = 0, fullscreen_events = 0, warnings = {} }
	function f.emit(event, ...)
		for _, callback in ipairs(f.events[event] or {}) do
			-- Native Lua suppresses recursive invocation of the same subscription.
			if not f.active_callbacks[callback] then
				f.active_callbacks[callback] = true
				callback(...)
				f.active_callbacks[callback] = nil
			end
		end
	end
	function f.workspace(id)
		if not f.workspaces[id] then
			f.workspaces[id] = setmetatable({ id = id, name = tostring(id), tiled_layout = "lua:bspwm" }, {
				__index = function(self, key)
					if key == "has_fullscreen" then
						for _, window in ipairs(f.windows) do
							if window.mapped and window.workspace == self and window.fullscreen ~= 0 then return true end
						end
						return false
					end
				end,
			})
		end
		return f.workspaces[id]
	end
	function f.context(workspace)
		local targets = {}
		for _, window in ipairs(f.windows) do
			if window.mapped and not window.floating and window.workspace == workspace then
				targets[#targets + 1] = { window = window, place = function(_, box)
					if window.fullscreen == 0 then window.box = box end
					-- Resizing sends the cached protocol fullscreen flag again.
					window.app_fullscreen = window.protocol_fullscreen
				end }
			end
		end
		return { targets = targets, area = { x = 0, y = 0, w = 1200, h = 800 } }
	end
	function f.reflow()
		local provider = f.providers.bspwm
		if not provider then return end
		for _, workspace in pairs(f.workspaces) do provider.recalculate(f.context(workspace)) end
	end
	function f.native_set(window, internal, client)
		local old_internal = window.fullscreen
		if old_internal == internal and window.fullscreen_client == client then return end
		window.fullscreen_client, window.protocol_fullscreen = client, client == 2
		-- A rule update can observe a transition in flight; the final event
		-- below is authoritative. Our restore must suppress its own observation.
		f.emit("window.update_rules", window)
		window.fullscreen = internal
		f.reflow()
		if old_internal ~= internal then
			f.fullscreen_events = f.fullscreen_events + 1
			f.emit("window.fullscreen", window)
		end
		f.emit("window.update_rules", window)
	end
	function f.lose_modes(layout)
		for _, workspace in pairs(f.workspaces) do workspace.tiled_layout = layout end
		for _, window in ipairs(f.windows) do
			if not window.floating then window.fullscreen, window.fullscreen_client = 0, 0 end
			-- Native state is gone, but static tags and protocol flags survive.
			f.emit("window.update_rules", window)
			f.emit("window.active", window, 7)
		end
		f.reflow()
	end
	function f.load_config()
		f.events, f.providers = {}, {}
		package.loaded[module_name] = disabled and { setup = function() end } or nil
		package.loaded["lua/extensions/bspwm"] = nil
		package.loaded["lua/extensions/bspwm_state"] = { open_session = function()
			return { load = function() end, save = function() return true end }
		end }
		local function rule(spec)
			function spec:set_enabled(value) self.enabled = value end
			return spec
		end
		_G.hl = {
			on = function(event, callback)
				f.events[event] = f.events[event] or {}
				table.insert(f.events[event], callback)
			end,
			get_windows = function()
				local result = {}
				for _, window in ipairs(f.windows) do if window.mapped then result[#result + 1] = window end end
				return result
			end,
			get_active_window = function() return f.active end,
			window_rule = rule, workspace_rule = rule,
			layout = { register = function(name, provider)
				f.providers[name] = provider
				-- New-provider callbacks happen before config.reloaded too.
				f.lose_modes("lua:" .. name)
			end },
			dispatch = function(fn) return fn() end,
			dsp = { window = {
				tag = function(opts) return function()
					local window, tag = assert(opts.window), opts.tag:sub(2)
					assert(window.mapped, "tagged an unmapped window")
					local changed = false
					if opts.tag:sub(1, 1) == "+" then
						if not has_tag(window, tag) then window.tags[#window.tags + 1] = tag; changed = true end
					else
						for i = #window.tags, 1, -1 do
							if window.tags[i] == tag then table.remove(window.tags, i); changed = true end
						end
					end
					if changed then f.tag_writes = f.tag_writes + 1; f.emit("window.update_rules", window) end
					return { ok = true }
				end end,
				fullscreen_state = function(opts) return function()
					assert(opts.window and opts.action == "set" and opts.layout_aware == false,
						"restore must target the saved window and set, never toggle")
					f.calls[#f.calls + 1] = opts
					if f.fail == "throw" then error("synthetic fullscreen failure") end
					if f.fail then return { ok = false } end
					f.native_set(opts.window, opts.internal, opts.client)
					-- Exercise a reentrant refresh while restoration is running.
					f.emit("config.props_refreshed", false)
					return { ok = true }
				end end,
				alter_zorder = function() return function() return { ok = true } end end,
			} },
		}
		f.api = require("lua/extensions/bspwm")
	end
	function f.finish_reload()
		f.emit("config.reloaded")
		f.lose_modes("lua:bspwm_b") -- deferred alias flip/refresh
		f.emit("config.props_refreshed", true)
	end
	function f.reload(syntax_failed)
		-- Exact important ordering: cache clear, OLD callbacks with lost native
		-- records, new Lua/providers, config.reloaded, alias flip, final refresh.
		package.loaded[module_name] = nil
		if not syntax_failed then
			f.lose_modes("dwindle")
			f.load_config()
		end
		f.finish_reload()
	end
	function f.open(id, wsid)
		local window = { stable_id = id, address = tostring(id), workspace = f.workspace(wsid or 1),
			mapped = true, floating = false, active = false, fullscreen = 0, fullscreen_client = 0,
			protocol_fullscreen = false, tags = { "personal" } }
		f.windows[#f.windows + 1] = window
		f.emit("window.open", window)
		f.reflow()
		return window
	end
	function f.focus(window)
		for _, other in ipairs(f.windows) do other.active = other == window end
		f.active = window
		f.emit("window.active", window, 7)
	end
	function f.node_action(window)
		f.focus(window)
		assert(f.providers.bspwm.layout_msg(f.context(window.workspace), "preselect r") == true)
		f.reflow()
	end
	function f.exit(window)
		-- Model Super+s: fullscreen_state(set, 0, 0) short-circuits on lost
		-- 0/0 records, just like an F11 unset when native client state is zero.
		f.native_set(window, 0, 0)
		window.app_fullscreen = false
	end
	f.load_config(); f.finish_reload()
	return f
end

function tests.unpatched_control_reproduces_fullscreen_after_exit_and_node_action()
	local f = fixture(true)
	local window, neighbor = f.open(1), f.open(2)
	f.native_set(window, 2, 2)
	f.reload()
	assert(window.fullscreen == 0 and window.fullscreen_client == 0 and window.protocol_fullscreen)
	f.exit(window); f.node_action(neighbor)
	assert(window.app_fullscreen, "control did not reproduce the reported bug")
end

function tests.manual_and_file_reload_preserve_all_mode_pairs_and_clean_exit()
	for internal = 0, 2 do
		for client = 0, 2 do
			local f = fixture()
			local window, neighbor = f.open(1), f.open(2)
			f.focus(neighbor)
			f.native_set(window, internal, client)
			for _ = 1, 3 do
				local before = #f.calls
				f.reload() -- no wrapper/shortcut or pre-reload helper
				assert(window.fullscreen == internal and window.fullscreen_client == client)
				assert(#f.calls == before + ((internal ~= 0 or client ~= 0) and 1 or 0))
				assert(f.active == neighbor and has_tag(window, "personal"))
				f.node_action(neighbor)
				assert(window.app_fullscreen == (client == 2))
			end
			f.exit(window); f.node_action(neighbor); f.reload(); f.node_action(neighbor)
			assert(not window.app_fullscreen and not window.protocol_fullscreen)
			assert(window.fullscreen == 0 and window.fullscreen_client == 0)
			assert(not has_tag(window, prefix .. internal .. "_" .. client))
		end
	end
end

function tests.client_only_changes_and_exits_are_recorded_without_fullscreen_events()
	local f = fixture()
	local window = f.open(1)
	local events = f.fullscreen_events
	f.native_set(window, 0, 2)
	assert(f.fullscreen_events == events and has_tag(window, prefix .. "0_2"))
	f.reload()
	assert(window.fullscreen == 0 and window.fullscreen_client == 2)
	f.native_set(window, 0, 0)
	assert(not has_tag(window, prefix .. "0_2"))
	local calls = #f.calls
	f.reload()
	assert(#f.calls == calls and not window.protocol_fullscreen)
end

function tests.old_teardown_and_new_registration_cannot_overwrite_markers()
	local f = fixture()
	local window = f.open(1)
	f.native_set(window, 2, 2)
	local writes = f.tag_writes
	package.loaded[module_name] = nil
	f.lose_modes("dwindle")
	assert(f.tag_writes == writes and has_tag(window, prefix .. "2_2"))
	f.load_config()
	assert(f.tag_writes == writes and has_tag(window, prefix .. "2_2"))
	assert(#f.calls == 0, "restored before the final layout was ready")
	f.finish_reload()
	assert(window.fullscreen == 2 and window.fullscreen_client == 2 and #f.calls == 1)
end

function tests.failed_syntax_reload_rearms_retained_module_for_future_transitions()
	local f = fixture()
	local window = f.open(1)
	f.native_set(window, 2, 2)
	f.reload(true)
	assert(window.fullscreen == 2 and package.loaded[module_name])
	f.exit(window)
	assert(not has_tag(window, prefix .. "2_2"))
	f.native_set(window, 1, 1)
	f.reload(true); f.reload()
	assert(window.fullscreen == 1 and window.fullscreen_client == 1)
end

function tests.inactive_workspaces_and_multiple_monitors_restore_independently()
	local f = fixture()
	local a, b, focused = f.open(1, 1), f.open(2, 7), f.open(3, 9)
	a.workspace.visible, b.workspace.visible = false, false
	f.focus(focused)
	f.native_set(a, 2, 2); f.native_set(b, 1, 0)
	f.reload()
	assert(a.fullscreen == 2 and b.fullscreen == 1 and b.fullscreen_client == 0)
	assert(focused.fullscreen == 0 and f.active == focused and #f.calls == 2)
end

function tests.ordinary_rule_refreshes_never_restore_or_churn_tags()
	local f = fixture()
	local window = f.open(1)
	f.native_set(window, 2, 2)
	local writes = f.tag_writes
	for _ = 1, 10 do f.emit("window.update_rules", window); f.emit("config.props_refreshed", true) end
	assert(f.tag_writes == writes and #f.calls == 0)
	f.exit(window)
	window.tags[#window.tags + 1] = prefix .. "2_2" -- deliberately stale marker
	f.emit("config.props_refreshed", true)
	assert(#f.calls == 0 and window.fullscreen == 0, "ordinary refresh replayed old state")
	f.emit("window.update_rules", window)
	assert(not has_tag(window, prefix .. "2_2"))
end

function tests.floats_hidden_group_members_and_other_layouts_are_not_forced_fullscreen()
	local f = fixture()
	local floating, hidden, foreign = f.open(1), f.open(2, 2), f.open(3, 3)
	floating.floating = true
	hidden.hidden, hidden.group = true, {}
	foreign.workspace.tiled_layout = "scrolling"
	for _, window in ipairs({ floating, hidden, foreign }) do
		window.tags[#window.tags + 1] = prefix .. "2_2"
		f.emit("window.update_rules", window)
		assert(not has_tag(window, prefix .. "2_2"))
	end
	f.native_set(floating, 2, 2)
	f.reload()
	assert(floating.fullscreen == 2 and #f.calls == 0)
	assert(hidden.fullscreen == 0 and foreign.fullscreen == 0)
end

function tests.live_state_and_surviving_floating_fullscreen_take_precedence()
	local f = fixture()
	local window, floating = f.open(1), f.open(2)
	f.native_set(window, 2, 2)
	package.loaded[module_name] = nil
	f.lose_modes("dwindle"); f.load_config()
	f.emit("config.reloaded"); f.lose_modes("lua:bspwm_b")
	f.native_set(window, 1, 0) -- new authoritative state before restoration
	f.emit("config.props_refreshed", true)
	assert(window.fullscreen == 1 and window.fullscreen_client == 0 and #f.calls == 0)
	assert(has_tag(window, prefix .. "1_0") and not has_tag(window, prefix .. "2_2"))

	f.native_set(window, 2, 2)
	package.loaded[module_name] = nil
	f.lose_modes("dwindle"); f.load_config()
	floating.floating = true
	f.native_set(floating, 2, 2)
	f.finish_reload()
	assert(floating.fullscreen == 2 and window.fullscreen == 0 and #f.calls == 0)
end

function tests.closed_and_remapped_windows_do_not_resurrect_saved_fullscreen()
	local f = fixture()
	local window = f.open(1)
	f.native_set(window, 2, 2)
	f.emit("window.close", window); window.mapped = false
	assert(not has_tag(window, prefix .. "2_2"))
	f.reload()
	assert(#f.calls == 0)
	-- An old tag may survive an unmap if native tagging was unavailable.
	window.tags[#window.tags + 1] = prefix .. "2_2"
	window.fullscreen, window.fullscreen_client, window.protocol_fullscreen = 0, 0, false
	window.mapped = true
	f.emit("window.open", window)
	f.reload()
	assert(#f.calls == 0 and not has_tag(window, prefix .. "2_2"))
end

function tests.conflicting_markers_are_discarded_without_touching_other_tags()
	local f = fixture()
	local window = f.open(1)
	window.tags = { "personal", "bspwm_selected", prefix .. "2_2", prefix .. "1_1", "bspwm_fullscreen_other" }
	f.reload()
	assert(#f.calls == 0 and window.fullscreen == 0)
	assert(has_tag(window, "personal") and has_tag(window, "bspwm_fullscreen_other"))
	assert(not has_tag(window, prefix .. "2_2") and not has_tag(window, prefix .. "1_1"))
end

function tests.failed_restore_is_reported_once_and_does_not_leave_observer_guard_stuck()
	for _, failure in ipairs({ "result", "throw" }) do
		local f = fixture()
		local window = f.open(1)
		f.native_set(window, 2, 2)
		f.fail = failure
		local original_print, warnings = print, {}
		_G.print = function(message) warnings[#warnings + 1] = tostring(message) end
		local ok, err = pcall(f.reload)
		_G.print = original_print
		assert(ok, err)
		assert(#warnings == 1 and warnings[1]:match("bspwm fullscreen: fullscreen_state failed"))
		local calls = #f.calls
		f.emit("config.props_refreshed", true)
		assert(#f.calls == calls)
		f.fail = nil
		f.native_set(window, 2, 2)
		assert(has_tag(window, prefix .. "2_2"))
		f.reload()
		assert(window.fullscreen == 2 and window.fullscreen_client == 2)
	end
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
