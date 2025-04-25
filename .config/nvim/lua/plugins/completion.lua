---@module 'blink.cmp'
local blink = {
  'saghen/blink.cmp',
  -- optional: provides snippets for the snippet source
  dependencies = {
	"neovim/nvim-lspconfig", -- only load after the nvim-lspconfig
    'L3MON4D3/LuaSnip'
  },

  -- use a release tag to download pre-built binaries
  version = '1.*',
  -- AND/OR build from source, requires nightly: https://rust-lang.github.io/rustup/concepts/channels.html#working-with-nightly-rust
  -- build = 'cargo build --release',
  -- If you use nix, you can build from source using latest nightly rust with:
  -- build = 'nix run .#build-plugin',

  ---@param opts blink.cmp.Config
  opts = function(_,opts)
    opts = {
    -- 'default' (recommended) for mappings similar to built-in completions (C-y to accept)
    -- 'super-tab' for mappings similar to vscode (tab to accept)
    -- 'enter' for enter to accept
    -- 'none' for no mappings
    --
    -- All presets have the following mappings:
    -- C-space: Open menu or open docs if already open
    -- C-n/C-p or Up/Down: Select next/previous item
    -- C-e: Hide menu
    -- C-k: Toggle signature help (if signature.enabled = true)
    --
    -- See :h blink-cmp-config-keymap for defining your own keymap
    keymap = {
      preset = 'super-tab',
      ["<CR>"] = {
        "select_and_accept",
        "fallback"
      },
      ["<C-p>"] = {
        function (cmp)
          if not cmp.get_selected_item() then
            return cmp.snippet_backward()
          end
        end,
        "show",
        "select_prev",
      },
      ["<C-n>"] = {
        "show",
        "select_next",
      },
      ["<A-n>"] = {
        "snippet_forward",
        "fallback"
      },
      ["<TAB>"] = {
		function(cmp)
          if cmp.snippet_active({direction = 1}) then
            return cmp.snippet_forward()
          end
          local selected = cmp.get_items()[1]
		  local snippet_id = 15
		  if selected and selected.kind == snippet_id then
			return cmp.select_and_accept()
		  end
		end,
		"select_next",
		"fallback"
	  }
    },

	snippets = { preset = 'luasnip' },

    appearance = {
      -- 'mono' (default) for 'Nerd Font Mono' or 'normal' for 'Nerd Font'
      -- Adjusts spacing to ensure icons are aligned
      nerd_font_variant = 'mono'
    },

    -- (Default) Only show the documentation popup when manually triggered
	completion = {
	  documentation = {
		auto_show = true,
		auto_show_delay_ms = vim.o.updatetime
	  },
      trigger = {
        show_on_insert_on_trigger_character = false
      },
	  list = {
		selection = {
		  preselect = false
		}
	  },
	  menu = {
		draw = {
		  treesitter = {"lsp"},
		},
		max_height = 50,
		min_width = 30
	  },
      ghost_text = {
        enabled = true,
      }
    },

    signature = {
      enabled = true,
    },

    -- Default list of enabled providers defined so that you can extend it
    -- elsewhere in your config, without redefining it, due to `opts_extend`
    sources = {
      default = { 'lsp', 'path', 'snippets', 'buffer' },
    },

    -- (Default) Rust fuzzy matcher for typo resistance and significantly better performance
    -- You may use a lua implementation instead by using `implementation = "lua"` or fallback to the lua implementation,
    -- when the Rust fuzzy matcher is not available, by using `implementation = "prefer_rust"`
    --
    -- See the fuzzy documentation for more information
    fuzzy = { implementation = "rust" }
  }
  return opts end,
  opts_extend = { "sources.default" }
}
return {
  {
    'L3MON4D3/LuaSnip',
    version = 'v2.*',
    dependencies = {
      'rafamadriz/friendly-snippets',
      'honza/vim-snippets',
    },
    config = function()
      require("luasnip.loaders.from_vscode").lazy_load()
      require("luasnip.loaders.from_snipmate").lazy_load()
    end
  },
  blink
}
