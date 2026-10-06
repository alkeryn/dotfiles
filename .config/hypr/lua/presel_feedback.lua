-- Predict the next bordered tile, then export output-local logical coordinates
-- to the native Wayland helper. No application titles/content are exported.
local M = {}

local function round(value) return math.floor(value + 0.5) end
local function gap(value, side)
	if type(value) == "table" then return value[side] or 0 end
	return tonumber(value) or 0
end

-- Space.cpp:recheckWorkArea. In this config the only gap override is the
-- single-window rule: after insertion there are >=2 tiles, so general gaps win.
-- Derive the FUTURE area, not the current gapless single-window rectangle.
function M.future_area(st, ws, gaps_out)
	local mon = ws.monitor
	if not mon or not mon.width or not mon.height or not mon.position then
		return st.tree and st.tree._box -- geometry-only callers without monitor data
	end
	local w, h = mon.width, mon.height
	if (mon.transform or 0) % 2 == 1 then w, h = h, w end
	w, h = round(w / (mon.scale or 1)), round(h / (mon.scale or 1))
	local reserved = mon.reserved or {}
	local left = (reserved.left or 0) + gap(gaps_out, "left")
	local top = (reserved.top or 0) + gap(gaps_out, "top")
	local right = (reserved.right or 0) + gap(gaps_out, "right")
	local bottom = (reserved.bottom or 0) + gap(gaps_out, "bottom")
	return { x = mon.position.x + left, y = mon.position.y + top,
		w = w - left - right, h = h - top - bottom }
end

-- WindowTarget.cpp:updatePos: inner gaps occur only at non-workarea edges.
-- This is the OUTSIDE of the future border: borders reserve space *inside*
-- this box, so subtracting border_size here would incorrectly shrink it twice.
function M.window_box(tile, area, gaps_in)
	local left = math.abs(tile.x - area.x) < 2 and 0 or gap(gaps_in, "left")
	local top = math.abs(tile.y - area.y) < 2 and 0 or gap(gaps_in, "top")
	local right = math.abs(tile.x + tile.w - area.x - area.w) < 2 and 0 or gap(gaps_in, "right")
	local bottom = math.abs(tile.y + tile.h - area.y - area.h) < 2 and 0 or gap(gaps_in, "bottom")
	return { x = round(tile.x) + left, y = round(tile.y) + top,
		w = round(tile.w) - left - right, h = round(tile.h) - top - bottom }
end

function M.preview_box(box, pre)
	local dir, ratio = pre.dir, pre.ratio or 0.5
	local x, y, w, h = box.x, box.y, box.w, box.h
	if dir == "u" or dir == "up" or dir == "north" then
		h = math.floor(h * ratio)
	elseif dir == "d" or dir == "down" or dir == "south" then
		local first = math.floor(h * ratio)
		y, h = y + first, h - first
	elseif dir == "l" or dir == "west" then
		w = math.floor(w * ratio)
	else -- east: ratio is the OLD/first child's share, as in bspwm
		local first = math.floor(w * ratio)
		x, w = x + first, w - first
	end
	return { x = x, y = y, w = w, h = h }
end

-- Pure function, also used by the regression tests. Querying live windows
-- prevents ghosts after closing/floating the last tile (no nonempty layout pass).
function M.rectangles(states, workspaces, windows, options)
	options = options or {}
	local live, result = {}, {}
	for _, w in ipairs(windows) do
		if w.mapped and not w.floating and w.workspace then live[w.stable_id] = w.workspace.id end
	end
	local function collect(node, ws, box, area)
		if not node then return false end
		local valid
		if node.t == "leaf" then
			valid = live[node.id] == ws.id
		else
			local first, second
			if node.axis == "h" then
				local w = math.floor(box.w * node.ratio)
				first = { x = box.x, y = box.y, w = w, h = box.h }
				second = { x = box.x + w, y = box.y, w = box.w - w, h = box.h }
			else
				local h = math.floor(box.h * node.ratio)
				first = { x = box.x, y = box.y, w = box.w, h = h }
				second = { x = box.x, y = box.y + h, w = box.w, h = box.h - h }
			end
			local a, b = collect(node.a, ws, first, area), collect(node.b, ws, second, area)
			valid = a and b
		end
		if valid and node.presel then
			local preview = M.window_box(M.preview_box(box, node.presel), area, options.gaps_in)
			preview.output = ws.monitor.name
			local origin = ws.monitor.position or { x = 0, y = 0 }
			preview.monitor_x, preview.monitor_y = origin.x, origin.y
			if preview.w > 0 and preview.h > 0 then result[#result + 1] = preview end
		end
		return valid
	end
	for _, ws in ipairs(workspaces) do
		local st, mon = states[ws.id], ws.monitor
		local special = mon and mon.active_special_workspace
		if st and mon and mon.name and st.mode ~= "monocle" and ws.visible and not ws.has_fullscreen
			and (ws.tiled_layout == "lua:bspwm" or ws.tiled_layout == "lua:bspwm_b")
			and (not mon or mon.dpms_status ~= false)
			and (not special or special.id == ws.id) then
			local area = M.future_area(st, ws, options.gaps_out)
			if area and area.w > 0 and area.h > 0 then collect(st.tree, ws, area, area) end
		end
	end
	table.sort(result, function(a, b)
		if a.output ~= b.output then return a.output < b.output end
		if a.x ~= b.x then return a.x < b.x end
		if a.y ~= b.y then return a.y < b.y end
		if a.w ~= b.w then return a.w < b.w end
		return a.h < b.h
	end)
	return result
end

function M.encode(rectangles)
	local parts = { "BSPWM_PRESEL_V2\n" }
	for _, b in ipairs(rectangles) do
		if b.output and b.output:match("^[%w_.:-]+$") then
			parts[#parts + 1] = string.format("%s %d %d %d %d\n", b.output,
				round(b.x - (b.monitor_x or 0)), round(b.y - (b.monitor_y or 0)), round(b.w), round(b.h))
		end
	end
	return table.concat(parts)
end

local function shell_quote(value)
	return "'" .. value:gsub("'", "'\\''") .. "'"
end

function M.setup(layout)
	local states, state_path, last_payload, timer
	local started, warned = false, false

	local function report_error(message)
		if not warned then
			warned = true
			print("bspwm preselection feedback: " .. tostring(message))
		end
	end

	local function write_state(payload)
		if not state_path or payload == last_payload then return end
		local tmp = state_path .. ".tmp"
		local file, err = io.open(tmp, "w")
		if not file then report_error(err); return end
		local ok = file:write(payload)
		local closed = file:close()
		if not ok or not closed then os.remove(tmp); report_error("state write failed"); return end
		local renamed, rename_err = os.rename(tmp, state_path)
		if not renamed then os.remove(tmp); report_error(rename_err); return end
		last_payload, warned = payload, false
	end

	local function publish()
		if started and states then
			write_state(M.encode(M.rectangles(states, hl.get_workspaces(), hl.get_windows(), {
				gaps_in = hl.get_config("general.gaps_in"),
				gaps_out = hl.get_config("general.gaps_out"),
			})))
		end
	end
	layout.set_feedback_sink(function(current)
		states = current
		publish()
	end)

	local function start()
		if started then publish(); return end
		-- config.reloaded also fires before outputs exist on compositor startup.
		if #hl.get_monitors() == 0 then return end
		local runtime = os.getenv("XDG_RUNTIME_DIR")
		local signature = os.getenv("HYPRLAND_INSTANCE_SIGNATURE")
		local home = os.getenv("HOME")
		if not runtime or not signature or not home or not signature:match("^[%w_.-]+$") then
			report_error("missing/invalid session environment"); return
		end
		local base = runtime .. "/bspwm_presel_" .. signature
		state_path = base .. ".state"
		-- Hide the old overlay immediately. The native helper retires only the
		-- verified Python process belonging to this exact session/state file.
		local legacy = base .. ".json"
		local file = io.open(legacy .. ".tmp", "w")
		if file then
			file:write('{"version":1,"rectangles":[]}\n'); file:close()
			os.rename(legacy .. ".tmp", legacy)
		end
		started = true
		publish()
		-- One lightweight reader per compositor; duplicate reload launches exit
		-- via flock. A timer covers workspace/fullscreen/DPMS changes that don't
		-- necessarily recalculate the layout. Writes happen only on changes.
		timer = hl.timer(publish, { timeout = 50, type = "repeat" })
		hl.exec_cmd(shell_quote(home .. "/.config/hypr/scripts/presel_feedback")
			.. " --state " .. shell_quote(state_path) .. " --legacy-state " .. shell_quote(legacy)
			.. " >> " .. shell_quote(state_path .. ".log") .. " 2>&1")
	end
	hl.on("hyprland.start", start)
	hl.on("config.reloaded", start)
	hl.on("hyprland.shutdown", function()
		if timer then timer:set_enabled(false) end
		write_state(M.encode({}))
	end)
end

return M
