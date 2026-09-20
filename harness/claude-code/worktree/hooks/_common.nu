# Shared by the two hooks. One rule: a hook never breaks a session. Every
# entry point wraps its work in `try` and exits 0; every lookup has a fallback
# rather than a failure mode. Nushell because the payload is JSON, which is
# one word here, and because the shell command these hooks defend is Nushell.
#
# Adapted from the ctx-flow hooks in the Loom repository, where the layout and
# the script behind it began (docs/concepts/worktree.md, "Where it came from").

# The hook payload as a record, or {} when stdin is absent or malformed.
export def payload []: any -> record {
  let parsed = try { $in | from json }
  if (($parsed | describe) starts-with "record") { $parsed } else { {} }
}

# Where the session is: the payload's cwd, else the project dir, else PWD.
export def cwd-of [p: record]: nothing -> string {
  $p.cwd? | default $env.CLAUDE_PROJECT_DIR? | default $env.PWD
}

# Trimmed stdout of a git command, or null when it failed or git is absent.
export def git-out [cwd: string, ...args: string]: nothing -> any {
  let r = try { ^git -C $cwd ...$args | complete }
  if ($r.exit_code? | default 1) == 0 { $r.stdout | str trim } else { null }
}

# The root of the bare-worktree layout `cwd` is in, or null. The module's own
# test: `rev-parse --git-common-dir` names the one real git dir from any
# depth, in a worktree or at the container; a layout's is called `.bare`, and
# its parent is the root. No marker file, no environment variable.
export def layout-root [cwd: string]: nothing -> any {
  let common = git-out $cwd rev-parse "--git-common-dir"
  if ($common | is-empty) { return null }
  let dir = if ($common | path type) == "dir" { $common } else { $cwd | path join $common }
  let dir = $dir | path expand
  if ($dir | path basename) != ".bare" { return null }
  $dir | path dirname
}

# Print `additionalContext` for an event, as the hook protocol wants it.
export def context [event: string, text: string] {
  print -n ({ hookSpecificOutput: { hookEventName: $event, additionalContext: $text } } | to json -r)
}
