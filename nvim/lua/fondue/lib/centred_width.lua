-- Shared, pure width/content-area arithmetic for the centred layout (no-neck-pain's
-- own padding, `plugins/navigation.lua`) and anything else that needs to agree with it
-- on the same "protect at least 80 columns of *text*" target -- currently the start
-- screen's own dashboard pane (`lib/session.lua`'s `open_start_screen_in`, task 18.1).
-- Pulled out into its own module (rather than staying a `local` inside
-- `plugins/navigation.lua`, tasks 17/18's original home for it) so both call sites share
-- one recipe instead of two separately-typed-out copies that can drift apart --
-- exactly the kind of drift task 18.1 found: the dashboard's own fixed ~60-column pane
-- was never told about this arithmetic at all.
local M = {}

-- The actual *text* area to protect -- not raw window columns (task 18.2's own
-- correction: a real code buffer's sign column, line numbers and fold column sit
-- outside this, widening the window further, rather than eating into it).
M.TARGET_TEXT_WIDTH = 80

-- One separator column either side of the centred content column, in a three-way
-- vsplit (confirmed with real window geometry, tasks 16.1/16.6/17.1).
M.WINDOW_SEPARATOR_COLUMNS = 2

-- no-neck-pain's own default (`minSideBufferWidth`, confirmed against the pinned
-- source's `config.lua`) -- this project never overrides it, so it is safe to hardcode
-- here; update this if that ever changes. Padding thinner than this is not rendered
-- thinly -- `ui.get_side_width`/`ui.create_side_buffers` (pinned source) silently close
-- an existing side entirely the next time either runs, rather than showing it -- so
-- asking no-neck-pain for less than this is never actually honoured (task 18.1's own
-- investigation: confirmed live, real padding vanishing entirely and the window going
-- to full width at 90 columns even though the naive math for an 80-column target would
-- have asked for a padding of only 4 on each side).
M.MIN_SIDE_BUFFER_WIDTH = 10

--- The `width` value to hand no-neck-pain's `opts.width`/`resize()`: the literal-third
--- split as a starting point, clamped so the resulting *text* area (not raw window
--- width) never drops below `M.TARGET_TEXT_WIDTH` while padding can still protect it,
--- accounting for `gutter` -- the sign column/line numbers/fold column of the buffer
--- actually being centred (0 for a buffer with none, e.g. the dashboard).
---
--- Once even zero padding cannot reach the target, or the padding needed would be too
--- thin for no-neck-pain to actually render (see `M.MIN_SIDE_BUFFER_WIDTH` above),
--- `columns` itself is returned -- no-neck-pain's own documented "no room for sides"
--- signal (`config.width >= vim.o.columns`), so content takes the entire window rather
--- than losing separator columns to sides that will not actually appear.
---@param columns integer
---@param gutter integer
---@return integer
function M.no_neck_pain_width(columns, gutter)
  local min_window_width = M.TARGET_TEXT_WIDTH + gutter

  local literal_third = math.max(1, math.floor(columns / 3))
  local literal_padding = math.floor((columns - literal_third) / 2)
  local literal_content = columns - 2 * literal_padding - M.WINDOW_SEPARATOR_COLUMNS

  if literal_content >= min_window_width then
    return literal_third -- wide enough already: unchanged from before this finding
  end

  local padding = math.max(0, math.floor((columns - min_window_width - M.WINDOW_SEPARATOR_COLUMNS) / 2))
  if padding > 0 and padding < M.MIN_SIDE_BUFFER_WIDTH then
    padding = 0 -- would be silently closed by no-neck-pain anyway; ask for none instead
  end
  if padding == 0 then
    return columns
  end
  return columns - 2 * padding
end

--- The actual resulting content-column width for a given `columns`/`width` pair (the
--- inverse direction of the same accounting `M.no_neck_pain_width` above uses,
--- confirmed against the pinned `ui.get_side_width`: `padding = floor((columns -
--- width) / 2)`, content = `columns - 2*padding - M.WINDOW_SEPARATOR_COLUMNS`), except
--- once `width >= columns` (no-neck-pain's own "no room" case), where content is the
--- entire window -- there are no side windows left to draw a separator against.
---@param columns integer
---@param width integer
---@return integer
function M.resulting_content_width(columns, width)
  if width >= columns then
    return columns
  end
  local padding = math.floor((columns - width) / 2)
  return columns - 2 * padding - M.WINDOW_SEPARATOR_COLUMNS
end

-- Finding 19.1-19.2 (interactive `/verify`, tenth pass): `Snacks.dashboard`'s own
-- `D:render()` (the installed `snacks.nvim`'s pinned `dashboard.lua`) horizontally
-- centres its pane with `self.col = self.opts.col or math.floor(self._size.width -
-- self.opts.width) / 2` -- note the division happens *outside* `math.floor`, on
-- `self._size.width`/`self.opts.width` (both always integers), so the subtraction
-- itself is already a whole number and `math.floor` is a no-op; the actual rounding
-- only happens implicitly, later, when that value is handed to `(" "):rep()`, which
-- silently truncates a fractional argument towards zero rather than rounding it (
-- confirmed directly: `(" "):rep(10.5)` returns a 10-character string, `(" "):rep(-2.5)`
-- returns an empty one) -- an *undocumented*, vendor-owned rounding behaviour this
-- project has no control over. Worse, `self._size.width` is whatever `self.win`'s
-- width happens to be at the exact moment `render()`/`update()` last ran -- for a
-- freshly-opened dashboard, that is measured synchronously inside `Snacks.dashboard
-- .open()` itself, *before* no-neck-pain's own debounced padding has necessarily been
-- applied (confirmed live, headless with a real pty: at 300 columns, `self._size.width`
-- at the moment of `open()` measured the full, still-unsplit 300-column window, not the
-- ~98-column content column no-neck-pain eventually settles the layout into), so the
-- very first frame this pane ever renders can be centred against entirely the wrong
-- width. A later `WinResized`/`VimResized`-triggered re-render (`D:init()`'s own
-- listener, plus this codebase's own `resync_dashboard_pane_width`) can correct this
-- once no-neck-pain's own layout settles, but that is a live *self.win* window, so it is
-- again subject to the exact same rep()-truncation rounding behaviour above.
--
-- Rather than depend on `Snacks.dashboard`'s own formula and its rep()-truncation
-- rounding, both call sites (`lib/session.lua`'s `open_start_screen_in` and
-- `resync_dashboard_pane_width`) now compute an explicit `col` themselves, with this
-- one shared, deterministic recipe, and pass it as `opts.col` -- `self.opts.col or ...`
-- (its own default is `nil`, and `0` is truthy in Lua, so an explicit `0` here is
-- honoured, not treated as unset) then uses it directly, bypassing the vendor's own
-- live-width-at-render-time formula (and its rounding) entirely.
--- The column offset to horizontally centre a `pane_width`-wide pane within a
--- `container_width`-wide container. Splits any odd leftover column onto the right
--- (`floor`, not `round`) -- the same one-column odd/even bias already accepted
--- elsewhere in this change (e.g. `M.no_neck_pain_width`'s own literal-third split),
--- so a pane can be at most one column further from centre than a perfectly even
--- split, never more, and never zero on one side while the other absorbs everything.
---@param container_width integer
---@param pane_width integer
---@return integer
function M.pane_col(container_width, pane_width)
  return math.max(0, math.floor((container_width - pane_width) / 2))
end

return M
