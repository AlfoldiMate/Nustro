---
name: doctor
description: Check that the worktree plugin can reach the shell command it drives — nu on PATH, Nustro's `worktree` module loaded by a login shell, git — and say what layout the current directory is in.
allowed-tools: Bash(nu --version), Bash(which -a nu), Bash(nu -l -c "use worktree *; worktree"), Bash(git rev-parse *), Bash(git worktree list *)
---

# worktree doctor

The shell this plugin drives:

```
!`nu --version 2>&1 || echo "nu is not on PATH"`
!`which -a nu 2>&1`
```

The command itself, from a login shell — the distro's `worktree` module,
which prints its subcommands when reached:

```
!`nu -l -c "use worktree *; worktree" 2>&1 || echo "worktree: exited $?"`
```

Where this session is:

```
!`git rev-parse --git-common-dir --show-toplevel 2>&1 || echo "not in a git repository"`
!`git worktree list 2>&1`
```

Read all four and report in at most six lines:

1. Whether `nu` is on PATH and its version. Two paths from `which -a` means
   a stale copy may shadow the one the distro was installed for.
2. Whether `worktree` printed its subcommand list. `Command \`worktree\` not
   found` or `Module not found` means the login shell is not the Nushell
   distro, or a distro older than the module: install it
   (`https://github.com/AlfoldiMate/Nustro`) or `nu-config upgrade`.
   `use` failing on a distro that has the module means `worktree` is not in
   `MODULES` in the user's `settings.nu`.
3. The layout: `--git-common-dir` ending in `.bare` is a bare-worktree
   layout, its parent the root; `--show-toplevel` present means the cwd is
   inside a worktree, absent (an error on the second line) means the root.
   Anything else is a plain repository, where this plugin does nothing until
   `/worktree:worktree init` — a transformation, the user's call.
4. If the hooks are silent in a layout (no BARE-WORKTREE LAYOUT line at
   session start): the plugin's hooks run `nu -n`, so 1 is the cause.
