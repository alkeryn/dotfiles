-- Reload workaround with the one-way behavior policy disabled.
local harness = require("tests/bspwm_fullscreen_fixture")
local prefix = "bspwm_fullscreen_"
local has_tag = harness.has_tag
local tests = {}
local module_name = harness.reload_module
local function fixture(disabled) return harness.new({ policy = false, reload = not disabled }) end

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
		assert(#warnings == 1 and warnings[1]:match("bspwm fullscreen reload: fullscreen_state failed"))
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

function tests.reload_only_owns_mode_tags_and_never_installs_policy()
	local f = fixture()
	local window = f.open(1)
	window.tags[#window.tags + 1] = prefix .. "independent" -- unrelated policy tag
	f.native_set(window, 2, 2); f.reload()
	assert(window.fullscreen == 2 and window.fullscreen_client == 2)
	assert(window.sync_fullscreen and #f.prop_calls == 0 and #f.timers == 0)
	f.emit("window.close", window)
	assert(not has_tag(window, prefix .. "2_2") and has_tag(window, prefix .. "independent"))
end

function tests.later_close_subscribers_cannot_recreate_mode_tags()
	local f = fixture()
	local window = f.open(1)
	f.native_set(window, 2, 2)
	hl.on("window.close", function(w)
		hl.dispatch(hl.dsp.window.tag({ window=w, tag="+other-cleanup" }))
	end)
	f.emit("window.close", window) -- native mapped is still true here
	assert(has_tag(window, "other-cleanup") and not has_tag(window, prefix .. "2_2"))
	window.mapped = false; f.emit("window.destroy", {})
	window.fullscreen, window.fullscreen_client, window.mapped = 0, 0, true
	f.emit("window.open_early", window); f.emit("window.open", window)
	f.native_set(window, 2, 2)
	assert(has_tag(window, prefix .. "2_2"), "new mapping was still retired")
end

harness.run(tests)
