-- One-way fullscreen behavior with the reload workaround disabled.
local harness = require("tests/bspwm_fullscreen_fixture")
local prefix = "bspwm_fullscreen_"
local has_tag = harness.has_tag
local tests = {}
local function fixture() return harness.new({ reload = false }) end

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

function tests.other_layouts_are_not_enrolled_by_application_fullscreen()
	local f = fixture()
	local window = f.open(1)
	window.workspace.tiled_layout = "scrolling"
	f.client_request(window, 2)
	assert(window.sync_fullscreen and not has_tag(window, prefix .. "independent"))
end

function tests.policy_never_writes_or_restores_mode_checkpoints()
	local f = fixture()
	local window = f.open(1)
	window.tags[#window.tags + 1] = prefix .. "1_1" -- owned by a different feature
	f.set_state(window, "tiled"); f.client_request(window, 2)
	assert(window.fullscreen == 2 and has_tag(window, prefix .. "independent"))
	assert(has_tag(window, prefix .. "1_1") and not has_tag(window, prefix .. "2_2"))
	local calls = #f.calls
	f.reload() -- simulated layout loss is NOT this module's job to repair
	assert(window.fullscreen == 0 and window.fullscreen_client == 0 and #f.calls == calls)
	assert(window.sync_fullscreen and has_tag(window, prefix .. "1_1"))
	f.emit("window.close", window)
	assert(not has_tag(window, prefix .. "independent") and has_tag(window, prefix .. "1_1"))
end

function tests.setup_without_reload_integration_supports_application_and_wm_actions()
	local f = harness.new({ policy=false, reload=false })
	package.loaded[harness.policy_module] = nil
	require(harness.policy_module).setup() -- no options / no reload readiness gate
	f.emit("config.reloaded"); f.emit("config.props_refreshed", true)
	local window = f.open(1)
	f.client_request(window, 2); f.demote(window)
	assert(window.fullscreen == 0 and window.fullscreen_client == 2)
	f.client_request(window, 0); f.client_request(window, 2)
	assert(window.fullscreen == 2 and window.fullscreen_client == 2)
end

harness.run(tests)
