-- Mason downloads language servers, formatters and linters into Neovim's own data
-- folder, so every machine gets the same tools without touching the system.
-- nvim-lspconfig supplies the ready-made server definitions that vim.lsp.enable() uses.
-- What to install is listed in one place: lua/fondue/tools.lua.
--
-- Pinning: both plugins publish semver tags (v2.x), so they get a version range.
return {
  {
    "mason-org/mason.nvim",
    version = "^2",
    -- Loaded on demand: by the language server setup below, or by these commands.
    cmd = { "Mason", "MasonInstall", "MasonUninstall", "MasonUninstallAll", "MasonUpdate", "MasonLog" },
    opts = {},
  },
  {
    "neovim/nvim-lspconfig",
    version = "^2",
    -- Load when a file is opened, before its filetype is detected, so the servers are
    -- known by the time the first buffer needs one.
    event = { "BufReadPre", "BufNewFile" },
    -- Mason first: it puts its folder of programs on PATH, which the setup relies on.
    dependencies = { "mason-org/mason.nvim" },
    config = function()
      require("fondue.lsp").setup()
    end,
  },
}
