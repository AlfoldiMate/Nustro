#!/bin/sh
# install.sh — get Nushell, get this distro, hand over to install.nu
#
#   curl -fsSL https://raw.githubusercontent.com/AlfoldiMate/Nustro/main/bootstrap/install.sh | sh
#   sh install.sh --yes                     take every default, ask nothing
#   sh install.sh --dir ~/src/nu-distro     clone somewhere else
#   sh install.sh --minimal --skip-deps     anything install.nu takes is handed on to it
#
# This script has exactly two jobs: make sure `nu` exists, and put the distro
# on disk. Everything after that is Nushell — `install.nu` is the installer,
# and it is written in the shell it installs.
#
# A `nu` older than the distro requires is not good enough: install.nu would
# refuse it, so this offers to upgrade it first, the way it was installed.
#
# It asks before it installs anything, it never writes outside $HOME, and
# re-running it is a `git pull`. Read it first; anyone piping a URL into a
# shell should be able to, which is why it is this short.
#
# Overridable with environment variables as well as flags:
#   NUSTRO_REPO  NUSTRO_DIR  NUSTRO_REF  NUSHELL_VERSION

set -eu

REPO="${NUSTRO_REPO:-https://github.com/AlfoldiMate/Nustro.git}"
DIR="${NUSTRO_DIR:-$HOME/.local/share/nustro}"
REF="${NUSTRO_REF:-}"
# Only used for the release-tarball path; resolved from GitHub when empty.
NU_VERSION="${NUSHELL_VERSION:-}"
BIN_DIR="${NUSHELL_BIN_DIR:-$HOME/.local/bin}"
# The oldest Nushell the distro runs on — nustro.nuon's `requires_nu`, which
# cannot be read before the clone. Raised together with it and the CI pin.
MIN_NU="0.116"
YES=0
RUN_INSTALLER=1
# Handed on to install.nu as they are.
PASS=""

while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes)     YES=1 ;;
    --dir|--repo|--ref)
      [ $# -ge 2 ] || { echo "$1 needs a value" >&2; exit 2; }
      case "$1" in --dir) DIR="$2" ;; --repo) REPO="$2" ;; --ref) REF="$2" ;; esac
      shift ;;
    --no-install) RUN_INSTALLER=0 ;;
    --minimal|--dry-run|--keep-existing|--clean|--skip-deps|--skip-tools|--skip-plugins|--skip-terminal|--skip-harness)
      PASS="$PASS $1" ;;
    -h|--help)    sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

# ── Talking to the user ───────────────────────────────────────────────────────
# Piped into `sh`, stdin is this script, so every prompt reads /dev/tty. When
# there is no terminal at all the script refuses to guess: --yes says so.

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  B=$(printf '\033[1m'); C=$(printf '\033[36;1m'); D=$(printf '\033[2m'); R=$(printf '\033[0m')
else
  B=''; C=''; D=''; R=''
fi

step() { printf '%s%s%s\n' "$C" "$1" "$R"; }
info() { printf '  %s\n' "$1"; }
note() { printf '  %s%s%s\n' "$D" "$1" "$R"; }
die()  { printf '%s\n' "error: $1" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# Is there a terminal to talk to? Opening it is the test: /dev/tty is
# world-readable, so `[ -r /dev/tty ]` says yes in an ssh command, a cron job
# and a provisioning script, where the open then fails with "Device not
# configured" and took the hand-over to install.nu down with it.
have_tty() { (: < /dev/tty) 2>/dev/null; }

# ask "question" "default(y|n)" -> 0 for yes
ask() {
  if [ "$YES" = 1 ]; then return 0; fi
  if ! have_tty; then
    die "no terminal to ask '$1' on — re-run with --yes to accept every default"
  fi
  hint='[Y/n]'; [ "$2" = n ] && hint='[y/N]'
  printf '  %s%s%s %s ' "$B" "$1" "$R" "$hint" > /dev/tty
  read -r reply < /dev/tty || reply=''
  case "${reply:-$2}" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# ── Nushell ───────────────────────────────────────────────────────────────────

target() {
  os=$(uname -s); arch=$(uname -m)
  case "$arch" in arm64|aarch64) arch=aarch64 ;; x86_64|amd64) arch=x86_64 ;; esac
  case "$os" in
    Darwin) echo "${arch}-apple-darwin" ;;
    Linux)  echo "${arch}-unknown-linux-gnu" ;;
    *) die "unsupported platform '$os' — install Nushell yourself, then re-run" ;;
  esac
}

latest_nu() {
  [ -n "$NU_VERSION" ] && { echo "$NU_VERSION"; return; }
  # One unauthenticated API call. A rate-limited or offline machine falls back
  # to the version this distro is verified against rather than failing.
  v=$(curl -fsSL https://api.github.com/repos/nushell/nushell/releases/latest 2>/dev/null \
      | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)
  echo "${v:-${MIN_NU}.0}"
}

# new_enough "0.116.0" -> 0 when it is MIN_NU or later. Major and minor only,
# compared as numbers: 0.99 is older than 0.116, which a string compare denies.
new_enough() {
  have_major=${1%%.*}; rest=${1#*.}; have_minor=${rest%%.*}
  want_major=${MIN_NU%%.*}; want_minor=${MIN_NU#*.}
  case "$have_major$have_minor" in *[!0-9]*|'') return 1 ;; esac
  [ "$have_major" -gt "$want_major" ] && return 0
  [ "$have_major" -eq "$want_major" ] && [ "$have_minor" -ge "$want_minor" ]
}

install_nu_tarball() {
  have curl || die "curl is needed to download Nushell"
  have tar  || die "tar is needed to unpack Nushell"
  v=$(latest_nu); t=$(target)
  url="https://github.com/nushell/nushell/releases/download/${v}/nu-${v}-${t}.tar.gz"
  info "downloading $url"
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  curl -fsSL "$url" -o "$tmp/nu.tar.gz" || die "could not download $url"
  tar xzf "$tmp/nu.tar.gz" -C "$tmp"
  mkdir -p "$BIN_DIR"
  # The tarball holds nu plus the plugins that ship with it, all in one
  # directory. They have to stay together: `nu-config plugins add` registers
  # whatever sits next to the nu binary.
  cp "$tmp"/nu-*/nu "$tmp"/nu-*/nu_plugin_* "$BIN_DIR/"
  info "installed nu $v into $BIN_DIR"
  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) note "$BIN_DIR is not on your PATH — add it, or the shell you just installed is not on it either" ;;
  esac
  NU="$BIN_DIR/nu"
}

ensure_nu() {
  step "Nushell"
  if have nu; then
    NU=$(command -v nu)
    v=$("$NU" --version 2>/dev/null || echo unknown)
    info "$v at $NU"
    if new_enough "$v"; then return; fi
    info "the distro needs $MIN_NU or later"
    # The manager that installed it is the one to upgrade it; the tarball
    # puts a second nu in $BIN_DIR, which is then the one the installer runs
    # and the one the terminal is pointed at.
    case "$NU" in
      */Cellar/*|*/homebrew/*|*/linuxbrew/*)
        if have brew && ask "upgrade it with Homebrew?" y; then
          brew upgrade nushell || brew install nushell
          v=$("$NU" --version 2>/dev/null || echo unknown)
          new_enough "$v" || die "brew finished but $NU is still $v"
          return
        fi ;;
    esac
    if ask "download the official release build into $BIN_DIR?" y; then
      install_nu_tarball
      v=$("$NU" --version 2>/dev/null || echo unknown)
      new_enough "$v" || die "$NU is $v — set NUSHELL_VERSION to a release that is $MIN_NU or later"
      [ "$(command -v nu)" = "$NU" ] || note "$(command -v nu) is still first on PATH — put $BIN_DIR ahead of it, or remove the old one"
      return
    fi
    die "Nushell $MIN_NU or later is required — https://www.nushell.sh/book/installation.html"
  fi
  info "not installed"
  # Offer the package manager the machine already has first: it is the one
  # that will also upgrade nu later. The tarball is the fallback that always
  # works, and it is what --yes takes.
  if have brew && ask "install it with Homebrew?" y; then
    brew install nushell
    NU=$(command -v nu) || die "brew finished but nu is not on PATH"
  elif ask "download the official release build into $BIN_DIR?" y; then
    install_nu_tarball
  else
    die "Nushell is required — https://www.nushell.sh/book/installation.html"
  fi
}

# ── The distro ────────────────────────────────────────────────────────────────

clone() {
  step "Distro"
  have git || die "git is needed to clone $REPO"
  if [ -d "$DIR/.git" ]; then
    info "already at $DIR — updating"
    git -C "$DIR" pull --ff-only || note "could not fast-forward; your checkout has local changes"
  elif [ -e "$DIR" ]; then
    die "$DIR exists and is not a git checkout — move it, or pass --dir"
  else
    info "cloning $REPO into $DIR"
    mkdir -p "$(dirname "$DIR")"
    git clone --quiet "$REPO" "$DIR" || die "could not clone $REPO into $DIR"
  fi
  if [ -n "$REF" ]; then
    git -C "$DIR" checkout --quiet "$REF" || die "$REF is not a branch, tag or commit of $REPO"
    info "checked out $REF"
  fi
  [ -f "$DIR/install.nu" ] || die "$DIR has no install.nu — is $REPO the right repository?"
}

# ── Hand over ─────────────────────────────────────────────────────────────────

main() {
  printf '%sNustro%s  %s\n\n' "$C" "$R" "$REPO"
  ensure_nu
  printf '\n'
  clone
  printf '\n'
  if [ "$RUN_INSTALLER" = 0 ]; then
    step "Next"
    info "$NU $DIR/install.nu"
    return
  fi
  # stdin is this script when we were piped into sh, and the installer is
  # interactive, so it is given the terminal instead. `exec` so that Nushell
  # owns the process from here: what you see next is the shell being installed.
  # $PASS unquoted on purpose: it is a list of flags, none with a space in it.
  # shellcheck disable=SC2086
  if ! have_tty; then
    exec "$NU" "$DIR/install.nu" --defaults $PASS
  elif [ "$YES" = 1 ]; then
    exec "$NU" "$DIR/install.nu" --defaults $PASS < /dev/tty
  else
    exec "$NU" "$DIR/install.nu" $PASS < /dev/tty
  fi
}

main
