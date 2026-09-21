-- Treesitter setup: the parsers we install, and the FileType autocmd that switches
-- highlighting (and folding) on for every buffer whose language has a parser.
local M = {}

-- Parsers we build. Neovim itself bundles Lua, Vim script, help files, queries and
-- Markdown, so those need nothing from us.
M.parsers = { "bash", "javascript", "json", "python", "swift" }

-- Parsers and dictionaries are installed here; lazy.nvim trims the runtimepath, so
-- init.lua adds this folder back (see M.setup).
M.site_dir = vim.fn.stdpath("data") .. "/site"

-- The list of parsers that are really installed (not only their query files).
local function installed_set()
  local ok, ts = pcall(require, "nvim-treesitter")
  local set = {}
  if not ok then
    return set, "nvim-treesitter is not installed"
  end
  for _, lang in ipairs(ts.get_installed("parsers")) do
    set[lang] = true
  end
  return set
end

-- Is the parser for this language installed?
function M.is_installed(lang)
  return installed_set()[lang] == true
end

-- Install the parsers that are missing (or rebuild them all with options.update).
-- options.wait       true: wait until finished (used by the installer)
-- options.timeout_ms how long to wait in total (default 10 minutes)
-- Returns { installed = {langs}, present = {langs}, failed = { {name=, reason=} } }.
function M.install(options)
  options = options or {}
  local result = { installed = {}, present = {}, failed = {} }

  local ok, lazy = pcall(require, "lazy")
  if ok then
    lazy.load({ plugins = { "nvim-treesitter" } })
  end
  local have_plugin, ts = pcall(require, "nvim-treesitter")
  if not have_plugin then
    for _, lang in ipairs(M.parsers) do
      result.failed[#result.failed + 1] = { name = lang, reason = "nvim-treesitter is not installed" }
    end
    return result
  end
  ts.setup({ install_dir = M.site_dir })

  local have = installed_set()
  local todo = {}
  for _, lang in ipairs(M.parsers) do
    if have[lang] and not options.update then
      result.present[#result.present + 1] = lang
    else
      todo[#todo + 1] = lang
    end
  end
  if #todo == 0 then
    return result
  end

  local task = ts.install(todo, { force = options.update })
  if not options.wait then
    return result
  end
  task:wait(options.timeout_ms or 600000)

  -- The task's own answer is not reliable (asking for an unknown language "succeeds"),
  -- so look at what is actually installed now.
  have = installed_set()
  for _, lang in ipairs(todo) do
    if have[lang] then
      result.installed[#result.installed + 1] = lang
    else
      result.failed[#result.failed + 1] = { name = lang, reason = "the parser was not built (needs the tree-sitter CLI and a C compiler)" }
    end
  end
  return result
end

-- Start highlighting for a buffer if its language has a parser. Returns true if started.
local function start_highlighting(buf)
  local lang = vim.treesitter.language.get_lang(vim.bo[buf].filetype)
  if not lang then
    return false
  end
  -- language.add() loads the parser; it gives nothing back when there is none, and never
  -- raises an error we would show. pcall protects against a broken parser file.
  local ok, loaded = pcall(vim.treesitter.language.add, lang)
  if not (ok and loaded) then
    return false
  end
  return pcall(vim.treesitter.start, buf, lang)
end

function M.setup()
  -- lazy.nvim trims the runtimepath; put the folder with our parsers back.
  if not vim.tbl_contains(vim.opt.rtp:get(), M.site_dir) then
    vim.opt.rtp:prepend(M.site_dir)
  end

  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("fondue_treesitter", { clear = true }),
    desc = "Start Treesitter highlighting and folds when the language has a parser",
    callback = function(args)
      -- Only real files: not the plugin manager window, terminals and the like.
      if vim.bo[args.buf].buftype ~= "" then
        return
      end
      local started = start_highlighting(args.buf)
      if started then
        -- Folds follow the code's structure. (foldlevelstart = 99 in core/options.lua
        -- means they all start open.) Treesitter indentation is not enabled.
        local win = vim.fn.bufwinid(args.buf)
        if win ~= -1 then
          vim.wo[win][0].foldmethod = "expr"
          vim.wo[win][0].foldexpr = "v:lua.vim.treesitter.foldexpr()"
        end
      end
      -- Spell checking depends on whether there is a syntax tree; see spell.lua.
      require("fondue.spell").apply(args.buf, started)
    end,
  })
end

return M
