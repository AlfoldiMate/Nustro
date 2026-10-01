# Updating

The distro is a git checkout, so an update is a pull — and because your
files are elsewhere, a pull never conflicts with anything you wrote.

```nu
nustro                    # status: `upstream` says how far behind the last check found the checkout
nustro upgrade            # git pull --ff-only in the checkout, the commits that came in, the Claude Code plugins
nustro upgrade status     # the last check's result in full, no network
nustro upgrade rollback   # back to the last version doctor saw parse; `upgrade` returns
```

A pull is checked before it is live. A configuration that fails to parse
does not mean no shell — Nushell prints the error and starts its stock
shell — but it does mean a shell with none of these commands in it, so the
check has to run while they still exist. `upgrade` fetches, checks the
upstream out into a throwaway worktree under `<your>/.state/nustro/`,
reads its `nustro.nuon` against the `nu` running (an upstream that needs a
newer Nushell is refused: `brew upgrade nushell` first), and `nu-check`s its
`distro.nu` — every `source` and `use` followed, your `settings.nu`
included. Only then does it fast-forward; otherwise it prints the parse
error and the checkout is as it was (0.24 s for the check, 2026-09-28).

What slips past — a change that parses and misbehaves — `rollback` undoes:
it checks out the last commit `nustro doctor` saw parse (its parse line
records it), or where the last `upgrade` started, or the commit you name.
HEAD is left detached, the shell says so at each start, and `nustro
upgrade` returns to the branch and pulls.

When `claude` is on PATH and the checkout is the registered marketplace,
the pull is followed by `nustro harness update`: the marketplace is
refreshed and every plugin installed from it (`worktree@nustro`,
`nushell@nustro`) is brought to the version the checkout now ships — Claude
Code keeps its own copy of a plugin, so a pull alone would leave it behind.
A moved version says so, with the reminder that a running Claude Code loads
it at its next start ([Agent harnesses](../concepts/harness.md)).

You do not have to remember to. Once every `UPDATE_CHECK_EVERY` (a day) an
interactive shell spawns a background job that fetches, and the next shell to
start prints one line when the checkout is behind:

```
distro: 2 commits behind origin/main · A new Ghostty window starts Nushell — nustro upgrade
```

The fetch is never on the startup path — a start reads the last result out of
`<your>/.state/nustro/upgrade.nuon` (0.3 ms) — and the line is keyed to the
HEAD the check saw, so it disappears as soon as HEAD moves, by `nustro
upgrade` or by hand. `nu -c` and scripts neither print nor spawn anything.
`const UPDATE_CHECK_EVERY = 0sec` in your `settings.nu` turns the check off.

`upgrade` ends with the wiring a new version may need: scaffold files your
directory lacks, the tool init files, the Claude Code plugins. A knob the
update added keeps its shipped value until you mention it; a module the
update added is off until `nustro module enable <name>`. After a pull,
`nustro` lists under `attention` anything that needs you — a theme template
newer than its render, say — and `nustro repair` settles what it lists: it
re-runs every wiring step, the theme's render (`terminal theme sync`)
included, and replaces nothing of yours.

## After `brew upgrade nushell`

```nu
nustro plugins add        # the registry is protocol-versioned against the nu that wrote it
nustro doctor
```

The plugin registry stores each plugin's signatures against the protocol
version of the `nu` that wrote them, so after a Nushell upgrade the entries
describe a protocol the new binary no longer speaks. `plugin list` showing an
old version, or a plugin command failing after an upgrade, is this and
nothing else ([Plugins](../concepts/plugins.md)).

Nushell makes breaking changes at minor versions; the distro is verified
against 0.116 (CI pins 0.116.0), and the pin is raised deliberately.
`nustro doctor` says so on the first line when the `nu` running it is
older.

## After installing a tool

```nu
nustro repair             # among its steps: the init file for anything newly installed, dropped for anything gone
nustro deps status        # which of the five tools are on PATH, and the line that installs each
```

zoxide, atuin and carapace each emit a Nushell init file; `repair`'s `tools`
step writes those into `vendor/autoload/`, where Nushell loads them after
`config.nu`. Installation is the switch. `nustro deps install` runs the same
step after it installs, and `nustro bootstrap tools setup | status` is that
step alone.

## When something is off

```nu
nustro repair             # every wiring step again; a table of step, result, note
nustro repair --dry-run   # what it would do
nustro repair --hard      # the installer again with every default: keeps what is there, installs what is missing
nustro repair --reset     # the installer from an empty directory; everything of yours moves to .backup/<stamp>/ first
```

The soft one changes nothing on a healthy setup and never replaces a file of
yours. `--reset` asks before it does and needs a terminal
([nustro](../reference/modules/nustro.md#repair)).

That is the whole of getting started. Where to go from here:
[Concepts](../README.md#concepts) for how it works, the
[Cookbook](../README.md#cookbook) for the next thing you want to do.
