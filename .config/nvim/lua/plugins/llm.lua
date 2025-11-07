return {
  -- lazy.nvim
  {
    "olimorris/codecompanion.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
    },
    opts = {
      strategies = {
        chat = {
          adapter = "openrouter"
        },
        inline = {
          adapter = "openrouter"
        },
        cmd = {
          adapter = "openrouter"
        }
      },
      adapters = {
        http = {
          openrouter = function()
            return require("codecompanion.adapters").extend("openai_compatible", {
                env = {
                  url = "https://openrouter.ai/api",
                  api_key = "cmd:svar -f ~/.config/etc/env get OPENROUTER_API_KEY",
                  chat_url = "/v1/chat/completions",
                },
                schema = {
                  model = {
                    default = "anthropic/claude-sonnet-4.5",
                  },
                },
              })
          end,
        }
      },

      display = {
        action_palette = {
          provider = "fzf_lua",
        },
        chat = {
          window = {
            position = "right"
          }
        }
      },
      -- NOTE: The log_level is in `opts.opts`
      opts = {
        log_level = "DEBUG", -- or "TRACE"
      },
    },
  },
}
