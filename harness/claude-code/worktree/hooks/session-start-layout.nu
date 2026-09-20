#!/usr/bin/env nu
# SessionStart: when the session starts inside a bare-worktree layout, say so
# once — the root, whether the cwd is a worktree or the container, the
# worktrees and the profiles that exist, and the one rule (the shell command,
# never raw `git worktree add`). A session that has to discover the layout
# by itself runs the raw command first and meets the deny hook second; this
# puts the fact before the first tool call. Outside a layout: nothing.
#
# `git worktree list --porcelain` lists the bare dir first ("worktree <root>/
# .bare", "bare"), then each linked worktree with its branch. Profiles are the
# directories under .profiles/ other than .state.
const COMMON = path self "_common.nu"
use $COMMON *

def main []: any -> nothing {
  let p = $in | payload
  try {
    let cwd = cwd-of $p
    let root = layout-root $cwd
    if $root == null { return }
    let here = git-out $cwd rev-parse "--show-toplevel"
    let where = if ($here | is-empty) {
      "at the root (the container), not in a worktree"
    } else {
      let branch = git-out $cwd branch "--show-current" | default ""
      $"in worktree `($here | path basename)`" + (if ($branch | is-empty) { "" } else { $" \(branch ($branch)\)" })
    }
    let worktrees = git-out $root worktree list "--porcelain"
      | default ""
      | lines
      | where ($it starts-with "worktree ")
      | each { $in | str substring 9.. | path basename }
      | where $it != ".bare"
    # dflt first, as it is applied first; the rest in name order.
    let profiles = try {
      ls -s ($root | path join .profiles) | where type == dir | get name | where $it != ".state"
        | sort-by {|p| if $p == "dflt" { 0 } else { 1 } }
    } | default []
    context "SessionStart" ($"BARE-WORKTREE LAYOUT: root ($root); this session is ($where). "
      + $"Worktrees: (if ($worktrees | is-empty) { 'none' } else { $worktrees | str join ', ' }). "
      + $"Profiles: (if ($profiles | is-empty) { 'none' } else { $profiles | str join ', ' }). "
      + "Start, refresh or remove a worktree with /worktree:worktree (the shell's `worktree` command), "
      + "never raw `git worktree add/remove/move`: those skip the profiles, the root .claude symlink "
      + "and the state manifest. `worktree which` shows what is applied here.")
  }
}
