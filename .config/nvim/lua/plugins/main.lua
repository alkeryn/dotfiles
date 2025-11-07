return {
  -- Auto complete
  -- this is handled by plugins/lsp.lua

  -- Highlighting
  "sheerun/vim-polyglot",
  'kaarmu/typst.vim',

  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
  },

  -- Behavior
  {
    'windwp/nvim-autopairs', -- autoclose brackets
    event = "InsertEnter",
    -- use opts = {} for passing setup options
    -- this is equivalent to setup({}) function
    config = true

  },
  {
    "kylechui/nvim-surround", -- surrounding
    version = "^3.0.0", -- Use for stability; omit to use `main` branch for the latest features
    event = "VeryLazy",
    config = true
  },

  -- Tools
  'ntpeters/vim-better-whitespace', -- "show when there is gross trailing whitespace
  {
    'numToStr/Comment.nvim', -- comment shortcut
    config = true
  },

  {
    "JoosepAlviste/nvim-ts-context-commentstring", -- multilang files comments
    cond = utils.executable("tree-sitter")
  },
  {
    "direnv/direnv.vim",
    cond = utils.executable("direnv") -- direnv integration
  },
  "mbbill/undotree",
  'rhysd/git-messenger.vim',
  'tpope/vim-fugitive',
  {
    "ibhagwan/fzf-lua",
    -- optional for icon support
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = function ()
      require("fzf-lua").register_ui_select()
	end
  },

  -- Looks
  'lilydjwg/colorizer', -- Colorize hexa or rgb
  'vim-airline/vim-airline', -- UPGRADE?
  'vim-airline/vim-airline-themes',
  'miyakogi/seiya.vim', -- background transparent again
  {
    "folke/snacks.nvim",
    ---@type snacks.Config
    opts = {
      indent = {
        enable = true
        -- your indent configuration comes here
        -- or leave it empty to use the default settings
        -- refer to the configuration section below
      }
    }
  },

  -- Themes
  'chriskempson/base16-vim',
  'kaicataldo/material.vim',
  'phanviet/vim-monokai-pro',

  -- Fancy
  'mhinz/vim-startify',
}
