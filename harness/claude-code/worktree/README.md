# worktree plugin for Claude Code

The bare-worktree layout — one bare repository, a sibling directory per
branch, the gitignored files each checkout needs kept in profiles — driven
from a Claude Code session. The layout and every command live in the
[Nustro](https://github.com/AlfoldiMate/Nustro)'s `worktree`
module; this plugin is its client, so a session gets the same command, the
same refusals and the care points a user has at the prompt.

## Install

Requires Nustro as the login shell's configuration (`nu -l`
must load it — `nustro doctor` in a shell says so), and `git`.

```
claude plugin marketplace add AlfoldiMate/Nustro
claude plugin install worktree@nustro
```

From a checkout of the distro without installing: `claude --plugin-dir
harness/claude-code/worktree`.

## What it adds

| Piece | What it does |
|---|---|
| `/worktree:worktree <sub> [args]` | Runs `nu -l -c "use worktree *; worktree <sub> [args]"` and interprets the result. `add`, `remove`, `apply` and `which` Claude runs itself; `init`, `discard` and `--force` are asked first. The care points — a transform, the junk warning, what `add` carries over, a diverged copy, a `.gitignore` pattern that misses a symlink — are in the skill |
| `/worktree:doctor` | nu on PATH, the module reachable from a login shell, git, and which layout the cwd is in |
| `SessionStart` hook | In a layout, one line before the first tool call: the root, whether the cwd is a worktree or the container, the worktrees and the profiles, and the rule. Silent elsewhere. 77 ms |
| `PreToolUse(Bash)` hook | Denies raw `git worktree add/remove/move` inside a layout — those skip the profiles, the root `.claude` symlink and the state manifest — and points at the skill. `list`, `prune` and `lock` pass; outside a layout everything passes. 14 ms when the command is not a worktree command, 30 ms when it is |

Both hooks are Nushell scripts run with `nu -n` — no config loaded, one
`git rev-parse` to recognise the layout — and wrapped in `try`, exit 0: a
bug costs one uncaught command, never a session. Measured 2026-09-20,
`hyperfine -N`, 25 runs each, M-series Mac.

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

Why a bare repository, why profiles, why symlinks and where copies come in:
[Worktrees](../../docs/concepts/worktree.md). Every command and flag, the
`profile.nuon` format and its hooks:
[worktree](../../docs/reference/modules/worktree.md).

## A `.claude/` in the layout

A `.claude/` at the root that git does not track is symlinked into every
worktree on `apply`, so one copy of the project's hooks, skills and memory
serves every branch. A project that *tracks* `.claude/` in git has it in
every worktree already; what it may still want is a symlink at the root
(`ln -s main/.claude .claude`), because a session started from the root
resolves `$CLAUDE_PROJECT_DIR/.claude` there.

## Where it came from

The module began as a standalone script in the Loom repository's `.claude/`,
written for a `/bare-worktree` command and a hook that denied raw `git
worktree` in a layout. The script moved into the distro as the `worktree`
module; the command and the hook moved here, pointed at the shell command
instead of a copy of the script, so the two cannot drift.
