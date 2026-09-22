-- nvim-lint runs command-line linters and shows their findings in the same diagnostics
-- list as the language servers'. Only shellcheck (bash and shell files) is used here:
-- Python is linted by the ruff language server, so running ruff here too would show
-- every finding twice.
-- No version tags are published, so the lockfile alone pins it.
return {
  {
    "mfussenegger/nvim-lint",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      local lint = require("lint")
      lint.linters_by_ft = {
        sh = { "shellcheck" }, -- bash scripts have the file type "sh"
        bash = { "shellcheck" },
      }

      local function run_lint()
        -- Skip quietly when shellcheck is not installed (the health check reports it).
        if vim.fn.executable("shellcheck") == 1 then
          lint.try_lint()
        end
      end

      -- Lint when a file is read, when it is saved and when insert mode is left.
      vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "InsertLeave" }, {
        group = vim.api.nvim_create_augroup("fondue_lint", { clear = true }),
        desc = "Run the linter for this file type",
        callback = run_lint,
      })
      -- This plugin loads on the first file read, so that read has already happened.
      -- Wait a moment so the file type has been detected.
      vim.schedule(run_lint)
    end,
  },
}
