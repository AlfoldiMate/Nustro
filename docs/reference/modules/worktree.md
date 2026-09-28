# worktree

A bare repository with one sibling directory per branch, and the gitignored
files each checkout needs — `.env`, a `.claude/`, a local config — kept once in
profiles and placed into every worktree.

```nu
worktree init                  # in an empty dir: a fresh layout; in a repo: transform it
worktree add main              # a worktree and a branch, the default profile applied
worktree add fix-42 -p ci      # another, with the `ci` profile on top; Tab completes profiles
worktree which                 # what is applied here, what exists to apply
worktree apply                 # refresh the entries after editing a profile
worktree remove fix-42         # undo the entries, then `git worktree remove`; Tab completes names
```

A worktree made by `git worktree add` is a checkout and nothing more: every
file git ignores — the very files a session needs — is missing. This module
makes the layout below, keeps those files in `.profiles/`, and places them
into each worktree as symlinks (or copies, when a profile says so), so a new
branch is ready to use the moment it exists. The design is
[Worktrees](../../concepts/worktree.md).

```
proj/                  the root: the container
├── .bare/             the one real git dir (bare)
├── .git               a file, `gitdir: ./.bare`, so git works from the root
├── .claude/           optional; symlinked into every worktree on apply
├── .profiles/         the gitignored files each worktree needs
│   ├── .state/        one manifest per worktree: what apply did
│   ├── dflt/          the default profile, always applied first
│   └── <name>/        any other directory is a named profile
└── <worktree>/        one sibling directory per branch
```

## Commands

Every command resolves the layout from the current directory: from inside a
worktree, from the root, from any depth below either. Tab completes worktree
names for `remove`, `--to` and `--on`, and profile names for `-p`.

| Command | Does |
|---|---|
| `worktree` | the subcommands, one line each |
| `worktree init` | in an empty directory: `.bare`, the `.git` pointer file and an empty `dflt` profile. In an existing repository: transforms it — history into `.bare`, the current branch checked out as `./<branch>`, every gitignored file moved into `.profiles/dflt`, the tracked files' originals removed from the root. Refuses a dirty tree, a detached HEAD and a layout that already exists |
| `worktree add <name> [-p a,b]` | `git worktree add` for a branch of that name — existing; on exactly one remote, tracked (`--track`); orphan when no branch has a commit yet; else new from the current worktree's HEAD, a bare HEAD that names no branch repointed at the first one — the base worktree's gitignored files carried over, then `dflt` and the listed profiles applied |
| `worktree remove <name> [--force]` | the profile entries discarded, then `git worktree remove`; `--force` goes through to git for a worktree with untracked files left |
| `worktree apply [-p a,b] [--to <wt>] [--reset]` | bare: refresh the set the manifest records; `-p`: change the set (`dflt` plus these, in order); `--reset`: back to `dflt` alone. `--to` names the worktree from the root |
| `worktree discard` | undo what `apply` placed in this worktree: symlinks always, a copy only while it still matches its source |
| `worktree which [--on <wt>]` | the applied profiles and every entry, when and from which profile, then the profiles that exist |

### Profiles

A profile is a directory under `.profiles/`. Every file in it is an entry:
symlinked into the worktree at the same relative path. `dflt` is always
applied first; a later profile's entry replaces an earlier one's. An optional
`profile.yaml` in the profile directory (never itself placed) overrides entries
and declares hooks:

```yaml
entries:
  - source: .env.local      # relative to the profile dir, or absolute
    type: copy              # symlink (default) | copy | none (exclude the target)
    override: true          # false: never replace something already there
    target: .env.local      # required only when source is absolute
hooks:
  before-apply:             # one record or a list of them
    - command: scripts/seed.nu   # relative: resolved in the profile dir
      args: ["--fast"]
  after-apply: ...
```

The hook points: `before-apply`, `after-apply` (both from `apply` and from
`add`), `after-add` (the worktree stands, profiles applied), `before-remove`
and `before-discard` (the entries still exist), `after-init` (`dflt` only,
once, when a transform completes). A hook runs in the worktree with `BW_ROOT`,
`BW_WORKTREE` and `BW_PROFILE` in its environment; a `.nu` command runs under
this `nu`, anything else as itself. A failing hook stops the command.

Three rules `apply` keeps whatever the profiles say:

- a git-tracked file is never overwritten — the entry is skipped with a
  warning;
- a real directory in the way of a file entry is left alone, with a warning;
- a root `.claude/` that git does not track is placed in every worktree unless
  a profile overrides or excludes the `.claude` target.

## Configuration

None. There are no knobs: the layout is the configuration, and every command
reads it from the current directory.

## Dependencies

| | | |
|---|---|---|
| `git` | hard | the layout is git's own: a bare repository, linked worktrees, the ignore rules that decide what a profile holds |

`nu-config module check worktree`.

## From a Claude Code session

The `worktree` plugin (`harness/claude-code/worktree/`, installed with
`claude plugin install worktree@nustro` once the checkout is
registered as a marketplace — the install does that) gives a session
`/worktree:worktree <sub> [args]`, which runs `nu -l -c "use worktree *;
worktree …"` with the care points above, `/worktree:doctor`, a hook that
denies raw `git worktree add/remove/move` in a layout, and one line at
session start naming the root, the worktree and the profiles
([its README](../../../harness/claude-code/worktree/README.md)).

## Design

Why a bare repository, why profiles rather than a script per project, why
symlinks and where copies come in, what the state manifest is for, and what
`add` carries over from the worktree it was started in:
[Worktrees](../../concepts/worktree.md).

## Measured

| | |
|---|---|
| loading the module: 68.8 ms of startup eager against 59.2 ms lazy, medians of 25 cold `nu -l` starts in three alternating rounds, Nushell 0.115.2, 2026-09-20 | 10 ms |
| `worktree which` inside a worktree, two worktrees and two profiles in the layout, median of 25 | 50 ms — two `git rev-parse` calls to find the layout, the manifest, the table |
| Tab on `worktree remove ` (the names completer), median of 25 | 32 ms — the same two `git rev-parse` calls, then one directory listing |

Lazy: `worktree` is the word every command starts with, so it is the trigger
and needs no `MODULES_TRIGGERS` entry.

## Files

```
mod.nu      the commands, the two completers, and `worktree activate` (nothing to wire)
load.nu     `use worktree *` + activate
meta.nuon   description, git as the dependency, the cost
```

Inside a layout, `.profiles/.state/<worktree>.nuon` records what `apply` last
placed: the profiles in order, when, and every entry with its type, source and
profile. `discard`, `remove` and the next `apply` read it; a stale entry the
new plan no longer produces is retired before the new one is placed. Nothing
is written under `$nu.data-dir`.

## Limits

- A lazy module is interactive-only: a script says `use worktree *` itself.
- `init` on an existing repository is a transformation. It refuses a dirty
  tree (untracked files included — only gitignored ones may remain) rather
  than stash for you; the gitignored leftovers become `dflt`, so review that
  directory afterwards: `node_modules`, `target` and friends are warned about
  and belong deleted, not in a profile.
- A profile directory pattern in `.gitignore` (`.claude/`) does not match a
  symlink; `apply` warns about every placed entry git does not ignore and
  says which pattern to use (`.claude`).
- `discard` keeps a copy that has diverged from its source and says so: that
  file is your work now.
- `remove` refuses a worktree with untracked files left, as git does; the
  error explains `--force`.
- Windows: symlinks need Developer Mode or elevation; untested there.

## Tests

`nu tests/run.nu worktree` — `tests/worktree/worktree.test.nu` runs every
command against a layout under the run's scratch directory: init, a
transform, add with profiles and a `profile.yaml`, apply's refresh and reset,
the tracked-file and diverged-copy rules, discard, remove.
