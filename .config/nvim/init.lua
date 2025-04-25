require("utils")
require("core.settings") -- always call settings before lazy
require("core.lazy")
vim.cmd('source ~/.config/nvim/vimrc')

require("core.keybinds")
require("core.theme")
require("core.diagnostics")

-- Treesitter setup if available
if utils.executable("tree-sitter") then
  require'nvim-treesitter.configs'.setup {
    ensure_installed = { "c", "lua", "rust", "svelte","javascript", "html", "css", "vim" },
    sync_install = false,
  }
end

-- Hide all semantic highlights
for _, group in ipairs(vim.fn.getcompletion("@lsp", "highlight")) do
  vim.api.nvim_set_hl(0, group, {})
end
