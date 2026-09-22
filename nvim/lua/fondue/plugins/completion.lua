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
--
-- The command line (`:`) uses the same keys and the same "nothing preselected" behaviour as
-- above, so completion feels identical in both places. The menu shows as soon as you start
-- typing a command, not only inside the command-line window. With no menu open, Up and Down
-- still recall command-line history exactly as usual, because falling back is part of the
-- same keymap: the arrow keys only move through the menu when there is something to move
-- through. Tab and Shift-Tab are the one deliberate exception: on the command line there is no
-- snippet to jump to, so they only move the selection (like Down/Up) and never fall back to
-- Neovim's own command-line completion, because that combination froze the editor while blink's
-- menu was still open.
--
-- The command-line window (`q:`) needs its own, separate fix below for the same reason: it is
-- genuine Insert mode of its own special, throwaway buffer, not Vim's `c` command-line mode, so
-- the `cmdline.keymap` override above (which only applies in `c` mode) never reaches it -- Tab
-- there would otherwise still resolve from the *top-level* insert keymap and fall through to
-- native completion while blink's menu is open, the exact same freeze. The fix is a buffer-local
-- Insert-mode override, set fresh every time the window opens, calling blink's own public API
-- directly (select_next/select_prev already do nothing when there is nothing to select, so this
-- needs no extra "is there a menu" check of its own). No cleanup is needed: `q:`'s buffer is
-- thrown away when the window closes, so the mapping can never leak into any other buffer, and a
-- new one simply replaces it the next time the window opens. Esc needs no equivalent fix: the
-- project's `<Esc>` override above is set at the *top level*, so it already applies to every
-- Insert-mode context, `q:` included -- only Tab/Shift-Tab were scoped narrowly enough (under
-- `cmdline.keymap`, which is `c`-mode only) to miss it.
vim.api.nvim_create_autocmd("CmdwinEnter", {
  group = vim.api.nvim_create_augroup("fondue_completion_cmdwin", { clear = true }),
  desc = "Keep Tab/Shift-Tab inside blink's own menu in the command-line window, same as ':'",
  callback = function(args)
    vim.keymap.set("i", "<Tab>", function() require("blink.cmp").select_next() end, { buffer = args.buf })
    vim.keymap.set("i", "<S-Tab>", function() require("blink.cmp").select_prev() end, { buffer = args.buf })
  end,
})

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
      cmdline = {
        -- Reuse the insert-mode keymap above (including the Esc override) instead of
        -- blink's own separate "cmdline" preset, so the two contexts cannot drift apart.
        -- Tab and Shift-Tab are carved out with no "fallback": the "enter" preset's Tab is
        -- for snippet fields, which don't exist on the command line, so it would otherwise
        -- always fall through to Neovim's own command-line completion -- and doing that while
        -- blink's menu is still open froze the editor entirely. Kept inside blink instead,
        -- matching blink's own "cmdline" preset, which never lets Tab escape either.
        keymap = {
          preset = "inherit",
          ["<Tab>"] = { "select_next" },
          ["<S-Tab>"] = { "select_prev" },
        },
        completion = {
          -- Same "nothing preselected, no auto-insert" behaviour as insert mode.
          list = { selection = { preselect = false, auto_insert = false } },
          -- Show the menu for ordinary `:` commands, not only inside the command-line
          -- window (blink's default only shows it there).
          menu = { auto_show = true },
        },
      },
    },
  },
  {
    "rafamadriz/friendly-snippets",
    lazy = true, -- only files; blink.cmp loads it
  },
}
