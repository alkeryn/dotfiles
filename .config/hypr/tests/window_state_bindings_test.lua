-- Run from ~/.config/hypr: lua tests/window_state_bindings_test.lua
-- Exercise the actual bindings/helpers with v0.56.2 dispatcher semantics.
local tests = {}

local function fixture()
	local f = { binds = {}, calls = {}, fullscreen_changes = 0 }
	local function ignored_dispatcher() return function() end end
	package.loaded["lua/bspwm"] = { close = function() end, reload = function() end }
	local window_dsp = setmetatable({}, { __index = function() return ignored_dispatcher end })

	local function dispatcher(kind, opts, apply)
		return function()
			assert(opts and opts.window, kind .. " must explicitly target the original window")
			f.calls[#f.calls + 1] = kind
			apply(opts.window)
			if f.switch_focus then f.active = f.other end
			return { ok = true }
		end
	end

	function window_dsp.fullscreen_state(opts)
		return dispatcher("fullscreen_state", opts, function(w)
			assert(opts.action == "set", "fullscreen must be set, not toggled")
			assert(opts.layout_aware == false, "request real fullscreen, not a layout-specific mode")
			if w.fullscreen ~= opts.internal or w.fullscreen_client ~= opts.client then
				f.fullscreen_changes = f.fullscreen_changes + 1
			end
			w.fullscreen, w.fullscreen_client = opts.internal, opts.client
		end)
	end

	function window_dsp.float(opts)
		return dispatcher("float", opts, function(w)
			assert(opts.action == "on" or opts.action == "off", "float must not toggle")
			local floating = opts.action == "on"
			if floating ~= w.floating then
				assert(w.fullscreen == 0 and w.fullscreen_client == 0,
					"clear fullscreen before changing floating state")
				w.floating = floating
			end
		end)
	end

	function window_dsp.pseudo(opts)
		return dispatcher("pseudo", opts, function(w)
			assert(opts.action == "on" or opts.action == "off", "pseudo must not toggle")
			w.pseudo = opts.action == "on"
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
	assert(w.fullscreen == target.fullscreen and w.fullscreen_client == target.fullscreen
		and w.floating == target.floating and w.pseudo == target.pseudo,
		"did not reach " .. target.name)
end

for _, target in ipairs(states) do
	tests[target.name .. "_overrides_every_state_and_is_idempotent"] = function()
		local f = fixture()
		-- Include maximized, combined and mismatched client/internal modes,
		-- including latent pseudo/floating flags under fullscreen.
		for internal = 0, 3 do
			for client = 0, 3 do
				for _, floating in ipairs({ false, true }) do
					for _, pseudo in ipairs({ false, true }) do
						f.active = { mapped = true, fullscreen = internal, fullscreen_client = client,
							floating = floating, pseudo = pseudo }
						f.press(target.key)
						expect_state(f.active, target)
						local changes = f.fullscreen_changes
						for _ = 1, 3 do
							f.press(target.key)
							expect_state(f.active, target)
						end
						assert(f.fullscreen_changes == changes, "repeated shortcut cycled fullscreen")
					end
				end
			end
		end
	end

	tests[target.name .. "_keeps_original_target_if_focus_changes"] = function()
		local f = fixture()
		local w = { mapped = true, fullscreen = 2, fullscreen_client = 2, floating = true, pseudo = true }
		f.active = w
		f.other = { mapped = true, fullscreen = 1, fullscreen_client = 1, floating = true, pseudo = true }
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

function tests.shortcuts_override_each_other_in_sequence()
	local f = fixture()
	f.active = { mapped = true, fullscreen = 0, fullscreen_client = 0, floating = false, pseudo = false }
	for _, source in ipairs(states) do
		for _, target in ipairs(states) do
			f.press(source.key)
			f.press(target.key)
			expect_state(f.active, target)
		end
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
