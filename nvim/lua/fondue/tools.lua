-- The one table of external tools that Mason provides: language servers, formatters
-- and the linter. The installer, the health check and the language server setup all
-- read this table, so adding a tool here is the only edit needed.
--
-- Each entry:
--   name     what we call it (also used in messages)
--   package  the package name in Mason's registry (check with :Mason)
--   exe      the program that must be on PATH once it is installed
--   kind     "server", "formatter" or "linter"
--   used_for a plain description shown in the health report
--   server   (servers only) the name nvim-lspconfig knows the server by
local M = {}

M.tools = {
  { name = "basedpyright", package = "basedpyright", exe = "basedpyright-langserver", kind = "server", server = "basedpyright", used_for = "Python types and completion" },
  { name = "ruff", package = "ruff", exe = "ruff", kind = "server", server = "ruff", used_for = "Python lint warnings and quick fixes (and the Python formatter)" },
  {
    name = "typescript-language-server",
    package = "typescript-language-server",
    exe = "typescript-language-server",
    kind = "server",
    server = "ts_ls",
    used_for = "JavaScript completion and diagnostics",
  },
  { name = "json-lsp", package = "json-lsp", exe = "vscode-json-language-server", kind = "server", server = "jsonls", used_for = "JSON completion and diagnostics" },
  { name = "bash-language-server", package = "bash-language-server", exe = "bash-language-server", kind = "server", server = "bashls", used_for = "bash completion and diagnostics" },
  {
    name = "lua-language-server",
    package = "lua-language-server",
    exe = "lua-language-server",
    kind = "server",
    server = "lua_ls",
    used_for = "Lua completion and diagnostics (for editing this configuration)",
  },
  { name = "prettier", package = "prettier", exe = "prettier", kind = "formatter", used_for = "formatting JavaScript and JSON" },
  { name = "shfmt", package = "shfmt", exe = "shfmt", kind = "formatter", used_for = "formatting bash" },
  { name = "stylua", package = "stylua", exe = "stylua", kind = "formatter", used_for = "formatting Lua" },
  { name = "shellcheck", package = "shellcheck", exe = "shellcheck", kind = "linter", used_for = "bash lint warnings" },
}

-- Make sure Mason is loaded (this also puts Mason's folder of programs on PATH).
local function load_mason()
  local ok, lazy = pcall(require, "lazy")
  if ok then
    lazy.load({ plugins = { "mason.nvim" } })
  end
  return require("mason-registry")
end

-- Is the program for this tool available (from Mason or from the system)?
function M.is_available(tool)
  -- Mason's folder may not be on PATH yet if Mason has not loaded; add it by hand for the check.
  local mason_bin = vim.fn.stdpath("data") .. "/mason/bin"
  return vim.fn.executable(tool.exe) == 1 or vim.fn.executable(mason_bin .. "/" .. tool.exe) == 1
end

-- The tools whose program is not available yet.
function M.missing()
  local list = {}
  for _, tool in ipairs(M.tools) do
    if not M.is_available(tool) then
      list[#list + 1] = tool
    end
  end
  return list
end

-- Install every tool that Mason does not have yet.
-- options.wait       true: wait until all installs finish (used by the installer)
-- options.timeout_ms how long to wait in total (default 10 minutes)
-- options.progress   function(name, ok, reason): called as each tool finishes
-- Returns { installed = {names}, present = {names}, failed = { {name=, reason=}, ... } }.
-- A failing tool is reported by name and never stops the others.
function M.install(options)
  options = options or {}
  local result = { installed = {}, present = {}, failed = {} }

  local ok, registry = pcall(load_mason)
  if not ok then
    for _, tool in ipairs(M.tools) do
      result.failed[#result.failed + 1] = { name = tool.name, reason = "Mason could not be loaded: " .. tostring(registry) }
    end
    return result
  end

  -- Fetch the list of packages (a quick download the first time, then cached for a day).
  -- An offline machine still works if the cache exists; without a cache there is no list at
  -- all, and that is what every tool's failure reason must say (not "no such package").
  -- refresh() answers (true, ...) or (false, error message); pcall adds its own first answer.
  local called, refreshed, detail = pcall(registry.refresh)
  local refresh_error = (not called and refreshed) or (called and refreshed == false and detail) or nil
  local listed, names = pcall(registry.get_all_package_names)
  local have_list = listed and type(names) == "table" and #names > 0
  local list_problem = "Mason's package list is not available (it could not be downloaded; is the network up?)"
  if type(refresh_error) == "string" then
    list_problem = list_problem .. ": " .. refresh_error:gsub("%s+", " ")
  end

  local function report_progress(name, ok, reason)
    if options.progress then
      pcall(options.progress, name, ok, reason)
    end
  end

  local pending = 0
  for _, tool in ipairs(M.tools) do
    local found, package = pcall(registry.get_package, tool.package)
    local present = false
    if found then
      local checked, installed = pcall(package.is_installed, package)
      present = checked and installed == true
    end
    if not found then
      local reason = have_list and ("no Mason package called '" .. tool.package .. "'") or list_problem
      result.failed[#result.failed + 1] = { name = tool.name, reason = reason }
    elseif present then
      result.present[#result.present + 1] = tool.name
    else
      pending = pending + 1
      local started, err = pcall(function()
        package:install({}, function(success, reason)
          pending = pending - 1
          if success then
            result.installed[#result.installed + 1] = tool.name
          else
            result.failed[#result.failed + 1] = { name = tool.name, reason = tostring(reason) }
          end
          report_progress(tool.name, success, success and nil or tostring(reason))
        end)
      end)
      if not started then
        pending = pending - 1
        result.failed[#result.failed + 1] = { name = tool.name, reason = tostring(err) }
        report_progress(tool.name, false, tostring(err))
      end
    end
  end

  if options.wait and pending > 0 then
    local finished = vim.wait(options.timeout_ms or 600000, function()
      return pending == 0
    end, 100)
    if not finished then
      result.failed[#result.failed + 1] = { name = "(timeout)", reason = "installs were still running after the time limit" }
    end
  end
  return result
end

return M
