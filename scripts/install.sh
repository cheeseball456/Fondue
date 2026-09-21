#!/bin/sh
# Fondue installer for macOS (Homebrew) and Arch Linux (pacman).
#
# Usage: install.sh --appname NAME [--dry-run] [--skip-packages]
#        install.sh --overwrite [--dry-run] [--skip-packages]
#        install.sh --check-only
#
# You must choose where Fondue is installed; with neither --appname nor --overwrite
# (and not --check-only) the installer refuses and changes nothing.
#
#   --appname NAME   install as ~/.config/NAME, beside your other configs (recommended);
#                    start it with: NVIM_APPNAME=NAME nvim
#   --overwrite      install as your default ~/.config/nvim. Whatever is already at the
#                    target is moved to a dated backup first (<target>.bak-<date>);
#                    nothing is ever deleted. Also allowed together with --appname NAME
#                    to replace an existing ~/.config/NAME the same way. Only the config
#                    folder is backed up: Neovim's data, state and cache folders
#                    (~/.local/share, ~/.local/state, ~/.cache) are shared with your
#                    previous configuration of the same name and are not moved.
#                    (--appname NAME on its own is the cleaner way to try Fondue.)
#   --dry-run        behave exactly like a real run, but only print the actions
#   --check-only     report missing prerequisites, install and change nothing
#   --skip-packages  do not install missing tools (the other steps still run)
#
# Steps: 1 prerequisites, 2 link nvim/, 3 restore plugins from the lockfile,
# 4 repository safety setup (secret scan) when this is a git or jj clone.
# It never prompts, never edits terminal settings, and is safe to run again.
# Exit status is 0 on success and non-zero on any failure.
#
# Testing hook: FONDUE_OS=macos|arch|other forces the detected system.

DRY_RUN=0
CHECK_ONLY=0
SKIP_PACKAGES=0
OVERWRITE=0
APPNAME=""
APPNAME_SEEN=0 # was --appname given at all (even with an empty value)?

CHANGES=0 # how many things this run changed (0 means "nothing to do")
FAILED=0

# Where this script lives, and so which repository it belongs to. Using an
# absolute path here is what lets another script call us from any directory.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P) || exit 1
REPO_DIR=$(dirname "$SCRIPT_DIR")

say() { printf '%s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }
die() { printf 'install.sh: ERROR: %s\n' "$*" >&2; exit 1; }

# --- Options -----------------------------------------------------------------
while [ $# -gt 0 ]; do
  case $1 in
    --dry-run) DRY_RUN=1 ;;
    --check-only) CHECK_ONLY=1 ;;
    --skip-packages) SKIP_PACKAGES=1 ;;
    --overwrite) OVERWRITE=1 ;;
    --appname)
      [ $# -ge 2 ] || die "--appname needs a name"
      # A name that looks like an option means the name was forgotten and we would swallow a flag.
      case $2 in -*) die "--appname needs a name, but got '$2' (a name may not start with '-')" ;; esac
      APPNAME=$2
      APPNAME_SEEN=1
      shift
      ;;
    --appname=*) APPNAME=${1#--appname=}; APPNAME_SEEN=1 ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
  shift
done

# The install target must be chosen explicitly, so nobody replaces their default
# configuration by accident. (--check-only changes nothing, so it needs no choice.)
# An empty name is an error, not "not given" (a script with an empty variable must not fall
# through to the default location).
if [ "$APPNAME_SEEN" -eq 1 ] && [ -z "$APPNAME" ]; then
  die "--appname needs a non-empty name (for example: --appname fondue). Nothing was changed."
fi
if [ "$CHECK_ONLY" -eq 0 ]; then
  if [ "$APPNAME_SEEN" -eq 0 ] && [ "$OVERWRITE" -eq 0 ]; then
    cat >&2 <<'FONDUE_REFUSE'
install.sh: ERROR: choose where to install Fondue. Nothing was changed.

  --appname NAME   (recommended) install beside your other configs, as ~/.config/NAME.
                   Start it with: NVIM_APPNAME=NAME nvim   (for example: --appname fondue)
  --overwrite      install as your default "nvim" configuration. Anything already at
                   ~/.config/nvim is moved to a dated backup (~/.config/nvim.bak-<date>)
                   first; nothing is deleted. Only the config folder is backed up.

Add --dry-run to preview either choice, for example:
  scripts/install.sh --dry-run --appname fondue
FONDUE_REFUSE
    exit 1
  fi
  # macOS file systems ignore case, so "Nvim" reaches ~/.config/nvim too.
  APPNAME_LOWER=$(printf '%s' "$APPNAME" | tr 'A-Z' 'a-z')
  if [ "$APPNAME_LOWER" = nvim ] && [ "$OVERWRITE" -eq 0 ]; then
    die "--appname $APPNAME installs as your default Neovim configuration (the name nvim, in any letter case), so it also needs --overwrite (whatever is at ~/.config/nvim is moved to a dated backup first). To keep your current configuration, choose another name, for example --appname fondue. Nothing was changed."
  fi
fi
# --overwrite on its own means the default name.
[ -n "$APPNAME" ] || APPNAME=nvim

# The name becomes a folder name, so keep it a plain word.
case $APPNAME in
  ""|*/*|.|..) die "--appname must be a simple name, not a path: '$APPNAME'" ;;
  -*) die "--appname may not start with '-': '$APPNAME'" ;;
  *[!A-Za-z0-9._-]*) die "--appname may only contain letters, digits, '.', '_' and '-': '$APPNAME'" ;;
esac

# Run a command, or only show it under --dry-run.
run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    say "  would run: $*"
  else
    say "  running: $*"
    "$@"
  fi
}

# --- Which system? -------------------------------------------------------------
detect_os() {
  if [ -n "${FONDUE_OS:-}" ]; then
    echo "$FONDUE_OS"
    return
  fi
  case $(uname -s) in
    Darwin) echo macos ;;
    Linux)
      # A subshell, so the variables from os-release do not leak into this script.
      (
        [ -r /etc/os-release ] || { echo other; exit 0; }
        . /etc/os-release
        case " ${ID:-} ${ID_LIKE:-} " in
          *" arch "*) echo arch ;;
          *) echo other ;;
        esac
      )
      ;;
    *) echo other ;;
  esac
}

OS=$(detect_os)
case $OS in
  macos|arch) ;;
  *) die "unsupported system. Fondue supports macOS (Homebrew) and Arch Linux (pacman). Nothing was changed." ;;
esac

# --- The prerequisite list -------------------------------------------------------
# One line per tool:  label | commands that count as "installed" | Homebrew package | pacman package
# "-" means there is no package to install; the message says what to do instead.
# "n/a" means the tool is not needed on that system (macOS has pbcopy/pbpaste built in).
# Keep this list in step with docs/PREREQUISITES.md and nvim/lua/fondue/health.lua.
tool_list() {
  cat <<'FONDUE_TOOLS'
Neovim|nvim|neovim|neovim
git|git|git|git
jj|jj|jj|jujutsu
tree-sitter CLI|tree-sitter|tree-sitter-cli|tree-sitter-cli
C compiler|cc gcc clang|-|gcc
ripgrep|rg|ripgrep|ripgrep
fd|fd|fd|fd
gitleaks|gitleaks|gitleaks|gitleaks
Clipboard helper (wl-clipboard)|wl-copy|n/a|wl-clipboard
FONDUE_TOOLS
}

have_any() { # have_any "cmd1 cmd2 ..."
  for c in $1; do
    command -v "$c" >/dev/null 2>&1 && return 0
  done
  return 1
}

# A Nerd Font is a set of font files whose names contain "Nerd".
have_nerd_font() {
  case $OS in
    macos) ls "$HOME/Library/Fonts" /Library/Fonts 2>/dev/null | grep -qi nerd ;;
    arch)
      if command -v fc-list >/dev/null 2>&1; then
        fc-list 2>/dev/null | grep -qi nerd
      else
        ls /usr/share/fonts/* "$HOME/.local/share/fonts" 2>/dev/null | grep -qi nerd
      fi
      ;;
  esac
}

case $OS in
  macos) FONT_PKG=font-jetbrains-mono-nerd-font ;;
  arch) FONT_PKG=ttf-jetbrains-mono-nerd ;;
esac

# Neovim 0.12 or later? Sets NVIM_FOUND to the version; returns 0 if new enough.
NVIM_FOUND=""
nvim_new_enough() {
  NVIM_FOUND=$(nvim --version 2>/dev/null | sed -n '1s/^NVIM v\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')
  [ -n "$NVIM_FOUND" ] || return 1
  major=${NVIM_FOUND%%.*}
  rest=${NVIM_FOUND#*.}
  minor=${rest%%.*}
  [ "$major" -gt 0 ] || [ "$minor" -ge 12 ]
}

# --- Step 1: prerequisites ------------------------------------------------------
MISSING_PKGS=""   # packages to install
MISSING_MANUAL="" # things we cannot install for the user
MISSING_COUNT=0
MISSING_FONT=0

check_tools() {
  MISSING_PKGS=""
  MISSING_MANUAL=""
  MISSING_COUNT=0
  MISSING_FONT=0
  while IFS='|' read -r label cmds brew_pkg pacman_pkg; do
    if [ "$OS" = macos ]; then want=$brew_pkg; else want=$pacman_pkg; fi
    [ "$want" != "n/a" ] || continue # not needed on this system
    if have_any "$cmds"; then
      say "  ok       $label"
    else
      say "  MISSING  $label"
      MISSING_COUNT=$((MISSING_COUNT + 1))
      if [ "$OS" = macos ]; then pkg=$brew_pkg; else pkg=$pacman_pkg; fi
      if [ "$pkg" = "-" ]; then
        MISSING_MANUAL="$MISSING_MANUAL
    - $label: run 'xcode-select --install' (a system dialog opens), then run this installer again"
      else
        MISSING_PKGS="$MISSING_PKGS $pkg"
      fi
    fi
  done <<FONDUE_LIST
$(tool_list)
FONDUE_LIST
  if have_nerd_font; then
    say "  ok       Nerd Font (installed; choosing it in your terminal is a manual step)"
  else
    say "  MISSING  Nerd Font (choosing it in your terminal is a manual step)"
    MISSING_COUNT=$((MISSING_COUNT + 1))
    MISSING_FONT=1
  fi
}

install_missing() {
  case $OS in
    macos)
      command -v brew >/dev/null 2>&1 ||
        die "Homebrew is not installed. Install it from https://brew.sh, then run this again."
      # shellcheck disable=SC2086  # a list of package names on purpose
      [ -z "$MISSING_PKGS" ] || run brew install $MISSING_PKGS || die "brew install failed."
      [ "$MISSING_FONT" -ne 1 ] || run brew install --cask "$FONT_PKG" || die "brew install --cask failed."
      ;;
    arch)
      command -v pacman >/dev/null 2>&1 || die "pacman was not found on this Arch system."
      pkgs="$MISSING_PKGS"
      [ "$MISSING_FONT" -ne 1 ] || pkgs="$pkgs $FONT_PKG"
      [ -n "$pkgs" ] || return 0
      # pacman needs root. Any password prompt comes from sudo, not from us.
      if [ "$(id -u)" -eq 0 ]; then
        # shellcheck disable=SC2086
        run pacman -S --needed --noconfirm $pkgs || die "pacman failed."
      else
        command -v sudo >/dev/null 2>&1 || die "sudo was not found; run this as root or install sudo."
        # shellcheck disable=SC2086
        run sudo pacman -S --needed --noconfirm $pkgs || die "pacman failed."
      fi
      ;;
  esac
  CHANGES=$((CHANGES + 1))
}

# --- Preflight: where will it go, and is that allowed? --------------------------------
# Decided before anything is installed, so a refused run never installs a package first.
CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
LINK=$CONFIG_HOME/$APPNAME
TARGET=$REPO_DIR/nvim
NEED_LINK=1
CONFLICT=""
if [ "$CHECK_ONLY" -eq 0 ]; then # --check-only changes nothing and needs no target
  [ -d "$TARGET" ] || die "cannot find $TARGET (is this a complete Fondue checkout?)"

  if [ -L "$LINK" ]; then
    if [ "$(cd "$LINK" 2>/dev/null && pwd -P)" = "$TARGET" ]; then
      NEED_LINK=0
    else
      CONFLICT="$LINK is already a link to $(readlink "$LINK")"
    fi
  elif [ -e "$LINK" ]; then
    CONFLICT="$LINK already exists"
  fi

  if [ -n "$CONFLICT" ] && [ "$OVERWRITE" -eq 0 ]; then
    say "install.sh: $CONFLICT, so it was left untouched. Nothing was changed." >&2
    say "  To proceed, do one of:" >&2
    say "    - run again with --overwrite (moves it to $LINK.bak-<date>, then links Fondue there)" >&2
    say "    - run again with --appname NAME for a different name, then start it with: NVIM_APPNAME=NAME nvim" >&2
    say "    - move or remove $LINK yourself" >&2
    exit 1
  fi
fi

step "1/4 Prerequisites ($OS)"
[ "$DRY_RUN" -eq 1 ] && say "(dry run: nothing will be changed)"
check_tools

if [ "$CHECK_ONLY" -eq 1 ]; then
  if nvim_new_enough; then
    say "  ok       Neovim version $NVIM_FOUND (0.12 or later required)"
  elif [ -n "$NVIM_FOUND" ]; then
    say "  TOO OLD  Neovim $NVIM_FOUND found; 0.12 or later is required"
    FAILED=1
  fi
  [ -z "$MISSING_MANUAL" ] || say "Manual steps:$MISSING_MANUAL"
  say ""
  if [ "$MISSING_COUNT" -gt 0 ]; then
    say "Check only: $MISSING_COUNT prerequisite(s) missing. Run without --check-only to install them."
    exit 1
  fi
  [ "$FAILED" -eq 0 ] || { say "Check only: a prerequisite is too old (see above)."; exit 1; }
  say "Check only: all prerequisites are present."
  exit 0
fi

if [ "$MISSING_COUNT" -gt 0 ]; then
  if [ "$SKIP_PACKAGES" -eq 1 ]; then
    say "  --skip-packages given: not installing $MISSING_COUNT missing item(s)."
  else
    install_missing
    if [ "$DRY_RUN" -eq 0 ]; then
      say "  Re-checking after install:"
      check_tools
      [ -z "$MISSING_MANUAL" ] || say "Manual steps:$MISSING_MANUAL"
      [ "$MISSING_COUNT" -eq 0 ] || die "some prerequisites are still missing (see above)."
    fi
  fi
else
  say "  All prerequisites are present."
fi

# Neovim must be 0.12 or later. (After a dry-run install we cannot check the new one.)
if command -v nvim >/dev/null 2>&1; then
  if nvim_new_enough; then
    say "  Neovim $NVIM_FOUND is new enough (0.12 or later required)."
  else
    if [ "$OS" = macos ]; then hint="brew upgrade neovim"; else hint="sudo pacman -Syu neovim"; fi
    msg="Neovim ${NVIM_FOUND:-of unknown version} was found, but 0.12 or later is required. Upgrade it (for example: $hint), then run this again."
    if [ "$DRY_RUN" -eq 1 ]; then
      say "  WOULD STOP: $msg"
      FAILED=1
    else
      die "$msg"
    fi
  fi
elif [ "$DRY_RUN" -eq 1 ]; then
  say "  (would verify the Neovim version after installing it)"
else
  die "Neovim is not installed, so the configuration cannot be set up (was --skip-packages used?)."
fi

# --- Step 2: link nvim/ ------------------------------------------------------------
step "2/4 Link the configuration"
[ "$NEED_LINK" -eq 1 ] || say "  $LINK already links to $TARGET; nothing to do."
if [ -n "$CONFLICT" ]; then
  # Only reachable with --overwrite (otherwise the preflight already refused).
  # Never delete: move whatever is there to a dated backup, then link.
  BACKUP_NAME="$LINK.bak-$(date +%Y%m%d-%H%M%S)"
  if [ -e "$BACKUP_NAME" ] || [ -L "$BACKUP_NAME" ]; then
    die "backup name $BACKUP_NAME is already taken; try again in a moment."
  fi
  say "  $CONFLICT; moving it to a backup."
  # -n: never replace something that appeared at the backup name in the meantime.
  run mv -n "$LINK" "$BACKUP_NAME" || die "could not move $LINK aside."
  if [ "$DRY_RUN" -eq 0 ]; then
    # mv -n can silently do nothing, so check the result rather than trust the exit status.
    if [ -e "$LINK" ] || [ -L "$LINK" ] || { [ ! -e "$BACKUP_NAME" ] && [ ! -L "$BACKUP_NAME" ]; }; then
      die "the backup did not happen ($LINK is still there or $BACKUP_NAME is missing). Nothing was deleted; please check both paths."
    fi
  fi
  CHANGES=$((CHANGES + 1))
fi

if [ "$NEED_LINK" -eq 1 ]; then
  run mkdir -p "$CONFIG_HOME" || die "could not create $CONFIG_HOME."
  run ln -s "$TARGET" "$LINK" || die "could not create the link $LINK."
  CHANGES=$((CHANGES + 1))
fi

# --- Step 3: restore plugins ---------------------------------------------------------
step "3/4 Restore plugins from the lockfile"
if [ "$DRY_RUN" -eq 1 ]; then
  say "  would run: NVIM_APPNAME=$APPNAME nvim --headless \"+Lazy! restore\" +qa"
else
  say "  running: NVIM_APPNAME=$APPNAME nvim --headless \"+Lazy! restore\" +qa"
  # Headless and non-interactive: lazy.nvim installs itself, then every plugin at its locked commit.
  NVIM_APPNAME=$APPNAME nvim --headless "+Lazy! restore" +qa || die "plugin restore failed."
  say ""
fi

# --- Step 4: repository safety ---------------------------------------------------------
step "4/4 Repository safety setup (push-time secret scan)"
if [ -e "$REPO_DIR/.git" ] || [ -e "$REPO_DIR/.jj" ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    "$SCRIPT_DIR/setup-repo" --dry-run "$REPO_DIR" || FAILED=1
  else
    out=$("$SCRIPT_DIR/setup-repo" "$REPO_DIR") || { say "$out"; die "repository setup failed."; }
    say "$out"
    if printf '%s\n' "$out" | grep -q '^setup-repo: set '; then
      CHANGES=$((CHANGES + 1))
    fi
  fi
else
  say "  Not a git or jj clone; skipping."
fi

# --- Summary ---------------------------------------------------------------------------
# Print-only note about a shell alias. It never edits any file.
# $1 is "now" for a finished install or "later" for a dry run.
print_alias_note() {
  [ "$APPNAME" != nvim ] || return 0 # plain `nvim` already uses the default name

  shell_name=${SHELL##*/}
  case $shell_name in
    zsh) rc_file="~/.zshrc"; alias_line="alias $APPNAME='NVIM_APPNAME=$APPNAME nvim'" ;;
    bash) rc_file="~/.bashrc"; alias_line="alias $APPNAME='NVIM_APPNAME=$APPNAME nvim'" ;;
    fish) rc_file="~/.config/fish/config.fish"; alias_line="alias $APPNAME 'env NVIM_APPNAME=$APPNAME nvim'" ;;
    *) rc_file="your shell's startup file"; alias_line="alias $APPNAME='NVIM_APPNAME=$APPNAME nvim'" ;;
  esac

  say ""
  if [ "$1" = later ]; then
    say "Note: after a real install with --appname $APPNAME, plain \"nvim\" will not use this"
    say "configuration. To start it with a short command, you would add this line to $rc_file:"
  else
    say "Note: you used --appname $APPNAME, so plain \"nvim\" does not use this configuration."
    say "To start it with a short command, add this line to $rc_file:"
  fi
  say ""
  say "    $alias_line"
  say ""
  if [ "$shell_name" = bash ] && [ "$OS" = macos ]; then
    say "(On macOS, bash may read ~/.bash_profile instead; add it there if ~/.bashrc has no effect.)"
  fi
  say "Then open a new terminal, or reload the file with: source $rc_file"
  say "The alias name \"$APPNAME\" is up to you; change it to anything you like."
  say "This installer does not edit your shell configuration."
}

say ""
if [ "$FAILED" -ne 0 ]; then
  say "Finished with problems (see above)."
  exit 1
fi
if [ "$DRY_RUN" -eq 1 ]; then
  say "Dry run complete. Nothing was changed."
  print_alias_note later
elif [ "$CHANGES" -eq 0 ]; then
  say "Nothing to do: already installed and linked."
  print_alias_note now
else
  if [ "$APPNAME" = nvim ]; then START="nvim"; else START="NVIM_APPNAME=$APPNAME nvim"; fi
  say "Done. Start Neovim with: $START"
  say "Remember: choose a Nerd Font in your terminal (docs/PREREQUISITES.md), then run :checkhealth fondue"
  print_alias_note now
fi
exit 0
