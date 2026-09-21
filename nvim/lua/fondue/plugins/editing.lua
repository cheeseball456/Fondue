-- Everyday editing helpers.
--
-- snacks.nvim is a collection of small modules; only three are switched on here:
--   indent   vertical guides for each indent level, with the current block highlighted
--   words    highlights other uses of the word under the cursor (needs a language server)
--   bigfile  turns expensive features off for very large files, so they open quickly
-- Pinning: snacks, nvim-autopairs and nvim-surround publish semver tags, so each gets a
-- version range. (The version numbers are used by lazy.nvim only when it updates.)
--
-- Comment toggling needs no plugin: Neovim's built-in `gc` does it (gcc for a line).

-- The colours rainbow-delimiters uses for bracket depth 1, 2, 3 ... (its own defaults, used
-- when it has not been loaded yet, or when the colourscheme does not change them).
local bracket_colours = {
  { "RainbowDelimiterRed", 0xcc241d },
  { "RainbowDelimiterYellow", 0xd79921 },
  { "RainbowDelimiterBlue", 0x458588 },
  { "RainbowDelimiterOrange", 0xd65d0e },
  { "RainbowDelimiterGreen", 0x689d6a },
  { "RainbowDelimiterViolet", 0xb16286 },
  { "RainbowDelimiterCyan", 0xa89984 },
}

-- Mix two colours (numbers like 0xRRGGBB); `amount` is how much of `front` shows.
local function mix(front, back, amount)
  local function channel(colour, shift)
    return bit.band(bit.rshift(colour, shift), 0xff)
  end
  local result = 0
  for _, shift in ipairs({ 16, 8, 0 }) do
    local value = math.floor(channel(front, shift) * amount + channel(back, shift) * (1 - amount) + 0.5)
    result = result + bit.lshift(value, shift)
  end
  return result
end

-- Indent guides get a faint version of the bracket colour for their depth; the guide of
-- the block the cursor is in gets the full colour. Returns the two lists of group names.
local function set_indent_colours()
  local background = vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg or 0x1e1e1e
  local guides, scopes = {}, {}
  for depth, entry in ipairs(bracket_colours) do
    local colour = vim.api.nvim_get_hl(0, { name = entry[1], link = false }).fg or entry[2]
    vim.api.nvim_set_hl(0, "FondueIndent" .. depth, { fg = mix(colour, background, 0.25) })
    vim.api.nvim_set_hl(0, "FondueIndentScope" .. depth, { fg = colour })
    guides[depth] = "FondueIndent" .. depth
    scopes[depth] = "FondueIndentScope" .. depth
  end
  return guides, scopes
end

return {
  {
    "folke/snacks.nvim",
    version = "^2",
    lazy = false, -- bigfile and indent must be ready before the first file is read
    priority = 1000,
    opts = function()
      local guides, scopes = set_indent_colours()
      -- A colourscheme change clears every highlight group, so set ours again.
      vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("fondue_indent_colours", { clear = true }),
        callback = set_indent_colours,
      })
      return {
        bigfile = { enabled = true },
        indent = {
          enabled = true,
          indent = { hl = guides },
          scope = { hl = scopes },
          -- The full-colour scope guide is enough; no extra corner "chunk" drawing.
          chunk = { enabled = false },
        },
        words = { enabled = true },
      }
    end,
  },
  {
    -- Closes brackets and quotes as you type: ( becomes ().
    "windwp/nvim-autopairs",
    version = "^0.10",
    event = "InsertEnter",
    opts = {},
  },
  {
    -- Surround editing with its standard keys: ys (add), cs (change), ds (delete).
    -- For example cs"' turns "text" into 'text'. These are not leader keys.
    "kylechui/nvim-surround",
    version = "^4",
    event = "VeryLazy",
    opts = {},
  },
}
