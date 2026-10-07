-- Run from ~/.config/hypr: lua tests/window_state_bindings_test.lua
-- Actual bindings/helpers; model v0.56.2's separate tiled/floating fullscreen
-- records AND the cached protocol flag (a final-state assertion alone misses
-- a temporary unset that already made a browser leave its fullscreen video).
local tests = {}

local function fixture()
	local f = { binds = {}, calls = {}, fullscreen_changes = 0 }
	package.loaded["lua/vars"] = { GAPS = 4, GAPS_OUT = 8, FLOAT_STEP = 20, terminal = "alacritty" }
	local function ignored_dispatcher() return function() end end
	package.loaded["lua/extensions/bspwm"] = {
		close = function() end, reload = function() end,
		set_floating = function(window, floating)
			return hl.dispatch(hl.dsp.window.float({ action = floating and "on" or "off", window = window }))
		end,
	}
	local window_dsp = setmetatable({}, { __index = function() return ignored_dispatcher end })

	function f.window(internal, client, floating, pseudo, destination_client)
		local w = { mapped = true, fullscreen = internal, fullscreen_client = client,
			floating = floating, pseudo = pseudo, expected_client = client,
			protocol_fullscreen = client == 2, app_fullscreen = client == 2, handlers = {},
			sync_fullscreen = true, tags = {} }
		w.handlers[floating] = { internal = internal, client = client }
		w.handlers[not floating] = { internal = 0, client = destination_client or 0 }
		return w
	end
	function f.configure(w)
		assert(w.protocol_fullscreen == (w.expected_client == 2), "client observed a fullscreen state change")
		w.app_fullscreen = w.protocol_fullscreen
	end
	function f.native_set(w, internal, client)
		if w.fullscreen == internal and w.fullscreen_client == client then return end
		f.fullscreen_changes = f.fullscreen_changes + 1
		w.handlers[w.floating] = { internal = internal, client = client }
		w.fullscreen, w.fullscreen_client = internal, client
		w.protocol_fullscreen = client == 2
		f.configure(w)
	end
	function f.client_request(w, client)
		-- Client requests go straight to FullscreenController. Unlike the
		-- explicit-pair dispatcher, they do NOT rewrite sync_fullscreen.
		w.expected_client = client
		f.native_set(w, w.sync_fullscreen and client or w.fullscreen, client)
	end

	local function dispatcher(kind, opts, apply)
		return function()
			assert(opts and opts.window, kind .. " must explicitly target the original window")
			f.calls[#f.calls + 1] = kind
			if f.fail == kind then return { ok = false } end
			apply(opts.window)
			if f.switch_focus then f.active = f.other end
			return { ok = true }
		end
	end

	function window_dsp.fullscreen_state(opts)
		return dispatcher("fullscreen_state", opts, function(w)
			assert(opts.action == "set", "fullscreen must be set, not toggled")
			assert(opts.layout_aware == false, "request real fullscreen, not a layout-specific mode")
			assert(opts.client == w.expected_client, "WM shortcuts must preserve the original client mode")
			if w.fullscreen == opts.internal and w.fullscreen_client == opts.client then return end
			w.sync_fullscreen = false
			f.native_set(w, opts.internal, opts.client)
			-- ConfigActions::fullscreenWindow RE-ENABLES sync for equal pairs.
			w.sync_fullscreen = w.fullscreen == w.fullscreen_client
		end)
	end
	function window_dsp.set_prop(opts)
		return dispatcher("set_prop", opts, function(w)
			assert(opts.prop == "sync_fullscreen" and (opts.value == "false" or opts.value == "true"))
			w.sync_fullscreen = opts.value == "true"
		end)
	end
	function window_dsp.tag(opts)
		return dispatcher("tag", opts, function(w)
			assert(opts.tag == "+bspwm_fullscreen_independent")
			for _, tag in ipairs(w.tags) do if tag == opts.tag:sub(2) then return end end
			w.tags[#w.tags + 1] = opts.tag:sub(2)
		end)
	end
	function window_dsp.float(opts)
		return dispatcher("float", opts, function(w)
			assert(opts.action == "on" or opts.action == "off", "float must not toggle")
			local floating = opts.action == "on"
			if floating ~= w.floating then
				assert(w.fullscreen == 0, "clear internal fullscreen before changing floating state")
				w.floating = floating
				-- Mode records don't follow the target to its new handler. The
				-- protocol state DOES survive; geometry resends that cached flag.
				local modes = w.handlers[floating]
				w.fullscreen, w.fullscreen_client = modes.internal, modes.client
				f.configure(w)
			end
		end)
	end
	function window_dsp.pseudo(opts)
		return dispatcher("pseudo", opts, function(w)
			assert(opts.action == "on" or opts.action == "off", "pseudo must not toggle")
			w.pseudo = opts.action == "on"
			f.configure(w)
		end)
	end

	_G.hl = {
		get_active_window = function() return f.active end,
		bind = function(keys, callback) f.binds[keys] = callback end,
		dispatch = function(callback) return callback() end,
		dsp = setmetatable({ window = window_dsp }, { __index = function() return ignored_dispatcher end }),
	}
	for _, name in ipairs({ "lua/helpers", "lua/bindings" }) do package.loaded[name] = nil end
	require("lua/bindings")
	function f.press(key) hl.dispatch(assert(f.binds["SUPER + " .. key])) end
	return f
end

local states = {
	{ key = "f", name = "fullscreen", fullscreen = 2, floating = false, pseudo = false },
	{ key = "s", name = "tiled", fullscreen = 0, floating = false, pseudo = false },
	{ key = "t", name = "pseudo_tiled", fullscreen = 0, floating = false, pseudo = true },
	{ key = "d", name = "floating", fullscreen = 0, floating = true, pseudo = false },
}

local function expect_state(w, target)
	assert(w.fullscreen == target.fullscreen and w.fullscreen_client == w.expected_client
		and w.floating == target.floating and w.pseudo == target.pseudo,
		"did not reach " .. target.name .. " with the original client mode")
	assert(w.app_fullscreen == (w.expected_client == 2), "application left fullscreen")
	assert(w.sync_fullscreen == (w.expected_client ~= 2), "incorrect application-entry / WM-demotion policy")
end

for _, target in ipairs(states) do
	tests[target.name .. "_overrides_internal_state_preserves_client_and_is_idempotent"] = function()
		local f = fixture()
		-- All valid internal/client pairs, latent flags, and stale/missing
		-- destination-handler client records left by previous transitions.
		for internal = 0, 2 do
			for client = 0, 2 do
				for destination_client = 0, 2 do
					for _, floating in ipairs({ false, true }) do
						for _, pseudo in ipairs({ false, true }) do
							f.active = f.window(internal, client, floating, pseudo, destination_client)
							f.press(target.key)
							expect_state(f.active, target)
							local changes = f.fullscreen_changes
							for _ = 1, 3 do f.press(target.key); expect_state(f.active, target) end
							assert(f.fullscreen_changes == changes, "repeated shortcut cycled fullscreen")
						end
					end
				end
			end
		end
	end

	tests[target.name .. "_keeps_original_target_if_focus_changes"] = function()
		local f = fixture()
		local w = f.window(2, 2, true, true)
		f.active, f.other = w, f.window(1, 1, true, true)
		f.switch_focus = true
		f.press(target.key)
		expect_state(w, target)
		assert(f.other.fullscreen == 1 and f.other.fullscreen_client == 1 and f.other.floating and f.other.pseudo,
			"shortcut affected another window")
	end

	tests[target.name .. "_without_mapped_focus_is_noop"] = function()
		local f = fixture()
		f.press(target.key)
		f.active = { mapped = false }
		f.press(target.key)
		assert(#f.calls == 0, "dispatched without a mapped focused window")
	end
end

function tests.shortcuts_override_each_other_in_sequence_without_changing_client_mode()
	for client = 0, 2 do
		local f = fixture()
		f.active = f.window(2, client, false, false)
		for _, source in ipairs(states) do
			for _, target in ipairs(states) do
				f.press(source.key); f.press(target.key)
				expect_state(f.active, target)
			end
		end
	end
end

function tests.client_exit_does_not_resurrect_stale_destination_modes()
	for _, key in ipairs({ "d", "s", "t" }) do
		local f = fixture()
		local w = f.window(2, 2, false, false)
		f.active = w
		f.press(key)
		assert(w.fullscreen == 0 and w.fullscreen_client == 2 and w.app_fullscreen)
		assert(w.sync_fullscreen == false)
		f.client_request(w, 0)
		-- Returning to an old handler must not resurrect its stale client=2.
		for _, next_key in ipairs({ "s", "d", "f", "t", "d", "s" }) do
			f.press(next_key)
			assert(w.fullscreen_client == 0 and not w.app_fullscreen)
		end
	end
end

function tests.noop_pairs_still_apply_application_entry_policy()
	for _, initial in ipairs({ {0, 0, "s"}, {2, 2, "f"} }) do
		local f = fixture()
		local w = f.window(initial[1], initial[2], false, false)
		f.active = w
		w.sync_fullscreen = initial[2] == 2 -- deliberately wrong inherited policy
		f.press(initial[3]) -- fullscreen_state itself is a native no-op
		assert(w.sync_fullscreen == (initial[2] ~= 2))
		if initial[2] == 0 then
			f.client_request(w, 2)
			assert(w.fullscreen == 2 and w.fullscreen_client == 2)
		end
	end
end

function tests.failed_fullscreen_clear_does_not_change_floating_or_pseudo()
	local f = fixture()
	f.active = f.window(2, 2, false, true)
	f.fail = "fullscreen_state"
	f.press("d")
	assert(#f.calls == 1 and f.active.fullscreen == 2 and not f.active.floating and f.active.pseudo)
end

function tests.failed_float_does_not_enter_fullscreen_on_wrong_handler()
	local f = fixture()
	f.active = f.window(0, 2, true, false)
	f.fail = "float"
	f.press("f")
	assert(f.active.fullscreen == 0 and f.active.fullscreen_client == 2 and f.active.floating)
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
