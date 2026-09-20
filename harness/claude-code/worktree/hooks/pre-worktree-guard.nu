#!/usr/bin/env nu
# PreToolUse(Bash): in a bare-worktree layout, raw `git worktree add/remove/
# move` skips everything the layout depends on — the profiles, the root
# `.claude` symlink, the state manifest — so the worktree comes up without
# its env files and `worktree which`/`discard` no longer tell the truth. The
# deny routes to the shell command instead. Outside a layout the hook stays
# silent: a plain repository has no profiles to skip. Read-only subcommands
# (list, prune, lock) pass everywhere.
#
# Wrapped in try, exit 0: a bug costs one uncaught worktree command, never a
# broken session.
const COMMON = path self "_common.nu"
use $COMMON *

# Anchored to the start of the command or to a separator, so a quoted mention
# (`echo "git worktree add"`) does not trip it: quotes are stripped first.
const RE = '(^|[;&|(]\s*)git\b[^;&|]*\bworktree\s+(add|remove|move)\b'

def main []: any -> nothing {
  let p = $in | payload
  try {
    let cmd = $p.tool_input?.command? | default ""
    let stripped = $cmd
      | str replace -ra `"[^"]*"|'[^']*'` ""
      | str replace -ra '\s+' " "
    if not ($stripped =~ $RE) { return }
    let root = layout-root (cwd-of $p)
    if $root == null { return }
    print -n ({ hookSpecificOutput: {
      hookEventName: "PreToolUse"
      permissionDecision: "deny"
      permissionDecisionReason: ($"This project is a bare-worktree layout \(root: ($root)\): raw `git worktree "
        + "add/remove/move` skips the profiles, the root .claude symlink and the state manifest. "
        + "Use /worktree:worktree add|remove|apply|which <args> — the shell's `worktree` command, "
        + 'run as `nu -l -c "use worktree *; worktree <sub> <args>"`. '
        + "`git worktree list/prune/lock` are fine to run raw.")
    } } | to json -r)
  }
}
