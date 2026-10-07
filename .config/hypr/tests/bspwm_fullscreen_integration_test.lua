-- Both independent modules wired through bspwm.lua.
local harness = require("tests/bspwm_fullscreen_fixture")
local prefix = "bspwm_fullscreen_"
local has_tag = harness.has_tag
local tests = {}
local module_name = harness.policy_module
local fixture = harness.new

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

function tests.policy_waits_for_complete_replay_even_with_reentrant_refreshes()
	local f = fixture()
	local a, b = f.open(1), f.open(2, 2)
	f.client_request(a, 2); f.client_request(b, 2)
	local props, replayed = #f.prop_calls, 0
	f.after_mode_dispatch = function()
		assert(not package.loaded[harness.reload_module].is_ready())
		assert(#f.prop_calls == props, "policy adopted a partially restored window list")
		assert(#f.timers == 0, "restoration was mistaken for application input")
		replayed = replayed + 1
	end
	f.reload()
	assert(replayed == 2 and package.loaded[harness.reload_module].is_ready())
	assert(#f.prop_calls == props + 2 and not a.sync_fullscreen and not b.sync_fullscreen)
end

harness.run(tests)
