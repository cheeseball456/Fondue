-- Colours for the indent guides and for the highlight of other uses of the word under the
-- cursor. The word highlight is clearly visible, yet distinct from the cursor line, the selection
-- and the diagnostics. Both are worked out from the ACTIVE colourscheme's own colours (its background, its
-- cursor-line and selection colours) so they stay readable whichever scheme is in use, and they
-- are worked out again whenever the scheme changes (a scheme change clears every highlight).
--
-- To tune the look, change the numbers in `M.settings` just below.
local M = {}

M.settings = {
  -- How clearly the vertical indent guides stand out from the background. This is a contrast
  -- ratio, like the ones used for text: 1 is invisible, 3 is clearly visible, 21 is black on white.
  guide_contrast = 3.0,
  -- The same for the guide of the block the cursor is in: clearly stronger than the others.
  scope_contrast = 6.5,
  -- How clearly the background behind the other uses of the word under the cursor stands out
  -- from the normal background (a background fill needs less than a line does). It must be clearly
  -- visible, but never mistaken for the cursor line, the selection or a diagnostic (diagnostics use
  -- coloured text and underlines, not a background, so a background of its own cannot be confused with them).
  word_contrast = 1.9,
  -- The word background must also differ from the cursor line and the selection by at least
  -- this much (distance between two colours, 0 to about 440), or it would look like one of them.
  word_min_distance = 30,
  -- The word background is tinted with the colour of the first of these highlight groups that
  -- gives a colour different enough from the cursor line and the selection.
  word_tints = { "Function", "Special", "Identifier", "Type", "String" },
  -- How clearly the fuzzy finder's dimmed path text (the folder part shown to tell two
  -- same-named files apart) stands out from the background. It links to NonText by
  -- default, which some colourschemes render too close to the background to read
  -- comfortably; this nudges it up a little while keeping it visibly secondary to the
  -- filename itself (which keeps its own full-contrast colour, unchanged).
  picker_path_contrast = 3.5,
  -- How clearly a terminal window's background stands out while it is in terminal mode
  -- (typing into the shell) -- FR-003's "terminal mode is visually distinguishable from
  -- normal mode", added after interactive verification found Neovim's own small
  -- `-- TERMINAL --` status text too easy to miss. Applied to the *whole* window (see
  -- `fondue.core.terminal_mode`), so this is deliberately gentler than `word_contrast`
  -- (which only tints a few characters' worth of background): strong enough to notice
  -- immediately at a glance, not so strong that a whole pane of shell scrollback becomes
  -- uncomfortable to read while typing into it.
  terminal_mode_contrast = 1.6,
  -- Like `word_min_distance`, but also kept apart from the word-highlight background
  -- itself, so "typing into a terminal" is never mistaken for "other uses of this word".
  terminal_mode_min_distance = 25,
  -- Tried in order, same idea as `word_tints`; a different first choice, so the two
  -- highlights do not routinely end up as the same colour on schemes that define both.
  terminal_mode_tints = { "DiagnosticWarn", "String", "Special", "Function", "Identifier" },
  -- Indent guides follow the bracket colours (rainbow-delimiters), one per nesting depth. When
  -- the scheme does not define those groups, these are the colours rainbow-delimiters uses.
  bracket_colours = {
    { "RainbowDelimiterRed", 0xcc241d },
    { "RainbowDelimiterYellow", 0xd79921 },
    { "RainbowDelimiterBlue", 0x458588 },
    { "RainbowDelimiterOrange", 0xd65d0e },
    { "RainbowDelimiterGreen", 0x689d6a },
    { "RainbowDelimiterViolet", 0xb16286 },
    { "RainbowDelimiterCyan", 0xa89984 },
  },
}

-- The highlight group names the indent guides use (see plugins/editing.lua): one per depth.
M.guide_groups = {}
M.scope_groups = {}
for depth = 1, #M.settings.bracket_colours do
  M.guide_groups[depth] = "FondueIndent" .. depth
  M.scope_groups[depth] = "FondueIndentScope" .. depth
end

-- The highlight group `fondue.core.terminal_mode` links a terminal window's `Normal`
-- (and `NormalNC`) to while it is in terminal mode.
M.terminal_mode_group = "FondueTerminalMode"

-- ---------------------------------------------------------------------------------------
-- Colour arithmetic. Colours are numbers like 0xRRGGBB.

local function channels(colour)
  return bit.band(bit.rshift(colour, 16), 0xff), bit.band(bit.rshift(colour, 8), 0xff), bit.band(colour, 0xff)
end

local function combine(r, g, b)
  return bit.lshift(r, 16) + bit.lshift(g, 8) + b
end

-- How bright a colour looks (0 black to 1 white), following the WCAG definition.
local function luminance(colour)
  local function linear(value)
    value = value / 255
    return value <= 0.03928 and value / 12.92 or ((value + 0.055) / 1.055) ^ 2.4
  end
  local r, g, b = channels(colour)
  return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
end

-- The contrast ratio between two colours: 1 (identical) to 21 (black on white).
function M.contrast(a, b)
  local la, lb = luminance(a), luminance(b)
  if la < lb then
    la, lb = lb, la
  end
  return (la + 0.05) / (lb + 0.05)
end

-- Mix two colours: amount 0 gives `from`, 1 gives `to`.
local function mix(from, to, amount)
  local fr, fg, fb = channels(from)
  local tr, tg, tb = channels(to)
  local function part(x, y)
    return math.floor(x + (y - x) * amount + 0.5)
  end
  return combine(part(fr, tr), part(fg, tg), part(fb, tb))
end

-- How different two colours look, as a plain distance in RGB (0 to about 440).
function M.distance(a, b)
  local ar, ag, ab = channels(a)
  local br, bg, bb = channels(b)
  return math.sqrt((ar - br) ^ 2 + (ag - bg) ^ 2 + (ab - bb) ^ 2)
end

-- Move `colour` towards `target` until its contrast with `background` is `wanted` (found by
-- halving the step; the contrast changes steadily along the way). Returns the colour reached, or
-- `target` itself if even that does not get as far as `wanted`.
local function reach_contrast(colour, target, background, wanted)
  local start, finish = M.contrast(colour, background), M.contrast(target, background)
  if (start - wanted) * (finish - wanted) > 0 then
    return target
  end
  local rising = finish > start
  local low, high = 0, 1
  for _ = 1, 20 do
    local middle = (low + high) / 2
    local reached = M.contrast(mix(colour, target, middle), background)
    if (rising and reached < wanted) or (not rising and reached > wanted) then
      low = middle
    else
      high = middle
    end
  end
  return mix(colour, target, high)
end

-- Give `colour` exactly the wanted contrast against `background`: fade it towards the background
-- if it is too strong, and push it towards white (dark scheme) or black (light scheme) if it is
-- too weak. Its hue is kept as far as possible.
local function with_contrast(colour, background, wanted)
  local current = M.contrast(colour, background)
  if math.abs(current - wanted) < 0.02 then
    return colour
  end
  if current > wanted then
    return reach_contrast(colour, background, background, wanted) -- fade towards the background
  end
  local extreme = luminance(background) < 0.18 and 0xffffff or 0x000000
  return reach_contrast(colour, extreme, background, wanted)
end

-- ---------------------------------------------------------------------------------------
-- Reading the scheme

local function group_colour(name, part)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  return ok and hl and hl[part] or nil
end

-- What was chosen last time, for M.describe().
M.chosen = {}

local function apply_indent_guides(background)
  local chosen = {}
  for depth, entry in ipairs(M.settings.bracket_colours) do
    local base = group_colour(entry[1], "fg") or entry[2]
    local guide = with_contrast(base, background, M.settings.guide_contrast)
    local scope = with_contrast(base, background, M.settings.scope_contrast)
    vim.api.nvim_set_hl(0, M.guide_groups[depth], { fg = guide })
    vim.api.nvim_set_hl(0, M.scope_groups[depth], { fg = scope })
    chosen[depth] = { base = base, guide = guide, scope = scope }
  end
  M.chosen.guides = chosen
end

-- Tint `background` with the first of `tints` (highlight group names, read for their
-- `fg`) that reaches `contrast` against `background` while staying at least
-- `min_distance` away from every colour in `avoid` -- shared by the word highlight and
-- the terminal-mode cue below, which both pick "a scheme colour, clearly different from
-- a short list of colours already in use nearby" for the same reason: neither must be
-- mistaken for the cursor line, the selection, or (for the terminal-mode cue) the word
-- highlight itself. Falls back to whichever candidate got closest, if none clears
-- `min_distance` outright, the same way the word highlight always did before this was
-- extracted -- no behaviour change for it, just shared with the new caller.
local function pick_tint(background, tints, contrast, min_distance, avoid)
  local best, best_score
  for _, name in ipairs(tints) do
    local tint = group_colour(name, "fg")
    if tint then
      local candidate = reach_contrast(background, tint, background, contrast)
      local score = math.huge
      for _, other in ipairs(avoid) do
        score = math.min(score, M.distance(candidate, other))
      end
      if not best or score > best_score then
        best, best_score = { colour = candidate, tint = name }, score
      end
      if score >= min_distance then
        return { colour = candidate, tint = name, distance = score }
      end
    end
  end
  return best and { colour = best.colour, tint = best.tint, distance = best_score } or nil
end

local function apply_word_highlight(background)
  local cursor_line = group_colour("CursorLine", "bg")
  local selection = group_colour("Visual", "bg")
  local others = {}
  if cursor_line then
    others[#others + 1] = cursor_line
  end
  if selection then
    others[#others + 1] = selection
  end

  local best = pick_tint(background, M.settings.word_tints, M.settings.word_contrast, M.settings.word_min_distance, others)
  if not best then
    return
  end
  for _, name in ipairs({ "LspReferenceText", "LspReferenceRead", "LspReferenceWrite" }) do
    vim.api.nvim_set_hl(0, name, { bg = best.colour })
  end
  M.chosen.word = { colour = best.colour, tint = best.tint, cursor_line = cursor_line, selection = selection, distance = best.distance }
end

-- The terminal-mode cue (FR-003, `fondue.core.terminal_mode`): a background tint for a
-- terminal window's `Normal`/`NormalNC`, applied only while it is in terminal mode.
-- Avoids the cursor line, the selection, and the word highlight's own background, so
-- none of the three is ever mistaken for another.
local function apply_terminal_mode(background)
  local cursor_line = group_colour("CursorLine", "bg")
  local selection = group_colour("Visual", "bg")
  local others = {}
  if cursor_line then
    others[#others + 1] = cursor_line
  end
  if selection then
    others[#others + 1] = selection
  end
  if M.chosen.word then
    others[#others + 1] = M.chosen.word.colour
  end

  local best = pick_tint(
    background,
    M.settings.terminal_mode_tints,
    M.settings.terminal_mode_contrast,
    M.settings.terminal_mode_min_distance,
    others
  )
  if not best then
    return
  end
  vim.api.nvim_set_hl(0, M.terminal_mode_group, { bg = best.colour })
  M.chosen.terminal_mode = { colour = best.colour, tint = best.tint, distance = best.distance }
end

-- snacks.picker's `SnacksPickerDir` group (the folder part of a path, shown dimmed
-- to tell same-named files in different folders apart, see the fuzzy-finding spec):
-- linked to NonText by default (lua/snacks/picker/config/highlights.lua). Only this one
-- group is adjusted, not NonText itself, which is used elsewhere for its own purpose.
local function apply_picker_path(background)
  local base = group_colour("NonText", "fg") or 0x808080
  local colour = with_contrast(base, background, M.settings.picker_path_contrast)
  vim.api.nvim_set_hl(0, "SnacksPickerDir", { fg = colour })
  M.chosen.picker_path = { base = base, colour = colour }
end

function M.apply()
  local background = group_colour("Normal", "bg")
  if not background then
    -- A transparent background: assume the terminal is dark, as most are.
    background = vim.o.background == "light" and 0xffffff or 0x1e1e1e
  end
  M.chosen.background = background
  apply_indent_guides(background)
  apply_word_highlight(background)
  apply_terminal_mode(background) -- after the word highlight, so it can avoid its colour
  apply_picker_path(background)
end

-- Work the colours out now, and again every time the colourscheme changes.
function M.setup()
  M.apply()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("fondue_highlights", { clear = true }),
    desc = "Work out the indent guide and word highlight colours for the new colourscheme",
    callback = M.apply,
  })
end

-- A readable list of what was chosen and the contrast ratios (used by the tests and handy when tuning).
function M.describe()
  local function hex(colour)
    return colour and string.format("#%06x", colour) or "none"
  end
  local lines = { "background " .. hex(M.chosen.background) }
  for depth, c in ipairs(M.chosen.guides or {}) do
    table.insert(
      lines,
      string.format(
        "depth %d: bracket %s  guide %s (%.2f:1)  current block %s (%.2f:1)",
        depth,
        hex(c.base),
        hex(c.guide),
        M.contrast(c.guide, M.chosen.background),
        hex(c.scope),
        M.contrast(c.scope, M.chosen.background)
      )
    )
  end
  local p = M.chosen.picker_path
  if p then
    table.insert(lines, string.format("fuzzy-finder path text %s (%.2f:1 against the background, from NonText %s)", hex(p.colour), M.contrast(p.colour, M.chosen.background), hex(p.base)))
  end
  local w = M.chosen.word
  if w then
    table.insert(
      lines,
      string.format(
        "word background %s (%.2f:1 against the background, tinted with %s); distance to cursor line %s: %.0f, to selection %s: %.0f",
        hex(w.colour),
        M.contrast(w.colour, M.chosen.background),
        w.tint,
        hex(w.cursor_line),
        w.cursor_line and M.distance(w.colour, w.cursor_line) or -1,
        hex(w.selection),
        w.selection and M.distance(w.colour, w.selection) or -1
      )
    )
  end
  local t = M.chosen.terminal_mode
  if t then
    table.insert(
      lines,
      string.format(
        "terminal-mode cue %s (%.2f:1 against the background, tinted with %s)",
        hex(t.colour),
        M.contrast(t.colour, M.chosen.background),
        t.tint
      )
    )
  end
  return lines
end

return M
