-- The Claude Code panel launcher (FR-002, FR-043; AD-12's "one launcher function").
-- Owns: deriving the session name, deciding whether to attach/resume/start a session,
-- the /exit-safe re-open path, the quit-time warning (D5), and the separate
-- "would this leave only the panel visible" guard (task 15; design.md's D5 addendum).
--
-- Task 23 (user-directed design correction, 2026-09-30): every earlier round of the
-- quit-time warning (tasks 15, 20, 21, 22) tried to correctly *predict* whether a given
-- quit command would end up closing the Claude session as a side effect of Neovim's own
-- window-closing mechanics, and was repeatedly defeated by real interactions between
-- no-neck-pain's own cascade, floating windows, and multi-window `:qa` teardown. Per the
-- user's own directive, the guard's confirm path no longer predicts this at all: it
-- explicitly and deterministically stops the session first (`stop_claude_session()`
-- below), then lets Neovim's own quit proceed (or, for the new panel-close trigger,
-- aborts the original command since the explicit stop already achieved its effect) --
-- so the session's fate no longer depends on correctly predicting which windows
-- Neovim's own quit command will or won't actually close. See design.md's new D5
-- correction (task 23) for the full write-up, including why `require("claudecode").
-- stop()` alone is NOT enough to actually end the running `claude` process.
--
-- Spike results (R-1, resolved during implementation -- see design.md "Spike results"
-- for the full write-up): `claude --resume "<name>"` DOES resume the exact session with
-- that display name directly, non-interactively, when one exists -- confirmed by
-- creating a real named session and checking the `session_id` a resumed, non-interactive
-- run actually used. There is still no dedicated "does a session with this name exist"
-- API, so `existing_titles()` below answers that itself, locally and at no API cost, by
-- reading each session transcript file Claude Code already writes under
-- `~/.claude/projects/<cwd-with-every-non-alphanumeric-character-turned-into-a-
-- dash>/*.jsonl` for `{"type":"custom-title","customTitle":"..."}` records. This is
-- reverse-engineered from Claude Code's own on-disk format, not a documented API, so
-- every read here is wrapped in `pcall` and a failure is treated as "unknown" (never an
-- error), falling back to attempting `--resume` directly.
--
-- Task 8.3 fix (found in interactive verification: a real, actively-running, externally
-- started session that had been given its name did not appear as pickable at all): a
-- session's `custom-title` record is only guaranteed to be on the *first* line when the
-- name is given at creation (`-n`/`--name`); one named or renamed later (`/rename`, or
-- the CLI's own interactive "name this session" UI, which the `-n` flag's own `--help`
-- text notes is "shown in the prompt box" and so can change during a session, not just
-- at its start) gets a *new* `custom-title` record appended wherever the rename happens
-- to land in the file, while line 1 is left exactly as it was (a different, stale title,
-- or -- for a session started with no name at all -- not a `custom-title` record at all).
-- Confirmed directly: a real, non-interactive `claude` session (`-p` with
-- `--input-format stream-json`, kept alive by holding its stdin open, the same
-- documented, legitimate CLI mode the R-1 spike used to avoid the interactive
-- workspace-trust dialog this sandboxed environment cannot click through) was started
-- with no name, later renamed mid-conversation via `/rename` to the exact name this
-- launcher would derive for its own directory, and this code -- reading only line 1 --
-- reported no matching (or even listed) session at all while that session was still
-- genuinely running, reproducing the user's exact symptom. This is a real bug in this
-- code (root cause (a) from task 8.3's investigation), not the inherent
-- actively-running-session limitation AD-17/R-8 already accept (root cause (b) was
-- ruled out along the way: a *separate*, real, concurrently-running `claude --resume
-- "<name>"` process was confirmed, by checking the transcript file it wrote to, to
-- attach to and append onto that exact same, still-running session rather than starting
-- a new one -- resuming an actively-running session by name is not itself blocked).
-- Fixed by scanning every line of each transcript (not just the first) and keeping the
-- *last* `custom-title` record found, since a rename's new record is always appended
-- after whatever came before it, making the last one always the session's current name.
local M = {}

local session_name_cache

--- The derived, memoised session name: "[directory name] Coordinator" (FR-043). Memoised
--- per Neovim instance since the working directory does not change during a session.
function M.session_name()
  if not session_name_cache then
    session_name_cache = vim.fs.basename(vim.fn.getcwd()) .. " Coordinator"
  end
  return session_name_cache
end

--- Claude Code's own per-project transcript directory for the current working
--- directory, matching the encoding observed empirically (every character that is not
--- a letter or digit becomes "-"; see design.md's Spike results for how this was
--- checked against more than one path shape).
local function project_transcript_dir()
  return vim.fn.expand("~/.claude/projects/" .. (vim.fn.getcwd():gsub("[^%w]", "-")))
end

--- Every named session found for this project directory, as { title = ..., id = ... }
--- entries, or nil if the lookup itself could not be done (missing directory, unreadable
--- file, unexpected format -- anything other than "the directory exists and has no named
--- sessions", which is a legitimate empty result, not a failure).
---
--- QA-T02 fix: a brand-new project (never had a Claude session) has no
--- `~/.claude/projects/<dir>` directory yet -- the ordinary, expected case this function's
--- own doc comment already calls out. `vim.fn.readdir()` on a nonexistent directory does
--- NOT fail the surrounding `pcall` (it returns `ok = true, {}`), but it still emits a raw
--- `E484: Can't open file <path>` to `:messages` as an independent side effect of the
--- failed read itself -- confirmed empirically. Checking existence first with
--- `vim.uv.fs_stat` (never emits a message, unlike `readdir`) avoids ever calling
--- `readdir` on a path that cannot possibly succeed, so "never an error" is actually true.
local function existing_titles()
  local dir = project_transcript_dir()
  if not vim.uv.fs_stat(dir) then
    return {}
  end
  local ok, entries = pcall(vim.fn.readdir, dir)
  if not ok or type(entries) ~= "table" then
    return nil
  end
  local titles = {}
  for _, entry in ipairs(entries) do
    if entry:match("%.jsonl$") then
      -- The whole file, not just the first line (see the note above): a rename's
      -- `custom-title` record can land anywhere, and the last one found is always
      -- the current name.
      local ok2, lines = pcall(vim.fn.readfile, dir .. "/" .. entry)
      if ok2 and lines then
        local latest
        for _, line in ipairs(lines) do
          local ok3, decoded = pcall(vim.json.decode, line)
          if ok3 and type(decoded) == "table" and decoded.type == "custom-title" and decoded.customTitle then
            latest = { title = decoded.customTitle, id = decoded.sessionId }
          end
        end
        if latest then
          titles[#titles + 1] = latest
        end
      end
    end
  end
  return titles
end

--- Quotes a value for claudecode.nvim's own argument parser (`claudecode.utils.
--- shell_split`, confirmed by reading its source): double quotes group a word, with
--- backslash escaping only `" \ $ ` `` inside them. This is not a real shell, so
--- `vim.fn.shellescape()` (single-quote based) would be the wrong quoting here.
local function quote(value)
  return '"' .. value:gsub("([\\\"])", "\\%1") .. '"'
end

--- Offers to start a new session with the derived name, or resume a different existing
--- session found for this directory (FR-043's "no session exists yet" scenario).
local function prompt_new_or_pick(name, titles)
  local choices = { string.format('Start a new session named "%s"', name) }
  for _, t in ipairs(titles) do
    choices[#choices + 1] = "Resume existing session: " .. t.title
  end
  vim.ui.select(choices, {
    prompt = string.format('No Claude session named "%s" yet:', name),
  }, function(_, idx)
    if not idx then
      return
    end
    if idx == 1 then
      vim.cmd("ClaudeCode -n " .. quote(name))
    else
      vim.cmd("ClaudeCode --resume " .. quote(titles[idx - 1].title))
    end
  end)
end

-- The filetype the panel's terminal buffer is overridden to at open time
-- (plugins/claude.lua's `terminal.snacks_win_opts.bo.filetype`, D2). Used below to
-- find the panel's own window without needing any state claudecode.nvim does not
-- already expose.
local FONDUE_CLAUDE_PANEL_FILETYPE = "fondue_claude_panel"

-- `no-neck-pain.nvim` gives its own centred-layout padding buffers this filetype by
-- default (`NoNeckPain.bufferOptionsBo.filetype`, applied via `ui.init_side_options` --
-- confirmed by reading the pinned plugin's own `lua/no-neck-pain/config.lua` and
-- `ui.lua`). Never real content; moved up here (from its original spot nearer
-- `no_real_content_would_remain()` below, which still uses it) so `fallback_focus_target()`
-- (task 14) can share it too.
local NO_NECK_PAIN_FILETYPE = "no-neck-pain"

-- The dashboard/start-screen buffer's own filetype (`Snacks.dashboard.open()`'s own
-- default, confirmed by reading the pinned snacks.nvim source and empirically via
-- `nvim_buf_get_option`/the 25.1 reproduction below). Used by task 25's new guard
-- (`closing_dashboard_leaves_only_panel()`) to recognise the one further case D5/task
-- 15 never covered: closing the dashboard *itself* while the panel is the only thing
-- that would be left.
local DASHBOARD_FILETYPE = "snacks_dashboard"

--- The panel's own window, if it currently has one that is genuinely on screen (not
--- merely a live-but-hidden window -- see the `hide` check below), or nil if the
--- panel has never been opened or is currently hidden. Task 13.2: needed to tell
--- "this action would hide the (visible) panel" apart from "this action would
--- show/focus it", since only the latter needs the occlusion guard below.
---
--- The panel's window is always a normal split (`plugins/claude.lua`'s
--- `terminal.split_side`, never `position = "float"`), so in practice
--- claudecode.nvim's own hide closes it outright rather than config-hiding it (that
--- trick, confirmed by reading `claudecode/terminal/snacks.lua`'s `cc_hide`, only
--- applies to a floating window) -- but the `hide` check is kept anyway so this does
--- not silently break if that ever changes.
local function panel_window()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == FONDUE_CLAUDE_PANEL_FILETYPE then
      local ok, config = pcall(vim.api.nvim_win_get_config, win)
      if not (ok and config.hide == true) then
        return win
      end
    end
  end
  return nil
end

--- Task 13.2's occlusion guard (design.md's D2/D3 occlusion note, task 13.1): the
--- test/run terminal is always a full-window float, and Neovim floats always draw
--- over the tabpage's normal window grid regardless of keyboard focus -- confirmed
--- directly in task 13.1, not assumed -- so showing or focusing the Claude panel's
--- own (normal split) window while that terminal is open lands the user in a state
--- that looks like nothing happened at all, with no on-screen cue. Rather than fight
--- that native stacking (not a bug in either plugin) or notify only after the fact,
--- this stops the *open/show/focus* path before it does anything: no window change,
--- no session start/resume/attach attempt, no focus change. Hiding an
--- already-shown panel needs no visual confirmation and must keep working even while
--- occluded (an open panel the terminal was opened on top of must stay dismissible
--- with a single `Space a a`), so every caller below checks this only on the
--- show/focus branch, never on the hide branch.
local function warn_occluded_by_terminal()
  vim.notify("Hide the test/run terminal first (Space t)", vim.log.levels.WARN)
end

local function terminal_is_open()
  return require("fondue.lib.terminals").is_open()
end

--- Derives the session name (if not already known) and resumes/starts/prompts as
--- FR-043 requires (design.md D4). Only ever reached when there is no already-open
--- panel to show/hide/focus instead (not connected at all): showing or starting a
--- panel from nothing is always an "open" for the 13.2 guard's purposes, never a
--- hide, so this always checks it first.
local function resume_or_start()
  if terminal_is_open() then
    warn_occluded_by_terminal()
    return
  end

  local name = M.session_name()
  local titles = existing_titles()
  local known_missing = titles ~= nil
  local exists = not known_missing -- lookup failed: try --resume directly, optimistically
  if titles then
    for _, t in ipairs(titles) do
      if t.title == name then
        exists = true
        break
      end
    end
  end

  if exists then
    vim.cmd("ClaudeCode --resume " .. quote(name))
  else
    prompt_new_or_pick(name, titles or {})
  end
end

--- Opens the Claude panel: attaches to an already-connected session in this Neovim
--- instance, resumes the derived-name session if one exists, or offers to start a new
--- one / pick an existing one otherwise (FR-043; design.md D4). Wired to
--- `<leader>aa`'s "show/hide" contract: while connected, this is a plain,
--- always-toggle show/hide regardless of focus (`:ClaudeCode`, claudecode.nvim's own
--- `simple_toggle`) -- distinct from `M.focus()`'s focus-aware toggle below. This
--- (not a separate copy of the toggle logic in `keymaps.lua`) is where task 13.2's
--- guard lives, so the same one check covers every way `<leader>aa` can show the
--- panel, including the "connected but currently hidden" case.
function M.open()
  local ok, claudecode = pcall(require, "claudecode")
  if not ok then
    vim.notify("Claude panel: claudecode.nvim is not available", vim.log.levels.ERROR)
    return
  end

  if claudecode.is_claude_connected() then
    if panel_window() then
      -- Already shown: toggling it hides it, regardless of focus or occlusion --
      -- no guard (see the note above panel_window()/warn_occluded_by_terminal()).
      vim.cmd("ClaudeCode")
      return
    end
    if terminal_is_open() then
      warn_occluded_by_terminal()
      return
    end
    vim.cmd("ClaudeCode")
    return
  end

  resume_or_start()
end

--- Task 14 fix: the window that was current immediately before focus last moved onto
--- the Claude panel, so `M.focus()` can return to it rather than hiding the panel (see
--- below). A single remembered id is enough -- the panel can only be focused from one
--- window at a time -- and nil until the panel has been focused at least once.
local pre_focus_win

--- Where to send focus back to when `pre_focus_win` is no longer valid (its window has
--- since been closed): the first other real window in the current tab, skipping the
--- panel itself, no-neck-pain's own padding buffers (never real content -- same
--- filetype `no_real_content_would_remain()` below excludes), and any floating window
--- (the test/run terminal, task 13's occlusion guard) so that returning from the panel
--- to "the code" never lands on an unrelated floating window that merely happens to be
--- open. nil if nothing suitable remains (nothing to fall back to; focus is simply left
--- where it is).
local function fallback_focus_target(panel_win)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if win ~= panel_win then
      local ok, config = pcall(vim.api.nvim_win_get_config, win)
      local floating = ok and config.relative ~= ""
      if not floating and vim.bo[vim.api.nvim_win_get_buf(win)].filetype ~= NO_NECK_PAIN_FILETYPE then
        return win
      end
    end
  end
  return nil
end

--- Toggles focus: shows/focuses the panel if hidden or unfocused; if it is already
--- focused, returns focus to wherever it was before (the code buffer you came from),
--- leaving the panel exactly as visible as it was -- otherwise identical to
--- `M.open()`'s attach/resume/start logic. "Focuses it" while it is
--- visible-but-unfocused counts as the guarded show/focus path too (task 13.2): moving
--- focus onto the panel while the terminal occludes it leaves the user looking at
--- exactly what they were looking at before, per task 13.1's finding that Neovim's
--- window focus does not affect float-over-split stacking at all.
---
--- Task 14 fix: this used to delegate the "already focused" branch to claudecode.nvim's
--- own `:ClaudeCodeFocus` (`focus_toggle`), whose actual behaviour (confirmed by reading
--- `lua/claudecode/terminal.lua`/`snacks.lua` while implementing 13.2) is "hide if its
--- own window is already the current window" -- the wrong semantics for a code<->panel
--- focus toggle (FR-002/FR-044): hiding is exclusively `Space a a`'s (`M.open()`'s) job,
--- never this one's. Implemented directly here instead, using `pre_focus_win` above.
--- The reverse direction (panel already focused -> back to code) is never guarded by
--- the occlusion check, symmetric with how hiding is never guarded either: leaving the
--- panel cannot itself land the user somewhere that looks like nothing happened.
function M.focus()
  local ok, claudecode = pcall(require, "claudecode")
  if ok and claudecode.is_claude_connected() then
    local win = panel_window()
    if win and win == vim.api.nvim_get_current_win() then
      local target = pre_focus_win
      if not (target and vim.api.nvim_win_is_valid(target)) then
        target = fallback_focus_target(win)
      end
      if target then
        vim.api.nvim_set_current_win(target)
      end
      return
    end
    if terminal_is_open() then
      warn_occluded_by_terminal()
      return
    end
    pre_focus_win = vim.api.nvim_get_current_win()
    vim.cmd("ClaudeCodeFocus")
    return
  end

  pre_focus_win = vim.api.nvim_get_current_win()
  resume_or_start()
end

-- QA-T01 fix: `NO_NECK_PAIN_FILETYPE` (declared above, near `FONDUE_CLAUDE_PANEL_FILETYPE`)
-- is load-bearing for `no_real_content_would_remain()` below: these are exactly the
-- windows no-neck-pain's own `main.disable` (`lua/no-neck-pain/main.lua`) ignores when
-- deciding whether to force a full `quitall!`.

--- Whether closing the current window would actually trigger no-neck-pain's own
--- `quitall!` cascade: true when every other window in the current (only) tab is one of
--- its own padding windows (never real content), and false the moment any floating
--- window is present anywhere (never reaches the cascade at all -- see the QA-T05 fix
--- note below) or any other real window remains.
---
--- This replaces a plain window-count check (`#windows == 1`), which is wrong the moment
--- the centred layout's padding is present -- which is this editor's default state. See
--- design.md's D5 "Quit warning: the padding cascade" for the full write-up of why; the
--- short version: with padding on, a plain `:q` on your one real window leaves 2 windows
--- (the padding pair), not 0, so the old check concluded the quit wouldn't end Neovim --
--- correct from Neovim's own immediate point of view, but wrong about what happens next.
--- `no-neck-pain.nvim` watches the same `QuitPre` event itself and, a `vim.schedule()`
--- tick later (confirmed by reading `main.lua`'s `_on_buf_delete`, which wraps its own
--- logic in `vim.schedule`), finds only its own padding left, and unconditionally runs
--- `vim.cmd("quitall!")` -- ending Neovim anyway, just too late for the old check to have
--- seen it coming.
---
--- `no-neck-pain.nvim`'s own force-quit decision (`main.disable`, `main.lua:591-622`)
--- filters a tab's windows down to those that are not its own left/right padding ids and
--- not "relative" (floating); if nothing is left, it quits. This function predicts that
--- outcome directly, by asking the same question about the window that is *about* to
--- close, rather than trying to observe the padding cascade after the fact (which has no
--- reliable, cancellable hook -- `QuitPre` itself does not support `v:event.abort`,
--- confirmed against `:help QuitPre`/`:help v:event`, only `CmdlineLeave` does. Any other
--- real window left standing -- the file tree, the Claude panel, an ordinary split --
--- is not ignored by `main.disable`'s own filter, so it correctly predicts "no" there too:
--- no-neck-pain only re-lays-out around it rather than quitting).
---
--- QA-T05 fix (found during the confirmation pass on QA-T01's original fix): a floating
--- window present (for example the test/run terminal, `lib/terminals.lua`, left open and
--- unfocused) means no-neck-pain's cascade is *not* actually reached, so this predicts
--- "no" rather than "yes" whenever one is open -- the opposite of what this function
--- previously assumed. `main.disable`'s own "not padding, not floating" filter (mirrored
--- above) is real, but it is gated by an *earlier* check in `_on_buf_delete`
--- (`lua/no-neck-pain/main.lua:382`, the same handler that eventually calls
--- `main.disable`): `if not state:is_active_tab_registered() or api.is_relative_window()
--- then return end` -- and `api.is_relative_window()` called with no argument
--- (`util/api.lua:37-41`) checks the *current window at the time this scheduled callback
--- runs*, i.e. whatever window Neovim's own close algorithm focuses next, not the window
--- that just closed. Confirmed directly, live (not just by reading): with the centred
--- layout's padding and the test/run terminal both present, closing the one real content
--- window with `:q` moves focus to the floating terminal (it was the most recently used
--- window relative to content -- Neovim's own alternate-window choice, confirmed via
--- `winnr("#")` before the close and via a `WinClosed` autocommand's own after-the-fact
--- observation after it), `is_relative_window()` sees a floating current window and bails
--- immediately, `main.disable` is never reached, and Neovim does not quit -- so the old
--- comment's claim that a floating window "does not save you from the cascade either" was
--- asserted from reading `main.disable`'s filter in isolation and was wrong; it never
--- accounted for `_on_buf_delete`'s own earlier gate. The floating window this codebase
--- creates (the test/run terminal, `lib/terminals.lua`'s `Snacks.terminal.open()`)
--- always enters/focuses itself when opened, so it being present but unfocused only
--- happens by switching back to the content
--- window afterward -- which is exactly what makes it Neovim's alternate window and thus
--- the close-time focus target this bailout keys on. Treating "a floating window is open"
--- as "the cascade will not run" therefore matches the only way a floating window and an
--- unfocused state can coexist here, without needing to reimplement Neovim's own
--- window-focus algorithm in full generality.
--- Task 22 fix (Critical regression, found in interactive `/verify`, thirteenth pass):
--- `blink.cmp`'s own cmdline completion popup (`plugins/completion.lua`'s `cmdline`
--- source, active since an earlier change -- this is not new) is itself a real,
--- genuine floating window (`filetype` one of `blink-cmp-menu`/`blink-cmp-signature`/
--- `blink-cmp-documentation`, per the pinned plugin's own `lua/blink/cmp/completion/
--- windows/menu.lua` etc.), and it is very often still open at the exact instant
--- `CmdlineLeave` fires: typing `:q<CR>` at ordinary human speed reliably has the
--- completion menu showing "qall/quit/quitall/cquit/..." on screen the moment `<CR>`
--- is pressed, confirmed directly, live, with a real pty and real per-character typing
--- delay (not assumed from reading the popup's lifecycle code) -- it is only actually
--- closed as a side effect of the command-line session ending, which happens *after*
--- this very `CmdlineLeave` autocommand returns. The QA-T05 fix above's own floating-
--- window check does not distinguish this from the test/run terminal's own floating
--- window (the case it was actually written for) and so was, wrongly, unconditionally
--- treating this popup's mere on-screen presence as "the padding cascade will not run" --
--- reproducing, byte-for-byte, this task's own reported regression: a real, live
--- `is_claude_connected() == true` session, the Claude panel genuinely closed (no
--- window at all, not merely hidden), one file window left, `:q` typed at human speed
--- -> no warning at all, and Neovim actually exits, confirmed live by checking the
--- process was gone afterward. Root cause confirmed directly (not guessed) with
--- temporary instrumentation logging every window's filetype/`relative`/`zindex` right
--- inside this exact check at the moment it ran: exactly one extra floating window was
--- present beyond the padding and the file, `filetype = "blink-cmp-menu"`. `focusable`
--- was `true` on that popup (checked directly, not assumed) so a `focusable`-based
--- distinction would not have worked either.
---
--- QA-T05's own reasoning does not actually apply to this popup at all: it is scoped
--- entirely to Neovim's post-close "alternate window" becoming a floating window that
--- *survives* the close (its own write-up: "always enters/focuses itself when opened
--- ... present but unfocused only happens by switching back ... afterward"). A cmdline
--- completion popup cannot ever do that -- it is inherently tied to the very
--- command-line session this check is being asked about, and is unconditionally gone,
--- one way or another, by the time no-neck-pain's own deferred `_on_buf_delete`
--- callback (what QA-T05's check predicts the outcome of) actually runs. So this is not
--- a narrowing of QA-T05's own fix -- it is excluding a case QA-T05 was never actually
--- about in the first place, the same way D8's Claude-panel exclusion did not reopen
--- that decision's own "no allowlist" reasoning (a single, permanent, already-named
--- filetype prefix, not a list of every floating-window-creating plugin this config
--- might ever gain).
---
--- Predates today's `fallback_to_start_screen()`/no-neck-pain work (tasks 20/21):
--- confirmed directly that neither of those tasks' own changes touch this function,
--- `is_last_window()`, or anything upstream of it -- this is QA-T05's own, separately
--- pre-existing bug, only now actually exercised by a real-pty test typing `:q` at
--- human speed from a genuinely-connected, genuinely-panel-closed state, a combination
--- no earlier pass in this change's history had actually driven through a real pty
--- (earlier real-pty passes either mocked `is_claude_connected()` directly -- so the
--- whole `ends_nvim == true` branch was never reached that way -- or exercised task 15's
--- own, separate panel-open guard instead, which has no floating-window check to hit
--- this bug in the first place).
local BLINK_CMP_FILETYPE_PREFIX = "blink-cmp-"

--- Task 23.4 fix (QA's Major finding on the adversarial confirmation pass of task 22's
--- own fix, 2026-09-30): LSP hover (`vim.lsp.buf.hover()`), signature help
--- (`vim.lsp.buf.signature_help()`), and diagnostic (`vim.diagnostic.open_float()`)
--- floats all share the exact same blind spot `blink-cmp-menu` had before task 22 --
--- and, per QA's own testing, were "currently safe only by coincidence" (Neovim's own
--- post-close focus happened to land on them in every trial QA ran), not by the
--- exclusion's own logic, which is exactly the kind of unverified "looked safe, wasn't"
--- gap this exact function has a documented history of (QA-T05, task 22).
---
--- Excluding these by filetype (the way `blink-cmp-*` is excluded above) was considered
--- and rejected: hover/signature-help floats default to `filetype = "markdown"`
--- (confirmed by reading the installed Neovim runtime's own `vim.lsp.util.
--- open_floating_preview()`), which is far too broad a filetype to blanket-exclude --
--- a genuine, persistent floating window showing real markdown content from some other
--- plugin would wrongly be ignored too. Excluded instead by a precise, non-filetype
--- marker: `open_floating_preview()` (confirmed by reading it directly -- every one of
--- hover, signature help, and `vim.diagnostic.open_float()` calls this same function
--- internally, so one check covers all three) sets `vim.w[floating_winnr].
--- lsp_floating_bufnr` on the floating window itself, unconditionally, every time. This
--- is Neovim's own internal bookkeeping for these floats (used by its own
--- `WinClosed`-driven preview cleanup), not something this codebase invented, and it
--- cannot collide with an unrelated real window the way a filetype guess could.
---
--- Honest residual uncertainty, not rounded up: unlike `blink-cmp-menu` (guaranteed
--- gone by the time no-neck-pain's own deferred callback runs, since it is tied to the
--- very cmdline session this check is being asked about -- see the comment on that
--- exclusion above), a hover/diagnostic float's own default `close_events` (`CursorMoved`/
--- `CursorMovedI`/`InsertCharPre`) give no such guarantee here: nothing about submitting
--- a quit command necessarily fires any of them first. QA's own testing (10/10 hover,
--- 5/5 diagnostic trials) found no reproduced data loss, but by their own account could
--- not rule out every layout, and this fix does not change that -- it implements the
--- task's own explicit instruction (treat these the same as `blink-cmp-*`) rather than
--- independently re-deriving new proof that it is always safe. Flagged here plainly so a
--- future adversarial pass knows this is the weaker-evidence half of this task's fix.
-- Task 26.1 fix (QA's adversarial re-check of task 25's own regression pass, 2026-09-30,
-- Critical): `blink.cmp`'s own completion menu grows a separate **scrollbar** -- a thumb
-- and, when its border allows it, a gutter -- both plain floating windows with NO
-- filetype at all (confirmed by reading the installed, pinned `blink.cmp`'s own
-- `lua/blink/cmp/lib/window/scrollbar/win.lua`'s `_make_win()`, which creates each one via
-- `vim.api.nvim_create_buf(false, true)`, a bare scratch buffer), created automatically
-- whenever a command's fuzzy-matched candidate count exceeds `completion.menu.max_height`
-- (this project's own `plugins/completion.lua` never overrides it, so it stays at
-- `blink.cmp`'s own default of 10 -- `config/completion/menu.lua`). QA measured this
-- project's own large `ClaudeCode*`/`NoNeckPain*`/`TodoQuickFix`-heavy command surface
-- crossing that threshold for several common quit words (`quit`=12, `close`=27, `clo`=28,
-- `x`=51 candidates, all needing a scrollbar; `q`=9, `xit`=3, neither does) -- explaining,
-- exactly, the previously-reported "intermittent" `:quit`/`:close`/`:clo`/`:x` failures:
-- before this fix, neither scrollbar window matched `BLINK_CMP_FILETYPE_PREFIX` (no
-- filetype at all) nor carried `lsp_floating_bufnr`, so `is_ignorable_transient_float()`
-- wrongly treated each one as a persistent floating window, and every guard built on
-- `no_real_content_would_remain()` silently declined to fire -- reproducing,
-- deterministically (not intermittently), the exact same class of data loss task 22
-- already fixed for the menu itself, for both D5's own original trigger and task 25's own
-- dashboard-close trigger.
--
-- Fixed using the installed plugin's own tracked window state, not by guessing from the
-- scrollbar windows' own properties (no filetype; `focusable = false`, a property a
-- future, unrelated plugin's float could just as easily share by coincidence) and not by
-- raising `max_height` (which would only move the threshold to a new candidate count, not
-- remove it). Each of `blink.cmp`'s three completion-adjacent windows -- the menu,
-- documentation, and signature-help popups (`lua/blink/cmp/completion/windows/menu.lua`,
-- `.../documentation.lua`, `lua/blink/cmp/signature/window.lua`, all read directly, not
-- assumed) -- exposes its own `win` field (a `blink.cmp.Window`,
-- `lua/blink/cmp/lib/window/init.lua`), whose own `scrollbar` field (present whenever that
-- window's own `scrollbar` option is enabled -- true by default for the menu and
-- documentation windows, confirmed in `config/completion/menu.lua`/`documentation.lua`;
-- false by default for signature help, checked here anyway since nothing relies on it
-- staying that way) is a `blink.cmp.Scrollbar` wrapping a `blink.cmp.ScrollbarWin`
-- (`lua/blink/cmp/lib/window/scrollbar/{init,win}.lua`) that tracks the live thumb/gutter
-- window ids directly, as `win.scrollbar.win.thumb_win`/`.gutter_win` -- the plugin's own
-- live bookkeeping, not a guess about window properties. `Win:close()`
-- (`lib/window/init.lua`) unconditionally calls `self.scrollbar:update()` with no target,
-- which hides both sub-windows -- so a scrollbar can never outlive the completion window
-- that owns it, matching the exact "tied to the very cmdline session, unconditionally gone
-- by the time no-neck-pain's own deferred cascade runs" property that already justifies
-- excluding `blink-cmp-*` itself above; this is not a new class of exception, just one
-- level deeper into the same menu's own window tree.
local BLINK_CMP_WINDOW_MODULES = {
  "blink.cmp.completion.windows.menu",
  "blink.cmp.completion.windows.documentation",
  "blink.cmp.signature.window",
}

local function is_blink_cmp_scrollbar_win(win)
  for _, mod_name in ipairs(BLINK_CMP_WINDOW_MODULES) do
    local ok, mod = pcall(require, mod_name)
    if ok and mod.win and mod.win.scrollbar and mod.win.scrollbar.win then
      local sb_win = mod.win.scrollbar.win
      if win == sb_win.thumb_win or win == sb_win.gutter_win then
        return true
      end
    end
  end
  return false
end

local function is_ignorable_transient_float(filetype, win)
  if filetype:sub(1, #BLINK_CMP_FILETYPE_PREFIX) == BLINK_CMP_FILETYPE_PREFIX then
    return true
  end
  if is_blink_cmp_scrollbar_win(win) then
    return true
  end
  local ok, lsp_floating_bufnr = pcall(function()
    return vim.w[win].lsp_floating_bufnr
  end)
  return ok and lsp_floating_bufnr ~= nil
end

--- `also_exclude`, when given, is skipped too, on top of the current window (task 25):
--- used by `closing_dashboard_leaves_only_panel()` below to ask "if the dashboard
--- window (about to close) and the panel were both set aside, would only no-neck-pain's
--- own padding be left" -- the panel is exactly what that guard expects to still be
--- standing afterward, so its own presence must not count against the check the way it
--- correctly does for `is_last_window()`/D5's own, different question below (whether
--- the panel survives is precisely what makes D5 correctly say "no, this would not end
--- Neovim" there). `is_last_window()`'s own call (no `also_exclude`) is unaffected.
local function no_real_content_would_remain(also_exclude)
  local current_win = vim.api.nvim_get_current_win()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if win ~= current_win and win ~= also_exclude then
      local ok, config = pcall(vim.api.nvim_win_get_config, win)
      local floating = ok and config.relative ~= ""
      local filetype = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
      if floating then
        if not is_ignorable_transient_float(filetype, win) then
          return false
        end
        -- else: a transient, self-dismissing float (blink.cmp's own completion/
        -- signature/documentation popup, or an LSP hover/signature-help/diagnostic
        -- float) -- ignored entirely (not merely exempted from "blocks the cascade"):
        -- it cannot affect the outcome either way, per the comments above.
      elseif filetype ~= NO_NECK_PAIN_FILETYPE then
        return false
      end
    end
  end
  return true
end

--- Whether a `:q`/`:quit`/`:wq`/`:x` from the current window would end Neovim: the last
--- tab, and closing this window would leave nothing no-neck-pain or Neovim itself
--- considers real content (see `no_real_content_would_remain()` above). `:qa`/`:qall`/
--- `:wqa`/`:xa` always end Neovim regardless of window count and never call this.
local function is_last_window()
  return #vim.api.nvim_list_tabpages() == 1 and no_real_content_would_remain()
end

--- Task 15's guard: whether the cmdline command being submitted would close the last
--- window showing real code, leaving only the Claude panel (and no-neck-pain's own now-
--- pointless padding) on screen, while a session is still connected. Deliberately a
--- different question from `is_last_window()`/D5 above: D5 asks "would Neovim actually
--- end" (it correctly does not here -- the panel's own window is real and separate, so
--- Neovim never quits and the session never ends), this asks "would there be no code
--- left to look at afterwards". Reuses `lib/session.lua`'s `M.has_real_content()` (the
--- same "ordinary buftype, named buffer" notion that module already uses to decide
--- whether a restored session is worth showing), rather than
--- `no_real_content_would_remain()` above, whose own "real content" is deliberately
--- wider for a different purpose -- it counts the panel (and any other real side window)
--- as real, since its job is predicting no-neck-pain's own force-quit filter, not
--- spotting "no code is left". See design.md's D5 addendum for the full reasoning.
local function would_lose_last_code_window()
  local current_win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(current_win)
  if not (vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= "") then
    return false -- not closing a code window at all; nothing this guard is about
  end
  if not panel_window() then
    return false -- no panel open: an ordinary quit, D5's territory if it's relevant at all
  end
  return not require("fondue.lib.session").has_real_content(current_win)
end

--- Task 25 (interactive `/verify`, fourteenth pass): whether the window being closed by
--- a guarded command is the dashboard/start-screen window itself, with the Claude panel
--- open and connected and nothing else real remaining -- i.e. there is nowhere further
--- to "fall back" to (task 15's own fallback path above IS the dashboard; this is the
--- one further step past it that task 15 never covered). Deliberately a third, separate
--- question from both `is_last_window()`/D5 (which correctly says "no" here -- the
--- panel's own window is real and survives the close, so Neovim does not quit on its
--- own) and `would_lose_last_code_window()`/task 15 just above (whose own first check,
--- `buftype == "" and name ~= ""`, is false for the dashboard's own `nofile` scratch
--- buffer, so it never even reaches its own panel check for a dashboard close).
---
--- Root cause, confirmed directly (a real, non-mocked `is_claude_connected()` and a
--- real dashboard window, not assumed): reproduced first with no code changes -- a
--- fresh directory (no persistence.nvim session file, so `lib/session.lua`'s own
--- `decide()` shows the start screen automatically), the panel opened for real from the
--- dashboard and genuinely connected (the same real WebSocket-handshake technique task
--- 22/23 established), nothing else open, then `:q` on the dashboard -- zero
--- `confirm()` calls of any kind, window count 4 -> 1, the panel left filling the whole
--- tab with no warning at all. `has_real_content()`/`no_real_content_would_remain()`'s
--- own "real content" notion deliberately treats a scratch/dashboard buffer as *not*
--- real -- correct for `lib/session.lua`'s own use (deciding whether a session restore
--- has anything worth showing, FR-008/FR-025) and correct for task 15's own guard (a
--- `:q` against the dashboard is not "closing a code window" at all) -- but it means
--- nothing in this file had ever asked "is the *dashboard itself* about to close while
--- the panel is the only thing that would be left", so that case fell through every
--- existing guard silently.
---
--- Reuses `no_real_content_would_remain()`'s own "padding/ignorable-float-only" notion
--- (the same one `is_last_window()`/D5 use above), not `has_real_content()`/task 15's
--- narrower one: this guard needs to tell "anything else genuinely real" (a file tree,
--- another split, ...) apart from "just no-neck-pain's own padding", exactly what
--- `no_real_content_would_remain()` already computes for D5 -- just with the panel
--- itself also set aside via that function's new `also_exclude` parameter, since the
--- panel is expected, correctly, to still be standing afterward. This is also what
--- correctly keeps this guard from firing when a file tree or another real window is
--- also open alongside the dashboard and the panel (task 25.4's own explicit check):
--- neither `no-neck-pain` padding nor an ignorable transient float, so
--- `no_real_content_would_remain(panel)` sees it and returns false.
local function closing_dashboard_leaves_only_panel()
  local current_win = vim.api.nvim_get_current_win()
  if vim.bo[vim.api.nvim_win_get_buf(current_win)].filetype ~= DASHBOARD_FILETYPE then
    return false
  end
  local panel = panel_window()
  if not panel then
    return false -- no panel open: an ordinary dashboard close, nothing this guard is about
  end
  return no_real_content_would_remain(panel)
end

--- Task 15.2: once the confirmed close has actually happened (and, per design.md's D5
--- padding-cascade note, no-neck-pain has had its own chance to react to it -- which, per
--- the bug this guard fixes, may mean dropping its padding around nothing and leaving the
--- panel to fill the whole tab), this puts the start screen into a fresh window if
--- nothing real is left, so the centred layout and the panel's own side position both
--- recover to the same familiar shape a fresh Neovim start already produces. Deferred by
--- 50ms -- the same margin `lib/session.lua` already uses elsewhere (`decide()`'s
--- `focus_real_content` call) to sit comfortably past no-neck-pain's own 5ms debounce;
--- confirmed empirically to be long enough here too (see design.md's Spike results).
---
--- Does not call `lib/session.lua`'s `show_start_screen()` directly: that function opens
--- with `:only`, which would also close the Claude panel this guard exists to keep open
--- -- exactly wrong here, even though it is the right thing to do at a fresh startup,
--- which is the only context that function was built for. `M.open_start_screen_in()`
--- (factored out of it for this reason) is used instead, into a fresh window created
--- explicitly on the correct side of the panel (see the comments inline below for why
--- that has to be explicit, and why a second explicit step is also needed to bring
--- no-neck-pain's own padding back).
local function fallback_to_start_screen()
  local session = require("fondue.lib.session")
  if session.has_real_content() then
    return -- something real is already showing; nothing left to fix
  end
  -- `no-neck-pain.nvim`'s own `ui.move_sides()` (confirmed by reading it directly) only
  -- ever repositions its *own* left/right padding windows -- never the Claude panel's,
  -- which is a plain "integration" it recognises by filetype but never physically moves.
  -- The panel's own on-screen position is therefore whatever `claudecode.nvim`/
  -- `Snacks.terminal.open()` put it at when it was opened, and stays there regardless of
  -- what else happens around it. So the new content window has to be created on the
  -- correct side of the panel *itself*, explicitly, rather than trusting no-neck-pain to
  -- sort it out afterwards: focusing the panel first and opening `leftabove vnew` (a
  -- direction modifier, unlike a plain `:vnew`/`:vsplit`, that does not depend on this
  -- config's own 'splitright' value or on whatever window happened to be current after
  -- the close) puts the new window on the panel's left -- correct for this codebase's
  -- `split_side = "right"` (plugins/claude.lua). Confirmed the hard way, headless: a
  -- plain `:vnew` from whatever window focus happened to land on after the close put the
  -- new window on the *panel's* right instead, on the one real-world run where that
  -- landed on the panel's own window -- reproducing, with no-neck-pain's own internal
  -- state (`curr`/`left`/integration ids) all otherwise entirely correct by this point,
  -- a visually swapped layout (the panel where the centred content should be, and the
  -- new content pushed out to the panel's own far side) that no subsequent no-neck-pain
  -- call fixes, since -- per the first paragraph above -- it was never no-neck-pain's
  -- layout logic that was wrong.
  --
  -- `:vnew`, not `:vsplit`: `:vsplit` would clone whatever buffer the current window
  -- happens to be showing at this point -- which, absent the explicit panel focus above,
  -- could well be the Claude panel's own terminal buffer. Confirmed the hard way,
  -- headless, against the real pinned snacks.nvim: passing that terminal buffer through
  -- to `Snacks.dashboard.open()`'s own `opts.buf` has it try to set `buftype = "nofile"`
  -- on a buffer whose `buftype` is already `"terminal"`, which Neovim rejects outright
  -- (`E474: Invalid argument` -- a terminal buffer's `buftype` cannot be changed once
  -- set). `:vnew` always opens a genuinely fresh, empty, unnamed buffer instead,
  -- regardless of what was current, so this can never happen.
  local panel = panel_window()
  if panel and vim.api.nvim_win_is_valid(panel) then
    vim.api.nvim_set_current_win(panel)
  end
  vim.cmd("leftabove vnew")
  local dashboard_win = vim.api.nvim_get_current_win()
  session.open_start_screen_in(vim.api.nvim_get_current_buf(), dashboard_win)

  -- Confirmed directly, headless, against the real pinned no-neck-pain commit: simply
  -- opening real content into a new window is NOT enough on its own to bring the
  -- padding back. Once no-neck-pain's own `_on_buf_delete` (design.md's D5
  -- padding-cascade note) decides nothing real is left and runs `main.disable`, it
  -- fully de-registers the tab -- it does not watch for a *future* window to adopt as
  -- "main" the way it does while still enabled, so the new dashboard window and the
  -- panel would otherwise be left exactly as `:q` alone had left them (dashboard
  -- content visible, but un-padded).
  --
  -- `main.enable()` records whatever window is *current at the moment it is called* as
  -- its own "main" content window -- confirmed the hard way: `Snacks.dashboard.open()`'s
  -- own setup can leave a different window current by the time it returns (its `D:init`/
  -- `D:update` do their own window-local work along the way), so focus is reasserted
  -- onto the dashboard window explicitly, immediately before `enable()`, rather than
  -- trusting whatever `Snacks.dashboard.open()` happens to leave focused.
  if vim.api.nvim_win_is_valid(dashboard_win) then
    vim.api.nvim_set_current_win(dashboard_win)
  end

  -- Task 20 fix (found in interactive `/verify`, eleventh pass): the comment this
  -- replaced called `enable()` alone here, on the assumption that it is always either
  -- a genuine fresh registration (the padding-cascade case just above) or a harmless,
  -- documented no-op (`skip_enable`'s "already registered" check) if no-neck-pain's own
  -- disable-cascade never actually ran. That assumption is false, confirmed directly by
  -- reading no-neck-pain's own `_on_win_change` (`main.lua`) and by live internal-state
  -- inspection (`_G.NoNeckPain.state.tabs[...].wins.main.curr`), not by re-guessing the
  -- same fix harder: whether the disable-cascade runs at all is itself a race between
  -- two independent no-neck-pain autocmd handlers reacting to the same `:q`
  -- (`_on_buf_delete`'s `QuitPre`/`BufDelete`, which is what runs the cascade this
  -- guard was originally written for, and `_on_win_change`'s own `WinClosed`, which
  -- reacts first in at least some real event-scheduling orders -- confirmed live,
  -- headless, at the same 225-column width as the user's own report). When
  -- `_on_win_change` wins that race, its own recovery path (`state:validate_sides()`,
  -- called because the file's window -- no-neck-pain's own recorded "curr" -- just
  -- became invalid) silently reassigns "curr" to the *panel's own window* (the most
  -- recently focused window still standing) and leaves the tab registered throughout --
  -- the disable-cascade this function's own comment assumed always happens (or is
  -- harmlessly skipped) never runs at all in this path. Calling `enable()` next is then
  -- a genuine, harmful no-op: `skip_enable` bails out on "already registered" before
  -- `main.enable()` ever reaches its own `state:set_side_id(current_win, "curr")` line,
  -- so "curr" stays wrongly pinned to the panel. Confirmed directly, live: after this
  -- exact sequence, `_G.NoNeckPain.state`'s own `curr` was still the panel's window id
  -- and its `integrations.fondue_claude_panel.id` was `nil` (never re-registered),
  -- both immediately after `:q` and still after `enable()` had already run and
  -- returned -- not merely a cosmetic asymmetry, a genuinely wrong internal state that
  -- happened to still look plausible in that one run's specific arithmetic, and the
  -- reported bug (an orphaned extra pad, and the panel sized by whatever arbitrary
  -- space Vim's own window layout leaves an unmanaged window, not by
  -- `split_width_percentage`) in others.
  --
  -- The first fix tried here -- unconditionally calling the public `require(
  -- "no-neck-pain").disable()` before `enable()`, on the theory that a fresh
  -- disable+enable always re-establishes "curr" regardless of which race outcome
  -- happened -- was itself wrong, confirmed live rather than trusted: `NoNeckPain.
  -- disable()` (`no-neck-pain/init.lua`) is `api.debounce("public_api_disable",
  -- main.disable)`, not a direct call -- it only *schedules* the real teardown for
  -- later, asynchronously, on no-neck-pain's own debounce timer. The `enable()` right
  -- after it therefore still ran against the *not-yet-disabled* tab (the same
  -- "skip: is_active_tab_registered" no-op as before), and the real, delayed
  -- `main.disable()` then fired *after* everything else (including a
  -- `plugins/navigation.lua`-driven `resize()` that had, by coincidence, already
  -- rebuilt correct padding) had already settled -- tearing that correct padding back
  -- down and leaving only the dashboard and the panel, no padding at all. Confirmed by
  -- instrumenting the public `enable`/`disable` functions directly and dumping the
  -- window list before/after each call, live.
  --
  -- Fixed properly by branching on exactly the condition that made `enable()` a no-op,
  -- rather than fighting the public API's own async behaviour: when the tab is still
  -- registered (the race outcome above), correct no-neck-pain's own "curr" directly
  -- via its (pinned, internal, but already-read-and-relied-upon-elsewhere-in-this-file)
  -- `state` module, then force a synchronous rescan via the *private*, undebounced
  -- `main.init()` -- the exact same function `enable()` itself would have called next
  -- had it not skipped. When the tab is genuinely not registered (the disable-cascade
  -- already ran, task 15.2's original, documented case), `enable()` does its own full,
  -- fresh registration exactly as before. Re-confirmed live, same method (direct
  -- `_G.NoNeckPain.state` inspection before/after): `curr` is the dashboard window and
  -- `integrations.fondue_claude_panel.id` is the panel's own window id afterward,
  -- every time, across every race outcome this investigation could actually trigger,
  -- with no extra close/recreate churn on the padding windows beyond what a genuine
  -- state change (a real new "curr") requires.
  local nnp_state = require("no-neck-pain.state")
  local registered = nnp_state:is_active_tab_registered()
  if registered then
    nnp_state:set_side_id(dashboard_win, "curr")
    pcall(require("no-neck-pain.main").init, "fondue_task15")
  else
    pcall(require("no-neck-pain").enable, "fondue_task15")
  end

  -- Task 21 fix (found in interactive `/verify`, twelfth pass): 20.2's own fix above
  -- did not actually resolve the user's report. Re-investigated with a genuinely real
  -- pty (real inter-keystroke delays, a real `vim.fn.confirm()` dialog answered with a
  -- real keystroke after a real reaction delay -- not a mocked return value -- and a
  -- real, live `claude` CLI process behind the panel, via R-1/R-3's own documented
  -- `-p`/`-n`-plus-held-open-stdin technique, standing in for a fully interactive
  -- session this sandbox's own trust-dialog restriction still rules out), which
  -- reproduced the user's exact reported symptom byte-for-byte (`29/66/15/112`-shaped:
  -- an orphaned pad between the dashboard and the panel, the panel ballooned) on the
  -- very first attempt, and again identically on a second, independent run.
  --
  -- The reproduction's own internal-state log shows this happened via the *registered
  -- == false* branch above -- `enable("fondue_task15")`, task 15.2's original,
  -- "always assumed fine" case, completely untouched by 20.2's own fix, not the
  -- `registered == true` branch 20.1/20.2 investigated. So the real, dominant bug was
  -- never the race between which branch runs; it is a bug in `enable()`'s own fresh
  -- registration path when it runs while the panel is already on screen but not yet
  -- part of no-neck-pain's state (exactly this guard's own case, every time it fires).
  --
  -- Root cause, read directly from `no-neck-pain.nvim`'s own `main.init`/`ui.lua`
  -- (not guessed): a fresh `enable()` creates *both* the left and right padding
  -- windows in the same pass (no prior "left"/"right" registration survives
  -- `main.disable()`). `main.init()` only calls `ui.move_sides()` (which physically
  -- relocates a side window to the true screen edge via `wincmd H`/`L`) when its own
  -- `determine_layout_action()` sees *exactly one* newly created side
  -- (`single_new_side = new_left ~= new_right`); with both created at once, that XOR
  -- is false, so `move_sides()` never runs for either side. The freshly created right
  -- padding window is therefore left exactly where a plain `nvim_open_win(...,
  -- split = "right")` puts it -- immediately right of "curr" (the new dashboard) --
  -- rather than at the true right edge, past the already-there Claude panel. Since the
  -- panel sits further right still, this produces exactly the reported orphaned pad,
  -- sitting between the dashboard and the panel instead of past it.
  --
  -- Separately, and independently: `ui.get_side_width()` sizes no-neck-pain's own pad
  -- by *reading* a registered integration's current width (`nvim_win_get_width`) and
  -- subtracting it from the available budget -- it never *writes* to an integration's
  -- width. Vim's own automatic window-layout reflow, triggered when `main.disable()`
  -- (above) closed the old padding windows a moment earlier, already freely resizes
  -- every window sharing that row, including the panel, before any of this runs --
  -- confirmed directly, live: the panel's own width had already changed from this
  -- guard's own real reproduction. Nothing in no-neck-pain's own `enable`/`init` path
  -- ever corrects it back to `split_width_percentage`, so it stays ballooned.
  --
  -- Fixed here, not in the pinned plugin, and using only its already-established
  -- points of contact (`state`, `main.init`) plus plain, public Vim APIs -- not by
  -- reaching further into `no-neck-pain.ui`'s own private functions, which this
  -- integration does not otherwise touch:
  --  1. Explicitly resize the panel back to its own configured
  --     `split_width_percentage` (read from claudecode.nvim's own effective
  --     `terminal` config, the same source its own provider code uses, rather than
  --     hardcoding the 0.30 default here) *before* rescanning, so the next
  --     `ui.get_side_width("right")` computation -- triggered by the extra
  --     `main.init()` call below -- sees the panel's real, correct width, not
  --     whatever Vim's own reflow momentarily left it at.
  --  2. Re-run `main.init()` once more so the right pad's width is recomputed
  --     against that corrected panel width.
  --  3. Explicitly move the right pad to the true screen edge with a plain `wincmd L`
  --     (exactly what no-neck-pain's own `ui.move_sides()` would have done, had its
  --     `single_new_side` condition been met), restoring the width `wincmd L`'s own
  --     resplit resets, the same width-preservation step `ui.move_sides()` itself
  --     takes.
  -- Left side is not touched: this guard's own dashboard content is what "curr"
  -- always is here, so there is no left-side integration for the same problem to
  -- apply to, and 20.1's own fresh-baseline comparison never found a left-side
  -- version of this symptom.
  do
    local panel = panel_window()
    if panel and vim.api.nvim_win_is_valid(panel) then
      local ok_term, terminal_module = pcall(require, "claudecode.terminal")
      local pct = (ok_term and terminal_module.defaults and terminal_module.defaults.split_width_percentage) or 0.30
      local correct_width = math.floor(vim.o.columns * pct)

      -- Correct the panel's own width unconditionally, whether or not a separate
      -- right-side padding window currently exists: this fix's own first version only
      -- did this inside the `right_id` branch below, which missed narrower terminals
      -- where no-neck-pain decides there is no room for a padding window on either
      -- side at all (task 17/18's own "too narrow" behaviour) -- confirmed live, at
      -- 160 columns specifically: `right_id` was `nil` throughout (the correct,
      -- expected no-padding outcome at that width), so the panel's width was never
      -- rechecked at all and stayed wrongly ballooned regardless.
      if vim.api.nvim_win_get_width(panel) ~= correct_width then
        vim.api.nvim_win_set_width(panel, correct_width)
        pcall(require("no-neck-pain.main").init, "fondue_task15:panel_width_fix")
      end

      local right_id = nnp_state:get_side_id("right")
      if right_id and vim.api.nvim_win_is_valid(right_id) and right_id ~= panel then
        local wins = vim.api.nvim_tabpage_list_wins(vim.api.nvim_win_get_tabpage(right_id))
        if wins[#wins] ~= right_id then
          local pad_width = vim.api.nvim_win_get_width(right_id)
          vim.api.nvim_win_call(right_id, function()
            vim.cmd("wincmd L")
          end)
          -- `wincmd L`'s own resplit does not just reset the *moved* window's width
          -- (the reason `ui.move_sides()` restores it too, above) -- confirmed live,
          -- the hard way, in this fix's own first attempt: it can also redistribute
          -- space from whichever window the move took columns from, which here is
          -- the panel (sharing the same row), leaving it a few columns off
          -- `split_width_percentage` again even though it was set correctly, right
          -- above, moments earlier. Re-asserting both widths after the move, in this
          -- order, is what actually holds; asserting only the moved pad's own width
          -- (matching `ui.move_sides()`'s own scope) was not enough on its own.
          if vim.api.nvim_win_is_valid(right_id) then
            vim.api.nvim_win_set_width(right_id, pad_width)
          end
          if vim.api.nvim_win_is_valid(panel) then
            vim.api.nvim_win_set_width(panel, correct_width)
          end
        end
      end

      -- One further, later re-assertion: `plugins/navigation.lua`'s own, pre-existing
      -- `apply_centred_width()` (tasks 17/18, unrelated to this guard) is independently
      -- deferred 50ms off the same `WinEnter`/`WinNew`/`BufWinEnter` flurry this
      -- function's own window creation/moves fire, and calls the public, further-
      -- debounced `no-neck-pain.resize()` -- which can still be in flight, or not yet
      -- even scheduled, at the point this function returns. Confirmed live: even after
      -- the immediate re-assertions above, the panel's width could still drift a few
      -- columns off `split_width_percentage` again shortly afterward (observed 67 -> 74
      -- at 225 columns, i.e. a real but much smaller residual than the original
      -- 67 -> 109-112 balloon this task was chasing, not eliminated by this comment
      -- alone) once that separate cascade finally runs. Rather than trying to make this
      -- function's own corrections race that unrelated one to the wire, re-check and
      -- reassert once more after it has had time to settle (`apply_centred_width`'s own
      -- 50ms defer, plus margin for whatever it schedules next) -- this is a genuinely
      -- separate finding from the one this task set out to fix, not fully chased to a
      -- root cause of its own within this pass; see this task's own write-up for the
      -- honest confidence level on this specific part.
      vim.defer_fn(function()
        if vim.api.nvim_win_is_valid(panel) and vim.api.nvim_win_get_width(panel) ~= correct_width then
          vim.api.nvim_win_set_width(panel, correct_width)
        end
      end, 120)
    end
  end
end

local ALWAYS_ENDS_NVIM = { qa = true, qall = true, wqa = true, xa = true }
-- Task 26.2 fix (QA's adversarial re-check, Part B, 2026-09-30, Critical, separate from
-- and unrelated to 26.1's scrollbar fix): `xit` was simply missing from this table --
-- `GUARDED_PANEL_CLOSE_COMMANDS`/`GUARDED_DASHBOARD_CLOSE_COMMANDS` already both include
-- it, but this original D5 table never did, with no comment anywhere justifying leaving it
-- out (unlike `close`/`clo`, deliberately excluded just below for a documented, empirically
-- confirmed reason). `:xit` is simply the unabbreviated spelling of `:x` (`:help :x`: "Like
-- `:wq`, but write only when changes have been made" -- `:xit` is explicitly documented as
-- the same command under its long name), not a `:close`-shaped command: it does NOT hit
-- `close`/`clo`'s own `E444` protection (Neovim does not refuse an `:xit` that would close
-- the last window -- confirmed empirically, live, the same way `:x` itself was confirmed:
-- an ordinary last window with the panel merely hidden and a session connected, `:xit`
-- writes if modified and then genuinely quits, byte-for-byte the same as `:x`), so this is
-- a plain one-line omission, not a second copy of that exclusion's own reasoning. Left out
-- before, `:xit` on an ordinary last window with the panel hidden silently ended Neovim
-- with a connected session, 100% deterministically, independent of 26.1's scrollbar issue.
local GUARDED_QUIT_COMMANDS = { q = true, quit = true, wq = true, x = true, xit = true, qa = true, qall = true, wqa = true, xa = true }

-- Task 15's own guarded set: only the single-window-closing commands, never the `qa`
-- family (those always end Neovim outright -- D5's `ALWAYS_ENDS_NVIM` already owns that
-- case unconditionally, panel included -- so there is never a "panel left alone" state
-- to reach from them), plus `:close`/`:clo`, which `GUARDED_QUIT_COMMANDS` above has no
-- reason to include (it can never end Neovim -- Neovim refuses a `:close` that would
-- close the last window, `E444` -- so D5 never needed it) but which this guard does care
-- about, per task 15.1's own "`:q`, `:close`, etc." wording.
local GUARDED_WINDOW_CLOSE_COMMANDS = { q = true, quit = true, wq = true, x = true, close = true, clo = true }

-- Task 23.2's new, unconditional trigger (b): `:q`/`:quit`/`:close`/`:clo`/`:x`/`:xit`
-- while the *current* window is specifically the panel's own window -- directly closing
-- it. `:wq` is still deliberately left out: confirmed empirically (`E382: Cannot write,
-- 'buftype' option is set`, state completely unchanged) that it errors on a terminal
-- buffer, exactly as task 23's original comment assumed. `:x`/`:xit` were *wrongly*
-- assumed to behave the same way and were excluded here on that basis -- task 24's
-- adversarial QA pass found this to be empirically false: `:x` only writes when the
-- buffer is modified, a terminal buffer is essentially never "modified" in Vim's sense,
-- so `:x` on the panel's own window silently proceeded exactly like an unguarded `:q`
-- (confirmed live: the panel's window closed with zero warning, while the session and
-- its scratch buffer survived untouched thanks to `bufhidden = "hide"`, reachable again
-- via `Space a a` -- recoverable, but the guard's own promised coverage was silently
-- skipped). `:x`/`:xit` are included here now for that reason, not left out.
local GUARDED_PANEL_CLOSE_COMMANDS = { q = true, quit = true, close = true, clo = true, x = true, xit = true }

-- Task 25's own guarded set, for closing the dashboard/start-screen window itself: the
-- same commands as `GUARDED_PANEL_CLOSE_COMMANDS` above, for the same reason -- `:wq` is
-- deliberately left out here too, confirmed empirically (`E382: Cannot write, 'buftype'
-- option is set`), the dashboard's own scratch buffer sharing the exact same
-- "can't be written" shape as the panel's own terminal buffer. Referencing the same
-- table (not duplicating its values) rather than reusing `GUARDED_PANEL_CLOSE_COMMANDS`
-- directly under its own name at the new call site, since this is a genuinely different
-- trigger condition (`closing_dashboard_leaves_only_panel()`, not "is the current window
-- the panel") even though the command set happens to coincide exactly.
local GUARDED_DASHBOARD_CLOSE_COMMANDS = GUARDED_PANEL_CLOSE_COMMANDS

--- Task 23 (user-directed design correction, 2026-09-30): explicitly, deterministically
--- ends the running Claude session, rather than relying on Neovim's own quit mechanics
--- to end it as an incidental side effect of whichever windows a quit command happens to
--- close. Confirmed directly by reading the installed, pinned `claudecode.nvim` source
--- (commit `2390c6e45c4789072c293ac69de051d169668b29`) -- not assumed from either
--- function's name, per this task's own instruction:
---
--- - `require("claudecode").stop()` (`claudecode/init.lua`) only stops claudecode.nvim's
---   own local WebSocket server, removes its lock file, and disables selection tracking
---   -- its body never references the terminal or the underlying `claude` CLI process at
---   all. Calling it alone leaves an already-running `claude` process completely
---   untouched, just disconnected from the IDE side -- NOT "cleanly ending the
---   underlying process," despite what the name suggests. It runs synchronously (no
---   deferred/scheduled work anywhere in its body) and is safe to call even when nothing
---   is running (`M.state.server == nil`): it just returns `false, "Server not running"`,
---   no error thrown, so no connected-check is needed before calling it here.
--- - The process only actually ends via `require("claudecode.terminal").close()`
---   (`claudecode/terminal.lua` -> the snacks provider's own `M.close()` ->
---   `Snacks.win`'s own `Win:close()`, all read directly, not assumed): the panel's
---   terminal buffer is opened with no explicit `opts.buf`/`opts.file`
---   (`plugins/claude.lua`), which `Snacks.win`'s own `open_buf()` handles by calling
---   `self:scratch()` -- confirmed by reading `snacks/win.lua` directly, this makes
---   `self.buf == self.scratch_buf`, which is exactly the condition `Win:close()` checks
---   before unconditionally force-deleting that buffer (`nvim_buf_delete(buf,
---   { force = true })`). Neovim itself terminates a terminal buffer's job the instant
---   its buffer is force-deleted -- the same native mechanism any `:bd!` on any terminal
---   buffer already relies on, nothing claudecode-specific. This also closes the window
---   first if one is currently open, and works correctly with none open at all (the
---   panel-hidden case, D5's original scenario): `self.win` being `nil` at that point
---   just skips the window-close branch, the buffer deletion still runs regardless --
---   confirmed live (see design.md's D5 correction) that this is genuinely headless-safe,
---   not merely read as such. `Win:close()` only defers its own work via `vim.schedule`
---   when called from inside a `WinClosed` handler or when the immediate close throws a
---   recoverable, retryable Vim error (a command-line window open, or a text-lock) --
---   neither applies here, called synchronously from `CmdlineLeave`; confirmed live this
---   runs to completion before this function returns, not merely assumed from the source.
---
--- Calling `terminal.close()` before letting a `qa`-family command proceed is also what
--- lets task 22.4's own, separately-found bug (`:qa`/`:qall`/`:wqa`/`:xa` while the
--- *current* window is any terminal-job buffer genuinely begins exiting, kills only that
--- window's job, then silently stops) be sidestepped rather than chased further: by the
--- time the original command actually runs, the terminal-job buffer that was colliding
--- with Neovim's own multi-window teardown has already been closed and deleted by this
--- function, synchronously, moments earlier, inside this same `CmdlineLeave` callback.
local function stop_claude_session()
  local ok_term, terminal_module = pcall(require, "claudecode.terminal")
  if ok_term then
    pcall(terminal_module.close)
  end
  local ok_cc, claudecode = pcall(require, "claudecode")
  if ok_cc then
    pcall(claudecode.stop)
  end
end

--- The raw, shared `vim.fn.confirm()` call both guards below build on: `confirm_label`
--- names the affirmative button (e.g. "Quit" for D5, "Close" for task 15/23) so each
--- dialog reads naturally for what it is actually about to do. `cancel_label` defaults
--- to "Cancel" (D5's own, original wording) but can be overridden when that would
--- collide with `confirm_label`'s own highlighted letter -- see task 15.6's own fix for
--- why this needed to become a parameter rather than staying hardcoded. Returns true
--- when the user picked the affirmative choice, false otherwise -- no `v:event.abort`
--- side effect here; callers decide what confirming/declining should actually do (task
--- 23's new panel-close trigger needs to abort on *both* outcomes, unlike D5/task 15's
--- own guards, which only abort on decline -- see `confirm_or_abort()`/
--- `confirm_then_always_abort()` below).
---
--- Task 15.6's own finding, still true here: `vim.fn.confirm()`'s `&`-prefixed-letter
--- convention highlights the *first* occurrence of the marked letter in each choice as
--- that choice's hotkey, and Vim does not itself check for or warn about a clash between
--- choices -- it just silently leaves both choices answerable by the same keypress.
local function confirm(question, confirm_label, cancel_label)
  local choice = vim.fn.confirm(question, string.format("&%s\n&%s", confirm_label, cancel_label or "Cancel"), 2)
  return choice == 1
end

--- The Vimscript-assignment detail below is D5's own empirical finding: `vim.v.event.
--- abort = true` (the natural Lua spelling) does NOT work -- `vim.v.event` hands back a
--- snapshot copy on each access, so writing to it is silently discarded and the command
--- proceeds anyway despite the assignment. `vim.cmd("let v:event.abort = v:true")`
--- (going through Vimscript's own assignment, which mutates the real, live dictionary)
--- is what actually cancels it -- confirmed by testing both side by side,
--- unconditionally, before trusting either.
local function abort_cmdline()
  vim.cmd("let v:event.abort = v:true")
end

--- D5's and task 15's own shape: a cancellable `vim.fn.confirm()` that aborts the
--- in-flight cmdline command only when the user declines. Returns true when the user
--- confirmed (the original command should proceed, completely untouched); false when
--- declined (already aborted).
local function confirm_or_abort(question, confirm_label, cancel_label)
  if confirm(question, confirm_label, cancel_label) then
    return true
  end
  abort_cmdline()
  return false
end

--- Task 23's new panel-close trigger's own shape: unlike `confirm_or_abort()` above,
--- this aborts the original typed command *regardless* of the user's choice. Used when
--- confirming already fully achieves everything the original command would have done
--- (here, `stop_claude_session()` above already closes the panel's own window as part of
--- ending its process) -- by the time the original `:q`/`:close` would otherwise run, the
--- window it was typed against is already gone, so letting it proceed afterward would
--- incorrectly act on whatever different window is now current instead. Returns true
--- when the user confirmed (the caller should still call `stop_claude_session()` itself;
--- this helper only owns the dialog and the abort, not the session-ending action, so it
--- reads the same as `confirm_or_abort()` at call sites), false when declined.
local function confirm_then_always_abort(question, confirm_label, cancel_label)
  local confirmed = confirm(question, confirm_label, cancel_label)
  abort_cmdline()
  return confirmed
end

--- The quit-time warning (FR-043, design.md D5).
---
--- Two mechanisms were tried and rejected during implementation before this one (see
--- design.md's Spike results for the full write-up, both confirmed empirically, not
--- assumed):
--- 1. Raising an error from a `QuitPre`/`ExitPre` autocommand, as design.md originally
---    proposed: does NOT cancel the pending `:q`/`:qa` in this Neovim version -- the
---    quit completes regardless, error message notwithstanding.
--- 2. `cnoreabbrev` replacing the typed command with a call to this function: works in
---    isolation, but this project's own command-line completion (`blink.cmp`'s
---    `cmdline` integration, from an earlier change) accepts a typed command by reading
---    `getcmdline()` and running it directly on `<CR>`, bypassing Neovim's native
---    abbreviation-expansion step entirely -- so the abbreviation silently never fired
---    once that plugin was active, confirmed by testing a trivial, unrelated abbreviation
---    the same way.
---
--- What works: `CmdlineLeave` (`:help CmdlineLeave`), which fires whenever a command-line
--- editing session ends -- via `<CR>`, and also however blink.cmp's own acceptance path
--- gets there -- and exposes a genuinely cancellable `v:event.abort` (mutable
--- false -> true) checked by Neovim itself before the command runs, regardless of how
--- `<CR>` was handled. Leaving it `false` lets the original command proceed completely
--- untouched, so there is no need to re-issue it. (The `v:event.abort`-must-be-set-via-
--- Vimscript detail this required is now documented once, on `confirm_or_abort()` above,
--- since task 15's guard below shares this same mechanism rather than reinventing it.)
---
--- Known gap, accepted rather than chased further (matches AD-17's "document, don't
--- block" spirit): `ZZ`/`ZQ` (the normal-mode write-and-quit/quit mnemonics) do not go
--- through command-line editing at all, so this guard does not see them. `!`-forced
--- variants (`:q!`, `:qa!`, ...) are also deliberately left unguarded, matching Neovim's
--- own convention that a bang bypasses safety prompts (e.g. the unsaved-changes check) --
--- and are naturally unguarded here too, since the typed text no longer matches a plain
--- entry in `GUARDED_QUIT_COMMANDS`. **This same accepted gap covers task 15's guard and
--- task 23's own new panel-close trigger below too, explicitly, not just this one**:
--- `ZZ`/`ZQ`/`<C-w>` (and any other normal-mode window-closing command) never reach
--- `CmdlineLeave` either, so closing your last code window (or the panel's own window)
--- that way while a session is connected is just as unguarded as quitting that way
--- already was -- the same cmdline-only scope, for the same reason, not a narrower or
--- wider gap that happens to have gone unstated.
local function on_cmdline_leave()
  if vim.v.event.abort then
    return -- already aborted for some other reason (e.g. Ctrl-C); nothing to add
  end
  local word = vim.trim(vim.fn.getcmdline())

  local ok, claudecode = pcall(require, "claudecode")
  local connected = ok and claudecode.is_claude_connected()
  if not connected then
    return
  end

  if GUARDED_QUIT_COMMANDS[word] then
    local ends_nvim = ALWAYS_ENDS_NVIM[word] or is_last_window()
    if ends_nvim then
      -- Task 23: on confirming, explicitly stop the session first (see
      -- `stop_claude_session()` above for why `require("claudecode").stop()` alone is
      -- not enough), THEN let the original command proceed exactly as before (do not
      -- abort) -- `stop_claude_session()` runs synchronously and completes before this
      -- function returns, so by the time Neovim actually executes the typed `:qa`/`:q`/
      -- etc., the session (and, for the qa-family-from-a-terminal-job-window case, the
      -- specific terminal buffer that was colliding with Neovim's own multi-window
      -- teardown) is already gone.
      if
        confirm_or_abort(
          string.format('Quit Neovim? The Claude session "%s" is still running.', M.session_name()),
          "Quit"
        )
      then
        stop_claude_session()
      end
      return
    end
  end

  -- Task 23.2's new, unconditional trigger (b): closing the panel's own window
  -- directly, via a genuine quit/close command (not the hide keybinding, `Space a a`,
  -- which FR-002 already guarantees never stops the session), while a session is
  -- connected -- regardless of whether this would end Neovim (it usually does not:
  -- reached here only once the branch above has already established this particular
  -- command would not end Neovim on its own). No floating-window/cascade prediction is
  -- needed at all for this case, unlike the branch above: it's a direct check of "is the
  -- panel open (it is -- it's the current window) and connected" plus "is this command
  -- inherently going to close it." `confirm_then_always_abort()` (not `confirm_or_abort()`)
  -- is used deliberately: `stop_claude_session()` on confirm already closes this exact
  -- window as part of ending the process, so the original `:q`/`:close` must never be
  -- allowed to run afterward regardless of the answer -- letting it proceed would close
  -- whatever different window is current by then instead.
  if GUARDED_PANEL_CLOSE_COMMANDS[word] and panel_window() == vim.api.nvim_get_current_win() then
    if
      confirm_then_always_abort(
        string.format('Close the Claude panel? The session "%s" will be stopped.', M.session_name()),
        "Close",
        "Keep editing"
      )
    then
      stop_claude_session()
      -- Minor UX polish, found while testing this trigger (not itself a safety
      -- concern): once the panel's own buffer is force-deleted, Neovim's own
      -- post-close focus reassignment can land on one of no-neck-pain's padding
      -- windows rather than the code the user almost certainly wants back --
      -- confirmed live (layout itself stays correctly centred, symmetric, no
      -- stale/lopsided pad; only the *focus* choice is the rough edge). Reuses
      -- `fallback_focus_target()` (task 14) unchanged: it already skips padding
      -- and floating windows and picks the first real window, exactly what's
      -- needed here too. Passing `nil` for `panel_win` is correct: the panel's
      -- window id from before this close no longer refers to anything, so it
      -- can never accidentally match a genuinely different real window.
      local target = fallback_focus_target(nil)
      if target then
        vim.api.nvim_set_current_win(target)
      end
    end
    return
  end

  -- Task 15: a separate guard, only reached once both branches above have established
  -- this particular command would neither end Neovim nor directly close the panel's own
  -- window (see `would_lose_last_code_window()`'s own comment for why that is correct
  -- and still not the right outcome on its own).
  if GUARDED_WINDOW_CLOSE_COMMANDS[word] and would_lose_last_code_window() then
    -- Task 21's own finding: `confirm_or_abort()` blocks here, inside this
    -- `CmdlineLeave` handler, *before* the real `:q` this guard is about has actually
    -- run (Neovim only runs the original command after `CmdlineLeave` returns with
    -- `v:event.abort` left false) -- so the `vim.defer_fn(..., 50)` below starts
    -- ticking in parallel with, not strictly after, `:q`'s own close and no-neck-pain's
    -- reaction to it. `fallback_to_start_screen()`'s own fix (below it, task 21) does
    -- not depend on winning that race cleanly -- it re-checks and corrects state
    -- directly rather than assuming a fixed ordering -- but this is why 50ms was never
    -- a safe-by-construction margin on its own.
    if
      confirm_or_abort(
        "Close this file? Only the Claude panel would be left visible (the session will keep running).",
        "Close",
        "Keep editing"
      )
    then
      vim.defer_fn(fallback_to_start_screen, 50)
    end
  end

  -- Task 25: closing the dashboard/start-screen window itself, while the Claude panel
  -- is open and connected and nothing else real remains (see
  -- `closing_dashboard_leaves_only_panel()`'s own comment for the root cause: neither
  -- D5's own `is_last_window()` above -- correctly "no", the panel's window survives --
  -- nor task 15's own `would_lose_last_code_window()` just above -- which never even
  -- looks at the panel for a dashboard close, since the dashboard is not "a code
  -- window" -- ever asked this question, so it fell through both with zero `confirm()`
  -- calls). Confirmed with the user directly: this should behave like closing your last
  -- window entirely, not like task 15's own fall-back-to-the-dashboard case -- there is
  -- nowhere further to fall back to from the dashboard itself. Reuses the exact same
  -- explicit-stop-then-quit mechanism and dialog wording as D5's own original trigger
  -- above (`confirm_or_abort`, not task 23.2's `confirm_then_always_abort`): on confirm,
  -- `stop_claude_session()` runs synchronously and closes the panel's own window as part
  -- of ending its process (task 23.1's own finding), and the original `:q`/`:close`/etc.
  -- is left to proceed (NOT aborted) -- unlike task 23.2's panel-close trigger, the
  -- window this command was typed against (the dashboard) is not the window
  -- `stop_claude_session()` itself closes, so it still needs to run its course. It then
  -- closes the dashboard's own window too; with both the panel and the dashboard gone,
  -- only no-neck-pain's own padding is left in the tab, and its own `QuitPre`-driven
  -- force-quit cascade (design.md's D5 padding-cascade note) genuinely ends Neovim.
  if GUARDED_DASHBOARD_CLOSE_COMMANDS[word] and closing_dashboard_leaves_only_panel() then
    if
      confirm_or_abort(
        string.format('Quit Neovim? The Claude session "%s" is still running.', M.session_name()),
        "Quit"
      )
    then
      stop_claude_session()
    end
  end
end

--- Registers the `CmdlineLeave` guard (D5's quit warning and task 15's panel-only
--- guard, both handled by `on_cmdline_leave` above). Safe to call more than once:
--- `nvim_create_autocmd` with a named group clears the previous registration first.
function M.setup()
  vim.api.nvim_create_autocmd("CmdlineLeave", {
    pattern = ":",
    group = vim.api.nvim_create_augroup("fondue_claude_quit_warning", { clear = true }),
    desc = "Warn (cancellably) before a quit/close that would end or hide-away a running Claude session's code",
    callback = on_cmdline_leave,
  })
end

return M
