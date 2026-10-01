# Install

Two lines, one per platform. Each makes sure `nu` exists, clones this repo to
`~/.local/share/nustro`, and hands over to `install.nu`:

```sh
# macOS, Linux
curl -fsSL https://raw.githubusercontent.com/AlfoldiMate/Nustro/main/bootstrap/install.sh | sh
```

```powershell
# Windows
irm https://raw.githubusercontent.com/AlfoldiMate/Nustro/main/bootstrap/install.ps1 | iex
```

Read either script before running it; they are short on purpose, and each
asks before installing anything. `sh install.sh --yes` takes every default;
`--dir` clones somewhere else; `NUSTRO_REPO`, `_DIR`, `_REF` and
`NUSHELL_VERSION` do the same from the environment; any flag of `install.nu`
(`--minimal`, `--skip-deps`, …; `-Pass` on Windows) is handed on to it.
Re-running one is a `git pull`. Run on 2026-10-01 on macOS, each against a
scratch config directory holding a broken `env.nu`: with `nu` present, with no
`nu` on PATH and with a 0.115.2 ahead on PATH — the last two fetched the
0.116.0 release build — and with no terminal to open (an ssh command, a
provisioning script), where `--yes` is what the hand-over then takes.

Nushell **0.116 or later** is required, and nothing older is supported. A
`nu` that is older is not installed over: the bootstrap offers to upgrade it
with the manager that installed it (Homebrew, winget) or to put the official
release build in `~/.local/bin`, and `install.nu` refuses to start on one,
naming the version it found and where.

Already have Nushell 0.116 and a checkout? Skip them:

```nu
git clone https://github.com/AlfoldiMate/Nustro ~/.local/share/nustro
nu ~/.local/share/nustro/install.nu
```

## Before the first screen

`install.nu` is the front door: it imports nothing, and checks three things
before the installer proper (`bootstrap/installer.nu`) is even parsed — the
running Nushell against `nustro.nuon`, that the checkout is whole (an
interrupted clone is not), and that the installer parses with this `nu`. Each
failure is one sentence and the command that fixes it, instead of a parse
error about a module.

## The seven screens

The installer is written in the shell it installs. Every screen is skippable,
and nothing is written before you say yes to the last one:

| | |
|---|---|
| 1. Where | the checkout, and your config directory — `$nu.default-config-dir`, the one a new shell will read; it is not a question (set `XDG_CONFIG_HOME` first to have it elsewhere). Then what is already in it: nothing, this distro's (a re-run), or **a configuration that is not this distro's** — its files are listed and the choice is *back it up and start clean* (the default, and what `--defaults` does), *keep the files, replace `config.nu`* (`--keep-existing`), or *stop* |
| 2. Modules | multi-select, with each module's measured startup cost and its dependency state |
| 3. Terminal | which of the two terminals — Ghostty (macOS, Linux), WezTerm (macOS, Linux, Windows) — is installed, and whether you are *running* in one. With neither: pick one to install (Enter takes the first; `--defaults` installs the platform's own unasked — Ghostty through the Homebrew cask, WezTerm through winget on Windows; where the plan is a link nothing runs; `--skip-terminal` leaves it out). With both and running in neither: which one `theme`, `font` and `terminal shell` configure (`terminal use` later). Without any the screen says what you do without — the theme stays at the ANSI tier, no `font`, no `terminal shell`, Alt keys depend on your terminal — how to get it back (install one, open a new shell), and offers to disable the `terminal` module (default no: it is lazy and costs nothing left on). Then whether a new window starts Nushell (default yes) |
| 4. Theme | the theme the run ends with: the one rendered before (a re-run), else `doomchad`, the default — or *pick another* among a hundred palettes (NvChad's, Catppuccin), previewed by painting the live terminal. Whichever it is, it is written to the terminal (with its icon, on Ghostty) and rendered for tables, `ls`, bat and the prompt by the same `theme use`, so a terminal and a shell configured at different times — after `--clean`, after a restored backup — cannot be left on two themes. Without a terminal nothing is written and the shell follows the terminal's sixteen colours |
| 5. Font | fifteen Nerd Fonts, installed on the spot, previewed in a window of the terminal's own. With none picked and none configured in the terminal, yours or ours, DejaVu Sans Mono Nerd Font is installed and written (`--skip-terminal` leaves it out); a font the terminal already has is never replaced unasked |
| 6. Tools | which of starship / zoxide / atuin / carapace / vivid are present, and for the missing ones: *install all* (the default, and what `--defaults` does), *choose*, or *none* — with the package manager the machine has (`nu-config deps status` shows the lines; `--skip-deps` leaves them out; with no manager the install pages are printed). Then which enabled module is missing the tool it needs (`claude` for `agent`, say), with the install line and what follows once it is there; a module left without its tool is lazy and its commands say what is missing until it arrives |
| 7. The plan | every line that will be written, then one yes |

```nu
nu install.nu              # the seven screens
nu install.nu --defaults   # no questions, the whole thing: an existing configuration backed up, the missing tools and the platform's terminal installed
nu install.nu --minimal    # nu-config, nu-complete and terminal only; agent, odata, worktree are `nu-config module enable` away
nu install.nu --dry-run    # print the plan, change nothing
nu install.nu --keep-existing   # leave an existing configuration's files in place; only its config.nu is set aside
nu install.nu --clean           # start from an empty directory whatever is there, this distro's own configuration included
nu install.nu --skip-deps --skip-tools --skip-plugins --skip-terminal --skip-harness
```

The theme preview paints the terminal and `theme reset` hands it back, so a
cancelled installer leaves the terminal's configuration alone. Fonts are the
exception, because a font has to exist before it can be shown; the installer
asks before downloading one.

With no terminal on stdin and stdout the installer takes every default by
itself, which is what makes `curl … | sh` work without a flag.

## An existing configuration

Nushell reads `env.nu` before `config.nu`, `login.nu` after it, then every
file in `vendor/autoload/` and `autoload/` — whoever wrote them. A file left
over from a previous setup that no longer works (a `source` of something that
moved, a completer in the pre-0.116 shape) is an error at every start, or the
distro not loading at all; that was the install that "failed because
`nu-config` was not available" (reproduced 2026-10-01 with a stale `env.nu`).
So a configuration that is not this distro's is not merged with:

- **moved, whole, to `<config dir>/.backup/<stamp>/`** — `config.nu`,
  `env.nu`, `login.nu`, `autoload/`, scripts, everything except what is
  Nushell's own (history, the plugin registry); off macOS, the `*.nu` in the
  data directory's `vendor/autoload/` too. A manifest (`.nustro-backup.nuon`)
  records what came from where, and `nu uninstall.nu` puts it back.
- `--keep-existing` moves only the old `config.nu` there and leaves the rest.
- `--clean` does the same move for a configuration that **is** this distro's,
  which a plain re-run leaves alone: `settings.nu`, your drop-ins, `.state/`
  (the theme, the terminal pin) and the generated init files all go to the
  backup, and what follows is a first install — the way to see one on a
  machine that has had it, or out of a directory nobody can say the state
  of. The manifest marks such a backup (`ours: true`), and `uninstall.nu`
  does not restore it: that would be installing again. To go back to it,
  move its entries back by hand.

Then the installer **starts a new shell and asks it** whether the distro
loaded, from this directory. When it did not, the install stops there with
the shell's own error, the files a shell reads in order and whose each is —
not with five later steps each failing on `nu-config`. On a re-run over the
distro's own `config.nu`, an `env.nu` or `login.nu` that breaks the shell is
set aside the same way and the shell tried again (not with `--keep-existing`).

The steps after that — terminal, theme, tool init files, plugins, Claude
Code — each run in a shell of their own: one that fails is one line in the
closing summary, with the command that repeats it, the others still happen,
and the exit code is 1.

## What it writes

- a three-line `config.nu` into Nushell's config directory, pointing at the
  checkout (what was there before is in `.backup/<stamp>/`)
- your directory's scaffold: a `settings.nu` with every knob commented out at
  its shipped value, a `README.md` saying what every file and directory is,
  one in each of `autoload/`, `completions/`, `themes/`, `modules/` and
  `plugins/`, and an example per kind that does nothing until renamed —
  `nu-config user init` writes the same thing again later, for whatever is
  missing
- the missing ones of starship, zoxide, atuin, carapace and vivid, through
  your package manager (`nu-config deps install`), and the init files for
  whichever of zoxide, atuin and carapace are installed (`vendor/autoload/`)
- the plugins that ship next to `nu`, into the plugin registry
- with `claude` on PATH: the checkout registered as a Claude Code plugin
  marketplace, `nustro`, and the install line of each plugin printed
  (`claude plugin install worktree@nustro`) — a plugin adds hooks to
  every session, so that one is yours ([Agent harnesses](../concepts/harness.md))
- with a terminal: the pin (`.state/terminal/target.nuon`), and in a file of
  its own that the terminal's config includes — Ghostty's `command = <nu>`
  or WezTerm's `default_prog`, and the theme you chose
  ([Files](../reference/files.md#ghostty))

Nothing you own is ever written inside the checkout, and nothing the distro
owns is written into your directory except that `config.nu`
([Layout](../concepts/layout.md)).

**The test that it went right:** accept every default and `nu-config knobs
--overridden` comes back empty. Your `settings.nu` lists all 64 knobs (counted 2026-09-19) and
every one is commented out; every value keeps tracking the distro.

Safe to re-run after every `git pull`, tool install or Nushell upgrade. Undo
at any time with `nu uninstall.nu`: [Undo the whole thing](../cookbook/uninstall.md).

Next: [Your first shell](first-shell.md).
