-- Session-only layout checkpoints. Data-only, bounded parser: never load/eval
-- a state file as Lua. Geometry/userdata are rebuilt by the compositor.
local M = {}
local HEADER = "BSPWM_LAYOUT_V1"
local MAX_BYTES, MAX_NODES, MAX_DEPTH, MAX_WORKSPACES = 1048576, 8192, 128, 256
local DIRECTIONS = { l=true, r=true, u=true, d=true, west=true, east=true,
	north=true, south=true, up=true, down=true }

local function integer(value, minimum)
	assert(type(value) == "number" and value == value and value % 1 == 0
		and value >= minimum and value <= 9007199254740991, "invalid integer")
	return value
end
local function ratio(value)
	assert(type(value) == "number" and value > 0 and value < 1, "invalid ratio")
	return value
end
local function presel_tokens(pre)
	if not pre then return "- -" end
	assert(DIRECTIONS[pre.dir], "invalid preselection direction")
	return pre.dir .. " " .. string.format("%.17g", ratio(pre.ratio or 0.5))
end

function M.encode(states, pending)
	local lines = { HEADER, "P " .. presel_tokens(pending) }
	local ids = {}
	for id in pairs(states) do ids[#ids + 1] = integer(id, -9007199254740991) end
	assert(#ids <= MAX_WORKSPACES, "too many workspaces")
	table.sort(ids)
	local total = 0
	for _, id in ipairs(ids) do
		local st, paths, rows, seen_ids = states[id], {}, {}, {}
		local function visit(node, path, depth)
			assert(depth <= MAX_DEPTH, "tree too deep")
			if not node then rows[#rows + 1] = "N"; return end
			total = total + 1
			assert(total <= MAX_NODES and not paths[node], "invalid/oversized tree")
			paths[node] = path
			if node.t == "leaf" then
				integer(node.id, 1)
				assert(not seen_ids[node.id], "duplicate leaf")
				seen_ids[node.id] = true
				rows[#rows + 1] = string.format("L %.0f %.0f %s", node.id,
					integer(node.n or 0, 0), presel_tokens(node.presel))
			else
				assert(node.t == "split" and node.a and node.b, "invalid split")
				rows[#rows + 1] = string.format("S %s %.17g %s", node.axis == "h" and "h" or "v",
					ratio(node.ratio), presel_tokens(node.presel))
				visit(node.a, path .. "a", depth + 1)
				visit(node.b, path .. "b", depth + 1)
			end
		end
		visit(st.tree, ".", 0)
		local selected = paths[st.selected] or "-"
		local insertion = paths[st.insertion_anchor] or "-"
		local function focus_token(path, value)
			return path == "-" and "-" or string.format("%.0f", integer(value, 1))
		end
		assert(st.mode == "tiled" or st.mode == "monocle", "invalid mode")
		lines[#lines + 1] = string.format("W %.0f %.0f %s %s %s %s %s", id,
			integer(st.seq or 0, 0), st.mode, selected, focus_token(selected, st.selected_focus_id),
			insertion, focus_token(insertion, st.insertion_window_id))
		for _, row in ipairs(rows) do lines[#lines + 1] = row end
	end
	local text = table.concat(lines, "\n") .. "\n"
	assert(#text <= MAX_BYTES, "checkpoint too large")
	return text
end

function M.decode(text)
	local function parse()
		assert(type(text) == "string" and #text <= MAX_BYTES, "checkpoint too large")
		local tokens = {}
		for token in text:gmatch("%S+") do tokens[#tokens + 1] = token end
		local pos, total, workspaces = 0, 0, 0
		local function next_token()
			pos = pos + 1
			local token = assert(tokens[pos], "truncated checkpoint")
			return token
		end
		local function number(minimum) return integer(tonumber(next_token()), minimum) end
		local function read_presel()
			local dir, value = next_token(), next_token()
			if dir == "-" then assert(value == "-", "invalid empty preselection"); return nil end
			assert(DIRECTIONS[dir], "invalid preselection direction")
			return { dir=dir, ratio=ratio(tonumber(value)) }
		end
		assert(next_token() == HEADER, "unsupported checkpoint version")
		assert(next_token() == "P", "missing pending preselection")
		local result = { states = {}, pending = read_presel() }
		while pos < #tokens do
			assert(next_token() == "W", "invalid workspace record")
			local id, seq, mode = number(-9007199254740991), number(0), next_token()
			assert(not result.states[id] and (mode == "tiled" or mode == "monocle"), "invalid workspace")
			workspaces = workspaces + 1
			assert(workspaces <= MAX_WORKSPACES, "too many workspaces")
			local selected, focused, insertion, inserted = next_token(), next_token(), next_token(), next_token()
			local seen_ids = {}
			local function read_node(depth)
				assert(depth <= MAX_DEPTH, "tree too deep")
				local kind = next_token()
				if kind == "N" then return nil end
				total = total + 1
				assert(total <= MAX_NODES, "too many nodes")
				if kind == "L" then
					local leaf_id, age = number(1), number(0)
					assert(not seen_ids[leaf_id], "duplicate leaf")
					seen_ids[leaf_id] = true
					return { t="leaf", id=leaf_id, n=age, presel=read_presel() }
				end
				assert(kind == "S", "invalid node type")
				local axis, split_ratio = next_token(), ratio(tonumber(next_token()))
				assert(axis == "h" or axis == "v", "invalid axis")
				local node = { t="split", axis=axis, ratio=split_ratio, presel=read_presel() }
				node.a, node.b = read_node(depth + 1), read_node(depth + 1)
				assert(node.a and node.b, "split missing child")
				return node
			end
			local tree = read_node(0)
			local function resolve(path, focus)
				if path == "-" then assert(focus == "-", "orphan focus"); return nil, nil end
				assert(path:match("^%.[ab]*$") and #path <= MAX_DEPTH + 1, "invalid node path")
				local node = tree
				for child in path:sub(2):gmatch(".") do node = node and node[child] end
				assert(node, "missing selected node")
				return node, integer(tonumber(focus), 1)
			end
			local st = { tree=tree, seq=seq, mode=mode, boxes={}, highlighted={} }
			st.selected, st.selected_focus_id = resolve(selected, focused)
			st.insertion_anchor, st.insertion_window_id = resolve(insertion, inserted)
			result.states[id] = st
		end
		return result
	end
	local ok, result = pcall(parse)
	if ok then return result end
	return nil, result
end

function M.open(path)
	local store = { path = path }
	function store:load()
		local file, err, code = io.open(self.path, "r")
		if not file then
			if code == 2 then return nil end -- first load, no checkpoint yet
			return nil, err
		end
		local text = file:read(MAX_BYTES + 1)
		file:close()
		local value, parse_error = M.decode(text or "")
		if value then self.last_payload = text end
		return value, parse_error
	end
	function store:save(states, pending)
		local ok, text = pcall(M.encode, states, pending)
		if not ok then return nil, text end
		if text == self.last_payload then return true end
		local tmp = self.path .. ".tmp"
		local file, err = io.open(tmp, "w")
		if not file then return nil, err end
		local written, write_error = file:write(text)
		local closed, close_error = file:close()
		if not written or not closed then os.remove(tmp); return nil, write_error or close_error end
		local renamed, rename_error = os.rename(tmp, self.path)
		if not renamed then os.remove(tmp); return nil, rename_error end
		self.last_payload = text
		return true
	end
	return store
end

function M.open_session()
	local runtime, signature = os.getenv("XDG_RUNTIME_DIR"), os.getenv("HYPRLAND_INSTANCE_SIGNATURE")
	if not runtime or not signature or not signature:match("^[%w_.-]+$") then
		return nil, "missing/invalid session environment"
	end
	return M.open(runtime .. "/bspwm_layout_" .. signature .. ".state")
end

return M
