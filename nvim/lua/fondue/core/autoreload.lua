-- Auto-reload of externally-changed buffers (FR-030), most notably from Claude editing a
-- file directly while its panel is open.
--
-- `autoread` only takes effect on a few specific events, not continuously, so it must be
-- paired with a `checktime` autocommand -- the standard combination (design.md D7).
-- `checktime` itself only reloads a buffer that has NO unsaved local changes; for one
-- that does, Neovim's own default `FileChangedShell` handling already shows a warning
-- (`W12`) and changes nothing, satisfying FR-030's "clearly warned, neither version
-- silently lost" without any extra code here -- confirmed headless (see design.md).
vim.o.autoread = true

vim.api.nvim_create_autocmd({ "FocusGained", "CursorHold", "BufEnter" }, {
  group = vim.api.nvim_create_augroup("fondue_autoreload", { clear = true }),
  desc = "Pick up external changes to the current buffer's file, if it has no local changes",
  callback = function()
    -- Only for a real, named file buffer: :checktime on a scratch/terminal/unnamed
    -- buffer either does nothing useful or, for a terminal, is actively wrong.
    if vim.bo.buftype == "" and vim.api.nvim_buf_get_name(0) ~= "" then
      vim.cmd("checktime")
    end
  end,
})
