-- Language servers through Neovim's built-in LSP (vim.lsp.config / vim.lsp.enable).
-- nvim-lspconfig provides each server's default command and root markers; here we
-- add only what we want to change. A server is switched on only when its program
-- exists, so a machine that lacks one carries on quietly.
local M = {}

-- Settings for individual servers, keyed by the nvim-lspconfig server name.
local function server_settings()
  -- Lua: know the `vim` global, and treat a jj workspace (a `.jj` folder, no `.git`) as a
  -- project root. Without any root marker the Lua server stays silent.
  local lua_markers = vim.deepcopy(vim.lsp.config.lua_ls.root_markers or { ".git" })
  local last = lua_markers[#lua_markers]
  if type(last) == "table" then
    table.insert(last, ".jj") -- the last group is the ".git" group; markers in a group rank equally
  else
    table.insert(lua_markers, ".jj")
  end

  return {
    basedpyright = {
      settings = {
        basedpyright = {
          analysis = {
            -- ruff already reports these two, so switch them off here: each is shown once.
            -- basedpyright keeps doing what ruff cannot: type checking.
            diagnosticSeverityOverrides = {
              reportUnusedImport = "none",
              reportUndefinedVariable = "none",
            },
          },
        },
      },
    },
    lua_ls = {
      root_markers = lua_markers,
      settings = { Lua = { runtime = { version = "LuaJIT" }, diagnostics = { globals = { "vim" } } } },
    },
    -- sourcekit-lsp also handles C and friends; we only want it for Swift.
    sourcekit = { filetypes = { "swift" } },
  }
end

function M.setup()
  -- Settings every server gets: the extra abilities the completion menu understands.
  local common = {}
  local ok, blink = pcall(require, "blink.cmp")
  if ok then
    common.capabilities = blink.get_lsp_capabilities()
  end
  vim.lsp.config("*", common)

  for name, settings in pairs(server_settings()) do
    vim.lsp.config(name, settings)
  end

  -- Switch on each server whose program exists.
  local enable = {}
  for _, tool in ipairs(require("fondue.tools").tools) do
    if tool.kind == "server" and require("fondue.tools").is_available(tool) then
      enable[#enable + 1] = tool.server
    end
  end
  -- Swift: only if the machine already has sourcekit-lsp (it comes with Xcode on the Mac).
  if vim.fn.executable("sourcekit-lsp") == 1 then
    enable[#enable + 1] = "sourcekit"
  end
  vim.lsp.enable(enable)

  -- Inlay hints (small inline labels such as parameter names) are on by default.
  -- Space c h switches them off and on for the current buffer.
  vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("fondue_lsp_attach", { clear = true }),
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client and client:supports_method("textDocument/inlayHint", args.buf) then
        vim.lsp.inlay_hint.enable(true, { bufnr = args.buf })
      end
    end,
  })
end

return M
