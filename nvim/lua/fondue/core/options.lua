-- Plain Neovim options. Movement keys (arrows, h/j/k/l) are deliberately not touched.
local o = vim.o

o.number = true
o.cursorline = true -- highlight the line the cursor is on
o.signcolumn = "yes" -- keep the sign column so the text does not jump
o.scrolloff = 4
o.splitright = true
o.splitbelow = true
o.ignorecase = true -- search ignores case...
o.smartcase = true -- ...unless you type a capital letter
o.undofile = true -- keep undo history across sessions
o.timeoutlen = 400 -- how long to wait for the next key (which-key menu delay)
o.foldlevelstart = 99 -- a file opens with every fold open

-- No autosave, ever: files are written only when you ask (Space w or :w).
-- These are already off by default; setting them makes the intent explicit.
o.autowrite = false
o.autowriteall = false
