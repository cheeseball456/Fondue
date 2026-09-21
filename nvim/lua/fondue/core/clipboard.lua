-- Copy and paste use the system clipboard.
-- Over SSH there is no local clipboard to talk to, so copying is sent to the
-- terminal as an OSC 52 escape sequence, which puts the text in the clipboard
-- of the machine you are sitting at.
vim.o.clipboard = "unnamedplus"

local over_ssh = vim.env.SSH_TTY ~= nil or vim.env.SSH_CONNECTION ~= nil

if over_ssh then
  local osc52 = require("vim.ui.clipboard.osc52")

  -- Many terminals refuse OSC 52 reads, so paste from Neovim's own registers instead.
  local function paste()
    return { vim.fn.split(vim.fn.getreg(""), "\n"), vim.fn.getregtype("") }
  end

  vim.g.clipboard = {
    name = "OSC 52",
    copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
    paste = { ["+"] = paste, ["*"] = paste },
  }
end
