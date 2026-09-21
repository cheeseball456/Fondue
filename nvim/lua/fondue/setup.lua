-- Language tooling setup, run by scripts/install.sh without opening the editor:
--   nvim --headless "+lua require('fondue.setup').run()" +qa
-- It installs whatever is missing: Treesitter parsers, the Mason tools from tools.lua,
-- the completion menu's prebuilt matcher and the English spell dictionary. Each step
-- waits until it is finished, never asks a question, and reports a failure by name
-- without stopping the others. It is safe to run again: finished steps do nothing.
local M = {}

-- Where the completion menu (blink.cmp) keeps its prebuilt fuzzy matcher.
function M.matcher_path()
  local extension = vim.fn.has("mac") == 1 and "dylib" or "so"
  return vim.fn.stdpath("data") .. "/lazy/blink.cmp/target/release/libblink_cmp_fuzzy." .. extension
end

function M.matcher_present()
  return vim.uv.fs_stat(M.matcher_path()) ~= nil
end

-- Download the matcher if it is missing, and wait for it. Returns { fetched, present, error }.
function M.ensure_matcher()
  if M.matcher_present() then
    return { fetched = false, present = true }
  end
  local ok, plugins = pcall(function()
    return require("lazy.core.config").plugins
  end)
  local plugin = ok and plugins and plugins["blink.cmp"]
  if not plugin then
    return { fetched = false, present = false, error = "the blink.cmp plugin is not installed" }
  end
  -- Only put the plugin on the runtimepath: loading it fully would start its own download.
  vim.opt.rtp:append(plugin.dir)
  local finished, err = false, nil
  local started, problem = pcall(function()
    require("blink.cmp.fuzzy.download").ensure_downloaded(function(e)
      err = e
      finished = true
    end)
  end)
  if not started then
    return { fetched = false, present = false, error = tostring(problem) }
  end
  vim.wait(120000, function()
    return finished
  end, 100)
  local present = M.matcher_present()
  return { fetched = present, present = present, error = (not present) and tostring(err or "download failed (no network?)") or nil }
end

-- Print one result line: a status word, then the text. The installer looks for "installed".
local function report(status, text)
  io.stdout:write(string.format("  %-10s %s\n", status, text))
  io.stdout:flush()
end

-- Report the { installed, present, failed } result of parsers or tools.
local function report_list(what, result)
  if #result.installed > 0 then
    report("installed", what .. ": " .. table.concat(result.installed, ", "))
  end
  if #result.present > 0 and #result.installed == 0 and #result.failed == 0 then
    report("ok", what .. ": all " .. #result.present .. " already installed, nothing to do")
  end
  for _, failure in ipairs(result.failed) do
    report("FAILED", what .. " " .. failure.name .. ": " .. tostring(failure.reason):gsub("%s+", " "))
  end
  return #result.failed
end

-- Run every step. Exits Neovim with a non-zero status if anything failed.
function M.run()
  local failed = 0

  failed = failed + report_list("Treesitter parsers", require("fondue.treesitter").install({ wait = true }))
  failed = failed + report_list("Mason tools", require("fondue.tools").install({ wait = true }))

  local matcher = M.ensure_matcher()
  if matcher.error then
    report("FAILED", "completion matcher: " .. matcher.error)
    failed = failed + 1
  elseif matcher.fetched then
    report("installed", "completion matcher: downloaded")
  else
    report("ok", "completion matcher: already present, nothing to do")
  end

  local dictionary = require("fondue.spell").ensure_dictionary()
  if dictionary.error then
    report("FAILED", "spell dictionary: " .. dictionary.error)
    failed = failed + 1
  elseif dictionary.fetched then
    report("installed", "spell dictionary: downloaded (en)")
  else
    report("ok", "spell dictionary: already present, nothing to do")
  end

  if failed > 0 then
    report("FAILED", failed .. " item(s) could not be installed; see the lines above")
    vim.cmd("cquit 1")
  end
  return failed
end

return M
