# Worktrees: one bare repository, a directory per branch, profiles for the rest

The question this page answers: *why does this distro have a `worktree`
module, when `git worktree` exists?*

Because `git worktree add` gives you a checkout and nothing more, and a
checkout is not a working directory. The reference page is
[worktree](../reference/modules/worktree.md); this is the reasoning.

## What a checkout is missing

Every project accumulates files git ignores on purpose: `.env` with the
credentials, a `.claude/` with the session's memory and hooks, an editor's
local settings, a `target/` that takes ten minutes to rebuild. Switch branches
in one clone and those stay; make a second worktree for a second branch and
every one of them is absent. So the second worktree is set up by hand, or by
a script that lives in one project and is rewritten for the next, or not at
all — the branch is started in the one clone by stashing, which is what
worktrees were meant to end.

The module's answer: the files git ignores are still part of the project, so
keep them once, next to the repository, and place them into every worktree.

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

**Bare, not a clone with worktrees hanging off it.** With a normal clone one
worktree is special: it is the one holding `.git/`, its branch cannot be
checked out anywhere else, and deleting the directory deletes the repository.
A bare `.bare/` makes every worktree a peer — `main` is a directory like
`fix-42`, removable like it — and gives the container a natural place for
what belongs to the project but to no branch.

**The `.git` pointer file at the root.** `git` finds its repository by walking
up until it meets a `.git` — directory or file. A file saying `gitdir: ./.bare`
means every git command works from the root itself (`git fetch`, `git branch
-a`, `git worktree list`), and it is also how the module recognises where it
is: `rev-parse --git-common-dir` from any depth names `.bare`, whose parent is
the root, and `--is-inside-work-tree` says whether the cwd is in a worktree or
in the container. No marker file, no environment variable.

**A remote fetched whole.** A repository cloned `--bare` gets the refspec
`+refs/heads/*:refs/remotes/origin/*` only if someone sets it; without it,
`git fetch` brings the default branch and nothing else, and `worktree add
fix-42` for a branch a colleague pushed finds nothing. `init` sets it on a
transform and tells you to on a fresh layout.

## Profiles

A profile is a directory; its files are the entries; an entry is placed at the
same relative path in the worktree. That is the whole format for the common
case — `mkdir .profiles/dflt && mv .env .profiles/dflt/` — and it is what a
transform produces: every gitignored path the repository had, moved as it was.

**Symlinks by default.** One `.env` in `.profiles/dflt` is the `.env` of every
worktree: edit it in one, all have it. The link is relative
(`../.profiles/dflt/.env`), so the container can be moved or synced whole.
Where a symlink is wrong — a tool that resolves it and writes next to the
target, a file each branch is meant to diverge in — `profile.yaml` says
`type: copy`, and `discard` then removes the copy only while it still matches
the source: a diverged copy is the user's work and is kept, with a warning.

**Layered, in order.** `dflt` first, then the profiles named with `-p`, in the
order given. A later entry for the same target replaces the earlier one unless
it says `override: false` (it then also defers to anything already present in
the worktree), and `type: none` removes the target from the plan — the way a
`ci` profile drops the `.env` a `dflt` would place. The root `.claude/`, when
present and untracked, enters the plan first as an implicit entry, so a profile
can override or exclude it like any other.

**Git-tracked files are never overwritten.** A profile can only ever supply
what git does not: if a target is in `git ls-files`, the entry is skipped with
a warning naming the profile. The rule is what makes a profile safe to apply
blindly after a pull.

**`profile.yaml` is machinery, not an entry.** It and any hook script inside
the profile directory are never placed. Hooks (`before-apply`, `after-apply`,
`after-add`, `before-remove`, `before-discard`, `after-init`) are for what a
symlink cannot do: seed a database, run `direnv allow`, `cargo fetch` — in the
worktree, with `BW_ROOT`, `BW_WORKTREE` and `BW_PROFILE` set, and a failure
stops the command.

## The state manifest

`apply` writes `.profiles/.state/<worktree>.nuon`: which profiles, when, every
entry with its type, source and profile. It exists for three reasons:

- `discard` and `remove` need to know what to undo, and only what was placed
  — never a file that happened to be at the same path;
- a bare `apply` means *refresh what is here*: after editing a profile, the
  same set is re-applied without naming it again (`-p` changes the set,
  `--reset` returns to `dflt`);
- the next plan may drop a target (an entry deleted from a profile, a profile
  dropped from the set): those are retired first, or the worktree keeps a
  dangling symlink nothing records.

`which` prints it. A profile deleted since the apply is dropped from the set
with a warning rather than failing the refresh; a teardown never fails over a
missing profile.

## What `add` carries over

`worktree add` run inside a worktree starts the new branch at *that*
worktree's HEAD (not the bare repository's), and copies that worktree's
gitignored files across — except symlinks into the root (apply recreates
those) and targets the profiles are about to place (copying them first would
only churn). This is what lets a local `target/` or `node_modules` follow a
branch that was split off mid-work, which no profile should hold: a profile is
for what every worktree needs, a carry-over is for what this one had.

## The transform

`worktree init` in an existing repository is the one destructive command, and
the module treats it that way: it refuses a detached HEAD and a tree with any
uncommitted or untracked file — only gitignored files may remain, because
they are what it is about to move. Then: `.git/` becomes `.bare/` with
`core.bare` set, the pointer file is written, the current branch is checked
out as `./<branch>`, every gitignored path is moved into `.profiles/dflt`, the
tracked files' originals (now duplicates of the checkout) are removed from the
root along with the directories that emptied. `.claude/` is left where it is:
the root is where `apply` symlinks it from. A `node_modules`, `target` or
`.venv` that lands in `dflt` is named in a warning — a fresh checkout should
rebuild those, and a profile holding them only bloats. The only deletions are
the duplicates of tracked files and the directories that emptied.

## Where it came from

The module began as a standalone script in the Loom repository's `.claude/`,
written for a Claude Code command (`/bare-worktree`) whose hook denied raw
`git worktree add|remove|move` in a layout, because those skip the profiles
and the `.claude` symlink. The script imported nothing from its surroundings
so that it could move into a shell config unchanged; this module is that move,
with the commands under `worktree`, Tab completion for worktree and profile
names, and the module contract around it. What a Claude Code session in such a
project needs — the deny hook, the command's care points — stays with that
project's `.claude/`; the shell command is what both call.
