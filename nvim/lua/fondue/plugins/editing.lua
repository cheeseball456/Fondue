-- Everyday editing helpers.
--
-- snacks.nvim is a collection of small modules; only three are switched on here:
--   indent   vertical guides for each indent level, with the current block highlighted
--   words    highlights other uses of the word under the cursor (needs a language server;
--            its colour is set in highlights.lua)
--   bigfile  turns expensive features off for very large files, so they open quickly
-- Pinning: snacks, nvim-autopairs and nvim-surround publish semver tags, so each gets a
-- version range. (The version numbers are used by lazy.nvim only when it updates.)
--
-- Comment toggling needs no plugin: Neovim's built-in `gc` does it (gcc for a line).

return {
  {
    "folke/snacks.nvim",
    version = "^2",
    lazy = false, -- bigfile and indent must be ready before the first file is read
    priority = 1000,
    opts = function()
      -- The guide colours (one group per nesting depth) are worked out in highlights.lua.
      local highlights = require("fondue.highlights")
      return {
        bigfile = { enabled = true },
        indent = {
          enabled = true,
          indent = { hl = highlights.guide_groups },
          scope = { hl = highlights.scope_groups },
          -- The full-colour scope guide is enough; no extra corner "chunk" drawing.
          chunk = { enabled = false },
        },
        words = { enabled = true },
      }
    end,
  },
  {
    -- Closes brackets and quotes as you type: ( becomes ().
    "windwp/nvim-autopairs",
    version = "^0.10",
    event = "InsertEnter",
    opts = {},
  },
  {
    -- Surround editing with its standard keys: ys (add), cs (change), ds (delete).
    -- For example cs"' turns "text" into 'text'. These are not leader keys.
    "kylechui/nvim-surround",
    version = "^4",
    event = "VeryLazy",
    opts = {},
  },
}
