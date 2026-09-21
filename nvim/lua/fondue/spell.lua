-- Spell checking (UK English) and plain-text comfort.
--
-- Where spelling is checked is decided here, in one place:
--   * plain text (filetype "text"): the whole buffer
--   * code with a syntax tree (Treesitter): only the parts its highlight queries mark
--     as spellable, which are comments and documentation strings. Identifiers, keywords
--     and ordinary string literals are not checked.
--   * everything else: not checked
-- To check other parts of code as well (for example every string), add a `highlights.scm`
-- for the language under nvim/queries/<language>/ that starts with `; extends` and marks
-- those nodes with @spell. This file would not need to change.
local M = {}

-- File types treated as plain text.
M.plain_text_filetypes = { "text" }

-- Vim has one English dictionary file (en.utf-8.spl); "en_gb" picks the British region,
-- so "colour" is right and "color" is flagged as belonging to another region.
M.language = "en_gb"
M.dictionary_file = "spell/en.utf-8.spl"

function M.setup()
  vim.o.spelllang = M.language
  -- Our own setup step fetches the dictionary; never stop to ask a question mid-edit.
  -- (This only matters when the dictionary is missing.)
  vim.g.loaded_spellfile_plugin = 1
end

-- Called for each buffer when its file type is known. `has_syntax_tree` is true when
-- Treesitter highlighting started for the buffer.
function M.apply(buf, has_syntax_tree)
  local win = vim.fn.bufwinid(buf)
  if win == -1 then
    return
  end
  -- `vim.wo[win][0]` sets an option for this buffer in this window only, so it does not
  -- follow the window when another file is opened in it.
  local local_opts = vim.wo[win][0]
  if vim.tbl_contains(M.plain_text_filetypes, vim.bo[buf].filetype) then
    local_opts.spell = true
    -- Long lines wrap at word boundaries and wrapped lines keep their indent.
    local_opts.wrap = true
    local_opts.linebreak = true
    local_opts.breakindent = true
  elseif has_syntax_tree then
    -- With a syntax tree, spell checking only looks at the spellable parts.
    local_opts.spell = true
  end
end

-- Is the English dictionary on the runtimepath?
function M.dictionary_present()
  return #vim.api.nvim_get_runtime_file(M.dictionary_file, false) > 0
end

-- Fetch the dictionary without asking, if it is missing. Blocks until done.
-- Returns { fetched = true|false, present = true|false, error = string|nil }.
function M.ensure_dictionary()
  if M.dictionary_present() then
    return { fetched = false, present = true }
  end
  local ok, spellfile = pcall(require, "nvim.spellfile")
  if not ok then
    return { fetched = false, present = false, error = "this Neovim has no built-in dictionary downloader" }
  end
  spellfile.config({ confirm = false }) -- the default asks "Download? [y/N]"
  local got, err = pcall(spellfile.get, "en")
  local present = M.dictionary_present()
  return { fetched = present, present = present, error = (not present) and (got and "download failed (no network?)" or tostring(err)) or nil }
end

return M
