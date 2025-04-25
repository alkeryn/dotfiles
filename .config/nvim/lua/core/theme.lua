local api = vim.api
-- Set default colors for BlinkCmp menu (black background, white text)
api.nvim_set_hl(0, "BlinkCmpMenu", { fg = "#ffffff", bg = "#000000" })
api.nvim_set_hl(0, "BlinkCmpMenuBorder", { fg = "#ffffff", bg = "#000000" })
api.nvim_set_hl(0, "BlinkCmpMenuSelection", { fg = "#000000", bg = "#ffffff" }) -- inverted for selection
api.nvim_set_hl(0, "BlinkCmpLabel", { fg = "#ffffff", bg = "#000000" })
api.nvim_set_hl(0, "BlinkCmpLabelDeprecated", { fg = "#aaaaaa", bg = "#000000", italic = true })
api.nvim_set_hl(0, "BlinkCmpLabelMatch", { fg = "#ff00ff", bg = "#000000", bold = true })
api.nvim_set_hl(0, "BlinkCmpLabelDetail", { fg = "#dddddd", bg = "#000000" })
api.nvim_set_hl(0, "BlinkCmpLabelDescription", { fg = "#dddddd", bg = "#000000" })
api.nvim_set_hl(0, "BlinkCmpKind", { fg = "#ffffff", bg = "#000000" })
-- vim.api.nvim_set_hl(0, "BlinkCmpSource", { fg = "#aaaaaa", bg = "#000000", italic = true })
-- vim.api.nvim_set_hl(0, "BlinkCmpGhostText", { fg = "#555555", bg = "#000000" })

-- Set related floating windows to black/white too
api.nvim_set_hl(0, "BlinkCmpDoc", { fg = "#ffffff", bg = "#000000" })
api.nvim_set_hl(0, "BlinkCmpDocBorder", { fg = "#ffffff", bg = "#000000" })
api.nvim_set_hl(0, "BlinkCmpDocSeparator", { fg = "#444444", bg = "#000000" })
api.nvim_set_hl(0, "BlinkCmpDocCursorLine", { fg = "#ffffff", bg = "#222222" })
api.nvim_set_hl(0, "BlinkCmpSignatureHelp", { fg = "#ffffff", bg = "#000000" })
api.nvim_set_hl(0, "BlinkCmpSignatureHelpBorder", { fg = "#ffffff", bg = "#000000" })
api.nvim_set_hl(0, "BlinkCmpSignatureHelpActiveParameter", { fg = "#ff00ff", bg = "#000000", bold = true })
