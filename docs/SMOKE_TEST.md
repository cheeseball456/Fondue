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

- [ ] Press `Space` and wait: the menu lists `w Save`, `u Undo tree`, `p Plugin manager`,
      `e File tree`, `m Pin current file`, `1` to `4` (jump to a pinned file), and the groups
      `c Code tools`, `f Fix` and `s Search`. Press `c`: the menu lists `f` (format) and `h`
      (inlay hints). Press `Space f`: it lists `a` (code action), `l` (diagnostics) and `t`
      (TODO list). Press `Space s`: it lists `f`, `t`, `r`, `o`, `b`, `k` and `h`.
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
      cursor-line colour, not the selection colour and not a diagnostic colour: clearly visible, yet
      distinct from the cursor line, the selection and the diagnostics), without any key press. Plain
      text files and files without a language server are not expected to highlight.
- [ ] The guide and word colours are worked out from the active colourscheme (see `nvim/lua/fondue/highlights.lua`,
      where the contrast targets are at the top); after `:colorscheme dayfox` (light) they are recalculated
      for the light background, and `:colorscheme carbonfox` restores the first look.
- [ ] A Swift file opens with colours and no error message, even if `sourcekit-lsp` is not installed.

## Language servers, diagnostics and code actions

- [ ] Opening a Python, JavaScript, JSON, bash or Lua file starts its language server. `:checkhealth vim.lsp`
      lists the servers attached to the current buffer (Neovim 0.12 has no `:LspInfo`). A deliberate mistake (an undefined name in Python, a stray comma in JSON) shows a
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
      function signature.
- [ ] The command line (`:`) behaves the same way: start typing a command and a menu appears with nothing
      chosen yet; the down and up arrows (or `Ctrl-n` and `Ctrl-p`) move through it without changing what you
      typed, and `Enter` on an item you moved to accepts it. `Tab` and `Shift-Tab` also move the selection,
      the same way the down and up arrows do (there is nothing to accept into, so they never do anything
      else). `Esc` closes the menu first and leaves the command line as you typed it; a second `Esc` leaves
      the command line as usual. With no menu open, the up and down arrows still recall your command-line
      history exactly as before.
- [ ] The command-line window (`q:`, opened from the command line or normal mode) behaves the same way too:
      start typing a command there and the same menu appears, with `Tab`/`Shift-Tab` and the arrow keys moving
      the selection and `Esc` closing the menu first, exactly as on the plain command line. Moving between
      lines and editing past commands in that window (Normal mode) is unaffected.
- [ ] Type `def` in a Python file and choose the function snippet: the template appears with the cursor on the
      first field. `Tab` jumps to the next field and `Shift-Tab` back.

## Formatting only on request

- [ ] Make a Python file badly formatted (extra spaces) and save it with `Space w`: the file stays exactly as you
      wrote it. Nothing is ever formatted on save.
- [ ] `Space c f` formats the buffer (Python with `ruff format`, JavaScript and JSON with `prettier`, bash with `shfmt`,
      Lua with `stylua`). In visual mode it formats only the selected lines.
- [ ] If nothing needed changing, `Space c f` says "already formatted" (in the buffer and in a selection), so
      silence is never mistaken for a failure.
- [ ] Styles: shell scripts are formatted by `shfmt` with two-space indentation (no tabs), unless the script's
      project has an `.editorconfig`, in which case `shfmt` follows that file (a project that says tabs keeps
      its tabs). Lua is formatted by `stylua`: files in this configuration follow `nvim/stylua.toml` (two
      spaces, double quotes), and a project's own `stylua.toml` or `.stylua.toml` wins for that project's Lua
      files. Python (`ruff format`) and JavaScript and JSON (`prettier`) use their defaults.
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
      `z=` suggests corrections, `]s` jumps to the next one. Long lines wrap at word boundaries, and `Down` / `j`
      move down through the wrapped rows of a long line (see Movement).
- [ ] In a Python file, a misspelled word in a comment or docstring is underlined; a misspelled variable name is not, and
      neither is a word inside an ordinary string. The same applies to the other languages.
- [ ] Turning spell checking on never asks you a question (the dictionary is installed by the installer).
- [ ] `:Lazy` lists no Markdown preview or rendering plugin.

## Saving

- [ ] Nothing saves automatically. Edit a file, then switch buffer, click away from the window,
      and leave insert mode: the file on disk does not change until you save with `Space w` (or `:w`).

## Movement

- [ ] Arrow keys and `h j k l` move the cursor as in stock Neovim, in every kind of file except plain text
      (see the next item).
- [ ] Plain text (a `.txt` file) is the one exception: there `Up`, `Down`, `j` and `k` move by screen row, so the
      cursor follows a long wrapped line instead of skipping over its wrapped part. With a count they keep
      their usual meaning (`3j` moves three real lines), `dj` still deletes two whole lines, and in insert mode
      the arrows are stock. In a Python (or any other code) file all four keys move by real lines.
      These screen-row mappings are set only in plain-text files; no other kind of file gets them.

## Clipboard

- [ ] Local: yank a line (`yy`) and paste it into another application, and copy text in
      another application and paste it into Neovim (`p`). On Arch this needs `wl-clipboard`.
- [ ] Over SSH: from your local machine, SSH to another machine, open Neovim there, yank some
      text (`yy`), then paste in a local application. The text arrives (this needs a terminal that
      allows OSC 52 writes; kitty does by default). `:checkhealth fondue` in that session
      reports "OSC 52 clipboard provider is in use".

## Finding files and text

- [ ] `Space s f` opens a fuzzy file search. In a project with two files sharing a name in
      different folders, both appear, distinguishable by their path.
- [ ] `Space s t` searches text across the whole project; selecting a result jumps straight to
      that match in that file.
- [ ] `Space s o` lists recently opened files, `Space s b` lists open buffers, `Space s k`
      searches this configuration's own keymaps (try searching "format"), and `Space s h`
      searches Neovim's help — each opens or jumps to what you pick.
- [ ] `Space s r` opens a search-and-replace view covering the whole project, separate from
      `Space s t`. Type a search and a replacement: it shows the proposed changes across every
      matching file before anything is written. Closing it without confirming leaves every file
      untouched; running its replace action writes the change to every matching file at once.

## The file tree

- [ ] `Space e` opens a file tree of the project. It is a fallback for browsing unfamiliar
      territory — day to day, go-to-definition and fuzzy file search (above) stay the quicker way
      to move around.
- [ ] With a file open two folders deep, `Space e` opens the tree already showing that file, with
      its parent folders expanded, rather than always starting at the project root.

## Centred layout

- [ ] A normal code file sits roughly in the middle third of the window, not flush to the left
      edge, including its line numbers and sign column.
- [ ] The centred padding on either side shows a blank statusline (no filename, cursor position
      or "[Scratch]") — the padding is an empty visual margin, not a window with ordinary content.
      This applies to the start screen's own padding too (see "Sessions and the start screen"
      below): both `nvim` with a real file and `nvim`/`nvim .` showing the start screen should
      show blank padding statuslines, never real ones (`navigation`'s own centred-layout decision;
      confirmed pre-existing, unaffected by this change other than the Claude panel's own
      `no-neck-pain` integration entry).
- [ ] Resize the terminal: the centred column adjusts to stay roughly a third of the new width.
- [ ] The centred content column's own *text* — not the raw window, which is wider by however many
      columns the sign column/line numbers/fold column take — is never narrower than 80 columns
      while the terminal is wide enough to allow it. Shrink the terminal gradually on a real code
      file (with line numbers and a sign column showing): padding on either side narrows first (a
      literal third would otherwise shrink content along with it), the *text* area holds at 80
      columns once a literal third would have dropped it below that (the window itself sits a bit
      wider than 80, by the gutter's own width), and only once the terminal itself is too narrow
      for 80 columns of text plus the gutter plus any padding at all does padding disappear
      entirely and content take the full window (text narrower than 80) — centring effectively
      stops at that point rather than the layout erroring or looking broken. Widen the terminal
      back past each of these thresholds and confirm the centred column returns cleanly each time,
      with no stale or lopsided padding window left over from the narrower state (checked
      specifically because of this plugin's own history of resize-handling glitches). Switch to the
      start screen (no gutter of its own) at a similar width and confirm its window sits at 80
      directly, with no extra room set aside for a gutter that is not there.
- [ ] Open the file tree (`Space e`) next to a centred file: both remain usable, and closing the
      tree again restores the same centred padding as before.
- [ ] Open the Claude panel (`Space a a`) next to a centred file: both remain usable, and the
      panel keeps its own width rather than being treated as ordinary content to centre. Open the
      file tree as well, so all three (tree, centred file, panel) are on screen together: each
      stays usable and distinguishable from the others.
- [ ] Open the test/run terminal (`Space t`) while the Claude panel is also open: the terminal
      covers the whole window (it is not treated as a side panel the way the Claude panel is);
      hiding it again reveals the panel and centred layout exactly as they were. This direction
      (terminal opened on top of an already-open panel) is unaffected by the guard below: the
      terminal is meant to cover whatever is on screen, panel included.
- [ ] With the test/run terminal open, try to open the Claude panel the other way round (`Space a a`
      or `Space a f`, panel not open yet): nothing visibly changes — no panel window appears, focus
      stays on the terminal — and you see a message telling you to hide the terminal first
      (`Space t`). This is deliberate: the terminal's floating window always renders over the
      panel's regardless of focus, so opening or focusing the panel while occluded would otherwise
      look like nothing happened at all. Hide the terminal, repeat, and the panel now opens/shows
      normally.
- [ ] Open the Claude panel first, *then* the test/run terminal on top of it (covering it, as
      above), then press `Space a a`: the panel hides correctly, with no message and no need to
      hide the terminal first — hiding an already-open panel never needs the on-screen confirmation
      that opening one does.

## Sessions and the start screen

- [ ] In a project directory with no previous session, `nvim` (or `nvim .`) shows a minimal start
      screen — at least a list of recent files and a way to open a new file — instead of an empty
      buffer or a directory listing.
- [ ] The start screen's own dashboard **pane itself** (the whole box the header/menu sit inside)
      sits horizontally centred within its window — roughly equal empty margin on its left and its
      right, not the pane pushed against one edge with all the slack piled up on the other side.
      Check this separately from the next item: the pane's own position and its per-line text
      alignment *within* that pane are two independently-breakable things (confirmed: the tenth
      interactive-verification pass found the pane itself off-centre — flush against the window's
      left edge with all the spare width sitting unused on the right — while the text inside the
      pane was still correctly centred within its own box). A quick way to check both without
      counting columns by eye: `:hi WinSeparator guifg=Red` then compare the gap outside the pane's
      left/right edges to the window's own borders.
- [ ] Within that pane, the header art and menu lines are themselves horizontally centred inside
      the pane's own box, not hugging its left edge — most noticeable on a wide window, where the
      centred layout's content column is wider than the dashboard's own default pane width.
- [ ] On a genuinely narrow terminal (too narrow even for the centred layout's own 80-column
      minimum, "Centred layout" above), the start screen (both the pane's own position and the text
      within it) still looks centred rather than flush-left or cut off on the right — resize
      gradually down and back up and confirm this holds throughout, not just at the start and end.
- [ ] Open a file in that directory, then quit. Running `nvim` (or `nvim .`) there again restores
      the buffers and splits from last time, not the start screen.
- [ ] `nvim` in a *different* project directory never shows the first directory's buffers: each
      directory keeps its own session.
- [ ] `nvim <file>` always opens that file directly — no restore, no start screen, either way.

## Diagnostics and TODOs

- [ ] With problems in two open files, `Space f l` lists every diagnostic across both, not only
      the current file; selecting one jumps straight to it.
- [ ] A comment such as `# TODO: fix this` is visually distinguished from an ordinary comment
      (the same applies to `FIXME`, `WARN` and `NOTE`), and `Space f t` lists every such comment
      across the project, jumping to the one you pick.

## Pinning files

- [ ] `Space m` pins the current file (up to four at a time); `Space 1` through `Space 4` jump
      straight to a pinned file. Pinning a fifth file is refused with a message rather than
      silently replacing one of the first four.
- [ ] Pins do not survive a restart: quit and reopen Neovim in the same directory, and no file is
      pinned.

## The test/run terminal

- [ ] `Space t` opens a full-window terminal on top of whatever was on screen, for running and
      testing a project without leaving Neovim.
- [ ] `Space t` again hides it, restoring exactly what was on screen before; the shell inside keeps
      running (start a long-running command, hide the terminal, show it again: the command is
      still going, not restarted).
- [ ] `Esc` inside this terminal leaves terminal mode (so normal Neovim keys work again), the same
      as it does in any other Neovim terminal.
- [ ] Open the terminal, press `Esc` to leave terminal mode, then `Space t`: it hides on this single
      press (no need to press it twice, and no `E21` error on whatever you press next). This is the
      exact sequence a first interactive pass found broken; it must work first time, every time.
- [ ] After `Esc`, pressing `i` or `a` goes straight back to typing in the shell, without hiding the
      window — this is standard Neovim behaviour on any terminal buffer, not a Fondue key of its
      own, and it is unchanged here.
- [ ] While typing into this terminal (terminal mode), the window looks visibly different from
      normal mode — a background tint beyond Neovim's own small `-- TERMINAL --` status text — and
      that difference disappears the instant you `Esc` out. Check this on the test/run terminal; the
      Claude panel (below) is deliberately excluded from this tint — it is a conversation, not a
      shell, and does not gain a background tint while you type into it.
- [ ] There is no way to open a second, concurrent terminal: the same `Space t` always shows or
      hides the one dedicated terminal, whatever count (if any) is typed before it.

## The Claude panel

Needs the `claude` CLI installed and already set up with your account.

- [ ] Neovim starts with the Claude panel hidden and no Claude process running (`Space a a` is the
      first time anything starts).
- [ ] If the test/run terminal (`Space t`) is currently open, `Space a a`/`Space a f` never starts,
      resumes, or shows the panel while it is open — you get a message telling you to hide the
      terminal first instead, with no other visible effect. See "Centred layout" above for the full
      set of open/hide-order checks this covers.
- [ ] `Space a a` in a project directory with no Claude session yet: you are offered a choice to
      start a new session (named "[the directory's name] Coordinator") or resume a different
      existing session for that directory, if one exists.
- [ ] Start a `claude` session in a plain terminal outside Neovim, in this same project directory,
      and leave it running. Open the panel here (`Space a a`): the running session should be offered
      as a pick option (named exactly what you named it), not skipped straight to "start new" — this
      is the exact interactive scenario an earlier pass found broken and this fix addresses; it
      needs a real interactive `claude` session outside Neovim to check, which the sandboxed
      environment that made the fix could not run end-to-end itself (see design.md's R-3).
- [ ] With a session already running, `Space a a` shows and hides the panel; hiding it never stops
      the session (leave something running in it, hide the panel, come back with `Space a a`: it
      is exactly as you left it) and returns focus to your code.
- [ ] `Space a f` is a two-way focus toggle between your code and the panel, never a hide: from
      code, it moves keyboard focus into the panel without hiding or reopening it, when it is
      already shown. Pressed again while the panel already has focus, it returns focus to the code
      window you were in before — the panel stays open and visible exactly as it was; it does not
      hide (hiding is `Space a a`'s job only, never this one's). If that earlier code window has
      since been closed, focus falls back to another real window instead of erroring.
- [ ] Quit Neovim entirely (`:qa`) while a Claude session is still running: a warning appears
      first, and choosing to cancel leaves Neovim open with the session untouched. Choosing to quit
      now explicitly, cleanly stops the Claude session first (its own process ends, not just the
      panel losing its connection) and *then* Neovim quits — the session's fate no longer depends on
      guessing which windows `:qa` happens to close. With no Claude session running, `:qa` quits with
      no extra prompt. Closing just the panel's window, or a single split, while other windows remain
      never shows this warning.
- [ ] With only one file open (no split, no file tree) and a Claude session still running, plain
      `:q` (also try `:quit`, `:wq`, `:x`, `:xit`) shows the same warning as `:qa` above, even though
      the centred layout's own padding makes it look like more than one window is open — this is the
      single most ordinary way to quit Neovim, and the case most worth checking by hand. `:xit` in
      particular was, until recently, a plain one-line omission from the guard's own word list (a
      pure oversight, unlike `:close`/`:clo`'s deliberate exclusion below) and would have silently
      ended Neovim with the session still connected — worth a specific, deliberate check by hand.
- [ ] With the test/run terminal (`Space t`) left open (not hidden) while you quit your only file
      with plain `:q`, no warning appears and Neovim does not actually quit either — you land back
      on the test/run terminal instead. This is expected, not a bug: the padding-only case above is
      the one that must warn; this one must not.
- [ ] Type `:qa` (or `:qall`/`:wqa`/`:xa`) while your cursor is actually *inside* a terminal window —
      either the Claude panel's own window or the plain test/run terminal's — rather than an ordinary
      file window: the warning still appears (when a Claude session is running), and confirming still
      cleanly stops the session first. From inside the panel's own window, Neovim should now fully
      quit too. From inside the plain test/run terminal, the session is still cleanly stopped, but
      Neovim quitting fully afterwards is a separate, lower-priority Neovim/layout quirk unrelated to
      Claude — if it doesn't fully quit in that specific case, that's a known, accepted residual, not
      a sign the session was lost (check with `:lua print(require("claudecode").is_claude_connected())`
      if in doubt — it should already read `false`).
- [ ] With the Claude panel open and *other* windows also present (so quitting would not end Neovim
      at all), move focus into the panel's own window and type `:q` (or `:quit`, `:close`, `:clo`,
      `:x`, `:xit` — all six behave identically here) directly on it: a warning still appears —
      "Close the Claude panel? The session ... will be stopped." — even though this would not end
      Neovim. Cancelling ("Keep editing") leaves everything exactly as it was. Confirming ("Close")
      cleanly stops the session and closes the panel's window, leaving you back on your code with the
      centred layout intact. `:wq` is the one exception: it errors instead ("Cannot write, 'buftype'
      option is set"), same as it always has, since a terminal buffer genuinely cannot be written.
- [ ] If you trigger an LSP hover popup (`K`) or a diagnostics float right before typing a guarded
      quit command and then *cancel*, the warning still appears exactly as if no popup were showing —
      this used to be a gap (the popup could be mistaken for something that would keep Neovim open).
      If you *confirm* Quit instead, with the float still open: the session is still cleanly stopped
      (check with `:lua print(require("claudecode").is_claude_connected())` if in doubt — it should
      already read `false`), but Neovim itself may not fully quit — the float can end up as the window
      left on screen instead, the same benign, accepted residual as the plain-test/run-terminal case
      above, just triggered by an ordinary file window plus a transient hover/diagnostic float rather
      than a terminal window. This is a known, accepted quirk, not a sign anything was lost — a second
      quit attempt right afterward succeeds cleanly.
- [ ] With one file open (no split, no file tree) and the Claude panel *also* open (`Space a a`,
      session connected), plain `:q` on the file's window shows a different warning — not the "quit
      Neovim" one above (Neovim genuinely would not quit; the panel's own window survives), but one
      asking whether you want to close the file and be left with only the panel. Cancel leaves the
      file open exactly as before, nothing changed. Confirm closes the file and shows the normal
      start screen in its place, still centred, with the panel still sitting in its usual side
      position — not the panel expanding to fill the whole window (the bug this checks for). This
      warning should *not* appear at all if the panel was never opened (plain `:q` on your last file
      alone behaves exactly as it always has), and should not appear either if another file window
      (e.g. a split) is still open after the close.
- [ ] Check the *resulting layout's widths* after confirming the above, not just that the start
      screen appears — this is deliberately more specific than "looks roughly centred" (task 20's
      own finding: a broken layout can still show the start screen and the panel in the right visual
      slot while being genuinely wrong underneath). Run `:hi WinSeparator guifg=Red ctermfg=Red` to
      make the window borders easy to see, then check: there are exactly four windows left to right
      (left padding, the centred start screen, the panel, right padding) — no extra, orphaned padding
      window anywhere, and no window sized noticeably larger than expected for its role. The panel's
      own width should look the same as it does on a *fresh* Neovim start with a file and the panel
      both open from the start (roughly 30% of the terminal's width, not roughly half of it — if
      you have a way to query window widths directly, e.g. `:lua print(vim.api.nvim_win_get_width(0))`
      in each window, even better). Try this at more than one terminal width if easy to do (resize
      the terminal and repeat) — this bug was found to depend on exactly how quickly no-neck-pain's
      own internal bookkeeping settles relative to the close, which can vary run to run.
- [ ] From the case above, confirm the close (so you land back on the start screen with the panel
      still open, session still connected), then quit the start screen *itself* with plain `:q`
      (also try `:quit`, `:close`, `:clo`, `:x`, `:xit` — all six now correctly warn here): a
      warning appears — "Quit Neovim? The Claude session ... is still running." — the same wording
      D5's own "quit Neovim" warning uses. There is nowhere further to fall back to from the start
      screen, so confirming here does not show the start screen again the way closing a *file* did
      above — it cleanly stops the session and Neovim actually quits. Cancelling leaves the start
      screen and the panel exactly as they were, session still connected. This should *not* happen
      if a file tree or any other real window is also open alongside the start screen and the panel
      (something real still remains — an ordinary, unguarded `:q` on just the start screen in that
      case, exactly like closing any other window that isn't the last one). **Known, accepted
      residual with `:close`/`:clo` specifically (not `:quit`/`:x`/`:q`/`:xit`):** confirming here
      stops the session cleanly every time (check with
      `:lua print(require("claudecode").is_claude_connected())` if in doubt — it should read
      `false`), but Neovim itself can be left running with just the two blank padding windows on
      screen, rather than fully quitting — the same benign, accepted shape as the plain-test/
      run-terminal and LSP-hover/diagnostic-float residuals above, not a sign anything was lost. A
      second `:q` on the remaining padding window quits cleanly right afterward.
- [ ] Open the command line (`:`), type a guarded quit word (for example `q`), press `Down` if a
      completion candidate appears, and press `Enter` twice if needed to actually submit it: the
      warning should still appear on whichever keypress actually runs the command, with a Claude
      session still running. This specific sequence has not been reliably confirmed by automated
      testing (see `QA_REPORT.md`'s QA-T04) — check it by hand here. `:quit`, `:close`, `:clo`, and
      `:x` specifically (as opposed to `:q`/`:xit`) used to be unreliable here for a fully
      root-caused, now-fixed reason: `blink.cmp`'s own completion-menu scrollbar (a thumb and gutter,
      with no filetype of their own) appears whenever the fuzzy-matched candidate count for what
      you've typed exceeds 10 — which happens for `quit`/`close`/`clo`/`x` in this project's own
      large command surface but not for `q`/`xit` — and was not being recognised as an ignorable
      popup the way the menu itself already was, so the warning silently never fired for those four
      words specifically. Fixed by recognising the scrollbar directly via `blink.cmp`'s own tracked
      window state; still worth checking by hand here with a real completion menu genuinely showing
      more than 10 candidates (for example type `close` or `x` and watch for the scrollbar before
      pressing Enter), since this exact mechanism has a documented history of looking fixed in one
      round of testing and not another.
- [ ] Typing `/exit` inside the panel ends that session; opening the panel again afterwards offers
      to resume or start fresh, without anything restarting on its own.
- [ ] Leaving the panel: a single `Esc` reaches Claude Code itself (for example to interrupt it);
      a quick double `Esc` leaves the panel's terminal mode instead. Still exactly two presses,
      no more and no less — check this both with some draft text typed into the prompt but not
      yet submitted, and with nothing typed at all.
- [ ] Right after that double `Esc` (either with draft text present or with an empty prompt),
      `Space a a` hides the panel cleanly on the first try — it does not silently re-enter the
      prompt (task 12.1's fix: the second `Esc`'s own mode-flip previously did not take effect
      until some further key was read, so the leader `Space` was being consumed settling it
      instead of starting the `<leader>aa` sequence, and the following `a` re-entered the prompt
      the same way a bare `a` normally resumes typing on any terminal buffer).

## Auto-reload

- [ ] With a file open in Neovim and no unsaved changes, edit and save that same file from another
      program (or have Claude edit it through its panel): the open buffer picks up the change
      automatically, with no action needed.
- [ ] Make an unsaved change in Neovim first, then edit and save the same file externally: Neovim
      warns about the conflict rather than silently keeping either version; your unsaved change is
      not discarded.

## After you update plugins

- Run `:Lazy update`, then run `scripts/install.sh` again (it only fetches what is missing: the completion
  plugin's matcher for a new release, and any parser that failed to rebuild), then run all the checks above, starting with `:checkhealth` and
  `:checkhealth fondue`. The update changes `nvim/lazy-lock.json`, which records the exact
  commit of every plugin. Updating the Treesitter plugin rebuilds the parsers in the background, so the
  editor stays usable; if one cannot be rebuilt you get a one-line warning, and running `scripts/install.sh`
  again retries it (the installer also rebuilds any parser that is out of date). If a language loses its colours afterwards, `:checkhealth fondue` says which parser is
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
