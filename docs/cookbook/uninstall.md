# Undo the whole thing

```nu
nu ~/.local/share/nustro/uninstall.nu --dry-run   # the plan
nu ~/.local/share/nustro/uninstall.nu             # the plan, one question, then it
```

`uninstall.nu` takes out what the distro wrote and puts back what was there
before. Nothing is deleted except caches: the pointer `config.nu`, `.state/`
and the generated init files are **moved** to
`<config dir>/.backup/nustro-<stamp>/`, so a regretted uninstall is a `mv`
back and a meant one is one `rm -rf` of that directory. Run on 2026-10-01
against a scratch config directory holding someone else's `config.nu`,
`env.nu`, `autoload/` and `scripts/`: after `install.nu --defaults` and
`uninstall.nu --yes` the directory listed exactly as before.

| | |
|---|---|
| the terminal | the distro's file and include line(s) are removed from Ghostty's and WezTerm's config, where they are there (`--skip-terminal` leaves them) |
| Claude Code | with `claude` on PATH and the marketplace registered as this checkout: the plugins installed from it are uninstalled and the marketplace removed (`--skip-harness` leaves them) |
| the previous configuration | the newest `.backup/<stamp>/` the installer made is moved back entry by entry, its `vendor/autoload` files included; the scaffold goes to the set-aside directory first so nothing collides (`--no-restore` leaves the backup where it is) |
| your directory | with nothing to restore, `settings.nu`, `autoload/`, `completions/`, `themes/`, `modules/` and `plugins/` stay — they are yours and nothing reads them once `config.nu` is gone; `--purge` sets them aside too |
| untouched | history and the plugin registry (Nushell's own), the checkout (the last line printed is its `rm -rf`), `nu`, and every tool and font installed along the way — those are your package manager's |

`--yes` skips the question; with no terminal and no `--yes` nothing is done.
A `config.nu` that does not point at this checkout is some other
configuration and is left alone. The script imports nothing, so it runs when
the checkout no longer parses; the terminal and Claude Code steps each run in
a child and are reported, not required.

## By hand

Nothing the distro did is hidden. It wrote one file into Nushell's config
directory, one file plus one line into the terminal's, and everything else it
owns is under the checkout or under `.state/`. Undoing it without the script
is removing those, in this order.

### 1. The terminal, if you let it in

```nu
terminal status              # what the distro wrote: theme, icon, command, font — and into which terminal
terminal reset               # remove its file and the include line(s); your config is left byte-identical
```

For Ghostty the distro's settings live in `nustro.ghostty` next to
Ghostty's config, included from it by one `config-file = ?nustro.ghostty`
line; for WezTerm in `nustro.lua` next to `wezterm.lua`, applied by one
`pcall(… dofile(… "/nustro.lua").apply(config) end)` line before its
`return`. `terminal reset` acts on the one being configured; `ghostty
reset` and `wezterm reset` name one, for a machine that had both.
`reset` removes both and nothing else; the `<config>.backup-<stamp>` it made
when it first added the line stays for you to compare. Do this while the
module is still loadable — it is the distro's command.

### 2. The pointer

```nu
rm $nu.config-path           # the three-line config.nu; what was there before is in .backup/<stamp>/
```

That is the uninstall. Nushell now starts with no configuration — its own
defaults, the standard library and the plugin registry — and nothing sources
the checkout any more. Run on 2026-09-19 with `XDG_CONFIG_HOME` pointed at a
scratch directory: `install-status` was `split` before, and after removing
`config.nu` a `nu -l` had no `nu-config` command and nothing else of the
distro's.

If you had a configuration before, it is in `.backup/<stamp>/` with a
manifest naming each entry (`config.nu.backup-<stamp>` beside `config.nu`
for an install before 2026-10-01); moving the entries back is the way back.

### 3. The checkout

```nu
rm -rf ~/.local/share/nustro     # or wherever `nu-config distro-root` said
```

### 4. What is left, and yours

Everything else in your config directory is yours, and the distro never
needed any of it removed:

| | keep or remove |
|---|---|
| `settings.nu`, `autoload/`, `completions/`, `themes/`, `modules/`, `plugins/` | yours. `settings.nu`, the READMEs and the `.off` examples came from the distro's `templates/user/`, but you own them now; nothing reads them once the distro is gone |
| `history.sqlite3`, `plugin.msgpackz` | Nushell's own; a plain `nu` goes on using them |
| `vendor/autoload/*.nu` | generated init files for zoxide, atuin, carapace. Nushell loads them without the distro too, so remove them if you do not want those tools wired: `nu-config tools remove <tool>` for each before step 2, or `rm` after |
| `.state/` | the theme render, the update check, agent sessions, the OData registry. Nothing reads them once the distro is gone; `rm -rf` |
| `$nu.cache-dir/nu-complete`, `$nu.cache-dir/odata` | caches; `rm -rf` |

Fonts installed by `font install` stay installed — they are files in your
font directory (`~/Library/Fonts`, `~/.local/share/fonts`) or a Homebrew
cask, and removing a font you may be using elsewhere is not the distro's
call.

## Keeping the shell, dropping the distro

If what you want is the same shell without the moving parts, that is not an
uninstall: `nu-config module disable <name>` for each module you do not want,
`const UPDATE_CHECK_EVERY = 0sec` in `settings.nu` for the update check, and
`SMART_TAB = false` for Nushell's own Tab menu
([Knobs](../reference/knobs.md)). What is left is `defaults.nu` and `conf/`,
which is a few hundred lines of values you can read in one sitting.
