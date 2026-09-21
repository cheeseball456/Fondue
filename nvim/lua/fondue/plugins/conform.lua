-- conform.nvim runs formatters, but ONLY when asked (Space c f). There is deliberately
-- no format-on-save option here. Which formatter serves which language is set below;
-- a language without one falls back to the language server's own formatting.
-- Pinning: conform publishes semver tags (v9.x).
return {
  {
    "stevearc/conform.nvim",
    version = "^9",
    lazy = true, -- loaded the first time Space c f is pressed (or :ConformInfo is run)
    cmd = { "ConformInfo" },
    opts = {
      formatters_by_ft = {
        python = { "ruff_format" },
        javascript = { "prettier" },
        json = { "prettier" },
        jsonc = { "prettier" },
        sh = { "shfmt" },
        bash = { "shfmt" },
        lua = { "stylua" },
      },
      default_format_opts = { lsp_format = "fallback" },
      formatters = {
        -- shfmt indents with tabs unless told otherwise. Two spaces is what the rest of this
        -- configuration uses, so that is the default, BUT only when the script's project has no
        -- .editorconfig: giving shfmt an explicit -i would override a project's own indentation
        -- settings, and other people's projects must keep their style.
        shfmt = {
          prepend_args = function(_, context)
            local has_editorconfig = vim.fs.find(".editorconfig", { upward = true, path = context.dirname })[1] ~= nil
            return has_editorconfig and {} or { "-i", "2" }
          end,
        },
        -- stylua looks for stylua.toml or .stylua.toml from the file's folder upwards and the nearest
        -- one wins: this configuration's nvim/stylua.toml (two spaces, double quotes) for the files in
        -- this folder, and a project's own file for a project's Lua files.
      },
    },
  },
}
