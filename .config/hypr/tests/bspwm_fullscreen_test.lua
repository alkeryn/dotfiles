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
		calls = {}, prop_calls = {}, tag_writes = 0, fullscreen_events = 0, timers = {}, native_depth = 0 }
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
		f.native_depth = f.native_depth + 1
		window.fullscreen_client, window.protocol_fullscreen = client, client == 2
		if f.protect == window then assert(window.protocol_fullscreen, "WM sent fullscreen unset to the application") end
		-- A rule update can observe a transition in flight; the final event
		-- below is authoritative. Our restore must suppress its own observation.
		f.emit("window.update_rules", window)
		window.fullscreen = internal
		if internal == 2 then window.box = { x=0, y=0, w=1200, h=800 } end
		f.reflow()
		if old_internal ~= internal then
			f.fullscreen_events = f.fullscreen_events + 1
			f.emit("window.fullscreen", window)
		end
		f.emit("window.update_rules", window)
		f.native_depth = f.native_depth - 1
	end
	function f.flush_timers()
		local timers = f.timers
		f.timers = {}
		for _, timer in ipairs(timers) do
			if timer.enabled then timer.enabled = false; timer.callback() end
		end
	end
	function f.client_request(window, client, defer)
		-- Controller captures WANT_SYNC before any rule callbacks execute.
		f.native_set(window, window.sync_fullscreen and client or window.fullscreen, client)
		if not defer then f.flush_timers() end
	end
	function f.demote(window)
		f.native_set(window, 0, window.sync_fullscreen and 0 or window.fullscreen_client)
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
		for _, timer in ipairs(f.timers) do timer.enabled = false end
		f.events, f.providers, f.timers = {}, {}, {}
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
			timer = function(callback, opts)
				assert(opts.type == "oneshot" and opts.timeout == 1, "no polling")
				local timer = { callback=callback, enabled=true }
				f.timers[#f.timers + 1] = timer
				return timer
			end,
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
					assert(f.native_depth == 0, "recursively changed fullscreen inside an in-flight native request")
					assert(opts.window and opts.action == "set" and opts.layout_aware == false,
						"restore must target the saved window and set, never toggle")
					f.calls[#f.calls + 1] = opts
					if f.fail == "throw" then error("synthetic fullscreen failure") end
					if f.fail then return { ok = false } end
					local window = opts.window
					if window.fullscreen ~= opts.internal or window.fullscreen_client ~= opts.client then
						window.sync_fullscreen = false
						f.native_set(window, opts.internal, opts.client)
						-- The native dispatcher re-enables sync for equal modes.
						window.sync_fullscreen = window.fullscreen == window.fullscreen_client
					end
					-- Exercise a reentrant refresh while restoration is running.
					f.emit("config.props_refreshed", false)
					return { ok = true }
				end end,
				set_prop = function(opts) return function()
					assert(opts.prop == "sync_fullscreen" and (opts.value == "false" or opts.value == "true" or opts.value == "unset"))
					f.prop_calls[#f.prop_calls + 1] = opts
					if f.fail_prop then return { ok = false, error = "synthetic property failure" } end
					opts.window.sync_fullscreen = opts.value == "true" or (opts.value == "unset" and opts.window.sync_rule ~= false)
					f.emit("window.update_rules", opts.window) -- exercise reentrant observers too
					return { ok = true }
				end end,
				float = function(opts) return function()
					local window, floating = opts.window, opts.action == "on"
					if window.floating ~= floating then
						assert(window.fullscreen == 0)
						window.floating = floating
						-- New handler: cached Wayland flag survives, mode records do not.
						window.fullscreen, window.fullscreen_client = 0, 0
						f.emit("window.update_rules", window)
						f.reflow()
					end
					return { ok = true }
				end end,
				pseudo = function(opts) return function() opts.window.pseudo = opts.action == "on" end end,
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
			protocol_fullscreen = false, sync_fullscreen = true, tags = { "personal" } }
		f.windows[#f.windows + 1] = window
		f.emit("window.open_early", window)
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
	function f.set_state(window, state)
		f.focus(window)
		package.loaded["lua/helpers"] = nil
		package.loaded["lua/vars"] = { GAPS = 4, GAPS_OUT = 8 }
		require("lua/helpers").set_window_state(state)
	end
	function f.reset_modes(window)
		-- Explicit reset for checkpoint/control tests; zero records short-circuit.
		-- Real application requests use f.client_request and its sync policy.
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
	f.reset_modes(window); f.node_action(neighbor)
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
			f.reset_modes(window); f.node_action(neighbor); f.reload(); f.node_action(neighbor)
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

function tests.state_shortcuts_keep_fullscreen_video_through_float_tile_and_reload()
	local f = fixture()
	local window, neighbor = f.open(1), f.open(2)
	f.native_set(window, 2, 2)
	for _, state in ipairs({ "floating", "tiled", "pseudo_tiled", "fullscreen", "floating", "tiled" }) do
		f.set_state(window, state)
		local internal = state == "fullscreen" and 2 or 0
		assert(window.fullscreen == internal and window.fullscreen_client == 2 and window.protocol_fullscreen)
		assert(not window.sync_fullscreen and has_tag(window, prefix .. "independent"))
		assert(has_tag(window, prefix .. internal .. "_2") == (state ~= "floating"))
		for _ = 1, 2 do
			f.reload()
			assert(window.fullscreen == internal and window.fullscreen_client == 2 and not window.sync_fullscreen)
			f.node_action(neighbor)
			assert(window.protocol_fullscreen and window.app_fullscreen)
		end
	end
	f.reset_modes(window); f.reload(); f.node_action(neighbor)
	assert(window.fullscreen == 0 and window.fullscreen_client == 0 and not window.app_fullscreen)
end

function tests.one_way_policy_survives_reload_and_covers_apps_without_prior_shortcuts()
	for _, syntax_failed in ipairs({ false, true }) do
		for _, state in ipairs({ "fullscreen", "tiled", "floating" }) do
			local f = fixture()
			local window, untouched = f.open(1), f.open(2, 2)
			f.native_set(untouched, 2, 2)
			if state == "fullscreen" then f.native_set(window, 2, 2) end
			f.set_state(window, state)
			for _ = 1, 3 do
				f.reload(syntax_failed)
				assert(window.sync_fullscreen == (window.fullscreen_client ~= 2) and has_tag(window, prefix .. "independent"))
				assert(not untouched.sync_fullscreen and has_tag(untouched, prefix .. "independent"))
			end
			-- App exits/enters via FullscreenController, not the pair dispatcher.
			for _, client in ipairs({ 0, 2, 0 }) do
				f.client_request(window, client)
				assert(window.fullscreen == client and window.fullscreen_client == client)
			end
		end
	end
end

function tests.close_and_remap_retire_policy_without_resurrecting_mode_marker()
	for _, rule in ipairs({ true, false }) do
		local f = fixture()
		local window = f.open(1)
		window.sync_rule = rule
		f.native_set(window, 2, 2); f.set_state(window, "fullscreen")
		f.emit("window.close", window)
		assert(window.sync_fullscreen == rule)
		assert(not has_tag(window, prefix .. "independent") and not has_tag(window, prefix .. "2_2"))
		window.mapped = false
		f.reload()
		-- Even an orphaned tag is cleared on remap, not used to restore policy.
		window.tags[#window.tags + 1] = prefix .. "independent"
		window.fullscreen, window.fullscreen_client, window.mapped = 0, 0, true
		f.emit("window.open_early", window)
		f.emit("window.open", window)
		assert(not has_tag(window, prefix .. "independent") and window.sync_fullscreen == rule)
		local props = #f.prop_calls
		f.reload()
		assert(#f.prop_calls == props)
	end
end

function tests.explicit_mode_set_applies_policy_once_then_updates_checkpoint()
	local f = fixture()
	local window = f.open(1)
	local controller = package.loaded[module_name]
	for _, modes in ipairs({ {0, 0}, {2, 2}, {0, 2}, {0, 2}, {2, 0} }) do
		local props = #f.prop_calls
		assert(controller.set_wm_modes(window, modes[1], modes[2]))
		assert(#f.prop_calls == props + 1, "explicit set repeated its policy write during adoption")
		assert(window.sync_fullscreen == (modes[2] ~= 2))
		if modes[1] ~= 0 or modes[2] ~= 0 then
			assert(has_tag(window, prefix .. modes[1] .. "_" .. modes[2]))
		end
	end
end

function tests.failed_sync_restore_is_reported_without_a_retry_loop()
	local f = fixture()
	local window = f.open(1)
	f.native_set(window, 2, 2); f.set_state(window, "fullscreen")
	f.fail_prop = true
	local original_print, warnings = print, {}
	_G.print = function(message) warnings[#warnings + 1] = tostring(message) end
	local ok, err = pcall(f.reload)
	_G.print = original_print
	assert(ok, err)
	assert(#warnings == 1 and warnings[1]:match("set_prop failed"))
	local count = #f.prop_calls
	f.emit("config.props_refreshed", true)
	assert(#f.prop_calls == count)
	f.fail_prop = nil
	f.reload()
	assert(not window.sync_fullscreen)
end

function tests.application_fullscreen_covers_monitor_then_new_tile_preserves_video()
	local config = assert(io.open("hyprland.lua", "r"))
	local source = config:read("*a"); config:close()
	assert(source:match("on_focus_under_fullscreen%s*=%s*2"), "new tiles must demote, not inherit fullscreen")
	for _, used_shortcut in ipairs({ false, true }) do
		local f = fixture()
		local window = f.open(1)
		f.open(2)
		if used_shortcut then f.set_state(window, "tiled") end
		f.client_request(window, 2)
		assert(window.fullscreen == 2 and window.fullscreen_client == 2 and not window.sync_fullscreen)
		assert(window.box.w == 1200 and window.box.h == 800, "application request stayed inside its tile")
		f.protect = window
		-- CWindow::mapWindow / FocusState with on_focus_under_fullscreen=2.
		local incoming = f.open(3)
		f.demote(window); f.focus(incoming); f.flush_timers()
		assert(window.fullscreen == 0 and window.fullscreen_client == 2 and window.app_fullscreen)
		assert(incoming.fullscreen == 0 and incoming.fullscreen_client == 0)
		assert(window.box.w < 1200 or window.box.h < 800)
		for _, state in ipairs({ "floating", "fullscreen", "tiled" }) do
			f.set_state(window, state); f.flush_timers()
			assert(window.fullscreen_client == 2 and window.protocol_fullscreen)
		end
		f.protect = nil
		f.client_request(window, 0)
		assert(window.fullscreen == 0 and window.sync_fullscreen)
		f.client_request(window, 2)
		assert(window.fullscreen == 2 and window.box.w == 1200 and window.box.h == 800)
		f.client_request(window, 0)
		assert(window.fullscreen == 0 and window.fullscreen_client == 0)
	end
end

function tests.native_demotions_and_duplicate_requests_do_not_reinflate_client_fullscreen_tiles()
	local f = fixture()
	local window = f.open(1)
	f.client_request(window, 2)
	f.protect = window
	f.demote(window)
	local props, calls = #f.prop_calls, #f.calls
	for _ = 1, 10 do
		f.client_request(window, 2) -- repeated assertion, NOT a fresh fullscreen entry
		f.emit("window.update_rules", window)
	end
	assert(window.fullscreen == 0 and window.fullscreen_client == 2)
	assert(#f.calls == calls and #f.prop_calls == props and #f.timers == 0)
end

function tests.application_exit_is_deferred_and_coalesced_not_recursive()
	local f = fixture()
	local window = f.open(1)
	f.client_request(window, 2)
	f.client_request(window, 0, true)
	local calls = #f.calls
	assert(window.fullscreen == 2 and window.fullscreen_client == 0 and #f.timers == 1)
	for _ = 1, 4 do f.emit("window.update_rules", window) end
	assert(#f.timers == 1 and #f.calls == calls)
	f.flush_timers()
	assert(window.fullscreen == 0 and window.sync_fullscreen and #f.calls == calls + 1)
end

function tests.delayed_exit_cannot_override_reentry_wm_shortcuts_close_destroy_or_reload()
	for _, action in ipairs({ "reenter", "shortcut", "close", "destroy", "reload", "failed_reload" }) do
		local f = fixture()
		local window = f.open(1)
		f.client_request(window, 2); f.client_request(window, 0, true)
		local timer = assert(f.timers[1])
		if action == "reenter" then f.client_request(window, 2, true)
		elseif action == "shortcut" then f.set_state(window, "fullscreen")
		elseif action == "close" then f.emit("window.close", window); window.mapped = false
		elseif action == "destroy" then window.mapped = false; f.emit("window.destroy", {})
		else f.reload(action == "failed_reload") end
		local calls, internal, client = #f.calls, window.fullscreen, window.fullscreen_client
		timer.callback() -- even an already-queued callback must fail its identity/lifetime guard
		f.flush_timers()
		assert(#f.calls == calls and window.fullscreen == internal and window.fullscreen_client == client, action)
	end
end

function tests.reload_reapplies_policy_from_client_modes_without_promoting_existing_video()
	local f = fixture()
	local normal, video = f.open(1), f.open(2, 2)
	for _, window in ipairs({ normal, video }) do
		window.tags[#window.tags + 1] = prefix .. "independent"
		window.sync_fullscreen = false
	end
	f.native_set(video, 0, 2)
	f.reload()
	assert(normal.sync_fullscreen and not video.sync_fullscreen)
	assert(video.fullscreen == 0 and video.fullscreen_client == 2)
	f.client_request(normal, 2)
	assert(normal.fullscreen == 2 and normal.fullscreen_client == 2)
	f.client_request(video, 0); f.client_request(video, 2)
	assert(video.fullscreen == 2 and video.fullscreen_client == 2)
end

function tests.other_layouts_are_not_enrolled_by_application_fullscreen()
	local f = fixture()
	local window = f.open(1)
	window.workspace.tiled_layout = "scrolling"
	f.client_request(window, 2)
	assert(window.sync_fullscreen and not has_tag(window, prefix .. "independent"))
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
	f.reset_modes(window)
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
	f.reset_modes(window)
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
