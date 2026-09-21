-- The actions behind the code-tool keys in keymaps.lua (format, inlay hints, code actions).
local M = {}

-- Format the buffer, or the selected lines when called from visual mode.
-- conform uses the formatter configured for the file type and falls back to the language
-- server; if neither can format the buffer it says so and the buffer is left unchanged.
function M.format()
  local options = { lsp_format = "fallback", timeout_ms = 5000 }

  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "\22" then
    -- Selection: format whole lines from the first to the last selected line.
    local first = vim.fn.getpos("v")[2]
    local last = vim.fn.getpos(".")[2]
    if first > last then
      first, last = last, first
    end
    local last_text = vim.api.nvim_buf_get_lines(0, last - 1, last, false)[1] or ""
    options.range = { start = { first, 0 }, ["end"] = { last, #last_text } }
    vim.cmd("normal! \27") -- leave visual mode
  end

  -- format() returns false when there was nothing to run.
  if not require("conform").format(options) then
    vim.notify("Fondue: cannot format this buffer (no formatter or language server available for it)", vim.log.levels.WARN)
  end
end

-- Switch inlay hints (small inline labels such as parameter names) off or on for this buffer.
function M.toggle_inlay_hints()
  local buf = vim.api.nvim_get_current_buf()
  vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = buf }), { bufnr = buf })
end

-- List the code actions (quick fixes and refactorings) available at the cursor,
-- or for the selected lines in visual mode.
function M.code_action()
  vim.lsp.buf.code_action()
end

return M
