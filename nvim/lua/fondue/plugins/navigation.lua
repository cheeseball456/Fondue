-- Moving around a project: fuzzy finding, the file tree, the centred layout, sessions
-- and the start screen, project-wide diagnostics and TODOs, and search-and-replace.
--
-- snacks.nvim itself is declared in plugins/editing.lua (its bigfile, indent and words
-- modules); this file adds its picker, explorer and dashboard modules through a
-- second spec entry for the same plugin. lazy.nvim merges every
-- spec entry for one plugin by calling each entry's `opts` function in turn, passing
-- the table built so far, so both entries mutate and return that same table (accept
-- `opts`, add keys, return it) rather than each returning a fresh table of its own,
-- which would silently discard whatever the other entry added.
--
-- The explorer and dashboard modules are configured but left `enabled = false`: their
-- own automatic behaviour (the explorer replacing a directory buffer on BufEnter, the
-- dashboard showing itself on UIEnter) would otherwise race fondue.lib.session, which
-- must be the one to decide what a `nvim`/`nvim .` start actually shows. Calling
-- `Snacks.explorer.open/reveal` and `Snacks.dashboard.open` still works with the
-- module "disabled": that flag only gates the automatic hooks, not the functions.
return {
  {
    "folke/snacks.nvim",
    opts = function(_, opts)
      opts.picker = { enabled = true }
      opts.explorer = { enabled = false, replace_netrw = false }
      opts.dashboard = {
        enabled = false,
        sections = {
          { section = "header" },
          { section = "keys", gap = 1, padding = 1 },
          { section = "recent_files", limit = 8, padding = 1 },
          { section = "startup" },
        },
      }
      return opts
    end,
  },

  -- Centred layout: text sits in roughly the middle third of the window, kept current
  -- on resize.
  {
    "shortcuts/no-neck-pain.nvim",
    version = "^3",
    lazy = false, -- must be ready before the first buffer, so the very first file is centred too
    opts = function()
      return {
        width = math.max(1, math.floor(vim.o.columns / 3)),
        -- "safe": debounced, so the start screen or a restored session settles first.
        autocmds = { enableOnVimEnter = "safe" },
        -- Without this, no-neck-pain does not recognise snacks.picker's own windows (the
        -- file tree, opened on the left by plugins/navigation.lua's explorer config
        -- below) as a side panel: it treats them as ordinary content and tries to add
        -- its own centring padding pair around them too, on top of the pair already
        -- centring the real buffer. That produces extra, lopsided windows and can leave
        -- focus on one of them instead of the tree. `snacks_picker` is one of
        -- no-neck-pain's own named integrations, matched against a window's filetype;
        -- the sidebar layout snacks.picker opens for the explorer is actually three
        -- windows (an outer `snacks_layout_box`, the `snacks_picker_list`, and the
        -- `snacks_picker_input` prompt), so all three filetypes need registering here
        -- (no-neck-pain's integration matching is not limited to its own built-in
        -- names: any filetype can be added as a key, matched the same way).
        integrations = {
          snacks_picker = { position = "left" },
          snacks_layout_box = { position = "left" },
        },
      }
    end,
    config = function(_, opts)
      require("no-neck-pain").setup(opts)
      vim.api.nvim_create_autocmd("VimResized", {
        group = vim.api.nvim_create_augroup("fondue_centred_width", { clear = true }),
        desc = "Keep the centred column at roughly a third of the window width",
        callback = function()
          pcall(require("no-neck-pain").resize, math.max(1, math.floor(vim.o.columns / 3)))
        end,
      })
    end,
  },

  -- Project-wide search and replace, kept separate from snacks.picker's grep: it has
  -- its own review-and-confirm step before anything is written to disk.
  {
    "MagicDuck/grug-far.nvim",
    version = "^1",
    cmd = "GrugFar",
    opts = {},
  },

  -- Sessions. Loads on BufReadPre (a real file being read) for a normal `nvim <file>`
  -- start; fondue.lib.session forces it to load early for the no-file-argument case,
  -- where that decision has to be made before any file is read.
  {
    "folke/persistence.nvim",
    version = "^3",
    event = "BufReadPre",
    opts = {},
  },

  -- TODO/FIXME/WARN/NOTE in comments, feeding Space f t.
  {
    "folke/todo-comments.nvim",
    version = "^1",
    event = "VeryLazy",
    opts = {},
  },
}
