-- Diagnostics are configured only through vim.diagnostic.config().
-- (The old sign_define calls and vim.diagnostic.disable() were removed in 0.12.)
local S = vim.diagnostic.severity

-- nr2char keeps the Nerd Font icons readable in source (they need a Nerd Font in the terminal).
vim.diagnostic.config({
  virtual_text = true,
  underline = true,
  severity_sort = true,
  float = { border = "rounded" },
  signs = {
    text = {
      [S.ERROR] = vim.fn.nr2char(0xf057),
      [S.WARN] = vim.fn.nr2char(0xf071),
      [S.INFO] = vim.fn.nr2char(0xf05a),
      [S.HINT] = vim.fn.nr2char(0xf0eb),
    },
  },
})
