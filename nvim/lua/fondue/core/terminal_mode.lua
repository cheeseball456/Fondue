-- FR-003's "Terminal mode is visually distinguishable from normal mode" requirement
-- (REQUIREMENTS.md v1.21; specs/test-run-terminal/spec.md), added after interactive
-- verification found Neovim's own small `-- TERMINAL --` status text too easy to miss.
--
-- Deliberately NOT scoped to this codebase's own *terminal-identifying* filetype
-- (`snacks_terminal`, from `lib/terminals.lua`'s test/run terminal): the requirement is
-- about terminal mode itself, on any terminal window, and native `TermEnter`/`TermLeave`
-- (`:h TermEnter`) already fire for every terminal buffer regardless of which plugin
-- created it. A single, generic pair of autocommands here therefore covers the test/run
-- terminal and the Claude panel alike without separate wiring into each one's own
-- opening code (an earlier count-prefix ad-hoc-terminal feature would also have been
-- covered by this same generic pair with no changes needed here at all -- it was
-- withdrawn for unrelated reasons; see `lib/terminals.lua`'s own history comment).
--
-- Task 9.3 exception (found in interactive `/verify`): the Claude panel (filetype
-- `fondue_claude_panel`, from D2/`plugins/claude.lua`) is deliberately excluded below.
-- The user found the tint felt wrong specifically there -- a conversation, not a shell
-- -- even though it is correct and wanted on the test/run terminal. This is a single,
-- explicit, already-known filetype to skip, not a reopening
-- of the "no allowlist to maintain" reasoning above: that reasoning was against building
-- an allowlist of every terminal-*creating* filetype this codebase happens to have today
-- (which would need updating each time a new terminal-backed feature is added), not
-- against ever checking anything at all. See design.md's "D8" for the full write-up.
local EXCLUDED_FILETYPE = "fondue_claude_panel"
--
-- The cue itself is a background tint (`fondue.highlights`' `FondueTerminalMode`,
-- worked out from the active colourscheme the same way the indent guides and word
-- highlight are, so it is not yet defined the moment this file runs -- `winhighlight`
-- referencing it by name is fine either way, since Neovim resolves the link when it
-- redraws, not when the option is set) applied to the window's `Normal`/`NormalNC` via
-- `winhighlight` -- whichever of the two is on-screen at the time, since a terminal is
-- drawn from its own buffer's `Normal` group whether or not the window itself is
-- currently focused. Any `winhighlight` already on the window (none, today, but not
-- assumed to stay that way) is preserved underneath and restored exactly on
-- `TermLeave`, rather than overwritten outright.
local SAVED_WINHIGHLIGHT = "fondue_saved_winhighlight"
local CUE = "Normal:FondueTerminalMode,NormalNC:FondueTerminalMode"

-- Both handlers below check this, not just `TermEnter` (see the note above): if
-- `TermEnter` skipped the panel, `TermLeave` must skip it too -- otherwise it would find
-- no saved value under `SAVED_WINHIGHLIGHT` (never set) and blank out the panel's own
-- `winhighlight` (snacks.nvim's own `Normal:SnacksNormal,...`) instead of leaving it
-- untouched, which is worse than never having added the cue at all.
local function is_excluded(buf)
  return vim.bo[buf].filetype == EXCLUDED_FILETYPE
end

vim.api.nvim_create_autocmd("TermEnter", {
  group = vim.api.nvim_create_augroup("fondue_terminal_mode_cue", { clear = true }),
  desc = "Add a clear visual cue while a terminal window is in terminal mode (FR-003)",
  callback = function(ev)
    if is_excluded(ev.buf) then
      return
    end
    local win = vim.api.nvim_get_current_win()
    local existing = vim.wo[win].winhighlight
    vim.w[win][SAVED_WINHIGHLIGHT] = existing
    vim.wo[win].winhighlight = existing ~= "" and (existing .. "," .. CUE) or CUE
  end,
})

vim.api.nvim_create_autocmd("TermLeave", {
  group = "fondue_terminal_mode_cue",
  desc = "Remove the terminal-mode visual cue on leaving terminal mode",
  callback = function(ev)
    if is_excluded(ev.buf) then
      return
    end
    local win = vim.api.nvim_get_current_win()
    vim.wo[win].winhighlight = vim.w[win][SAVED_WINHIGHLIGHT] or ""
    vim.w[win][SAVED_WINHIGHLIGHT] = nil
  end,
})
