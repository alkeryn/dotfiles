local o = vim.opt
-- Colors
vim.cmd("set t_Co=256") -- TODO check if useful
o.background = "dark"
o.termguicolors = true

o.number = true
o.relativenumber = true
o.numberwidth = 1

o.hlsearch = true -- highlight search
o.ignorecase = true -- not case sensitive
o.smartcase = true -- case smart

-- o.foldmethod = "syntax"
o.clipboard = "unnamedplus"
o.mouse = "ni"

-- Indent settings
o.autoindent = true -- always set autoindenting on
o.copyindent = true -- copy indentation

-- File settings
o.backup = false -- do not keep a backup file, use versions instead
o.autoread = true
o.encoding = "utf-8"
if vim.bo.modifiable then
o.fileencoding = "utf-8" -- write
o.fileencodings = "utf-8" -- read
end
o.bomb = true -- unicode header
o.binary = true -- warning: disable expandtab if set after

-- Tabs settings
o.shiftwidth = 4 -- tab indent size
o.tabstop = 4 -- tab display
o.softtabstop = 4 -- insert tab
o.expandtab = true -- tabs are space
o.completeopt = "noinsert,menuone,noselect"

-- globals
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

vim.g.NERDTreeDirArrowExpandable = "▸"
vim.g.NERDTreeDirArrowCollapsible = "▾"
vim.g.seiya_auto_enable = 1
-- Default value: ['ctermbg']
vim.g.seiya_target_groups = vim.fn.has('nvim') == 1 and {'guibg'} or {'ctermbg'}
