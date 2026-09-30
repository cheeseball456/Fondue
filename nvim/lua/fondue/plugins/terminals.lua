-- The test/run terminal (FR-003), backed by snacks.nvim's own terminal (declared
-- already in plugins/editing.lua) -- separate from the Claude panel in
-- plugins/claude.lua, which uses claudecode.nvim instead. FR-003 (v1.22) rules out a
-- second, concurrent terminal; an earlier on-demand ad-hoc-terminal feature was
-- implemented and then withdrawn -- see `lib/terminals.lua`'s own history comment.
--
-- Full-window: a floating window sized to the whole editor. This needs an *explicit*
-- `width = 0, height = 0` (see `lib/terminals.lua`'s `BASE_WIN_OPTS` and design.md's
-- "Spike results" for why leaving them unset does not work -- a floating window's default
-- "float" style otherwise merges in a 90%-sized default), laid on top of whatever else is
-- open. Hiding it (`:hide` on the window, not closing the buffer/job) leaves the
-- underlying shell running and restores whatever was visible underneath -- nothing else
-- was ever touched, unlike `session.lua`'s `:only`-based start screen, which is not
-- reversible the same way and is not needed here since the float never disturbs the
-- layout beneath it.
return {
  {
    "folke/snacks.nvim",
    opts = function(_, opts)
      opts.terminal = { enabled = true }
      return opts
    end,
  },
}
