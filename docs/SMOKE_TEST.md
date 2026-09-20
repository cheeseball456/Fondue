# Smoke test

A manual checklist to run after installing Fondue on a machine and after updating plugins.
There is no automated test suite (by design); this is the substitute. Work through a phase's
section top to bottom and note anything that fails.

## Running the checks

- After a fresh install (`scripts/install.sh --appname fondue`, then `NVIM_APPNAME=fondue nvim`): run every phase section below.
- After a plugin update (`:Lazy update`, then commit `nvim/lazy-lock.json`): run the checks,
  starting with `:checkhealth` and `:checkhealth fondue`. If a plugin misbehaves, restore the
  previous lockfile (`git checkout nvim/lazy-lock.json` or the jj equivalent) and run `:Lazy restore`.
- Other machines pick up an update by pulling and running `scripts/install.sh --appname fondue` (or `--overwrite` for your default config; it restores
  plugins from the lockfile).

## Adding a section for a new phase

Each phase adds a section below (`## Phase N: name`) listing only the checks that phase makes
true, in the same checklist form. Keep the earlier sections; they still have to pass.
Update the section in the same change that introduces the feature.

## Phase 0: foundation

- [ ] `:checkhealth` shows no new errors from lazy.nvim (lua and luarocks warnings from lazy
      about `luarocks` are harmless: no plugin here needs it).
- [ ] `:checkhealth fondue` opens a report with sections for Neovim and tools, configuration,
      and repository safety. No errors. Warnings are acceptable only for tools marked "needed
      from" a later phase, and for the reminder to confirm GitHub push protection.
      Missing jj is an error inside a jj repository (the push scan alias needs it) and a
      warning elsewhere. On Arch, a missing `wl-clipboard` is an error in the clipboard section.
- [ ] Press `Space` and wait: the menu lists `w Save`, `u Undo tree`, `p Plugin manager`.
      (Declared groups such as Search appear once they contain keys.)
- [ ] `Space w` saves the current buffer. Edit a file, switch buffer, click away, leave insert
      mode: the file on disk does not change until you save.
- [ ] `Space u` opens the undo tree; `Space p` opens the lazy.nvim window.
- [ ] `nvim .` does not open a netrw directory listing.
- [ ] The colourscheme is `carbonfox` (`:colorscheme` prints `carbonfox`).
- [ ] Arrow keys and `h j k l` move the cursor as in stock Neovim.
- [ ] Nerd Font: icons render in the terminal (for example run `:lua print(vim.fn.nr2char(0xf057) .. " " .. vim.fn.nr2char(0xf071))`
      and check you see two icons, not boxes or question marks). If not, choose the Nerd Font in
      the terminal's settings.
- [ ] Local clipboard: yank a line (`yy`) and paste it into another application, and copy text in
      another application and paste it into Neovim (`p`). On Arch this needs `wl-clipboard`.
- [ ] Yank over SSH: from the local machine, SSH to another machine, open Neovim there, yank
      some text (`yy`), then paste in a local application. The text arrives (needs a terminal
      that allows OSC 52 writes; kitty does by default). `:checkhealth fondue` in that session
      reports "OSC 52 clipboard provider is in use".
- [ ] Secret scan: in a scratch clone, create a file containing a fake GitHub token
      (for example `ghp_` followed by 36 random letters and digits), commit it, and try
      `jj push` (or `git push`): the push is blocked and names the commit and file. Then
      remove the commit. Remember that `jj git push` typed directly bypasses this scan.
- [ ] GitHub push protection is enabled in the repository settings (Code security >
      Push protection). This cannot be checked from the editor.
