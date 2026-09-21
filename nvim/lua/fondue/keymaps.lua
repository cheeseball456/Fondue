-- THE single table of every custom key. Plugin specs never define keys of their own.
-- To add a key: add a line to `keys` below. The registry (keymap_registry.lua)
-- checks it is not already used and that it has a description.
--
-- Each key: { mode = "n", lhs = "<leader>w", desc = "What it does", action = ... }
-- (`mode` may be left out for normal mode.)
return {
  -- Groups are just labels for a prefix. They bind nothing, so an empty group is fine;
  -- keys are added to them as features are added.
  groups = {
    { prefix = "<leader>s", desc = "Search" },
    { prefix = "<leader>v", desc = "Version control" },
    { prefix = "<leader>f", desc = "Fix" },
    { prefix = "<leader>d", desc = "Debug and test" },
    { prefix = "<leader>l", desc = "LSP navigation" },
    { prefix = "<leader>r", desc = "Refactor" },
    { prefix = "<leader>a", desc = "AI" },
    { prefix = "<leader>c", desc = "Code tools" },
    { prefix = "<leader>n", desc = "Navigation" },
  },

  keys = {
    { lhs = "<leader>w", desc = "Save", action = "<cmd>write<cr>" },
    -- The undo tree ships with Neovim 0.12 but must be loaded with :packadd first.
    { lhs = "<leader>u", desc = "Undo tree", action = "<cmd>packadd nvim.undotree | Undotree<cr>" },
    { lhs = "<leader>p", desc = "Plugin manager", action = "<cmd>Lazy<cr>" },
  },
}
