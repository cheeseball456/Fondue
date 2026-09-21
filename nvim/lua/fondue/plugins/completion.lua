-- Completion menu and snippets.
--
-- blink.cmp stays on its stable 1.x line (`version = "1.*"`): lazy.nvim then checks out a
-- tagged release, which comes with a ready-made fuzzy matcher that is downloaded, so no
-- Rust toolchain is needed. Its main branch is moving to an incompatible 2.x.
-- If the download ever fails, blink falls back to a slower matcher written in Lua
-- (with a warning), and completion still works.
--
-- Keys (the "enter" preset), set below in the plugin's own options rather than in
-- keymaps.lua because they are insert-mode keys, not leader keys:
--   Enter            accept the highlighted item
--   Down / Up        move through the menu (Ctrl-n / Ctrl-p do the same)
--   Tab / Shift-Tab  jump to the next / previous snippet field
return {
  {
    "saghen/blink.cmp",
    version = "1.*",
    -- Snippet collection for many languages; blink reads it from the runtimepath.
    dependencies = { "rafamadriz/friendly-snippets" },
    -- lsp.lua also loads this plugin early, because servers need to know what the menu supports.
    event = { "InsertEnter", "CmdlineEnter" },
    opts = {
      keymap = { preset = "enter" },
      sources = { default = { "lsp", "path", "snippets", "buffer" } },
      -- Snippets are expanded by Neovim's built-in snippet support (vim.snippet).
      snippets = { preset = "default" },
    },
  },
  {
    "rafamadriz/friendly-snippets",
    lazy = true, -- only files; blink.cmp loads it
  },
}
