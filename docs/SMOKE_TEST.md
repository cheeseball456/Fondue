# Checking your installation

A manual checklist for checking that your Fondue installation works, and for running again
after you update plugins. Start Neovim the way you installed it: `nvim` if you used
`scripts/install.sh --overwrite`, or `NVIM_APPNAME=NAME nvim` if you used
`scripts/install.sh --appname NAME` (for example `NVIM_APPNAME=fondue nvim`).

Work through it top to bottom and note anything that fails.

## Install and health

- [ ] `:checkhealth` shows no new errors from lazy.nvim (lua and luarocks warnings from lazy
      about `luarocks` are harmless: no plugin here needs it).
- [ ] `:checkhealth fondue` opens a report with sections for Neovim and tools, language tooling,
      configuration, clipboard, and repository safety (the last only when your configuration is
      linked from a clone of the Fondue repository). It shows no errors. Warnings are acceptable
      for tools the report says are only used by features you may not use yet, and for the
      reminder to confirm GitHub push protection. Every language server, formatter, parser, the
      spell dictionary and the completion matcher shows OK; the Swift language server is
      shown as information only (it is optional).
      A missing jj is an error inside a jj repository (the push scan alias needs it) and a
      warning elsewhere. On Arch, a missing `wl-clipboard` is an error in the clipboard section.

## Startup and appearance

- [ ] Neovim starts without any messages.
- [ ] The colourscheme is `carbonfox` (`:colorscheme` prints `carbonfox`).
- [ ] Nerd Font: icons render in the terminal (for example run
      `:lua print(vim.fn.nr2char(0xf057) .. " " .. vim.fn.nr2char(0xf071))` and check you see two
      icons, not boxes or question marks). If not, choose the Nerd Font in the terminal's settings.

## Keys

- [ ] Press `Space` and wait: the menu lists `w Save`, `u Undo tree`, `p Plugin manager`, and the
      groups `c Code tools` and `f Fix`. (A group such as Search appears in the menu once it
      contains keys.) Press `c`: the menu lists `f` (format) and `h` (inlay hints). Press `Space f`:
      it lists `a` (code action).
- [ ] `Space w` saves the current buffer.
- [ ] `Space u` opens the undo tree; pressing `Space u` again closes it.
- [ ] `Space p` opens the lazy.nvim plugin manager window.

## Highlighting and folds

Use a Python, JavaScript, JSON, bash or Swift file (any small project file will do).

- [ ] The file is coloured by its structure (Treesitter). `:checkhealth fondue` shows a parser for each of
      these languages.
- [ ] Nested brackets, for example `[1, (2, {3: 4})]`, each level in a different colour.
- [ ] Every fold is open when the file opens. On a function's first line press `zc`: the whole
      function collapses (not just lines at the same indentation). `zo` opens it, `zR` opens all folds.
- [ ] Vertical indent guides show each indentation level in a clearly visible colour (each depth has its own
      colour, matching the bracket colours), and the guide of the block your cursor is in is clearly
      stronger and changes as you move between blocks.
- [ ] In a code file with a language server attached, rest the cursor on a variable name that appears several
      times: the other occurrences get a clearly visible background of their own (a tint that is not the
      cursor-line colour, not the selection colour and not a diagnostic colour), without any key press. Plain
      text files and files without a language server are not expected to highlight.
- [ ] The guide and word colours are worked out from the active colourscheme (see `nvim/lua/fondue/highlights.lua`,
      where the contrast targets are at the top); after `:colorscheme dayfox` (light) they are recalculated
      for the light background, and `:colorscheme carbonfox` restores the first look.
- [ ] A Swift file opens with colours and no error message, even if `sourcekit-lsp` is not installed.

## Language servers, diagnostics and code actions

- [ ] Opening a Python, JavaScript, JSON, bash or Lua file starts its language server (`:checkhealth vim.lsp`
      lists it). A deliberate mistake (an undefined name in Python, a stray comma in JSON) shows a
      diagnostic. In Python an unused import and an undefined name are each shown once.
- [ ] Opening a Lua file in this configuration does not warn about the global `vim`.
- [ ] Python: inlay hints (small inline labels such as parameter names) appear without any action.
      `Space c h` hides them and shows them again.
- [ ] `Space f a` on an unused Python import lists a fix for it (also works on a visual selection).
- [ ] A bash file with an unquoted variable (`echo $name`) shows a shellcheck warning when opened, when saved and
      after leaving insert mode.

## Completion and snippets

These keys are the plugin's own insert-mode keys (they are not `Space` keys).

- [ ] Type part of a name in a Python file (for example `os.pa`): a menu lists matches, but nothing in it is
      chosen yet and your text is not changed. The down and up arrows (or `Ctrl-n` and `Ctrl-p`) move through
      it, and only `Enter` on an item you moved to accepts it. With nothing chosen, `Enter` is a normal
      `Enter` (a new line) and the menu closes.
- [ ] `Esc` while the menu is open closes the menu and stays in insert mode; a second `Esc` leaves insert mode
      as usual. With no menu open `Esc` leaves insert mode at once. `Ctrl-e` also closes the menu.
- [ ] Type a path prefix such as `./` inside a comment or string: file names are offered.
- [ ] Other keys of the completion plugin, all in insert mode: `Ctrl-e` hides the menu, `Ctrl-Space` opens it (and
      shows or hides the documentation), `Ctrl-b` and `Ctrl-f` scroll the documentation, `Ctrl-k` shows the
      function signature. The same plugin also serves the command line (`:`): `Tab` and `Shift-Tab`, `Ctrl-n`
      and `Ctrl-p`, and the left and right arrows move through its menu when one is showing, and
      `Ctrl-Space` opens it.
- [ ] Type `def` in a Python file and choose the function snippet: the template appears with the cursor on the
      first field. `Tab` jumps to the next field and `Shift-Tab` back.

## Formatting only on request

- [ ] Make a Python file badly formatted (extra spaces) and save it with `Space w`: the file stays exactly as you
      wrote it. Nothing is ever formatted on save.
- [ ] `Space c f` formats the buffer (Python with `ruff format`, JavaScript and JSON with `prettier`, bash with `shfmt`,
      Lua with `stylua`). In visual mode it formats only the selected lines.
- [ ] In a file with no formatter and no language server, `Space c f` shows a short message and changes nothing.

## Editing helpers

- [ ] Typing `(` inserts `()` with the cursor between them; the same for quotes and other brackets. The pairing
      plugin also takes over insert-mode `Backspace` (deleting an opening bracket deletes its partner when
      they are empty) and `Enter` between a pair (`{` `Enter` `}` opens an indented block).
- [ ] Surround: with the cursor inside `"text"`, `cs"'` changes it to `'text'`; inside `(a + b)`, `ds(` removes the
      parentheses; `ysiw)` surrounds a word. (`ys`, `cs` and `ds` are the plugin's own keys, not `Space` keys.)
      The plugin has more keys: `yss` surrounds the whole line, `yS` and `ySS` put the pair on their own lines,
      `cS` changes a pair the same way, in insert mode `Ctrl-g s` and `Ctrl-g S` add a pair, and in visual mode
      **`S` surrounds the selection (this replaces Vim's own visual `S`)**.
- [ ] `gcc` comments the current line with the right syntax: `#` in Python and bash, `//` in JavaScript. `gc` with a
      motion or in visual mode comments a range.
- [ ] A very large file (a few megabytes, or a minified file with very long lines) opens promptly, and a
      message says that some features were turned off for it.

## Spell checking and plain text

- [ ] Open a plain text file (`.txt`) containing `recieve`, `colour` and `color`: `recieve` is underlined as an error,
      `colour` is not, and `color` is underlined as valid only in another region (US spelling).
      `z=` suggests corrections, `]s` jumps to the next one. Long lines wrap at word boundaries.
- [ ] In a Python file, a misspelled word in a comment or docstring is underlined; a misspelled variable name is not, and
      neither is a word inside an ordinary string. The same applies to the other languages.
- [ ] Turning spell checking on never asks you a question (the dictionary is installed by the installer).
- [ ] `:Lazy` lists no Markdown preview or rendering plugin.

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

- Run `:Lazy update`, then run `scripts/install.sh` again (it only fetches what is missing: the completion
  plugin's matcher for a new release, and any parser that failed to rebuild), then run all the checks above, starting with `:checkhealth` and
  `:checkhealth fondue`. The update changes `nvim/lazy-lock.json`, which records the exact
  commit of every plugin. Updating the Treesitter plugin rebuilds the parsers in the background, so the
  editor stays usable; if one cannot be rebuilt you get a one-line warning, and running `scripts/install.sh`
  again retries it. If a language loses its colours afterwards, `:checkhealth fondue` says which parser is
  the problem.
- The completion plugin fetches its matcher itself when it first loads after an update, if the installer has
  not already done so. With downloads blocked, completion keeps working with a slower matcher and
  `:checkhealth fondue` shows a warning.
- If a plugin misbehaves, restore the previous lockfile (`git checkout nvim/lazy-lock.json`, or
  `jj restore nvim/lazy-lock.json` in a jj repository) and run `:Lazy restore`.
- To bring another machine to the same plugin versions, pull the repository there and run
  `scripts/install.sh --appname NAME` (or `--overwrite` for your default configuration); it
  restores plugins from the lockfile.

## The installer's language step

- [ ] `scripts/install.sh --dry-run --appname NAME` prints a "Language tooling" step and installs nothing.
- [ ] A real run prints a line saying the step can take a minute or two, then shows each item's result as
      it finishes.
- [ ] A real run on a fresh setup lists what it installed (parsers, tools, completion matcher, dictionary) and
      ends normally. Running it a second time reports "nothing to do" for each and changes nothing.
- [ ] If a download fails (for example with the network off), the installer names the item that failed, carries on
      with the rest and ends with a non-zero status; running it again once the network is back completes it.
- [ ] Swift: without `sourcekit-lsp` a Swift file has colours but no language server; with it (it comes with Xcode
      on macOS) you also get completion and diagnostics.

## If you push to this repository

Only needed if you push changes to the Fondue repository itself.

- [ ] Secret scan: in a scratch clone, create a file containing a fake GitHub token (for example
      `ghp_` followed by 36 random letters and digits), commit it, and try `jj push` (or `git push`):
      the push is blocked and names the commit and file. Then remove the commit. Remember that
      `jj git push` typed directly bypasses this scan.
- [ ] GitHub push protection is enabled in the repository settings (Code security >
      Push protection). This cannot be checked from the editor.
