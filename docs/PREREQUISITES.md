# Prerequisites

Everything Fondue needs from outside this repository, per operating system.
`scripts/install.sh` checks for each of these and installs what it can; run
`scripts/install.sh --check-only` to see what is missing without changing anything.

Supported systems: **macOS** (Homebrew) and **Arch Linux** (pacman). Windows is not supported.

## Tools

| Tool | What for | macOS (Homebrew) | Arch (pacman) | Needed from |
|------|----------|------------------|---------------|-------------|
| Neovim 0.12 or later | the editor | `neovim` | `neovim` | now |
| git | version control, plugin installs, the pre-push hook | `git` | `git` | now |
| gitleaks | push-time secret scan (blocks a push containing a secret) | `gitleaks` | `gitleaks` | now |
| jj | push-time secret scan alias (`jj push`) and version control for jj repositories, including this one | `jj` | `jujutsu` | now (missing jj is an error in `:checkhealth fondue` inside a jj repository, a warning elsewhere) |
| tree-sitter CLI | building Treesitter parsers | `tree-sitter-cli` | `tree-sitter-cli` | phase 1 (editing-core) |
| C compiler | building Treesitter parsers | Xcode Command Line Tools: `xcode-select --install` | `gcc` | phase 1 (editing-core) |
| ripgrep (`rg`) | project text search | `ripgrep` | `ripgrep` | phase 2 (navigation) |
| fd | file search | `fd` | `fd` | phase 2 (navigation) |
| Nerd Font | icons in the editor | cask `font-jetbrains-mono-nerd-font` | `ttf-jetbrains-mono-nerd` | now |
| wl-clipboard (Arch only) | Neovim's system clipboard (`unnamedplus`) needs a helper program on Linux; the Arch desktop uses Wayland | nothing extra (`pbcopy`/`pbpaste` are built in) | `wl-clipboard` | now |

Notes:

- On macOS no clipboard tool needs installing. On Arch, without `wl-clipboard` Neovim reports "No provider" on every yank or paste; `:checkhealth fondue` names this fix. Over SSH no local helper is needed (copying uses OSC 52).
- On macOS the installer does not run `xcode-select --install` for you (it opens a
  system dialog); it tells you to run it.
- Homebrew must already be installed (<https://brew.sh>). The installer does not install it.
- On Arch, `pacman` needs root. The installer prints the exact `sudo pacman ...` command
  before running it; any password prompt comes from `sudo`, not from the installer.
- The installer checks that Neovim is 0.12 or later and stops if it is not. If your package
  manager only offers an older Neovim, install 0.12 another way (for example the official
  release from <https://github.com/neovim/neovim/releases>) and run the installer again.

## Manual step: choose the Nerd Font in your terminal

The installer installs a Nerd Font, but **selecting it in your terminal is manual**: no script
edits terminal settings, and `:checkhealth fondue` cannot see which font the terminal uses.
Set the terminal's font to "JetBrainsMono Nerd Font" (or any Nerd Font you prefer), then check
that the icons render (see the smoke test).

## Installing

```sh
scripts/install.sh --check-only                 # report missing prerequisites only (needs no other option)
scripts/install.sh --dry-run --appname fondue   # preview exactly what a real run would do, change nothing
scripts/install.sh --appname fondue             # recommended: link as ~/.config/fondue; start with: NVIM_APPNAME=fondue nvim
scripts/install.sh --overwrite                  # install as your default ~/.config/nvim
scripts/install.sh --appname fondue --overwrite # replace an existing ~/.config/fondue
```

You must choose the install target explicitly. With neither `--appname NAME` nor `--overwrite`
the installer refuses, changes nothing, and explains both choices.

- `--appname NAME` (recommended) installs beside your other Neovim configurations. If
  `~/.config/NAME` already exists the installer stops and leaves it untouched.
- `--overwrite` makes Fondue your default `nvim` configuration. Anything already at the target
  (a directory, a file, or a link to somewhere else) is moved to `<target>.bak-<YYYYmmdd-HHMMSS>`
  first, automatically. The installer never deletes anything, and there is no separate backup option.
  `--appname nvim` also needs `--overwrite`, because it targets the default location (the name `nvim` in any letter case, since macOS ignores case). An empty `--appname` value is an error.
- **Only the config folder is backed up.** Neovim's data, state and cache folders
  (`~/.local/share/<name>`, `~/.local/state/<name>`, `~/.cache/<name>`) are shared with your previous
  configuration of the same name and are not moved. For the default name this means Fondue's
  lazy.nvim and plugins are installed into the same plugin folder your old configuration used
  (Fondue adds its own plugins and sets any plugin of the same name to its locked commit; nothing there is deleted). To go back, remove the
  Fondue link and move the `.bak-<date>` folder back to `~/.config/nvim`. For exactly this reason
  `--appname fondue` is the cleaner way to try Fondue: it has its own data, state and cache folders.
- A script that calls the installer (for example a future dotfiles setup) must pass `--appname NAME`
  or `--overwrite`; without one the installer refuses and exits with a non-zero status.
- Running the same command again changes nothing. The installer honours `XDG_CONFIG_HOME` when
  choosing where to link, and never edits your shell or terminal settings.
- With a custom name it ends by printing the shell alias line to add (it does not write it).

## Before the first push: secret scanning (public repository)

The Fondue repository is public, so nothing is pushed until secret scanning is in place.

- **Local scan.** `scripts/setup-repo` (run automatically by the installer inside a clone)
  turns on the push-time scan: a Git `pre-push` hook for plain git, and a `jj push` alias
  for jj. Both run the same script, `scripts/secret-scan`, which scans every commit that has
  not been published yet (in a jj repository that includes the working-copy commit).
- **Use `jj push`, not `jj git push`.** Typing `jj git push` directly **bypasses the local
  scan**, because jj does not run Git hooks. `git push --no-verify` also bypasses the hook.
  `:checkhealth fondue` confirms the alias and hook are configured, but it cannot stop you
  typing the wrong command.
- **Backstop: GitHub push protection.** In the GitHub repository settings, enable
  *Code security > Secret protection > Push protection* on the public repository and confirm
  it is on. This cannot be verified from your machine.
