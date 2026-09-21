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
--   Down / Up        move through the menu (Ctrl-n / Ctrl-p do the same); nothing is chosen until
--                    you do this, and the text is not changed while you look
--   Enter            accept the item you moved to; with nothing chosen it is a normal Enter
--   Esc              close the menu if it is open (staying in insert mode); otherwise it leaves
--                    insert mode as usual
--   Ctrl-e           close the menu
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
      keymap = {
        preset = "enter",
        -- "hide" closes the menu when there is one; "fallback" then does Esc's normal job.
        ["<Esc>"] = { "hide", "fallback" },
      },
      completion = {
        -- No item is preselected and moving through the menu does not insert text, so Enter
        -- only accepts something you chose on purpose, and otherwise starts a new line.
        list = { selection = { preselect = false, auto_insert = false } },
      },
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
