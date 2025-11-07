return {
  -- LSP Configuration & Plugins
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      -- Automatically install LSPs and related tools to stdpath
      "williamboman/mason.nvim",
      "williamboman/mason-lspconfig.nvim",
      "WhoIsSethDaniel/mason-tool-installer.nvim",

      -- Useful status updates for LSP
      { "j-hui/fidget.nvim", opts = {} },
    },
    config = function()

      -- Configure mason for autoinstalling LSP servers
      require("mason").setup({
          ui = {
            border = "rounded",
          },
        })

      local lsp_list = {
        "rust_analyzer",
        "lua_ls",
        "pylyzer",
      }
      require("mason-lspconfig").setup({
          ensure_installed = lsp_list,
          automatic_installation = true,
          automatic_enable = true
        })

      -- Additional tools to install (formatters, linters, etc)
      require("mason-tool-installer").setup({
          ensure_installed = {
            "stylua", -- lua formatter
          },
          auto_update = true,
          run_on_start = true,
        })

      -- Configure rust_analyzer
      vim.lsp.config["rust_analyzer"] = {
        settings = {
          ['rust-analyzer'] = {
            cargo = {
              allFeatures = true,
            },
            procMacro = {
              enable = true,
            },
          },
        },
      }

      -- Configure lua_ls for Neovim Lua development
      vim.lsp.config["lua_ls"] = {
        root_dir = "",
        settings = {
          Lua = {
            diagnostics = {
              globals = { 'vim' },
            },
            workspace = {
              library = vim.api.nvim_get_runtime_file("", true),
              checkThirdParty = false,
            },
            telemetry = {
              enable = false,
            },
          },
        },
      }
      vim.o.updatetime = 150

      -- for _, lsp in ipairs(lsp_list) do
      --   vim.lsp.enable(lsp)
      -- end
    end,
  },
}
