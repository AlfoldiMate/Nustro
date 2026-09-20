# Agent harnesses: the shell inside Claude Code

The question this page answers: *the `agent` module puts Claude Code inside
the shell; what puts the shell inside Claude Code, and why is it shaped the
way it is?*

The `harness/` directory. A harness is what runs an agent — Claude Code
today; the directory is named for the general case because a second one
would go beside it, not inside it. Under it, one directory per harness, and
under that one plugin per module of this distro that wants a presence in a
session:

```
.claude-plugin/marketplace.json     the marketplace: Claude Code looks for it at the root, nowhere else
harness/
└── claude-code/
    └── worktree/                   one plugin, named after its module
        ├── .claude-plugin/plugin.json
        ├── README.md               the plugin's own reference page
        ├── skills/<name>/SKILL.md  what the session can invoke: /worktree:worktree, /worktree:doctor
        └── hooks/                  hooks.json and the Nushell scripts it names
```

## A plugin is a client of the shell

The `worktree` module is 650 lines of Nushell. The plugin that drives it
holds none of them: its skill runs

```
nu -l -c "use worktree *; worktree <sub> <args>"
```

and interprets the result. `-l` loads the distro, so the module is on the
search path; the explicit `use` is what the shell does by itself on the
first mention of a lazy module, and a `-c` string has no hook to do it. So
the plugin works whether the module is loaded, lazy, or even disabled in the
user's `MODULES` — the distro's `modules/` is always on `NU_LIB_DIRS` — and
what it cannot survive is a login shell that is not this distro at all:
`Module not found`, which `/worktree:doctor` names and `nu-config harness
status` shows beside the module.

That is the alternative rejected: shipping a copy of the script in the
plugin, which is what the Loom repository did before the module existed and
what let the two drift. One implementation, two front doors. The same holds
for anything a session needs to know: the care points in the skill are the
ones in the module's reference page, in the words a session acts on.

## One plugin per module, one marketplace

A single "nushell" plugin would be one install. It would also be every
hook for every module in every session: the `worktree` plugin's Bash hook
runs on each Bash call (14 ms when the command is not a worktree command),
and a user without worktrees has no reason to pay it. Per module, a plugin
is installed by the people who use the module, its version moves with the
module, and its name is the module's, so `/worktree:worktree` at the prompt
of a session is `worktree` at the prompt of the shell. The marketplace is
what is shared: one manifest at the root listing them all, one `claude
plugin marketplace add`, and `nu-config harness status` reading the same
file to put each plugin beside its module.

The naming has one cost: Claude Code namespaces a plugin's skills as
`/<plugin>:<skill>`, so the command skill of a plugin named after its module
reads `/worktree:worktree`. `/worktree:add` and five siblings were the
alternative; they would spread one set of care points over six files.

## What the install does

`install.nu` registers the checkout as the marketplace when `claude` is on
PATH (`nu-config harness register`, in the same child shell that renders the
theme and generates the tool files); `--skip-harness` leaves it out. A
directory marketplace is used in place — Claude Code records the path and
reads the manifest from it — so `git pull` is the marketplace update, and
adding the same path again is a no-op while adding another path under the
same name re-points it (verified 2026-09-20). Which plugin to install is
printed, not decided: a plugin adds hooks to every session, and that is the
user's yes.

A plugin, unlike the marketplace, is copied into Claude Code's cache at its
`version`. A change to one is a bump in its `plugin.json` and `claude plugin
update worktree@nustro` on the machine.

## Measured

| | |
|---|---|
| `SessionStart` hook in a layout: `nu -n`, four `git` calls, one `ls`; `hyperfine -N`, 25 runs, 2026-09-20 | 77 ms, once per session |
| `PreToolUse(Bash)` hook, a worktree command in a layout (regex, one `git rev-parse`) | 30 ms |
| the same hook, any other command (the regex misses, git is not called) | 14 ms |
| `nu-config doctor`'s Claude Code section: `claude plugin marketplace list --json` and `claude plugin list --json` | 0.35 s, the slowest line of doctor; skipped without `claude` |
| Claude Code's skill listing budget: every skill's description in one list, 8000 characters on a 200k-context model (`skillListingBudgetFraction`); over it, descriptions are kept by priority and the rest listed name-only, a new plugin skill last. On this machine, beside 28 other skills on haiku, 230 characters was the most a new skill kept (`claude --plugin-dir … -p --debug-file`, 2026-09-20) | a test keeps a plugin description ≤ 230 characters — the listing is shared, and the plugin's line is the first to go |

## Testing

`nu tests/run.nu claude-code` — `tests/claude-code/plugin.test.nu`: the two
manifests agree with each other and with `modules/`; every hook a plugin
declares is a script that exists, parses and is run with `nu -n`; the
worktree hooks against a real layout under scratch — deny with the root and
the skill in the reason, context with the worktree and the profiles, silence
for `git worktree list`, a quoted mention, a plain repository and no payload
at all; `claude plugin validate --strict` on everything when `claude` is on
the machine; `nu-config harness status` against a user directory of the
test's own.

A session end to end is not in the suite — it costs a model call — and was
run by hand on 2026-09-20 from a scratch layout, `claude --plugin-dir
harness/claude-code/worktree -p`: `/worktree:worktree which` ran the exact
command under the skill's `allowed-tools` with no permission prompt; a
requested `git worktree add ../fix-42 -b fix-42` was denied by the hook with
the reason above, no worktree was created, and the session quoted the
start-up context back.
