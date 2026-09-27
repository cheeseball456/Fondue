-- THE single table of every custom key. Plugin specs never define keys of their own.
-- To add a key: add a line to `keys` below. The registry (keymap_registry.lua)
-- checks it is not already used and that it has a description.
--
-- Each key: { mode = "n", lhs = "<leader>w", desc = "What it does", action = ... }
-- (`mode` may be left out for normal mode.)
return {
  -- Groups are just labels for a prefix. They bind nothing, so an empty group is fine;
  -- keys are added to them as features are added.
  groups = {
    { prefix = "<leader>s", desc = "Search" },
    { prefix = "<leader>v", desc = "Version control" },
    { prefix = "<leader>f", desc = "Fix" },
    { prefix = "<leader>d", desc = "Debug and test" },
    { prefix = "<leader>l", desc = "LSP navigation" },
    { prefix = "<leader>r", desc = "Refactor" },
    { prefix = "<leader>a", desc = "AI" },
    { prefix = "<leader>c", desc = "Code tools" },
    { prefix = "<leader>n", desc = "Navigation" },
  },

  keys = {
    { lhs = "<leader>w", desc = "Save", action = "<cmd>write<cr>" },
    -- The undo tree ships with Neovim 0.12 but must be loaded with :packadd first.
    { lhs = "<leader>u", desc = "Undo tree", action = "<cmd>packadd nvim.undotree | Undotree<cr>" },
    { lhs = "<leader>p", desc = "Plugin manager", action = "<cmd>Lazy<cr>" },

    -- File tree: a fallback for unfamiliar territory, not the everyday way to move
    -- around (that stays LSP go-to-definition and fuzzy file search, below). Reveals
    -- the current file's position in the tree, rather than always the project root;
    -- an unnamed buffer (for example the start screen) has nothing to reveal. If the
    -- tree is already open but not focused (for example the cursor moved back into
    -- the code), pressing this again moves focus into it, rather than doing nothing;
    -- pressing it while focus is already in the tree still toggles it closed, as before.
    -- "Already in the tree" checks all three of its own windows (fondue.lib.session's
    -- own `TREE_FILETYPES`, shared rather than re-typed here so the two cannot drift
    -- apart the way an earlier version of this check did).
    {
      lhs = "<leader>e",
      desc = "File tree",
      action = function()
        local explorer = Snacks.picker.get({ source = "explorer" })[1]
        if explorer and not require("fondue.lib.session").TREE_FILETYPES[vim.bo.filetype] then
          explorer:focus()
        elseif vim.api.nvim_buf_get_name(0) ~= "" then
          Snacks.explorer.reveal()
        else
          Snacks.explorer.open()
        end
      end,
    },

    -- Pinned files: up to four, remembered only for this session.
    {
      lhs = "<leader>m",
      desc = "Pin current file",
      action = function()
        require("fondue.lib.pins").pin()
      end,
    },
    {
      lhs = "<leader>1",
      desc = "Jump to pin 1",
      action = function()
        require("fondue.lib.pins").jump(1)
      end,
    },
    {
      lhs = "<leader>2",
      desc = "Jump to pin 2",
      action = function()
        require("fondue.lib.pins").jump(2)
      end,
    },
    {
      lhs = "<leader>3",
      desc = "Jump to pin 3",
      action = function()
        require("fondue.lib.pins").jump(3)
      end,
    },
    {
      lhs = "<leader>4",
      desc = "Jump to pin 4",
      action = function()
        require("fondue.lib.pins").jump(4)
      end,
    },

    -- Search group, all through snacks.picker except sr, which needs its own
    -- review-and-confirm step and so opens grug-far instead.
    {
      lhs = "<leader>sf",
      desc = "Find files",
      action = function()
        Snacks.picker.files()
      end,
    },
    {
      lhs = "<leader>st",
      desc = "Search text (project)",
      action = function()
        Snacks.picker.grep()
      end,
    },
    { lhs = "<leader>sr", desc = "Search and replace (project)", action = "<cmd>GrugFar<cr>" },
    {
      lhs = "<leader>so",
      desc = "Recent files",
      action = function()
        Snacks.picker.recent()
      end,
    },
    {
      lhs = "<leader>sb",
      desc = "Open buffers",
      action = function()
        Snacks.picker.buffers()
      end,
    },
    {
      lhs = "<leader>sk",
      desc = "Search keymaps",
      action = function()
        Snacks.picker.keymaps()
      end,
    },
    {
      lhs = "<leader>sh",
      desc = "Search help",
      action = function()
        Snacks.picker.help()
      end,
    },

    -- Diagnostics and TODOs: two lists that feel like one family.
    {
      lhs = "<leader>fl",
      desc = "Diagnostics (project)",
      action = function()
        Snacks.picker.diagnostics()
      end,
    },
    {
      lhs = "<leader>ft",
      desc = "TODO / FIXME list",
      action = function()
        Snacks.picker.todo_comments()
      end,
    },

    -- Code tools. Formatting happens only when you press this; never on save.
    {
      mode = { "n", "x" },
      lhs = "<leader>cf",
      desc = "Format buffer or selection",
      action = function()
        require("fondue.code_tools").format()
      end,
    },
    {
      lhs = "<leader>ch",
      desc = "Toggle inlay hints",
      action = function()
        require("fondue.code_tools").toggle_inlay_hints()
      end,
    },
    -- Fix group: what the language server offers at the cursor (or for the selection).
    {
      mode = { "n", "x" },
      lhs = "<leader>fa",
      desc = "Code action",
      action = function()
        require("fondue.code_tools").code_action()
      end,
    },
  },
}
