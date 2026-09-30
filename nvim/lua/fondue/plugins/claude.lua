-- The Claude Code side panel (FR-002, FR-043). claudecode.nvim runs the `claude` CLI
-- inside a snacks.nvim terminal (the same provider `plugins/terminals.lua` uses for the
-- test/run terminal) and bridges it to Neovim's own diff view and file/selection context.
--
-- Pinned to an exact commit, not a version range: the plugin is pre-1.0/beta (no tagged
-- releases yet), so `:Lazy update` must never move it without a deliberate re-pin.
--
-- Loaded eagerly (not lazy-loaded on a command), so `fondue.lib.claude`'s launcher can
-- always `require("claudecode")` directly, the same way it calls `is_claude_connected()`
-- before the panel has ever been opened. This does not start a Claude process: `setup()`
-- with the plugin's default `auto_start = true` only starts claudecode.nvim's own local
-- WebSocket server (a Lua TCP listener for editor/CLI communication), never the `claude`
-- CLI itself -- that only happens when something calls `:ClaudeCode`/`terminal.open()`,
-- which the launcher does not do until the panel is actually opened (FR-002).
--
-- The panel's own buffer filetype is overridden to "fondue_claude_panel" (instead of the
-- shared "snacks_terminal" the test/run terminal in plugins/terminals.lua gets) so
-- plugins/navigation.lua's centred-layout integration can treat this one specifically as
-- a side panel, without also catching the test/run terminal. Confirmed possible by
-- reading snacks.nvim's
-- own source: `Snacks.win.resolve()` merges the caller's `win` table over the "terminal"
-- style's own `bo.filetype = "snacks_terminal"` default, so a caller-set `bo.filetype`
-- here wins. The config path is `terminal.snacks_win_opts` (a top-level key on
-- claudecode.nvim's own terminal config), NOT `terminal.provider_opts.snacks_win_opts`
-- as design.md's own "Facts checked" notes assumed -- checked against the installed
-- plugin's actual source (`lua/claudecode/terminal.lua`'s `defaults` table and
-- `build_config()`), not from memory; corrected here and in design.md's Spike results.
--
-- Task 12.1 fix (found in interactive `/verify`: draft text typed but not submitted,
-- `Esc` `Esc`, `Space a a` re-entered the Claude prompt instead of hiding the panel).
-- Two hypotheses were checked before touching anything:
--   1. Unsent draft text changing what `Esc` does (e.g. the CLI itself consuming the
--      first `Esc` to clear the draft line before Neovim's own double-Esc-to-leave ever
--      sees it) -- RULED OUT. Confirmed with a headless RPC harness driven by a real
--      pty (matching 8.1's own method): the exact same key sequence against a real
--      terminal-job buffer, with unsent draft text typed into the underlying shell
--      first versus an empty prompt, produced byte-for-byte identical mode-transition
--      timing in both cases. This is also true by construction, not just by test: the
--      style default's own `term_normal` mapping (below) is a Neovim `t`-mode keymap
--      that intercepts every `<Esc>` keypress and decides "first or second press" for
--      itself (via its own `esc_timer`) *before* anything is forwarded to the
--      underlying job -- draft text living inside that job cannot change what Neovim's
--      own mapping does with the keystroke that reaches it.
--   2. **The same class of bug as 8.1 -- CONFIRMED, this is the real root cause.**
--      snacks.nvim's own "terminal" style default for `term_normal` (`lua/snacks/
--      terminal.lua`) is itself an `expr = true` mapping whose second-press branch
--      calls `vim.cmd("stopinsert")` directly from inside that expr evaluation --
--      exactly the shape 8.1 found buggy in this change's *own* override before it set
--      `expr = false` explicitly. Confirmed directly, headless, with a real pty and
--      genuinely idle time (a single check after a full second of idle with no RPC
--      calls at all during the wait, to rule out a query itself acting as the "further
--      key" that flushes the pending state -- an earlier pass of this same investigation
--      was fooled by exactly that: repeated polling every ~10-20ms turned out to be
--      settling the transition itself, producing a false "resolves on its own in ~70ms"
--      reading until the polling was removed): after a real double-`Esc` (well within
--      the style default's own 200ms window), `nvim_get_mode()` still reports
--      terminal-job mode a full second later with nothing else sent. Sending one more
--      key (a `Space`) immediately flips it to normal-mode-in-terminal -- confirming
--      that keystroke is what settles the still-pending transition, exactly as 8.1
--      described, rather than being seen as the start of a `<leader>` sequence: a fake
--      `<leader>aa` mapping registered for the same test never fired. Sending a further
--      `a` right after (now the first `a` of what the user intended as `<leader>aa`,
--      since the `Space` was consumed settling the mode) re-enters terminal-job mode --
--      Neovim's own native terminal-buffer `a` (confirmed working as-intended,
--      unmodified, in task 9.2) -- reproducing the user's exact symptom ("after the
--      second `a`, focus re-enters the Claude prompt").
--
-- Fixed by overriding `term_normal` here too, keeping the double-Esc *behaviour*
-- (Claude Code uses a single `Esc` for its own purposes -- see the comment on the "a"
-- keymap group in keymaps.lua -- so, unlike the test/run terminal, this panel must keep
-- requiring two) but without `expr` at all: the first press starts the same 200ms timer
-- and forwards a literal `Esc` byte to the underlying `claude` CLI directly via
-- `nvim_chan_send` on the terminal's own job channel (replacing `expr`'s
-- "return a string, let Neovim forward it" mechanism, which is not available to a
-- plain, non-expr mapping); the second press (within the window) stops the timer and
-- calls `stopinsert` from a genuinely plain callback -- the same fix shape as 8.1's own
-- `expr = false` correction, so `stopinsert` now takes effect immediately rather than
-- waiting on a further keystroke to flush it. Re-confirmed with the same headless
-- pty harness, genuinely idle (no polling during the wait): after the fix, a real
-- double-`Esc` flips to normal-mode-in-terminal within the same idle window with no
-- further key needed, in both the draft-text-present and empty-prompt cases, and a
-- follow-up `Space a a` (a fake `<leader>aa` mapping, standing in for the real one)
-- fires exactly once with no re-entry into terminal mode.
return {
  {
    "coder/claudecode.nvim",
    commit = "2390c6e45c4789072c293ac69de051d169668b29",
    lazy = false,
    opts = {
      terminal = {
        provider = "snacks",
        split_side = "right",
        snacks_win_opts = {
          bo = { filetype = "fondue_claude_panel" },
          keys = {
            term_normal = {
              "<Esc>",
              function(self)
                self.esc_timer = self.esc_timer or (vim.uv or vim.loop).new_timer()
                if self.esc_timer:is_active() then
                  self.esc_timer:stop()
                  vim.cmd("stopinsert")
                else
                  self.esc_timer:start(200, 0, function() end)
                  local chan = vim.b[self.buf].terminal_job_id
                  if chan then
                    vim.api.nvim_chan_send(chan, "\27")
                  end
                end
              end,
              mode = "t",
              expr = false, -- see the note above: without this, the "terminal" style
              -- default's own `expr = true` survives the deep merge (the exact same
              -- leak 8.1 found and fixed in lib/terminals.lua) and `stopinsert` never
              -- takes effect synchronously
              desc = "Double escape to normal mode",
            },
          },
        },
      },
    },
  },
}
