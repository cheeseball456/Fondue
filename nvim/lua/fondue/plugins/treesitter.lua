-- Treesitter: real syntax trees for highlighting and folding, instead of Vim's
-- pattern-based syntax files. This uses the `main` branch of nvim-treesitter, the
-- rewrite for Neovim 0.12; the old `master` branch does not work with it.
--
-- The plugin is not lazy-loaded (it does not support that). It only installs and
-- updates parsers; starting highlighting is done in lua/fondue/treesitter.lua.
-- Pinning: its version tags belong to the old branch, so the lockfile alone pins it.
return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    -- After the plugin is installed or updated, rebuild the parsers so they match its queries.
    -- With a screen (`:Lazy update`) this runs in the background so the editor stays usable,
    -- and a parser that fails to rebuild is reported when the rebuild ends. Without a screen
    -- (the installer's plugin restore) it waits, because the process would exit before a
    -- background rebuild finished.
    build = function()
      local headless = #vim.api.nvim_list_uis() == 0
      require("fondue.treesitter").install({
        update = true,
        wait = headless,
        on_done = function(result)
          if #result.failed == 0 then
            return
          end
          -- One short line: a long message makes Neovim stop and wait for Enter. The reasons
          -- are in :messages (nvim-treesitter prints each one as it happens).
          local names = {}
          for index, failure in ipairs(result.failed) do
            if index <= 3 then
              names[#names + 1] = failure.name
            end
          end
          local more = #result.failed > 3 and (" and " .. (#result.failed - 3) .. " more") or ""
          vim.notify(
            "Fondue: could not rebuild the Treesitter parsers for " .. table.concat(names, ", ") .. more
              .. " (see :messages); run scripts/install.sh to retry",
            vim.log.levels.WARN
          )
        end,
      })
    end,
  },
  {
    -- Colours nested brackets by depth, using the syntax tree.
    "HiPhish/rainbow-delimiters.nvim",
    version = "^0.12",
    event = { "BufReadPost", "BufNewFile" },
  },
}
