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
  -- pcall: the plugin is a rewrite that may still change; a broken call must not raise.
  local listed, parsers = pcall(ts.get_installed, "parsers")
  if listed and type(parsers) == "table" then
    for _, lang in ipairs(parsers) do
      set[lang] = true
    end
  end
  return set
end

-- Is the parser for this language installed?
function M.is_installed(lang)
  return installed_set()[lang] == true
end

-- The oldest tree-sitter command-line program that nvim-treesitter's main branch works with.
M.min_cli_version = "0.26.1"

-- Version of the installed tree-sitter CLI as a vim.version object, or nil if it is missing or
-- its output cannot be read.
function M.cli_version()
  if vim.fn.executable("tree-sitter") == 0 then
    return nil
  end
  local ok, proc = pcall(vim.system, { "tree-sitter", "--version" }, { text = true })
  if not ok then
    return nil
  end
  local out = proc:wait().stdout or ""
  return vim.version.parse(out:match("(%d+%.%d+%.%d+)") or "")
end

-- While parsers are being installed, remember nvim-treesitter's own error lines
-- ("[nvim-treesitter/install/<language>] error: ...") so a failure can be explained
-- accurately. Returns the table of language -> message and a function that stops listening.
local function listen_for_errors()
  local errors = {}
  local original = vim.api.nvim_echo
  vim.api.nvim_echo = function(chunks, history, opts)
    pcall(function()
      local text = chunks and chunks[1] and chunks[1][1] or ""
      local lang, message = text:match("^%[nvim%-treesitter/install/([%w_%-]+)%] error: (.*)$")
      if lang then
        errors[lang] = vim.split(message, "\n")[1]
      end
    end)
    return original(chunks, history, opts)
  end
  return errors, function()
    vim.api.nvim_echo = original
  end
end

-- Why did this parser fail? Use nvim-treesitter's own message when there is one, and blame
-- the tree-sitter CLI or the C compiler only when one of them is really missing or too old.
local function failure_reason(lang, errors)
  local reason = errors[lang] or "the parser was not installed (see the messages above)"
  local missing = {}
  if vim.fn.executable("tree-sitter") == 0 then
    missing[#missing + 1] = "the tree-sitter CLI is not installed"
  else
    local version = M.cli_version()
    if version and vim.version.lt(version, vim.version.parse(M.min_cli_version)) then
      missing[#missing + 1] = "the tree-sitter CLI is older than " .. M.min_cli_version
    end
  end
  if vim.fn.executable("cc") == 0 and vim.fn.executable("gcc") == 0 and vim.fn.executable("clang") == 0 then
    missing[#missing + 1] = "no C compiler was found"
  end
  if #missing > 0 then
    reason = reason .. " (" .. table.concat(missing, "; ") .. ")"
  end
  return reason
end

-- Install the parsers that are missing (or rebuild them all with options.update).
-- options.wait       true: wait until finished (used by the installer)
-- options.timeout_ms how long to wait in total (default 10 minutes)
-- options.on_done    function(result): with wait = false, called when the work has finished
-- Returns { installed = {langs}, present = {langs}, failed = { {name=, reason=} } }.
-- Without wait, the returned table only holds what was already installed; use on_done.
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
    if options.on_done then
      options.on_done(result)
    end
    return result
  end
  pcall(ts.setup, { install_dir = M.site_dir })

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
    if options.on_done then
      options.on_done(result)
    end
    return result
  end

  local errors, stop_listening = listen_for_errors()
  local started, task = pcall(ts.install, todo, { force = options.update })
  if not started then
    stop_listening()
    for _, lang in ipairs(todo) do
      result.failed[#result.failed + 1] = { name = lang, reason = "nvim-treesitter raised an error: " .. tostring(task) }
    end
    if options.on_done then
      options.on_done(result)
    end
    return result
  end

  -- The task's own answer is not reliable (asking for an unknown language "succeeds"),
  -- so look at what is actually installed once it has finished.
  local function finish()
    stop_listening()
    have = installed_set()
    for _, lang in ipairs(todo) do
      if have[lang] then
        result.installed[#result.installed + 1] = lang
      else
        result.failed[#result.failed + 1] = { name = lang, reason = failure_reason(lang, errors) }
      end
    end
    if options.on_done then
      options.on_done(result)
    end
  end

  if options.wait then
    pcall(function()
      task:wait(options.timeout_ms or 600000)
    end)
    finish()
  else
    task:await(function()
      vim.schedule(finish)
    end)
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
