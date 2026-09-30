-- The test/run terminal (Space t, FR-003: toggleable, full-window, separate from the
-- Claude panel), backed by `Snacks.terminal.open()` (the same provider the Claude panel
-- uses via claudecode.nvim, but never the same instance or filetype -- see
-- plugins/claude.lua's own note on this). Only one terminal exists at a time -- FR-003
-- (v1.22) rules out a second, concurrent one; see design.md's "D2 correction" (10.1's
-- withdrawal) for why an earlier count-prefix ad-hoc-terminal feature was built, used,
-- and then removed entirely rather than further patched.
local M = {}

-- `width = 0, height = 0`: snacks.win's own sizing (`lua/snacks/win.lua`'s `dim()`)
-- treats a size of exactly 0 as "full size of the parent" -- confirmed by reading its
-- source, along with the reason these cannot simply be left unset: `Snacks.win.new()`
-- unconditionally merges in the generic "float" style (`width = 0.9, height = 0.9`)
-- whenever `position == "float"`, regardless of the "terminal" style also in effect, so
-- an *explicit* 0 is needed to override that 90%-sized default rather than leaving these
-- keys absent and hoping nothing else sets them -- checked empirically (headless, with
-- real window geometry), not assumed, since the plugin's own docs do not mention this
-- interaction between `position = "float"` and the shared "float" style.
--
-- `keys.term_normal` replaces snacks' own default binding for the same name (the
-- "terminal" style's built-in double-Esc-to-leave, confirmed by reading its source:
-- `Snacks.win:show()` applies the merged `opts.keys` -- which a plain buffer-local
-- `vim.keymap.set` from a `FileType` autocommand cannot reliably win against, since
-- `show()` calls `self:map()` (applying those same keys) *after* `FileType` already
-- fired -- checked empirically, not assumed, since a first attempt using `FileType`
-- was silently overridden this way).
--
-- The replacement must be a *function*, not a plain string: `Snacks.win:map()`
-- (confirmed by reading its source) treats a string/table `spec[2]` as the name of
-- one of its own actions (like the style default's `q = "hide"`), not a literal key
-- sequence to replay -- a first attempt using the string `"<C-\\><C-n>"` here was
-- silently swallowed as an unknown action name, leaving Esc doing nothing. A function
-- is called directly instead, so `vim.cmd("stopinsert")` (the standard way to leave
-- terminal-job mode from Lua) actually runs.
--
-- Task 8.1 fix (`Space t` needing a second press to actually hide, found in
-- interactive `/verify`): `Snacks.win.resolve()` merges style defaults and this
-- table with `vim.tbl_deep_extend("force", ...)`, which recurses into nested tables
-- -- and `keys.term_normal` is exactly such a nested table on both sides (this one
-- and the "terminal" style default's own double-Esc entry). Because this table never
-- set `expr`, the merge kept the style default's `expr = true` (deep-extend only
-- overwrites keys actually present in the later table -- confirmed directly by
-- reading `Snacks.win.resolve`/`Snacks.win.new`, and by dumping the *live* merged
-- keymap with `nvim_buf_get_keymap(buf, "t")`, which showed `expr = 1` on this
-- mapping despite this table never mentioning `expr` at all). With `expr` still
-- true, Neovim runs this callback as an expression-mapping: `vim.cmd("stopinsert")`
-- inside that context does not take effect synchronously -- confirmed directly, with
-- real pty-driven keystrokes and a headless RPC harness, that `stopinsert` reports
-- success (no error) but `nvim_get_mode()` still reports terminal-job mode
-- afterwards, indefinitely, with no further input at all (not merely a short delay --
-- confirmed by polling for 1.5s of genuine idle time with the outer pty continuously
-- drained). The mode flip is only actually applied once *some* further key arrives,
-- which is what made this look like "the first `Space t` does nothing, the second
-- one works": the first press's `<Esc>`-then-`Space`-then-`t` sequence can land with
-- the terminal-job-mode-to-normal-mode flip still pending when `Space` (the leader
-- key) is read, so that keystroke gets spent settling the mode instead of starting
-- the `<leader>t` sequence cleanly, and while it is unsettled, any other normal-mode
-- keystroke landing on the still nonmodifiable terminal buffer gives `E21`. Setting
-- `expr = false` explicitly here overrides the inherited `true` (rather than leaving
-- the key absent and hoping the merge omits it, which is what caused this), so this
-- mapping runs as a plain callback and `stopinsert` takes effect immediately, with no
-- reliance on a follow-up keystroke to "flush" it. This fix is unrelated to the
-- ad-hoc-terminal feature removed below and is unaffected by that removal.
--
-- Task 9.1 originally added a `current_terminal()` helper (toggling whichever tracked
-- terminal's window was actually focused, not always the dedicated one) plus
-- `border = "rounded"` and a distinct per-terminal `title` ("Test terminal" for the
-- dedicated one, "Terminal 2", "Terminal 3", ... for each ad-hoc one), so a second,
-- count-prefixed ad-hoc terminal (`2<leader>t`) could be told apart from the dedicated
-- one and hidden independently. That whole ad-hoc-terminal feature (`M.open_adhoc()`,
-- `adhoc_terminals`, `next_adhoc_number`, `current_terminal()`) has since been withdrawn
-- (REQUIREMENTS.md FR-003 v1.22): using 9.1's own fix surfaced that even a
-- correctly-working second terminal had no way to be seen or returned to once you
-- moved past it, and the underlying need for more than one concurrent terminal was not
-- judged strong enough to justify solving that. See design.md's "D2 correction" (the
-- 10.1 one) for the full write-up. `border = "rounded"` and the "Test terminal" title
-- are kept regardless of that removal -- harmless with only one terminal, and still a
-- small, already-built bit of polish, so there is no reason to revert them.
local BASE_WIN_OPTS = {
  position = "float",
  border = "rounded",
  width = 0,
  height = 0,
  backdrop = false,
  title = "Test terminal",
  keys = {
    term_normal = {
      "<Esc>",
      function()
        vim.cmd("stopinsert")
      end,
      mode = "t",
      expr = false, -- see the note above: without this, the style default's own
      -- `expr = true` survives the deep merge and this mapping's `stopinsert`
      -- never takes effect synchronously
      desc = "Leave terminal mode",
    },
  },
}

--- This terminal's own window opts -- a fresh copy of `BASE_WIN_OPTS` rather than the
--- shared table itself, so nothing downstream can mutate the shared default.
local function win_opts()
  return { win = vim.tbl_deep_extend("force", {}, BASE_WIN_OPTS) }
end

-- The dedicated test/run terminal: one singleton, reused across toggles so its shell
-- keeps running while hidden (`Space t` again shows the same buffer, not a new shell).
-- There is no mechanism anywhere in this module for a second, concurrent terminal
-- (FR-003 v1.22).
local test_run

--- Toggle the dedicated test/run terminal: shown if it was hidden or does not exist
--- yet, hidden if it is currently shown. Hiding closes only the window (Snacks'
--- `hide()` is `close({buf = false})`), so the shell inside keeps running and whatever
--- was on screen before reappears untouched -- this terminal is a float laid on top,
--- never part of the underlying layout.
function M.toggle_test_run()
  if test_run and test_run:buf_valid() then
    test_run:toggle()
    return
  end
  test_run = Snacks.terminal.open(nil, win_opts())
end

--- Whether the test/run terminal is currently open (a valid, on-screen window
--- actually showing it, not merely a live-but-hidden buffer). Added for task 13.2's
--- occlusion guard in `lib/claude/init.lua`: this terminal is always a full-window
--- float (`position = "float"` above) and Neovim floats always draw over the
--- tabpage's normal window grid regardless of focus (confirmed in design.md's D2/D3
--- occlusion note, task 13.1) -- so any code that is about to show or focus a normal
--- split window (like the Claude panel's) needs to know this first, to avoid doing so
--- into a state the user cannot actually see.
---
--- Mirrors `M.toggle_test_run()`'s own hide/show decision exactly, rather than
--- introducing a second definition of "open": Snacks' own `Win:toggle()` (which
--- `test_run:toggle()` above calls) decides hide-vs-show via `self:valid()` (window
--- valid, buffer valid, and the window is actually showing that buffer) -- the same
--- check used here.
---
--- `self:valid()`'s own `win_valid() and buf_valid() and ...` chain can evaluate to
--- a bare `nil` rather than `false` once `self.win` itself is nil (Lua's `and`
--- returns the first falsy *value*, not a coerced boolean, and a hidden float's
--- `self.win` is set to nil by Snacks' own `close()`) -- confirmed directly, not
--- assumed, by checking this after a real hide. Harmless in a plain `if`, but
--- `not not (...)` here keeps this function's own return type a genuine boolean,
--- matching its doc comment ("whether ..."), for any caller that checks it more
--- strictly than truthiness.
function M.is_open()
  return not not (test_run and test_run:valid())
end

return M
