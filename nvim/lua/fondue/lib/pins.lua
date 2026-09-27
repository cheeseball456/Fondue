-- Pinned files: up to four files, remembered only for this Neovim session. Never
-- written to disk, never restored by session persistence, and none pinned by default.
local M = {}

M.MAX = 4

-- Slot 1 to M.MAX, each either an absolute file path or nil.
local slots = {}

-- Pin the current buffer's file into the next free slot. Reports the list is full
-- instead of pinning a fifth file.
function M.pin()
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    vim.notify("Fondue: this buffer has no file to pin", vim.log.levels.WARN)
    return
  end
  for i = 1, M.MAX do
    if slots[i] == path then
      vim.notify(string.format("Fondue: already pinned as %d", i), vim.log.levels.INFO)
      return
    end
  end
  for i = 1, M.MAX do
    if slots[i] == nil then
      slots[i] = path
      vim.notify(string.format("Fondue: pinned as %d (%s)", i, vim.fn.fnamemodify(path, ":~:.")), vim.log.levels.INFO)
      return
    end
  end
  vim.notify("Fondue: all " .. M.MAX .. " pin slots are full", vim.log.levels.WARN)
end

-- Open the file pinned in slot n, or do nothing if that slot is empty.
function M.jump(n)
  local path = slots[n]
  if not path then
    return
  end
  vim.cmd.edit(vim.fn.fnameescape(path))
end

-- The current pins, 1 to M.MAX (nil for an empty slot). Used by the tests.
function M.list()
  return vim.deepcopy(slots)
end

-- Clear every pin. Used by the tests; there is no keymap for this.
function M.clear()
  slots = {}
end

return M
