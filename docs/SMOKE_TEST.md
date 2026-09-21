# Checking your installation

A manual checklist for checking that your Fondue installation works, and for running again
after you update plugins. Start Neovim the way you installed it: `nvim` if you used
`scripts/install.sh --overwrite`, or `NVIM_APPNAME=NAME nvim` if you used
`scripts/install.sh --appname NAME` (for example `NVIM_APPNAME=fondue nvim`).

Work through it top to bottom and note anything that fails.

## Install and health

- [ ] `:checkhealth` shows no new errors from lazy.nvim (lua and luarocks warnings from lazy
      about `luarocks` are harmless: no plugin here needs it).
- [ ] `:checkhealth fondue` opens a report with sections for Neovim and tools, configuration,
      clipboard, and repository safety (the last only when your configuration is linked from a
      clone of the Fondue repository). It shows no errors. Warnings are acceptable for tools
      the report says are only used by features you may not use yet, and for the reminder to
      confirm GitHub push protection.
      A missing jj is an error inside a jj repository (the push scan alias needs it) and a
      warning elsewhere. On Arch, a missing `wl-clipboard` is an error in the clipboard section.

## Startup and appearance

- [ ] Neovim starts without any messages.
- [ ] The colourscheme is `carbonfox` (`:colorscheme` prints `carbonfox`).
- [ ] Nerd Font: icons render in the terminal (for example run
      `:lua print(vim.fn.nr2char(0xf057) .. " " .. vim.fn.nr2char(0xf071))` and check you see two
      icons, not boxes or question marks). If not, choose the Nerd Font in the terminal's settings.

## Keys

- [ ] Press `Space` and wait: the menu lists `w Save`, `u Undo tree`, `p Plugin manager`.
      (A group such as Search appears in the menu once it contains keys.)
- [ ] `Space w` saves the current buffer.
- [ ] `Space u` opens the undo tree; pressing `Space u` again closes it.
- [ ] `Space p` opens the lazy.nvim plugin manager window.

## Saving

- [ ] Nothing saves automatically. Edit a file, then switch buffer, click away from the window,
      and leave insert mode: the file on disk does not change until you save with `Space w` (or `:w`).

## Movement

- [ ] Arrow keys and `h j k l` move the cursor as in stock Neovim.

## Clipboard

- [ ] Local: yank a line (`yy`) and paste it into another application, and copy text in
      another application and paste it into Neovim (`p`). On Arch this needs `wl-clipboard`.
- [ ] Over SSH: from your local machine, SSH to another machine, open Neovim there, yank some
      text (`yy`), then paste in a local application. The text arrives (this needs a terminal that
      allows OSC 52 writes; kitty does by default). `:checkhealth fondue` in that session
      reports "OSC 52 clipboard provider is in use".

## Starting Neovim on a directory

- [ ] `nvim .` opens an empty buffer. It does not show a directory listing.

## After you update plugins

- Run `:Lazy update`, then run all the checks above, starting with `:checkhealth` and
  `:checkhealth fondue`. The update changes `nvim/lazy-lock.json`, which records the exact
  commit of every plugin.
- If a plugin misbehaves, restore the previous lockfile (`git checkout nvim/lazy-lock.json`, or
  `jj restore nvim/lazy-lock.json` in a jj repository) and run `:Lazy restore`.
- To bring another machine to the same plugin versions, pull the repository there and run
  `scripts/install.sh --appname NAME` (or `--overwrite` for your default configuration); it
  restores plugins from the lockfile.

## If you push to this repository

Only needed if you push changes to the Fondue repository itself.

- [ ] Secret scan: in a scratch clone, create a file containing a fake GitHub token (for example
      `ghp_` followed by 36 random letters and digits), commit it, and try `jj push` (or `git push`):
      the push is blocked and names the commit and file. Then remove the commit. Remember that
      `jj git push` typed directly bypasses this scan.
- [ ] GitHub push protection is enabled in the repository settings (Code security >
      Push protection). This cannot be checked from the editor.
