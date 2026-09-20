# Fondue

Fondue is a single, version-controlled Neovim configuration, kept identical across
macOS and Arch Linux machines. It uses lazy.nvim for plugins (pinned by a committed
lockfile), one central keymap table, and the `carbonfox` colourscheme by default.

**Supported systems:** macOS (Homebrew) and Arch Linux (pacman). Windows is not supported.
**Requires:** Neovim 0.12 or later.

## Install

You must choose where Fondue is installed; the installer refuses to run (exit status non-zero) without a choice. A script that calls the installer must pass `--appname NAME` or `--overwrite` too.

```sh
scripts/install.sh --dry-run --appname fondue   # preview: show what would happen, change nothing
scripts/install.sh --appname fondue             # recommended: install beside your other configs, start with NVIM_APPNAME=fondue nvim
scripts/install.sh --overwrite                  # install as your default nvim config (existing ~/.config/nvim is moved to a dated backup)
```

See [docs/PREREQUISITES.md](docs/PREREQUISITES.md) for every external tool, and
[docs/SMOKE_TEST.md](docs/SMOKE_TEST.md) for the checklist to run after installing or updating.

## Layout

- `nvim/` - the whole Neovim configuration (linked to `~/.config/nvim`)
- `scripts/` - installer and the push-time secret scan
- `docs/` - prerequisites and the smoke test
