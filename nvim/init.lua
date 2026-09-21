-- Fondue: thin bootstrap. Feature logic lives under lua/fondue/, not here.

-- 1. Version floor. Fondue needs Neovim 0.12 or later; on anything older we
--    print one clear message and stop, so the editor stays usable and there is
--    no stack trace.
if vim.fn.has("nvim-0.12") == 0 then
  local v = vim.version()
  vim.api.nvim_echo({
    {
      string.format(
        "Fondue needs Neovim 0.12 or later, but this is %d.%d.%d. Configuration not loaded.",
        v.major, v.minor, v.patch
      ),
      "WarningMsg",
    },
  }, true, {})
  return
end

-- 2. Leader key: must be set before any mapping is registered.
vim.g.mapleader = " "

-- 3. Turn netrw off at the very start, so `nvim .` never opens it.
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.g.loaded_netrwSettings = 1
vim.g.loaded_netrwFileHandlers = 1

-- 4. Install lazy.nvim if it is missing (based on the snippet in its docs).
--    One change from that snippet: we clone the default branch (not `stable`)
--    and then move to the commit recorded in lazy-lock.json. lazy.nvim cannot
--    do this for itself on a first run, and it would otherwise overwrite the
--    lockfile entry for lazy.nvim with whatever it just cloned.
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local out = vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git", lazypath,
  })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    -- Wait for a keypress only when there is a screen to read the message on.
    if #vim.api.nvim_list_uis() > 0 then
      vim.fn.getchar()
    end
    os.exit(1)
  end

  -- Use the locked commit if there is a lockfile (protected: never block startup).
  local lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json"
  local ok, lock = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(lockfile), "\n"))
  end)
  local commit = ok and lock["lazy.nvim"] and lock["lazy.nvim"].commit
  if commit then
    local co = vim.fn.system({ "git", "-C", lazypath, "checkout", "--quiet", commit })
    if vim.v.shell_error ~= 0 then
      -- Do not stay silent: lazy.nvim will now stay at the latest commit and rewrite the
      -- lockfile entry. Carry on so the editor is still usable.
      vim.api.nvim_echo({
        { "Fondue: could not check out lazy.nvim at the locked commit " .. commit .. ":\n", "WarningMsg" },
        { co, "WarningMsg" },
        { "\nlazy.nvim stays at the latest version and lazy-lock.json will change; review it before committing.", "WarningMsg" },
      }, true, {})
    end
  end
end
vim.opt.rtp:prepend(lazypath)

-- 5. Load in a fixed order: core defaults, then the keymap registry, then plugins.
require("fondue.core")
require("fondue.keymap_registry").setup(require("fondue.keymaps"))

require("lazy").setup({
  spec = { { import = "fondue.plugins" } },
  -- Updates are deliberate: never check for them in the background.
  checker = { enabled = false },
  change_detection = { notify = false },
  -- The config directory is a link into the repo, so the lockfile lands in nvim/.
  lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json",
  -- First run: if nightfox is not installed yet, use a built-in scheme meanwhile.
  install = { colorscheme = { "carbonfox", "habamax" } },
})

-- 6. Behaviour that is not a plugin. This comes after lazy.nvim because it trims the
--    runtimepath, and the next lines put back what they need.
require("fondue.treesitter").setup() -- highlighting and folds per file type
require("fondue.spell").setup() -- UK English spelling
