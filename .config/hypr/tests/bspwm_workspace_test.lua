-- 0.57 API-shaped fixtures: named/special workspaces have id=nil, windows hex IDs.
local identity = require("lua/extensions/bspwm_workspace")
local codec = require("lua/extensions/bspwm_state")
local feedback = require("lua/extensions/presel_feedback")
local mon = { id=1, name="DP-1", position={x=0,y=0}, width=1600, height=900, scale=1 }
local numbered = { id=1, name="renamed number", addressable_name="1" }
local named = { name="display", addressable_name="code space" }
local other = { name="display", addressable_name="chat" }
local special = { name="special:scratch", addressable_name="special:scratch", special=true }
local workspaces = { numbered, named, other, special }
local windows, contexts, rules, events = {}, {}, {}, {}
local active, current, provider, api, states
local function emit(event, ...)
	for _, callback in ipairs(events[event] or {}) do callback(...) end
end
for _, ws in ipairs(workspaces) do
	ws.monitor, ws.tiled_layout, ws.visible = mon, "lua:bspwm", true
	contexts[identity.key(ws)] = { area={x=0,y=0,w=1600,h=900}, targets={} }
	function ws:get_windows()
		local result = {}
		for _, w in ipairs(windows) do if w.workspace == self then result[#result+1] = w end end
		return result
	end
end
assert(identity.key(numbered) == 1 and identity.selector(numbered) == 1)
assert(identity.key(named) == "name:code space" and identity.key(other) == "name:chat")
assert(identity.key(special) == "special:scratch" and identity.selector(special) == "special:scratch")
local function focus(w)
	for _, other_window in ipairs(windows) do other_window.active = other_window == w end
	active, current = w, w.workspace
	current.last_window = w
	mon.active_workspace = current
	emit("window.active", w, 5)
end
local function recalc(ws) provider.recalculate(contexts[identity.key(ws)]) end
local function rule(spec)
	rules[#rules+1] = spec
	return { set_enabled=function() end }
end
local function dispatcher(fn) return function(args) return function() return fn(args) or {ok=true} end end end
local function resolve(selector)
	if type(selector) == "table" then return selector end
	for _, ws in ipairs(workspaces) do
		if tostring(identity.selector(ws)) == tostring(selector) then return ws end
	end
end
local function load(saved)
	events, rules = {}, {}
	package.loaded["lua/extensions/bspwm_state"] = { open_session=function()
		if not saved then return nil end
		return { load=function() return assert(codec.decode(saved)) end,
			save=function(_, s, pending) assert(codec.decode(codec.encode(s, pending))); return true end }
	end }
	_G.hl = {
		layout={register=function(name, impl) if name == "bspwm" then provider = impl end end},
		on=function(event, callback) events[event] = events[event] or {}; table.insert(events[event], callback) end,
		window_rule=rule, workspace_rule=rule,
		get_windows=function() return windows end, get_workspaces=function() return workspaces end,
		get_workspace=resolve, get_monitors=function() return {mon} end,
		get_active_monitor=function() return mon end,
		get_active_window=function() return active end, get_active_workspace=function() return current end,
		dispatch=function(fn) return fn() end,
		dsp={
			focus=dispatcher(function(args) if args.window then focus(args.window) else current=resolve(args.workspace) end end),
			layout=dispatcher(function(message) provider.layout_msg(contexts[identity.key(current)], message); recalc(current) end),
			window={
				tag=dispatcher(function(args)
					args.window.tags[args.tag:sub(2)] = args.tag:sub(1,1) == "+" or nil
				end),
				alter_zorder=dispatcher(function() end),
				move=dispatcher(function(args)
					local w, dest = args.window or active, assert(resolve(args.workspace))
					local source, target = w.workspace
					local source_ctx, dest_ctx = contexts[identity.key(source)], contexts[identity.key(dest)]
					for i, t in ipairs(source_ctx.targets) do if t.window == w then target=table.remove(source_ctx.targets,i); break end end
					w.workspace = dest
					table.insert(dest_ctx.targets, assert(target))
					emit("window.move_to_workspace", w, dest)
					recalc(source); recalc(dest)
				end),
			},
		},
	}
	api = dofile("lua/extensions/bspwm.lua")
	api.set_feedback_sink(function(value) states=value end)
	for _, ws in ipairs(workspaces) do recalc(ws) end
	if saved then emit("config.reloaded"); emit("config.props_refreshed", true) end
end
local function open(id, ws)
	local w = {stable_id=id,workspace=ws,monitor=mon,mapped=true,hidden=false,floating=false,fullscreen=0,tags={},focus_history_id=0}
	local target = {window=w}
	function target:place(box) w.at={x=box.x,y=box.y}; w.size={x=box.w,y=box.h} end
	table.insert(windows,w); table.insert(contexts[identity.key(ws)].targets,target)
	recalc(ws); focus(w)
	return w
end
local function message(text)
	assert(provider.layout_msg(contexts[identity.key(current)],text) == true)
	recalc(current)
end
load()
local a, b = open("a",named), open("ffffffffffffffff",named)
open("10",other); open("20",special)
assert(states["name:code space"].tree.t == "split" and states["name:chat"].tree.id == "10")
assert(states["special:scratch"].tree.id == "20")
focus(a); message("preselect r"); message("pratio 0.3")
local rectangles = feedback.rectangles(states,workspaces,windows,{gaps_in=0,gaps_out=0})
assert(#rectangles == 1, "preselection must use nonnumeric workspace keys")
local saved = codec.encode(states)
load(saved)
assert(codec.encode(states) == saved, "named/special topology and preselection must survive reload")
local grab = assert(api.resize_begin(a,{x=700,y=700}))
assert(api.resize_motion(a,grab,{x=780,y=700}) and a.size.x == 880)
assert(api.drag_swap(a,b) and a.at.x == 880)
message("mode")
assert(states["name:code space"].mode == "monocle")
local found = false
for _, spec in ipairs(rules) do if spec.workspace == "name:code space" then found=true end end
assert(found, "monocle must target the addressable name, not the display name")
message("mode")
assert(api.drag_transfer(a,other) and a.workspace == other)
assert(states["name:code space"].tree.id == b.stable_id)
assert(api.swap_workspaces(named,special) == true)
assert(b.workspace == special and windows[4].workspace == named)
local round_trip = assert(codec.decode(codec.encode(states)))
assert(round_trip.states["special:scratch"].tree.id == b.stable_id)
-- Mixed numbered/named workspace navigation must not compare nil IDs.
package.loaded["lua/vars"] = {GAPS=4,GAPS_OUT=8,FLOAT_STEP=20,terminal="alacritty"}
package.loaded["lua/extensions/bspwm"] = api
package.loaded["lua/helpers"] = nil
local helpers = require("lua/helpers")
current = numbered
assert(helpers.relative_workspace(1) == other)
current = other
assert(helpers.relative_workspace(1) == named)
-- Byte encoding preserves names with spaces, UTF-8 and line breaks without eval.
local strange = "name:é space\nline"
local encoded = codec.encode({[1]={mode="tiled"},[strange]={mode="monocle"}})
assert(assert(codec.decode(encoded)).states[strange].mode == "monocle")
assert(not codec.decode("BSPWM_LAYOUT_V4\nP - -\nW s0 0 tiled - - - -\nN\n"))
print("PASS 0.57 numbered/named/special identity, tiling, checkpoint, preselection, drag, monocle, swaps and navigation")
