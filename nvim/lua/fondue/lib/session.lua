-- Decides, during startup, whether `nvim`/`nvim .` restores a saved session or shows the
-- start screen. This is Fondue's own decision, not persistence.nvim's: the plugin never
-- restores on its own, and it exposes no "does a session exist for this directory" check.
--
-- A file argument (`nvim <file>`) does neither: the file opens cleanly, with no restore
-- and no start screen. See `M.setup()` below for exactly when and why this runs.
local M = {}

-- No arguments, or exactly one argument that names a directory (`nvim .`), both count as
-- "no file argument".
local function no_file_argument()
  local argc = vim.fn.argc(-1)
  if argc == 0 then
    return true
  end
  if argc == 1 then
    local arg = vim.fn.argv(0) --[[@as string]]
    return arg ~= "" and vim.fn.isdirectory(arg) == 1
  end
  return false
end

-- persistence.nvim is lazy-loaded on BufReadPre (a real file being read) for the normal
-- case; a no-file-argument start reaches this decision before any file is read, so it is
-- forced into existence here instead of waiting for that event.
local function persistence()
  require("lazy").load({ plugins = { "persistence.nvim" } })
  return require("persistence")
end

-- The session file persistence.nvim would use for the current directory: its own
-- `current()` (with the same branch-suffix fallback `load()` uses internally), rather
-- than a naming convention re-implemented here.
local function session_file(p)
  local file = p.current()
  if vim.fn.filereadable(file) == 0 then
    file = p.current({ branch = false })
  end
  return file
end

local function session_exists(p)
  return vim.fn.filereadable(session_file(p)) == 1
end

-- Whether any current window shows a real, named, ordinary buffer (a file, not a
-- scratch/plugin window such as the centred-layout padding). A session can be saved
-- (a session file genuinely exists) and still restore to nothing worth seeing: for
-- example, closing every real window one at a time and quitting on the last one lets
-- persistence.nvim's VimLeavePre save capture only what is left at that instant
-- (the centred-layout padding and empty scratch splits), even though a real buffer
-- was still open moments before. Confirmed by reproducing exactly that sequence.
local function has_real_content()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= "" then
      return true
    end
  end
  return false
end

local function show_start_screen()
  -- Close everything else first (the normal single-window shape a start screen has),
  -- rather than leaving it sharing the tab with whatever windows are already open.
  pcall(vim.cmd, "silent! only")
  Snacks.dashboard.open({ buf = vim.api.nvim_get_current_buf(), win = vim.api.nvim_get_current_win() })
end

-- Moves focus to a window showing real content, if the current one is not already one
-- (for example one of the centred-layout's own padding windows). Needed because
-- no-neck-pain's own debounced re-enable (`autocmds.enableOnVimEnter = "safe"`,
-- plugins/navigation.lua) rebuilds the padding a few milliseconds after `BufEnter`, and can
-- leave focus on one of the new padding windows rather than the restored buffer. Re-checked
-- after a short delay (comfortably past no-neck-pain's own 5ms debounce) rather than
-- immediately, so this runs after that settles rather than racing it.
local function focus_real_content()
  local cur_buf = vim.api.nvim_win_get_buf(0)
  if vim.bo[cur_buf].buftype == "" and vim.api.nvim_buf_get_name(cur_buf) ~= "" then
    return
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= "" then
      vim.api.nvim_set_current_win(win)
      return
    end
  end
end

-- The file tree's own three windows: a `snacks.picker` "sidebar" layout is actually an
-- outer container (`snacks_layout_box`) plus the picker's usual list and input. Exposed
-- (`M.TREE_FILETYPES`) so `keymaps.lua`'s own "is the tree already focused" check for
-- `<leader>e` uses this same enumeration, rather than a second, separately-typed-out list
-- that can drift out of sync with this one (a review caught exactly that: the keymap's
-- check once only recognised the `snacks_picker` prefix, missing `snacks_layout_box`).
M.TREE_FILETYPES = {
  snacks_layout_box = true,
  snacks_picker_list = true,
  snacks_picker_input = true,
}

-- Every window that belongs to transient, Lua-state-driven UI (the file tree above, the
-- centred layout's own padding, and anything else built on snacks.picker's own sidebar
-- layout) rather than to a real file. These can never be meaningfully restored — a
-- session script can only `:edit` a real file or start an empty scratch buffer, neither
-- of which reconstructs a picker, no-neck-pain's own padding, or grug-far's own buffer —
-- so they must never be captured by a session in the first place, closed before
-- persistence.nvim saves rather than cleaned up after the fact. (Most of snacks.picker's
-- own UI, including the diagnostics and TODO lists, opens in a floating window, which
-- `:mksession` already leaves out of a session on its own; the file tree is the one
-- snacks.picker source configured to open in a real split instead, see
-- plugins/navigation.lua. grug-far also opens a real split by default, with an unnamed
-- scratch buffer, so it is included here too. `no-neck-pain`'s own padding windows
-- (filetype `no-neck-pain`) are *also* real, saveable splits with no filetype restored
-- by `:mksession` (it only ever emits a bare `enew` for them): left alone, every restore
-- both keeps the old, now-unrecognised padding *and* lets no-neck-pain's own
-- `enableOnVimEnter` add a fresh pair on top, and the surplus is then saved again into
-- the next session — an unbounded leak on every ordinary multi-window restore, confirmed
-- with an ordinary vsplit session across repeated quit/restore cycles. no-neck-pain
-- rebuilds its padding from scratch around whatever real content is left once these are
-- gone, the same way it already does on a completely fresh start, so closing them here
-- first is safe. Checked directly against the running plugins, not assumed.
--
-- Every one of these, including grug-far, is closed the same way: a raw, ID-based
-- `nvim_win_close`, never through a plugin's own "close" API. An earlier version routed
-- grug-far through its own `hide_instance(buf)` specifically, reasoning that a raw close
-- would bypass the running-task confirmation grug-far's own close action offers. That
-- reasoning did not survive a *real* quit: Neovim's own exit sequence fires `BufUnload`
-- for grug-far's buffer before this `PersistenceSavePre` handler ever runs, and grug-far's
-- own cleanup for that event (`lua/grug-far.lua`'s `setupCleanup`) already removes the
-- buffer from its instance registry *and* unconditionally aborts any running task itself
-- — with no confirmation of its own, since that confirmation only exists in the separate,
-- explicit close action (`<localleader>c` or `inst:close()`), never in `BufUnload`.
-- `hide_instance`'s registry lookup was therefore already resolving to nothing by the time
-- it ran, so it silently did nothing, and the window survived into `:mksession` as a
-- leaked, filetype-less fourth window that never resolved on its own. Since any running
-- task is already aborted, without confirmation, by grug-far's own code the moment a real
-- quit starts tearing down its buffer — regardless of what this function does — a raw
-- close here loses nothing beyond what an ordinary `:qa` was already going to do; it is
-- also, unlike `hide_instance`, immune to this same race, since it never depends on
-- grug-far's own bookkeeping still being intact by the time it runs.
local TRANSIENT_FILETYPES = vim.tbl_extend("force", {}, M.TREE_FILETYPES, {
  snacks_dashboard = true,
  ["grug-far"] = true,
  ["no-neck-pain"] = true,
})

local function close_transient_windows()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if TRANSIENT_FILETYPES[vim.bo[buf].filetype] then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
end

-- Restores this directory's session, or shows the start screen, when there is no file
-- argument. Calling `:edit`/`:source` from ordinary, unnested script code (not from
-- inside any autocommand callback) is what makes `BufRead`/`FileType` fire correctly
-- for the restored buffers, exactly as they would from the command line (confirmed
-- headless) — that is the reason `M.setup()` below goes out of its way to call this
-- either directly or from a scheduled callback, never synchronously from inside an
-- autocommand.
local function decide()
  if not no_file_argument() then
    return
  end
  local p = persistence()
  if session_exists(p) then
    p.load()
    if not has_real_content() then
      show_start_screen()
    else
      vim.defer_fn(focus_real_content, 50)
    end
  else
    show_start_screen()
  end
end

function M.setup()
  -- Whether to decide now, synchronously, or wait for a UI to actually attach depends on
  -- whether one already has, checked with `#vim.api.nvim_list_uis() > 0` *before* this
  -- module is even required: `init.lua` calls `M.setup()` from its own top-level
  -- execution (not from `VimEnter` or any other autocommand), at a point where the
  -- initial buffer already exists and the command-line arguments are already known, but
  -- `VimEnter` has not fired, no file argument has been opened, and -- for a real
  -- terminal session -- nothing has been typed yet.
  --
  -- Confirmed with a real pseudo-terminal: a normal interactive `nvim` already has a UI
  -- attached (the built-in TUI) by this point, before Neovim has even finished sourcing
  -- this configuration, let alone reached `VimEnter` -- so for that, the overwhelmingly
  -- common case, `decide()` below runs directly, with no `vim.schedule()` gap at all:
  -- there is no tick in which an unrestored placeholder buffer could receive a keystroke.
  --
  -- A `--headless` process with no UI yet attached is different, and covers two quite
  -- different situations that must not be treated the same way. One is this project's
  -- own test harness (and, for real users, GUI front-ends that start Neovim headless and
  -- attach their own UI moments later over RPC): there, a UI *will* attach, just not yet,
  -- so the decision needs to wait for `UIEnter`. The other is an ordinary, non-interactive
  -- script with no intention of ever attaching a UI at all -- `scripts/install.sh`'s
  -- language-tooling step and `:checkhealth fondue`'s own test suite both run Neovim this
  -- way, with no file argument either. Confirmed the hard way: an earlier version of this
  -- fix ran `decide()` unconditionally and hung a health-check run because a stale session
  -- happened to exist for the directory it was invoked from, and it is not this module's
  -- place to decide that a scripted, headless invocation should behave like an interactive
  -- session. `UIEnter` never fires for a script like that, so registering the decision
  -- there rather than running it unconditionally leaves those scripts untouched, exactly
  -- as they were before session restore existed at all.
  --
  -- Deciding after `UIEnter` still means deciding from inside an autocommand, so the same
  -- `:help autocmd-nested` problem `M.setup()`'s history (see below) already ran into
  -- applies again, and `decide()` is scheduled out of that context for the same reason.
  -- Confirmed empirically that this reopens the keystroke race for this path specifically:
  -- an adversarial test that connects and types the instant the socket accepts a
  -- connection (this project's own test harness attaches its UI this way) landed every
  -- keystroke in the placeholder again, 10/10 -- scheduling a callback does not reliably
  -- win a race against typeahead that arrives before it runs.
  --
  -- Rather than accept that narrower window, the placeholder buffer itself is made
  -- non-modifiable for as long as it might still be current when a keystroke arrives: an
  -- attempted edit then fails outright (`E21`, visible in `:messages`) instead of silently
  -- writing text into a buffer nobody will ever see again. `decide()` always ends by
  -- moving off this buffer (a restored real file switches to a different one entirely; the
  -- start screen may reuse this same buffer number, but read-only is the right state for
  -- it too), so nothing is ever left stuck non-modifiable that a user actually needs to
  -- type into.
  if #vim.api.nvim_list_uis() > 0 then
    decide()
  elseif no_file_argument() then
    vim.bo[vim.api.nvim_get_current_buf()].modifiable = false
    vim.api.nvim_create_autocmd("UIEnter", {
      group = vim.api.nvim_create_augroup("fondue_session", { clear = true }),
      once = true,
      desc = "Restore this directory's session, or show the start screen, once a UI actually attaches",
      callback = function()
        vim.schedule(decide)
      end,
    })
  end
  -- Note: a file argument with no UI yet attached (a GUI front-end opening a specific
  -- file headlessly before attaching) needs nothing from this module at all -- `decide()`
  -- would do nothing for it anyway, and Neovim's own, ordinary file-opening path already
  -- handles that buffer safely without our involvement.

  vim.api.nvim_create_autocmd("User", {
    pattern = "PersistenceSavePre",
    group = vim.api.nvim_create_augroup("fondue_session_save", { clear = true }),
    desc = "Never save the file tree, grug-far, no-neck-pain's own padding, or any other transient window into a session",
    callback = close_transient_windows,
  })
end

return M
