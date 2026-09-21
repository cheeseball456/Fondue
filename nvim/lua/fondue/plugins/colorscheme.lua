-- carbonfox (from nightfox.nvim) is the default colourscheme, plus the icon set
-- other plugins use. Pinning: nightfox publishes semver tags (v3.x), so it gets
-- a version range; nvim-web-devicons tags are not consistent semver (v0, v0.99,
-- v0.100), so it is pinned by the lockfile alone.
return {
  {
    "EdenEast/nightfox.nvim",
    version = "^3",
    lazy = false, -- the colourscheme must be ready at startup
    priority = 1000, -- and load before other plugins
    config = function()
      -- pcall: if the scheme is missing or broken, keep the built-in one and carry on.
      pcall(vim.cmd.colorscheme, "carbonfox")
    end,
  },
  {
    "nvim-tree/nvim-web-devicons",
    lazy = true, -- loaded on demand by plugins that use icons
  },
}
