-- Workspace identity changed in 0.57: only numbered workspaces have .id.
-- Keep numeric keys for numbered/old sessions; use absolute selectors otherwise.
local M = {}

function M.selector(ws)
	-- A running 0.56 session still exposes negative IDs and the old full name.
	if not ws.addressable_name and ws.id then
		return ws.id > 0 and ws.id or "name:" .. ws.name
	end
	if ws.special then
		local name = ws.addressable_name or ws.name
		return name:match("^special:") and name or "special:" .. name
	end
	if ws.id and ws.id > 0 then return ws.id end
	return "name:" .. (ws.addressable_name or ws.name)
end

function M.key(ws)
	if not ws then return nil end
	if ws.id ~= nil then return ws.id end
	return M.selector(ws)
end

function M.less(a, b)
	if type(a) ~= type(b) then return type(a) == "number" end
	return a < b
end

return M
