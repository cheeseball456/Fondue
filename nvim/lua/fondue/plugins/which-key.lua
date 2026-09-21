-- which-key shows the leader menu. It is fed from keymaps.lua through the
-- registry (group labels here, key descriptions come from the mappings
-- themselves), so this spec defines no keys of its own.
return {
  {
    "folke/which-key.nvim",
    version = "^3",
    event = "VeryLazy",
    opts = function()
      return {
        spec = require("fondue.keymap_registry").which_key_spec(),
      }
    end,
  },
}
