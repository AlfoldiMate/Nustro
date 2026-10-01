# nustro

The distro's own command: where the setup stands, what needs attention, and
how to put it right.

```nu
nustro                   # = nustro status: version, behind or not, what needs attention
nustro doctor            # the full health check: roots, layout, parse, tools, plugins, modules
nustro repair            # re-run every wiring step; nothing installed, nothing of yours replaced
nustro upgrade           # pull the distro; the shell says when there is something to pull
nustro edit              # your config directory in $EDITOR
nustro set '$env.config.table.mode = "rounded"'   # one knob into your settings.nu
```

## Commands

Every day:

| Command | Does |
|---|---|
| `nustro` / `status` | one record: `version` (from `nustro.nuon`), `head`, `upstream`, `checked`, `nushell`, `layout`, `distro`, `yours`, `modules`, `lazy`, `theme`, and `attention` — rows of `{what, fix}`, each a thing that is off with the command that settles it. State files, PATH and one `nu -n` for the scaffold; no network, no git, no `claude` |
| `doctor` | health check: both roots, layout state, files, search paths, parse, tools, plugins, Claude Code (the marketplace, each plugin beside its module), completion caches, modules |
| `repair [--hard \| --reset] [--dry-run]` | put the wiring back the way an install leaves it — [Repair](#repair) |
| `upgrade` | fetch; check the upstream out into a throwaway worktree under `<your>/.state/nustro/`, refuse it when its `nustro.nuon` needs a newer Nushell or its `distro.nu` fails `nu-check` with the running `nu` (the parse error is printed, the checkout untouched); then `git pull --ff-only`, the commits that came in, `bootstrap scaffold init` for any scaffold file the new version ships and your directory lacks (a README, an example — never a file you have), `bootstrap tools setup`, and `harness update` when `claude` is on PATH and the checkout is the registered marketplace. After a `rollback`, returns to the branch first |
| `upgrade status` | the last check's result, with the pins `last_good`, `previous` and `branch`; touches no network |
| `upgrade rollback [commit]` | `git checkout --detach` of the commit `doctor` last saw parse (`last_good`), else the one the last `upgrade` moved off (`previous`), else the one named; the startup line then says so until `upgrade` returns |
| `edit` | open your config directory in `$EDITOR`, after the scaffold is written (what was written is printed); on the way out, `settings.nu` and every drop-in are parse-checked |
| `edit distro` | open the checkout — to read `defaults.nu`, or to work on it |
| `set <assignment>` | one assignment into `settings.nu`, replacing the knob's line whether live or commented — what `module enable` and the installer use |
| `knobs [--overridden]` | every knob from `defaults.nu` and every module's `meta.nuon`, with whether your `settings.nu` sets it |
| `module list \| info \| check \| enable \| disable \| lint` | the module system — [Modules](../../concepts/modules.md). `check` prints each dependency with its install line and, for a missing one, `then:` — what to do once it is installed; a `group` (Ghostty or WezTerm) is satisfied by any member. `enable` of a module of yours is lazy whatever the flag: the eager `source` lines are parse-time and the distro's, so an eager module of yours is a `use` in `settings.nu` |
| `module help <name> [--path]` | the page `docs:` names in the module's `meta.nuon`, through `glow` when installed and `$PAGER` otherwise — before the module has loaded, when `help terminal` still says nothing; `--path` prints where it is |
| `deps status \| manager \| install [tool …] [--dry-run]` | the five tools the distro is built around — starship, zoxide, atuin, carapace, vivid: which are on PATH, and the line that installs each with this machine's package manager (Homebrew; winget or Scoop on Windows; pacman on Arch, which has no carapace). `install` runs it for every missing one, or the ones named, one tool at a time so a failure is one row, then `bootstrap tools setup`; with no manager it prints each tool's install page and runs nothing. Package names checked 2026-10-01; only the Homebrew lines have been run |
| `plugins status \| add` | the plugin registry: the plugins beside `nu` (found through the symlinks `nu` is reached by) and whether each is registered from a file that still exists; `add` registers them all again — after every Nushell upgrade, because the registry names the versioned file |
| `completion explain "<line>"` | which rule answered a line, what it offered, what each stage cost — the same code path as Tab |
| `completion status` | what the engine has cached, and where |
| `completion clear` | forget the session's memoised answers: the next Tab asks the tool again |
| `completion fetch <tool>` | vendor one from nu_scripts **into your directory**, never the distro |
| `harness status \| register \| update` | the checkout as a Claude Code plugin marketplace: is it registered, and each plugin beside its module with the version installed and the version the checkout ships (`available`); `register` runs `claude plugin marketplace add <checkout>`, idempotent, re-pointing when another checkout held the name; `update` refreshes the marketplace and runs `claude plugin update <plugin>@nustro` for every plugin installed from it — 0.7 s each — quiet unless `--verbose` when there is no `claude` or the marketplace is another checkout's ([Agent harnesses](../../concepts/harness.md)) |
| `startup-time [n]` | time N cold interactive starts |
| `loaded-files` | what was parsed this session — find a slow import |

The four `completion` commands are the ones a person types; the engine is
[nu-complete](nu-complete.md), and its `nu-complete …` commands are what a
spec in `completions/` calls.

### Repair

`nustro repair` is what `status` and `doctor` point at. It returns a table of
`step`, `result` (`ok`, `done`, `would`, `failed`) and `note`; a step that
fails is one row, and the ones after it still run.

| Mode | Does |
|---|---|
| `repair` | soft: every step below, in order. Each writes what is missing or stale and leaves the rest alone, so on a healthy setup it changes nothing. Nothing is installed, nothing of yours is replaced |
| `repair --hard` | the installer again, taking every default (`install.nu --defaults`): what is there stays; `config.nu`, the scaffold, the missing tools, the terminal, theme, init files, plugins and Claude Code are written or installed where missing |
| `repair --reset` | the installer from an empty directory (`install.nu --clean`): everything of yours moves to `<config dir>/.backup/<stamp>/` first. It asks before it does, so it needs a terminal on both ends and errors without one |
| `--dry-run` | with any of the three: what would be done, nothing changed |

| Step | Puts back |
|---|---|
| `settings` | a `MODULES` line in `settings.nu` that still says `nu-config` — the module's name before 2026-10-02 — rewritten to `nustro` |
| `state` | `.state/nu-config/` from that time, moved to `.state/nustro/` |
| `scaffold` | the READMEs, the examples, `settings.nu`: what is missing is written (`bootstrap scaffold init`) |
| `tools` | init files for the installed tools regenerated, stale ones removed (`bootstrap tools setup`) — regenerated whether or not one is out of step, since a generator a pull changed shows only in the file's content |
| `plugins` | registered again when one is missing or names a file that is gone (`plugins add`) |
| `theme` | the last theme rendered again from the templates as they are now (`terminal theme sync`, in a shell of its own so this module never loads the lazy one) |
| `completion` | the session's memoised answers dropped (`completion clear`) |
| `harness` | the Claude Code plugins brought to the version the checkout ships (`harness update`), when `claude` is on PATH and the checkout is the registered marketplace |
| `parse` | `nu-check` on `distro.nu` and everything it sources; a pass is recorded as what `upgrade rollback` returns to |

### Bootstrap

`nustro bootstrap …` is plumbing: what the installer, the startup hooks and
`repair` run. None of it is for every day — `repair` runs the steps in order,
`status` and `doctor` read the answers. They are commands all the same,
because the installer runs each in a shell of its own and a test asks them
one at a time.

| Command | Does |
|---|---|
| `bootstrap scaffold init [--dry-run] [--force <file>]` | write every scaffold file that is missing; append to `settings.nu` the knobs it never mentions, commented; `--force` replaces one file, keeping `<file>.backup-<stamp>` |
| `bootstrap scaffold status` | every scaffold file: `present` (as init would write it), `edited`, `missing` |
| `bootstrap scaffold render <file>` | what init would write for one file, to stdout |
| `bootstrap tools setup \| status \| remove \| dir` | generated init files for installed third-party tools. zoxide's and atuin's are the tool's own `init`; carapace's is written here, not by `carapace _carapace nushell`: one direct call per slot, the answer kept twenty seconds and narrowed as you type (70 ms a key → 3 ms in a pty), `place.command` for the spans, no whole-`$env.config` assignment |
| `bootstrap upgrade check \| stale <every> \| notice \| good \| head \| branch` | fetch now; is the last result older than `every`; the startup line — `conf/update.nu` wires those two; `good` records HEAD as `last_good` — `doctor`'s parse line and `repair`'s last step call it; `head` and `branch` are the checkout's, read from `.git` without a fork |
| `bootstrap plugins notice` | the startup line when a registered plugin's file is gone (`conf/plugins.nu`) |
| `bootstrap root` / `user-root` / `layout` / `config-dir` / `in-place?` | where things are: the checkout, your directory, `split`, `in-place` or `other` with both paths, where Nushell reads its configuration on this platform, and whether the checkout is doubling as the config directory |
| `bootstrap manifest [root]` | the checkout's `nustro.nuon`: `version` and `requires_nu`; `status`, `doctor`'s first line and `upgrade`'s check read it |
| `bootstrap nu-older-than <version>` | is the running `nu` older than that |
| `bootstrap missing-tool <module> [bin] [--command]` | the error a command raises when its module's tool is not installed, worded from `meta.nuon` — for modules to import from `missing.nu`, not to type; `missing-tools` is the table behind it |

## Configuration

None. This module is deliberately knob-free: it is what you use when the
configuration is wrong, so it must not depend on the configuration being right.
`UPDATE_CHECK_EVERY` in `defaults.nu` belongs to `conf/update.nu`, which reads
it and passes it to `bootstrap upgrade stale`; the module itself never sees the const.

## Dependencies

None.

## Measured costs

17 ms at startup, `nustro` with the `nu-complete` it imports, as its
`meta.nuon` has it — 14 ms as `nu-config`, and 3 ms more for `status`,
`repair` and the `bootstrap` namespace (31.0 → 33.8 ms, `nu -n -c 'use
<module>'`, interleaved medians of 60, 2026-10-02) — eager and not optional, since it is how everything else
is inspected and repaired. Everything below reads `meta.nuon` and the state
files at the moment you ask, never at startup.

## Design

Five facts shape this module.

**Two layers of names.** What a person types is exported from `mod.nu` by
name; everything else the files export — the steps an install is made of —
is re-exported by `bootstrap.nu` under `nustro bootstrap`. `repair.nu` runs
those steps in order, each in a `try` of its own, so "what do I run after
this" has one answer.

**It is imported by the installer (`bootstrap/installer.nu`, which `install.nu` runs), a script.** A script loads no
config, so none of the config's parse-time constants exist. Anything this
module reads from the config must come through `$env` — `$env.NU_LIB_DIRS`,
`$env.NU_SMART_TAB`, `$env.NU_MODULES` — never the `const`. Referencing a const
in the module makes it unimportable outside a loaded shell, and the error points
at a line that looks fine.

**`update` is a Nushell built-in.** `nustro upgrade` is the name a user
expects, but a module that defines `update` shadows the built-in for everything
parsed after it in the same scope — `use nu-complete *` in `mod.nu` failed to
parse when a module defining `update` was exported above it, because `engine.nu` calls the
built-in. So the command is `upgrade`, and the file is `upstream.nu`, because
a module cannot export a command with its own name.

**The update check never touches the network at startup.** A start reads the
last result from `<your>/.state/nustro/upgrade.nuon` (0.3 ms, measured with
`timeit`) and prints one line when it says the checkout is behind; when the
result is older than `UPDATE_CHECK_EVERY` it spawns the fetch as a `job`, whose
result the *next* start reports. The record carries the HEAD it was measured
against, read at startup from `.git/HEAD` and its ref file rather than a `git`
fork, so a pull by any means retires the line at once. A job dies with its
shell, so a window closed within a second or two loses that check and the next
one repeats it — the result is still stale.

**`module` is a Nushell keyword.** `module list` is a perfectly good exported
name, but it cannot be *called* from inside `mod.nu` — the parser reads it as
the `module` keyword. Hence the private `mod-list`, `mod-info` and `mod-check`,
which the exported commands delegate to.

## Your directory

`user.nu` renders `templates/user/` into your directory — or rather
`scaffold.nu` does, run as a script in a `nu -n` of its own. The generator is
350 lines and costs **4.4 ms** to parse (2026-09-19, minimum of fifteen
`nu -n -c "use user.nu"` against an empty `nu -n`); a `use` is parse-time and
cannot be deferred, so a shell that never regenerates its directory would pay
that at every start. `user.nu` is the 40-line face, **0.5-0.9 ms**: it names
the directory (`--dir`, or the one this shell's config came from, which a
config-less child cannot know), runs the script, and reads the NUON it prints
back into a table. A call costs one nu start: `bootstrap scaffold status`, which renders
all ten files, is 71 ms, and `doctor` pays that for its `scaffold` line. The
rules the generator keeps:

- **Write only what is missing.** A file you have is never overwritten;
  `--force <file>` is the one exception and backs the old one up first. The
  installer calls the same command, so the two cannot drift.
- **`settings.nu` is generated, not copied.** Its body is `defaults.nu` with
  every assignment commented out — sections, comments and multi-line values
  kept, the file's own header dropped — followed by one section per module
  with knobs in its `meta.nuon`, and a `Yours` section for `use` lines. The
  parser is thirty lines: a section rule, a comment block, a blank line, or a
  knob whose brackets are followed to their close. `nustro knobs` reads
  the same two sources, so the file and the command cannot disagree.
- **A new knob is appended, commented, under a dated mark** — the only thing
  init writes into a file you have. It is a knob the file does not mention
  at all, live or commented, so a knob you deleted on purpose comes back
  once and then stays wherever you put it.
- **Links are rewritten per destination.** A relative path in a template is
  written for the template's place in the checkout (`../../docs/…` from
  `templates/user/`) and rewritten for the file's place in your directory,
  in one pass: every path is fenced with a unit separator, the text split on
  it, and the odd segments mapped. Replacing token by token would let a short
  path match inside a longer one already rewritten. A path that resolves to
  nothing in the checkout is left alone — that is what `../settings.nu` and
  `../plugins/nu_plugin_foo` do, and `templates/user/` mirrors your directory
  so they are right as written.
- **Edited is a content comparison.** `bootstrap scaffold status` renders the template
  and compares, line endings and the trailing newline ignored; mtime is
  what a `cp` or a sync changes.
- **`nustro set` replaces in place.** The knob's line is found whether live or
  commented, a commented multi-line value (`# const EDITORS = [` … `# ]`) is
  replaced whole, and a knob the file never mentioned is appended under a
  dated mark. So an installed `settings.nu` with two overrides reads as the
  knob list with two lines live in it, not as a template with a tail.

The three `.off` examples are complete and checked in CI: renamed, the
drop-in parses and binds its key, `hello` completes three slots, the palette
resolves at tier three ([Your directory](../../cookbook/user-directory.md)).

## Measured

Eager and never disabled: it is how you diagnose everything else, so it has to
load even when something below it is broken. `module disable nustro` is
refused for the same reason.

## Files

```
mod.nu         `status`, `doctor`, `knobs`, `edit`, `module …`, and what the other files export by name
repair.nu      `repair`: the wiring steps in order, or the installer again
bootstrap.nu   `bootstrap …`: every other export, re-exported as plumbing
roots.nu       where the two directories are: `root`, `user-root`, `layout`, `config-dir`, `in-place?`
user.nu        your directory's scaffold: `scaffold init | status | render` and `set` — the face
scaffold.nu    the generator behind it, a script run in a `nu -n` so that startup never parses it
tools.nu       the third-party tool registry and generator: `tools setup | status | remove | dir`
deps.nu        the tools themselves: `deps status | manager | install`
plugins.nu     the plugins beside `nu`: `plugins status | add | notice`
completion.nu  `completion explain | status | clear | fetch`, over the nu-complete engine
harness.nu     the Claude Code marketplace: `harness status | register | update`
upstream.nu    `upgrade`: is the checkout behind its remote, and pulling it
missing.nu     `missing-tool`: the error a module gives without its tool
load.nu        `use nustro`
meta.nuon      description
```

## Tests

`nu tests/run.nu config` — 65 tests in `tests/config/` (2026-10-01):
`layering` (a `const` and an `$env.` leaf in `settings.nu` reaching the
`conf/` file that reads them, `knobs` against `defaults.nu` and every
`meta.nuon`, `--overridden` naming exactly the live lines, the rule that no
`conf/` file assigns a knob `defaults.nu` owns, what startup parses and
what it leaves to the lazy hook, the hook's trigger words), `modules`
(`list | info | check | lint | enable | disable` against a user directory
with a module that keeps the contract and one that breaks it every way
`lint` knows), `upgrade` (`check | status | notice | stale | upgrade`
against a bare clone of this repository as the remote, commits pushed from
a third clone, a checkout with commits of its own, no remote, a fetch that
fails), `install` (`--dry-run` writing nothing, `--defaults` writing exactly
the scaffold with no override, a second run, a configuration that is not the
distro's moved to `.backup/` whole or `config.nu` alone with
`--keep-existing`, another setup's init files in the data dir, a broken
`env.nu` or `settings.nu` stopping the install by name, an older Nushell and
a partial checkout refused at the front door, a checkout refused as the
target), `uninstall` (the previous configuration put back exactly, a first
one left in place, `--purge`, `--dry-run`, no `--yes` without a terminal,
another configuration left alone, a pre-manifest backup), `deps` (`status`,
`install` against a fake `brew` alone on PATH: once per missing tool, named
tools only, one failing and the rest going on, no manager) and `tools` (`setup | status | remove`, the files
parsing, the carapace file asking a fake carapace once per slot, an unknown
command looked up without starting brew). [Tests](../tests.md) is the harness.

## Limits

`doctor`'s parse check runs `nu-check` on `distro.nu`, which follows every
`source` but does not execute anything — a file that parses can still fail at
runtime.
