---
---@param max table
---@param str string
local function newmax(max, str)
  local length = string.len(str)
  if length > max[1] then
    max[1] = length
  end
end

---@param diagnostic vim.Diagnostic
local function get_diag_count(diagnostic) -- TODO use line number and character position
  local diags = vim.diagnostic.get(diagnostic.bufnr, {
    namespace = diagnostic.namespace,
    lnum = diagnostic.lnum,
  })
  local total = 0
  for _, v in ipairs(diags) do
    local col = v.col == diagnostic.col
    local col_end = v.end_col == diagnostic.end_col
    if col and col_end then
      total = total + 1
    end
  end
  return total
end

local diag_i = 1
local suffix_size = { 0 }
---@param diagnostic vim.Diagnostic
---@return string
local function format_function(diagnostic)
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

  local diag_total = get_diag_count(diagnostic)
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
    diag_i = 1
    suffix_size = { 0 }
    -- could be overriden by making my own window like
    -- vim.api.nvim_open_win(diagnostic.bufnr, true, { relative = "cursor", row = 0, col = 1, width = 10, height = 5})
    vim.diagnostic.open_float({
        bufnr = args.buf,
        scope = "cursor"
      },
      { focus = false }
    )
  end,
})
