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

-- One line of text from any error or reason: no line breaks, no runs of spaces.
local function one_line(text)
  return (tostring(text):gsub("%s+", " "))
end

-- Print a progress line as one item finishes, so a long download shows signs of life.
local function progress(name, ok, reason)
  io.stdout:write(string.format("    %s ... %s\n", name, ok and "done" or ("FAILED (" .. one_line(reason) .. ")")))
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
    report("FAILED", what .. " " .. failure.name .. ": " .. one_line(failure.reason))
  end
  return #result.failed
end

-- Run one step. A step returns how many items failed; if it raises an unexpected error, that is
-- reported by name as one failure and the next step still runs.
local function run_step(name, step)
  local ok, result = xpcall(step, one_line)
  if not ok then
    report("FAILED", name .. ": unexpected error: " .. result)
    return 1
  end
  return result or 0
end

local function matcher_step()
  local matcher = M.ensure_matcher()
  if matcher.error then
    report("FAILED", "completion matcher: " .. one_line(matcher.error))
    return 1
  elseif matcher.fetched then
    report("installed", "completion matcher: downloaded")
  else
    report("ok", "completion matcher: already present, nothing to do")
  end
  return 0
end

local function dictionary_step()
  local dictionary = require("fondue.spell").ensure_dictionary()
  if dictionary.error then
    report("FAILED", "spell dictionary: " .. one_line(dictionary.error))
    return 1
  elseif dictionary.fetched then
    report("installed", "spell dictionary: downloaded (en)")
  else
    report("ok", "spell dictionary: already present, nothing to do")
  end
  return 0
end

-- Run every step, whatever happens in the others. Exits Neovim with a non-zero status if anything
-- failed, including an unexpected error. When it returns normally the last line printed is
-- "finished", which the installer looks for.
function M.run()
  local failed = 0
  local all_steps_ran, problem = pcall(function()
    failed = failed + run_step("Treesitter parsers", function()
      return report_list("Treesitter parsers", require("fondue.treesitter").install({ wait = true }))
    end)
    failed = failed + run_step("Mason tools", function()
      return report_list("Mason tools", require("fondue.tools").install({ wait = true, progress = progress }))
    end)
    failed = failed + run_step("completion matcher", matcher_step)
    failed = failed + run_step("spell dictionary", dictionary_step)
  end)
  if not all_steps_ran then
    -- Nothing above should escape run_step; this is the last line of defence.
    report("FAILED", "language tooling: unexpected error: " .. one_line(problem))
    failed = failed + 1
  end

  if failed > 0 then
    report("FAILED", failed .. " item(s) could not be installed; see the lines above")
    vim.cmd("cquit 1")
  end
  report("finished", "language tooling steps complete")
  return failed
end

return M
