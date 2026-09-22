# Fondue

Fondue is a single, version-controlled Neovim configuration, kept identical across
macOS and Arch Linux machines. It uses lazy.nvim for plugins (pinned by a committed
lockfile), one central keymap table, and the `carbonfox` colourscheme by default.

It is set up for everyday editing of Python, JavaScript, JSON, bash and Lua (Swift with lightweight
support): syntax highlighting and folds from real syntax trees, language servers, completion and
snippets, formatting only when you ask (`Space c f`), shellcheck for bash, bracket pairing, surround
editing, indent guides, and UK English spell checking. Nothing is saved or formatted automatically.

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
[docs/SMOKE_TEST.md](docs/SMOKE_TEST.md) for the checklist to run after installing or updating. The installer also fetches the language tools (parsers, servers, formatters, dictionary, the completion matcher) once. Editing itself downloads nothing, with one exception: after `:Lazy update` moves the completion plugin to a newer release, that release's matcher is fetched the first time it loads (run `scripts/install.sh` after updating to fetch it up front).

## Layout

- `nvim/` - the whole Neovim configuration (linked to `~/.config/nvim`)
- `scripts/` - installer and the push-time secret scan
- `docs/` - prerequisites and a checklist for checking your installation
