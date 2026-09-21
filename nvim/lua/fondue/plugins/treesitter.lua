-- Treesitter: real syntax trees for highlighting and folding, instead of Vim's
-- pattern-based syntax files. This uses the `main` branch of nvim-treesitter, the
-- rewrite for Neovim 0.12; the old `master` branch does not work with it.
--
-- The plugin is not lazy-loaded (it does not support that). It only installs and
-- updates parsers; starting highlighting is done in lua/fondue/treesitter.lua.
-- Pinning: its version tags belong to the old branch, so the lockfile alone pins it.
return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    -- After the plugin is updated, rebuild the parsers so they match its queries.
    build = function()
      require("fondue.treesitter").install({ wait = true, update = true })
    end,
  },
  {
    -- Colours nested brackets by depth, using the syntax tree.
    "HiPhish/rainbow-delimiters.nvim",
    version = "^0.12",
    event = { "BufReadPost", "BufNewFile" },
  },
}
