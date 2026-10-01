---
name: worktree
description: Drive the bare-worktree layout through Nustro's `worktree` command: init, add, remove, apply, discard, which. Use for a worktree, a branch in its own directory or a profile, in a project whose root holds `.bare`.
argument-hint: "<init|add|remove|apply|discard|which> [args]"
allowed-tools: Bash(nu -l -c "use worktree *; worktree *"), AskUserQuestion
---

# worktree

Everything is implemented in the shell: the layout, the profile format and
every subcommand live in Nustro's `worktree` module. This skill
runs it and interprets the result. Run it from the directory the user means —
every subcommand resolves the layout from the cwd, and root against inside a
worktree changes what `add`, `apply` and `which` do:

```bash
nu -l -c "use worktree *; worktree $ARGUMENTS"
```

`-l` is what loads the distro, so its module is on the search path; the
module is lazy, so the `use` is what a login shell would do on the first
mention. With no arguments it prints the subcommands, one line each — show
that rather than guess a subcommand. `/worktree:doctor` says whether the
command is reachable at all.

## The layout

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

A profile is a directory; every file in it is placed into the worktree at
the same relative path, as a relative symlink unless the profile's
`profile.nuon` says `type: copy`. `dflt` first, then the profiles named with
`-p`, in order; a later entry replaces an earlier one. A git-tracked file is
never overwritten.

| Subcommand | Does |
|---|---|
| `init` | in an empty directory: a fresh layout. In an existing repository: transforms it |
| `add <name> [-p a,b]` | a worktree and a branch of that name, the base worktree's gitignored files carried over, `dflt` and the listed profiles applied |
| `remove <name> [--force]` | the profile entries discarded, then `git worktree remove` |
| `apply [-p a,b] [--to <wt>] [--reset]` | refresh the recorded set; `-p` changes it, `--reset` returns to `dflt` |
| `discard` | undo what apply placed in this worktree |
| `which [--on <wt>]` | the applied profiles and every entry, then the profiles that exist |

## What you may run, and what is the user's

Run `add`, `remove` (without `--force`), `apply` and `which` yourself: the
command refuses anything unsafe, and the refusal is the answer. `init`,
`discard` and any `--force` are the user's: ask with `AskUserQuestion` and
run only on a yes in this conversation.

Care points, in order of severity:

- **`init` on an existing repository is a transformation** — history moves
  into `.bare`, the working tree is re-created as a worktree, gitignored
  files move into `.profiles/dflt`, the tracked files' originals are removed
  from the root. Confirm before running it on a repository that was not just
  created for this. It refuses a dirty tree; relay that refusal as-is, never
  stash or commit on the user's behalf to get past it.
- **After a transform, relay the junk warning verbatim** (`node_modules`,
  `target`, `.venv` landing in `.profiles/dflt`) and offer to delete those —
  they are rebuildable and only bloat the profile.
- **`add` inside a worktree branches from that worktree's HEAD**, not from
  the bare repository's, and copies that worktree's gitignored files across.
  From the root nothing is carried over and the branch starts at the
  repository's HEAD. Say which one is about to happen when it matters (a
  `target/` of many gigabytes takes minutes to clone).
- **`remove` refuses when untracked files remain**; the error explains
  `--force`. Ask before re-running with it — those files are usually
  rebuildable, but it is the user's call.
- **`discard` keeps a copy that diverged from its source** and says so; a
  kept file is the user's work, never delete it by hand to "finish the job".
- **A warning about an entry that is not gitignored** means the project's
  `.gitignore` needs a pattern fix: a symlink does not match a `dir/`
  pattern, `.claude` does where `.claude/` does not. Surface it.

Read-only git (`git worktree list`, `prune`, `lock`) is fine to run raw;
`add`, `remove` and `move` are not, and a hook in this plugin denies them in
a layout for that reason.
