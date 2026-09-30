-- Moving around a project: fuzzy finding, the file tree, the centred layout, sessions
-- and the start screen, project-wide diagnostics and TODOs, and search-and-replace.
--
-- snacks.nvim itself is declared in plugins/editing.lua (its bigfile, indent and words
-- modules); this file adds its picker, explorer and dashboard modules through a
-- second spec entry for the same plugin. lazy.nvim merges every
-- spec entry for one plugin by calling each entry's `opts` function in turn, passing
-- the table built so far, so both entries mutate and return that same table (accept
-- `opts`, add keys, return it) rather than each returning a fresh table of its own,
-- which would silently discard whatever the other entry added.
--
-- The explorer and dashboard modules are configured but left `enabled = false`: their
-- own automatic behaviour (the explorer replacing a directory buffer on BufEnter, the
-- dashboard showing itself on UIEnter) would otherwise race fondue.lib.session, which
-- must be the one to decide what a `nvim`/`nvim .` start actually shows. Calling
-- `Snacks.explorer.open/reveal` and `Snacks.dashboard.open` still works with the
-- module "disabled": that flag only gates the automatic hooks, not the functions.

-- Finding 17.1 (interactive `/verify`, eighth pass): with a text file open and no other
-- split, the centred content column measured only 67 columns wide on a smaller
-- terminal -- confirmed with the user as too narrow; REQUIREMENTS.md FR-006 (v1.24) now
-- requires the centred content column never be narrower than 80 columns while the
-- terminal is wide enough to allow it, with padding shrinking first (down to zero) to
-- protect that width, and only content itself shrinking below 80 once the terminal is
-- too narrow for 80 columns of content plus any padding at all.
--
-- no-neck-pain's own `width` option is *not* the padding itself: confirmed with real
-- window geometry (`nvim_win_get_width`, headless-embed with a real column count set
-- before plugin load, matching the method 16.1/16.6 already used elsewhere in this
-- change) against the pinned plugin's own `ui.get_side_width`, that it computes each
-- side's actual rendered padding as `floor((vim.o.columns - config.width) / 2)`, and the
-- real content column left over is `vim.o.columns - 2*padding - 2` (2 columns lost to
-- the window separators either side of the content column -- the exact accounting
-- 16.1/16.6 already established: a 225-column terminal with `width = 75` measured
-- left = right = 75, content = 73, matching `225 - 2*75 - 2`). Reproduced live: at 205
-- columns (a plausible real terminal width), the previous literal-third formula
-- (`width = floor(205/3) = 68`) rendered padding = 68, content = 67 -- the user's exact
-- reported number. Because `width` and padding are related through this
-- (non-invertible-by-inspection) formula rather than being the same value, protecting a
-- minimum *content* width means solving for the `width` to hand no-neck-pain, not
-- passing a padding value straight through.
--
-- Finding 18.2 (interactive `/verify`, ninth pass): the 80-column target above measured
-- *raw window width*, not usable text width -- a real code buffer's sign column, line
-- numbers and fold column sit inside that window, so the actual text area came out
-- narrower than 80 (the user measured 75). REQUIREMENTS.md FR-006 (v1.25) now requires
-- the 80-column minimum to mean 80 columns of *text*, with the gutter sitting outside
-- that 80 and widening the window further. The actual width/content-area arithmetic
-- (including the 80-plus-gutter target) now lives in `lib/centred_width.lua`, shared
-- with `lib/session.lua`'s dashboard-pane sizing (see that module and design.md's
-- "Findings 18.1-18.2" for the full write-up of why a shared module exists at all, not
-- just a local function here).
local centred_width = require("fondue.lib.centred_width")

-- Every filetype known to be a side integration, floating overlay, or no-neck-pain's
-- own padding, rather than the buffer actually being centred -- excluded from gutter
-- measurement (below) the same way `plugins/navigation.lua`'s own `integrations` table
-- (further down this file) already lists them for no-neck-pain's benefit. A window
-- showing one of these when a resize/focus-change fires is not the window whose gutter
-- FR-006's 80-column target is about; `last_known_gutter` (below) is reused instead of
-- guessing 0, so a resize while focus happens to be elsewhere does not wrongly relax
-- the protected width for the real content buffer sitting underneath.
local NON_CONTENT_FILETYPES = {
  ["no-neck-pain"] = true,
  fondue_claude_panel = true,
  snacks_terminal = true,
  snacks_picker = true,
  snacks_layout_box = true,
  snacks_picker_list = true,
  snacks_picker_input = true,
}

local last_known_gutter = 0

--- The gutter width (sign column + line numbers + fold column) of the window currently
--- showing the buffer being centred -- task 18.2. `getwininfo().textoff` is Neovim's own
--- computed "columns occupied by any foldcolumn, signcolumn and line number in front of
--- the text", used directly rather than re-deriving it from `signcolumn`/`numberwidth`/
--- `foldcolumn` by hand: it already accounts for things that change the real rendered
--- width without changing any of those settings (a long file needing a wider number
--- column than `numberwidth` alone specifies, signs actually present under an `auto`
--- signcolumn, etc.) -- confirmed available on the pinned Neovim (`:h getwininfo()`).
--- The dashboard genuinely has none (`snacks.nvim`'s own dashboard style sets
--- `number = false`, `signcolumn = "no"`), so this naturally returns 0 for it with no
--- special-casing needed (task 18.3's "unaffected" scenario).
---@return integer
local function current_gutter_width()
  local win = vim.api.nvim_get_current_win()
  local ok, config = pcall(vim.api.nvim_win_get_config, win)
  if not ok or config.relative ~= "" then
    return last_known_gutter -- a floating window (e.g. the test/run terminal): not it
  end
  local buf = vim.api.nvim_win_get_buf(win)
  if NON_CONTENT_FILETYPES[vim.bo[buf].filetype] then
    return last_known_gutter
  end
  local info = vim.fn.getwininfo(win)[1]
  if info then
    last_known_gutter = info.textoff
  end
  return last_known_gutter
end

--- Computes the `width` value to hand no-neck-pain, protecting `TARGET_TEXT_WIDTH`
--- columns of actual *text* (not raw window width) for whichever buffer is currently
--- being centred. Reads `vim.o.columns` and the current window's own gutter fresh each
--- time, so it is safe to call on every resize/focus-change rather than tracking any
--- state of its own beyond `last_known_gutter`'s own deliberate fallback above.
---@return integer
local function fondue_centred_width()
  return centred_width.no_neck_pain_width(vim.o.columns, current_gutter_width())
end

return {
  {
    "folke/snacks.nvim",
    opts = function(_, opts)
      opts.picker = { enabled = true }
      opts.explorer = { enabled = false, replace_netrw = false }
      opts.dashboard = {
        enabled = false,
        sections = {
          -- Finding 16.6 (interactive `/verify`, seventh pass): the user's own live
          -- geometry check (`nvim_win_get_width`/`nvim_win_get_position`) confirmed the
          -- three windows are genuinely evenly split (left = right, to the column) and a
          -- live `:hi WinSeparator guifg=Red` check confirmed the borders themselves are
          -- evenly spaced -- so this was never a no-neck-pain/split-width bug at all. The
          -- actual cause, confirmed by reading the installed `snacks.nvim`'s own
          -- `dashboard.lua`: each item in `sections` has its own `align` field
          -- ("left"|"center"|"right", `D:align()`), defaulting to "left" when unset --
          -- exactly what every entry here left unset. `D:render()` *does* already centre
          -- the dashboard's own content pane as a whole within the window (`self.col`,
          -- computed from `self.opts.width`, default 60), but that only centres the
          -- pane's outer box -- text left-aligned *within* that box still hugs the box's
          -- own left edge, which is what actually produced the visibly off-centre look in
          -- a content window wider than 60 columns (matching the user's own confirmed
          -- 73-column content window: a ~6-column pane margin on each side, then every
          -- menu line hugging the pane's left edge instead of filling it). `align =
          -- "center"` on every entry (the "header" ASCII art is already centred within
          -- its own text via `formats.header`, independent of this, but is given it too
          -- for consistency) makes each item's own content centre within the pane, so the
          -- two centring mechanisms compose into a dashboard that is genuinely centred in
          -- its window, not just pane-centred with left-hugging text inside. Verified
          -- headless by reading the rendered buffer's own lines directly
          -- (`nvim_buf_get_lines`): each non-blank line's leading and trailing whitespace
          -- (relative to the window's width) now differ by at most the unavoidable
          -- odd/even rounding of one column, at both a 73-column content width (the
          -- user's own reported figure) and this sandbox's own narrower default.
          { section = "header", align = "center" },
          { section = "keys", gap = 1, padding = 1, align = "center" },
          { section = "recent_files", limit = 8, padding = 1, align = "center" },
          { section = "startup", align = "center" },
        },
      }
      return opts
    end,
  },

  -- Centred layout: text sits in roughly the middle third of the window, kept current
  -- on resize.
  {
    "shortcuts/no-neck-pain.nvim",
    version = "^3",
    lazy = false, -- must be ready before the first buffer, so the very first file is centred too
    opts = function()
      return {
        width = fondue_centred_width(),
        -- "safe": debounced, so the start screen or a restored session settles first.
        autocmds = { enableOnVimEnter = "safe" },
        -- Finding 16.1/16.2 (interactive verification, pre-existing from `navigation`,
        -- confirmed unrelated to this change's own edits): with no statusline plugin in
        -- this configuration (there is none -- Neovim 0.12's own built-in default
        -- `statusline` is what renders everywhere: a non-empty global default with the
        -- filename, ruler and diagnostics segments, not the classic empty/ruler-only
        -- default older Neovims shipped), the padding windows' `laststatus=2` per-window
        -- statuslines showed that ordinary content (cursor position and, for an unnamed
        -- `buftype=nofile` buffer specifically, the literal string "[Scratch]") -- a
        -- real-looking statusline on what is supposed to be an empty visual margin.
        -- No-neck-pain does not touch `statusline` itself (checked its pinned source:
        -- neither `config.lua`'s `bufferOptionsWo` defaults nor `ui.lua` set it), so
        -- blanking it is this project's own responsibility, via the one `vim.wo`
        -- passthrough no-neck-pain already offers for exactly this purpose (`buffers.wo`,
        -- applied to both side windows -- see `ui.init_side_options`). A single space,
        -- not an empty string: a window-local `statusline` of `""` is Vim's own documented
        -- sentinel for "inherit the global value" (`:h 'statusline'`), which is exactly
        -- the rich default this needs to override, not fall through to -- confirmed with
        -- real window geometry (`nvim_get_option_value("statusline", { win = ... })`)
        -- that `""` left the padding windows showing the very same global default text,
        -- while `" "` genuinely renders blank.
        buffers = { wo = { statusline = " " } },
        -- Without this, no-neck-pain does not recognise snacks.picker's own windows (the
        -- file tree, opened on the left by plugins/navigation.lua's explorer config
        -- below) as a side panel: it treats them as ordinary content and tries to add
        -- its own centring padding pair around them too, on top of the pair already
        -- centring the real buffer. That produces extra, lopsided windows and can leave
        -- focus on one of them instead of the tree. `snacks_picker` is one of
        -- no-neck-pain's own named integrations, matched against a window's filetype;
        -- the sidebar layout snacks.picker opens for the explorer is actually three
        -- windows (an outer `snacks_layout_box`, the `snacks_picker_list`, and the
        -- `snacks_picker_input` prompt), so all three filetypes need registering here
        -- (no-neck-pain's integration matching is not limited to its own built-in
        -- names: any filetype can be added as a key, matched the same way).
        integrations = {
          snacks_picker = { position = "left" },
          snacks_layout_box = { position = "left" },
          -- The Claude panel (plugins/claude.lua): a real side panel, like the file
          -- tree above, so it must be named here too -- matching claudecode.nvim's own
          -- `terminal.split_side` ("right"). Its buffer filetype is deliberately
          -- overridden away from the shared "snacks_terminal" the test/run terminal
          -- (plugins/terminals.lua) gets, specifically so it can be named here without
          -- also catching that one, which is meant to be treated as ordinary
          -- full-window content, not padded as a side integration (D3/D2 in the design
          -- record).
          fondue_claude_panel = { position = "right" },
        },
      }
    end,
    config = function(_, opts)
      require("no-neck-pain").setup(opts)

      -- Finding 17.3 (interactive `/verify`, eighth pass, live resize path): the "too
      -- narrow for 80 columns of content plus any padding" case above passes no-neck-
      -- pain a `width` equal to `vim.o.columns`, which its own `ui.get_side_width`
      -- correctly refuses to *create* new padding for (`config.width >= vim.o.columns`
      -- returns 0). Confirmed live (headless-embed with a real column count, resizing an
      -- already-padded session down past this point, not just read from source) that
      -- the same 0 does *not* make `ui.create_side_buffers()`'s own re-check close a
      -- side that already exists from before the resize -- that re-check only closes a
      -- side when `get_side_width` returns exactly -1 or a too-small-but-positive value,
      -- never plain 0 -- so a stale, wrongly-sized padding window was left behind
      -- instead of being removed (reproduced: left = 56, content = 1, right = 1 after
      -- resizing a 300-column session straight down to 60 columns, rather than a single
      -- full-width window). Rather than patch the vendored plugin, this sidesteps the
      -- gap: when the computed width means no room for any padding, `disable()` no-neck-
      -- pain outright (its teardown removes both sides unconditionally, not through
      -- `get_side_width`) instead of asking it to `resize()` to a value it cannot act on
      -- correctly, then `enable()` it again once the terminal is wide enough for padding
      -- to return. `enable()` is itself a safe no-op when already enabled (checked
      -- against the pinned source: `event.skip_enable`'s `is_active_tab_registered`
      -- check); `disabled_for_width` still guards against calling `disable()` repeatedly
      -- on every resize event while the terminal stays narrow, since that repeated-call
      -- case was not checked against the pinned source and isn't needed here anyway.
      --
      -- Finding 18.1 (interactive `/verify`, ninth pass): confirmed live that this same
      -- "no-neck-pain silently drops padding it was asked to show" gap is not limited to
      -- the literal `width == columns` boundary above -- `ui.create_side_buffers()`'s own
      -- re-check (pinned source) *also* closes an *already-open* side outright the
      -- moment its recomputed padding is a small-but-positive value below its own
      -- `minSideBufferWidth` (default 10, `lib/centred_width.lua`'s
      -- `MIN_SIDE_BUFFER_WIDTH`) -- reproduced live at 90 columns: the naive 80-column
      -- target only needed a padding of 4 on each side, comfortably fitting the window,
      -- but no-neck-pain closed both sides anyway on the very next `resize()`, leaving
      -- the content window at the full 90 columns instead of the intended ~82.
      -- `lib/centred_width.lua`'s `no_neck_pain_width()` now snaps straight to "no room"
      -- (returns `columns`) whenever the padding it would otherwise ask for is inside
      -- that unrenderable range, so `width >= vim.o.columns` below already catches this
      -- case uniformly alongside the original one -- no separate check needed here.
      local disabled_for_width = false

      local function apply_centred_width()
        -- Finding 18.1's own 50ms defer (below) can land after Neovim has already
        -- started quitting -- confirmed live: `:qa` right after a `WinEnter`/
        -- `BufWinEnter` (e.g. a `:checkhealth` buffer opening and closing again) left
        -- this deferred callback still queued, and by the time it ran no-neck-pain's
        -- own tab was already torn down, so `resize()`/`enable()`/`disable()` (all of
        -- which call its `main.init()`) errored with "called the internal `init`
        -- method on a `nil` tab" instead of silently no-op'ing. `v:exiting` is
        -- `v:null` until Neovim genuinely starts exiting (`:h v:exiting`), so bailing
        -- out here whenever it is set avoids doing any layout work Neovim is about to
        -- discard anyway, on the one path (a deferred callback, not a direct autocmd
        -- callback) old enough to still be pending when that starts.
        if vim.v.exiting ~= vim.NIL then
          return
        end
        local columns = vim.o.columns
        local width = fondue_centred_width()
        if width >= columns then
          if not disabled_for_width then
            disabled_for_width = true
            pcall(require("no-neck-pain").disable)
          end
        else
          if disabled_for_width then
            disabled_for_width = false
            pcall(require("no-neck-pain").enable, "fondue_centred_width")
          end
          pcall(require("no-neck-pain").resize, width)
        end

        -- Finding 18.1: keep an already-open start screen's own dashboard pane in sync
        -- with the same content width, rather than leaving it at whatever fixed size it
        -- was given when it was first opened -- see `lib/session.lua`'s
        -- `resync_dashboard_pane_width()` and `lib/centred_width.lua` for why the
        -- dashboard needs telling about this at all. A no-op whenever no dashboard is
        -- currently open (checked there, not here).
        pcall(require("fondue.lib.session").resync_dashboard_pane_width, columns, width)
      end

      vim.api.nvim_create_autocmd({ "VimResized", "WinEnter", "BufWinEnter" }, {
        group = vim.api.nvim_create_augroup("fondue_centred_width", { clear = true }),
        desc = "Keep the centred column at roughly a third of the window width, "
          .. "protecting 80 columns of *text* (gutter-aware, task 18.2) for whichever "
          .. "buffer/window is current, and correctly tearing down padding entirely "
          .. "once the terminal is too narrow for any (tasks 17.1/17.3/18.1)",
        -- Deferred 50ms, not called inline or merely scheduled one tick: two separate
        -- reasons, both confirmed live, not assumed.
        --
        -- (1) `BufWinEnter` for a buffer being switched into the current window fires
        -- *before* that buffer's own window-local options are necessarily settled --
        -- confirmed directly for the dashboard specifically, whose `D:init()` calls
        -- `nvim_win_set_buf` (firing `BufWinEnter` synchronously, inline) *before* it
        -- applies its own `wo` (`number = false`, `signcolumn = "no"`) a few lines
        -- later in the same function -- so an inline recompute would measure the
        -- *previous* buffer's gutter, not the dashboard's genuine zero.
        --
        -- (2) A plain `vim.schedule()` (one tick, ~0ms) is not enough on its own either,
        -- specifically for the very first time this fires during a fresh start:
        -- no-neck-pain's own `enableOnVimEnter = "safe"` reaches its first real
        -- `enable()` through a *debounced* `BufEnter` handler of its own
        -- (`no-neck-pain/init.lua`, a 5ms debounce) -- so a same-tick recompute lands
        -- while `_G.NoNeckPain.state.enabled` is still unset, `resize()`'s own
        -- `ensure_plugin_enabled()` throws, the `pcall` around it swallows that
        -- silently, and the correctly-computed width is simply discarded -- confirmed
        -- live by instrumenting this exact callback: it computed the right value
        -- (`width = 82` for a 110-column, gutter-0 dashboard) on the very first call,
        -- yet `_G.NoNeckPain.config.width` stayed at the stale, gutter-5 value from
        -- initial `setup()` (`88`) afterwards, because that first call landed before
        -- no-neck-pain's own debounced enable had run at all -- and nothing else
        -- re-triggers this handler once the buffer stops changing, so it never
        -- self-corrected. 50ms is the same margin `lib/session.lua`'s own
        -- `focus_real_content` already uses for exactly this "comfortably past
        -- no-neck-pain's own 5ms debounce" reason -- reused here rather than a second,
        -- separately-chosen number.
        callback = function()
          vim.defer_fn(apply_centred_width, 50)
        end,
      })

      -- Finding 16.5 (interactive `/verify`, seventh pass, retested): after 16.2's fix
      -- (`buffers.wo.statusline = " "` above), a retest on the real interactive install
      -- still showed "All" in the right padding window's corner. Investigated before
      -- reapplying the same fix harder, per this task's own instruction:
      --   1. `vim.o.laststatus` -- checked directly (`nvim_get_option_value`, this
      --      config's real `fondue-verify` install): it is `2` (Neovim's own default,
      --      untouched anywhere in `core/`), not `3`. A global statusline would make a
      --      per-window `wo.statusline` override structurally unable to do anything, but
      --      that is not the situation here -- this is not a hard, unfixable constraint.
      --   2. Whether `no-neck-pain.nvim`'s own `resize()` (the `VimResized` handler just
      --      above) or its window-recreation path (`ui.create_side_buffers()`, on the
      --      pinned source) ever re-touches a padding window/buffer without reapplying
      --      `buffers.wo` -- read directly: `create_side_buffers()` only calls
      --      `ui.init_side_options()` (the function that applies `buffers.wo`) for a side
      --      that is not already tracked as valid, i.e. only on genuine creation, and
      --      `resize()`/`state:resize_win()` only ever change a window's *width*, never
      --      recreate it or touch its options. Tested this live and directly, not just
      --      read: a real pty (window size set before Neovim starts, matching a genuine
      --      interactive terminal) and, separately, a real `screen` session (closer still
      --      to genuine interactive rendering than a raw pty, since this investigation's
      --      own earlier finding -- 16.1 -- already showed a headless-embed harness can
      --      give a false reading for this exact area) -- across: an ordinary resize
      --      up/down, a resize that crosses `minSideBufferWidth` (closing and recreating
      --      the padding windows outright, not just resizing them), and opening/closing
      --      the real Claude panel (`fondue_claude_panel`, the one *other* named
      --      integration on the right side, so the most plausible thing to disturb the
      --      right padding specifically). In every one of these, queried live via
      --      `nvim_get_option_value("statusline", { win = ... })` immediately afterward,
      --      both padding windows kept (ordinary resize) or correctly regained (recreate
      --      cases) `statusline = " "` -- no case was found, live, where the option comes
      --      back wrong.
      -- Given (1) rules out a structural block and (2) could not be reproduced live
      -- despite substantially more faithful methods than the 16.3 harness that first
      -- shipped this fix, this could not be pinned down to a specific reproducible code
      -- defect in this sandboxed environment. Rather than leave 16.2's fix exactly as it
      -- was and call the retest inconclusive, this closes the one class of risk (2) was
      -- checking for defensively and for free: reapply `statusline = " "` to any
      -- `no-neck-pain`-filetype window on every layout-affecting event, not only at
      -- initial creation, so that even a future/real-world recreation path this
      -- investigation did not manage to trigger cannot leave one behind unblanked.
      local function blank_padding_statuslines()
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_is_valid(win) then
            local buf = vim.api.nvim_win_get_buf(win)
            if vim.bo[buf].filetype == "no-neck-pain" then
              if vim.api.nvim_get_option_value("statusline", { win = win, scope = "local" }) ~= " " then
                vim.api.nvim_set_option_value("statusline", " ", { win = win, scope = "local" })
              end
            end
          end
        end
      end

      vim.api.nvim_create_autocmd({ "VimResized", "WinEnter", "WinNew", "WinClosed", "BufWinEnter" }, {
        group = vim.api.nvim_create_augroup("fondue_centred_statusline", { clear = true }),
        desc = "Defensively re-blank the centred layout's padding statuslines on any "
          .. "layout-affecting event, in case something recreates or re-touches those "
          .. "windows without reapplying no-neck-pain's own buffers.wo options (task 16.5)",
        callback = function()
          vim.schedule(blank_padding_statuslines)
        end,
      })
    end,
  },

  -- Project-wide search and replace, kept separate from snacks.picker's grep: it has
  -- its own review-and-confirm step before anything is written to disk.
  {
    "MagicDuck/grug-far.nvim",
    version = "^1",
    cmd = "GrugFar",
    opts = {},
  },

  -- Sessions. Loads on BufReadPre (a real file being read) for a normal `nvim <file>`
  -- start; fondue.lib.session forces it to load early for the no-file-argument case,
  -- where that decision has to be made before any file is read.
  {
    "folke/persistence.nvim",
    version = "^3",
    event = "BufReadPre",
    opts = {},
  },

  -- TODO/FIXME/WARN/NOTE in comments, feeding Space f t.
  {
    "folke/todo-comments.nvim",
    version = "^1",
    event = "VeryLazy",
    opts = {},
  },
}
