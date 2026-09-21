-- :checkhealth fondue
-- Neovim finds this file by name and calls check(); no extra plugin is needed.
local M = {}

local health = vim.health

-- Run a command and return its first line of output, or nil if it cannot run.
local function first_line(cmd)
  local ok, proc = pcall(vim.system, cmd, { text = true })
  if not ok then
    return nil
  end
  local res = proc:wait()
  if res.code ~= 0 then
    return nil
  end
  return vim.split(vim.trim((res.stdout ~= "" and res.stdout or res.stderr) or ""), "\n")[1]
end

local function run(cmd)
  local ok, proc = pcall(vim.system, cmd, { text = true })
  if not ok then
    return nil
  end
  local res = proc:wait()
  return res.code == 0 and vim.trim(res.stdout or "") or nil, res
end

-- The Fondue clone the running configuration is linked from, if any.
local function fondue_repo()
  local cfg = vim.uv.fs_realpath(vim.fn.stdpath("config"))
  if not cfg then
    return nil
  end
  local root = vim.fs.dirname(cfg)
  if vim.uv.fs_stat(root .. "/scripts/secret-scan") then
    return root
  end
end

-- Tools to look for, each with a plain "used for" description shown in the report.
-- A missing `needed_now` tool is an error; any other tool is a warning, because no current
-- feature needs it. When a feature starts to use a tool, raise its severity to an error
-- by setting `needed_now = true`. (jj has its own rule, see check_tools.)
-- Keep this list in step with scripts/install.sh and docs/PREREQUISITES.md.
local tools = {
  { name = "git", exes = { "git" }, needed_now = true, used_for = "version control, plugin installs and the pre-push hook" },
  {
    name = "gitleaks (secret scanner)",
    exes = { "gitleaks" },
    needed_now = true,
    used_for = "the push-time secret scan; without it every push is blocked, and pushing is not safe",
  },
  -- jj is used by the push-scan alias in a jj repository. A missing jj is an error when the
  -- Fondue clone is a jj repository and a warning otherwise (see check_tools).
  { name = "jj", exes = { "jj" }, jj_rule = true },
  { name = "tree-sitter CLI", exes = { "tree-sitter" }, used_for = "building Treesitter parsers" },
  { name = "C compiler", exes = { "cc", "gcc", "clang" }, used_for = "building Treesitter parsers" },
  { name = "ripgrep", exes = { "rg" }, used_for = "project text search" },
  { name = "fd", exes = { "fd" }, used_for = "file search" },
}

local function check_tools()
  health.start("Fondue: Neovim and tools")

  local v = vim.version()
  local vstr = string.format("%d.%d.%d", v.major, v.minor, v.patch)
  if vim.fn.has("nvim-0.12") == 1 then
    health.ok("Neovim " .. vstr .. " (0.12 or later required)")
  else
    health.error("Neovim " .. vstr .. " is older than the required 0.12", "Upgrade Neovim, then run scripts/install.sh")
  end

  for _, tool in ipairs(tools) do
    local found
    for _, exe in ipairs(tool.exes) do
      if vim.fn.executable(exe) == 1 then
        found = exe
        break
      end
    end
    if found then
      local ver = first_line({ found, "--version" }) or first_line({ found, "version" })
      health.ok(tool.name .. ": " .. (ver or found))
    elseif tool.jj_rule then
      local root = fondue_repo()
      if root and vim.uv.fs_stat(root .. "/.jj") then
        health.error(
          "jj is not installed, but this Fondue clone is a jj repository: jj pushes cannot be scanned",
          "Run scripts/install.sh (Homebrew: jj, Arch: jujutsu)"
        )
      else
        health.warn(
          "jj is not installed (needed for the push-scan alias if you use jj; an error inside a jj repository)",
          "Run scripts/install.sh"
        )
      end
    else
      local msg = tool.name .. " is not installed (used for " .. tool.used_for .. ")"
      if tool.needed_now then
        health.error(msg, "Run scripts/install.sh")
      else
        health.warn(msg, "Run scripts/install.sh")
      end
    end
  end
end

-- Autocmds cannot be inspected inside a Lua callback, so this matches on what
-- we can see: the command, description, group name, and the file that defined the
-- callback. It is a best-effort tripwire, not a proof.
local function autocmd_text(a)
  local parts = { a.command or "", a.desc or "", a.group_name or "" }
  if type(a.callback) == "function" then
    local info = debug.getinfo(a.callback, "S")
    parts[#parts + 1] = info and info.source or ""
  elseif type(a.callback) == "string" then
    parts[#parts + 1] = a.callback
  end
  return table.concat(parts, " "):lower()
end

local function risky_autocmds()
  local found = {}
  local function scan(events, patterns, label)
    for _, a in ipairs(vim.api.nvim_get_autocmds({ event = events })) do
      local text = autocmd_text(a)
      for _, p in ipairs(patterns) do
        if text:find(p) then
          found[#found + 1] = string.format("%s on %s (group: %s)", label, a.event, a.group_name or "none")
          break
        end
      end
    end
  end
  -- Formatting when a file is written.
  scan({ "BufWritePre", "BufWrite", "BufWritePost", "FileWritePre" }, { "format", "conform", "fmt" }, "format-on-save")
  -- Saving when focus or the buffer changes.
  scan(
    { "FocusLost", "BufLeave", "WinLeave", "InsertLeave", "TextChanged", "TextChangedI", "CursorHold", "CursorHoldI" },
    { "write", "update", "save", "wall", "%f[%a]wa%f[%A]", "%f[%a]w%f[%A]" },
    "autosave"
  )
  return found
end

local function check_invariants()
  health.start("Fondue: configuration")

  -- Leader key
  if vim.g.mapleader == " " then
    health.ok("Leader key is Space")
  else
    health.error("Leader key is not Space", "init.lua must set vim.g.mapleader = ' ' before anything else")
  end

  -- Keymap registry
  local ok, registry = pcall(require, "fondue.keymap_registry")
  if not ok then
    health.error("Keymap registry could not be loaded: " .. tostring(registry))
  else
    local conflicts = registry.conflicts()
    if #conflicts == 0 then
      health.ok("Keymap registry: no conflicts, every key has a description")
    else
      for _, c in ipairs(conflicts) do
        health.error("Keymap registry (" .. c.kind .. "): " .. c.message, "Fix the entry in nvim/lua/fondue/keymaps.lua")
      end
    end
  end

  -- netrw
  if vim.g.loaded_netrw == 1 and vim.g.loaded_netrwPlugin == 1 and vim.fn.exists("#FileExplorer") == 0 then
    health.ok("netrw is disabled")
  else
    health.error("netrw is active", "init.lua must set vim.g.loaded_netrw and vim.g.loaded_netrwPlugin to 1 first")
  end

  -- No format-on-save, no autosave
  local risky = risky_autocmds()
  if vim.o.autowrite or vim.o.autowriteall then
    risky[#risky + 1] = "the 'autowrite' or 'autowriteall' option is on"
  end
  if #risky == 0 then
    health.ok("No format-on-save and no autosave found")
  else
    for _, r in ipairs(risky) do
      health.error("Found " .. r, "Fondue never saves or formats automatically")
    end
  end
end

-- Which clipboard helper does a local (non-SSH) session need, and is it there?
-- Pure logic (no Neovim calls) so it can be tested: `env` has os ("mac" or "linux"),
-- wayland (boolean: is WAYLAND_DISPLAY set?) and has(name) (is this program installed?).
-- Returns { ok = boolean, message = string, advice = string|nil }.
function M.clipboard_helper_status(env)
  if env.os == "mac" then
    if env.has("pbcopy") and env.has("pbpaste") then
      return { ok = true, message = "Clipboard helper: pbcopy and pbpaste are present" }
    end
    return { ok = false, message = "pbcopy or pbpaste is missing, so the system clipboard cannot work", advice = "They ship with macOS; check your PATH" }
  end
  local fix = "Install wl-clipboard (Arch: sudo pacman -S wl-clipboard, or run scripts/install.sh)"
  if env.wayland then
    if env.has("wl-copy") and env.has("wl-paste") then
      return { ok = true, message = "Clipboard helper: wl-copy and wl-paste are present (Wayland)" }
    end
    return { ok = false, message = "No Wayland clipboard helper (wl-copy/wl-paste): the system clipboard (unnamedplus) will not work", advice = fix }
  end
  -- X11 or no Wayland: accept any known helper (xclip and xsel are accepted for X11).
  for _, tool in ipairs({ "wl-copy", "xclip", "xsel" }) do
    if env.has(tool) then
      return { ok = true, message = "Clipboard helper: " .. tool .. " is present" }
    end
  end
  return { ok = false, message = "No clipboard helper (wl-copy, xclip or xsel) found: the system clipboard (unnamedplus) will not work", advice = fix }
end

local function check_clipboard()
  local over_ssh = vim.env.SSH_TTY ~= nil or vim.env.SSH_CONNECTION ~= nil
  if not over_ssh then
    -- Local session: Neovim needs a helper program for the system clipboard.
    health.start("Fondue: clipboard")
    local st = M.clipboard_helper_status({
      os = vim.fn.has("mac") == 1 and "mac" or "linux",
      wayland = (vim.env.WAYLAND_DISPLAY or "") ~= "",
      has = function(name)
        return vim.fn.executable(name) == 1
      end,
    })
    if st.ok then
      health.ok(st.message)
    else
      health.error(st.message, st.advice)
    end
    return
  end
  -- SSH session: copying goes out as OSC 52, so no local helper is needed.
  health.start("Fondue: clipboard (SSH session)")
  local cb = vim.g.clipboard
  if type(cb) == "table" and cb.name == "OSC 52" then
    health.ok("OSC 52 clipboard provider is in use")
    health.info("The terminal must allow OSC 52 writes (kitty does by default); check it with docs/SMOKE_TEST.md")
  else
    health.warn("This is an SSH session but the OSC 52 clipboard provider is not in use", "See nvim/lua/fondue/core/clipboard.lua")
  end
end

local function check_repo()
  local root = fondue_repo()
  if not root then
    return -- not running from a Fondue clone (for example a copied config): nothing to check
  end
  health.start("Fondue: repository safety")

  local has_git = vim.uv.fs_stat(root .. "/.git") ~= nil
  local has_jj = vim.uv.fs_stat(root .. "/.jj") ~= nil

  if not has_git and not has_jj then
    health.warn(
      root .. " is not a git or jj repository, so the push-time secret scan is not active",
      "Once the repository exists, run scripts/setup-repo"
    )
  end

  if has_git then
    local hooks = run({ "git", "-C", root, "config", "--local", "--get", "core.hooksPath" })
    if hooks == "scripts/git-hooks" then
      health.ok("Git pre-push hook is configured (core.hooksPath = scripts/git-hooks)")
    else
      health.error("Git pre-push hook is not configured: git pushes would not be scanned", "Run scripts/setup-repo")
    end
  end

  if has_jj then
    local alias = vim.fn.executable("jj") == 1 and run({ "jj", "-R", root, "config", "get", "aliases.push" }) or nil
    if alias and alias:find("scripts/secret-scan", 1, true) then
      health.ok("jj push alias is configured (use `jj push`, not `jj git push`)")
    else
      health.error("jj push alias is not configured: jj pushes would not be scanned", "Run scripts/setup-repo (needs jj installed)")
    end
  end

  if has_git or has_jj then
    health.warn(
      "Confirm GitHub secret-scanning push protection is enabled on the public repository",
      { "Repository settings > Code security > Push protection", "This cannot be checked from here" }
    )
  end
end

function M.check()
  check_tools()
  check_invariants()
  check_clipboard()
  check_repo()
end

return M
