-- Mock native events/handlers shared by policy, reload and integration suites.
local M = {}
M.policy_module = "lua/extensions/bspwm_fullscreen_policy"
M.reload_module = "lua/extensions/bspwm_fullscreen_reload"

local function has_tag(window, tag)
	for _, value in ipairs(window.tags) do if value == tag then return true end end
	return false
end

function M.new(options)
	options = options or {}
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
		package.loaded[M.policy_module] = options.policy == false and { setup = function() end } or nil
		package.loaded[M.reload_module] = options.reload == false and {
			setup = function() end, is_ready = function() return true end,
		} or nil
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
					if f.after_mode_dispatch then f.after_mode_dispatch(opts) end
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
		package.loaded[M.policy_module], package.loaded[M.reload_module] = nil, nil
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

M.has_tag = has_tag

function M.run(tests)
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
end

return M
