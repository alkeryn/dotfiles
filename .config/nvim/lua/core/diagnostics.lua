---
---@param max table
---@param str string
local function newmax(max, str)
  local length = string.len(str)
  if length > max[1] then
    max[1] = length
  end
end

local diag_i
local diag_total
local suffix_size = { 0 }
---@param diagnostic vim.Diagnostic
---@param i integer
---@param total integer
---@return string
local function format_function(diagnostic, i, total)
  newmax(suffix_size, diagnostic.message)

  local lsp_info = diagnostic.user_data.lsp.relatedInformation or {}

  local ret = {}

  table.insert(ret, diagnostic.message)
  newmax(suffix_size, diagnostic.message)

  if next(lsp_info) then
    local rel = "\n\nRelated information:\n\n"
    table.insert(ret, rel)
    newmax(suffix_size, rel)
  end

  -- related info stuff
  for _, v in ipairs(lsp_info) do
    local message = v["message"]
    local character = v["location"]["range"]["start"]["character"] + 1
    local line = v["location"]["range"]["start"]["character"] + 1
    local uri = v["location"]["uri"]
    if uri then
      uri = uri:match("([^/]-([^.]+))$")
    end

    local mes = string.format(" *%s#%s,%s: %s\n", uri, line, character, message)
    table.insert(ret, mes)
    newmax(suffix_size, mes)
  end

  -- change behavior if there is a code and codeDescription
  local newline = "\n"
  if diag_i == diag_total then
    newline = ""
  end
  local endstr = string.format("\n (%s)%s", diagnostic.source, newline)
  table.insert(ret, endstr)

  diag_i = diag_i + 1
  return table.concat(ret)
end

vim.diagnostic.config({
  -- virtual_lines = {current_line = false }, -- pretty cool
  virtual_text = false,     -- Whether to show diagnostics inline
  underline = true,         -- Underline text with issues
  update_in_insert = false, -- Don't update diagnostics in insert mode
  severity_sort = true,     -- Sort diagnostics by severity
  float = {                 -- Configure the hover window
    source = "if_many",     -- Always show source
    focusable = false,      -- Make it non-focusable
    header = "",
    prefix = " ",
    format = format_function,
    suffix = function(_, i, total)
      local is_last = i == total
      local highlight = "DiagnosticFloatingInfo"
      if not is_last then
        local sep_line = string.rep("─", suffix_size[1])
        return sep_line, highlight
      end
      return "", highlight
    end
  },
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = "❌",
      [vim.diagnostic.severity.WARN] = "⚠️",
      [vim.diagnostic.severity.HINT] = "💡",
      [vim.diagnostic.severity.INFO] = "ℹ️"
    },
  },
})

vim.api.nvim_create_autocmd({ "CursorHold" }, {
  callback = function(args)
    suffix_size = { 0 }
    diag_i = 1
    diag_total = #vim.diagnostic.get(args.buf)
    vim.diagnostic.open_float(nil, { focus = false })
  end,
})
