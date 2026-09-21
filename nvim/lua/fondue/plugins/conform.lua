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
    },
  },
}
