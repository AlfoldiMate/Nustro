# missing.nu — the one error a command gives when the tool its module needs is
# not installed
#
#   missing-tool agent claude --command "agent ask"
#
#   Error: agent ask needs claude (Claude Code), which is not installed
#     help: every verb runs one `claude -p` turn
#           install: brew install --cask claude-code
#           then:    open a new shell — Alt+E and `agent` come alive; …
#
# Everything in it is read from the module's meta.nuon (`requires`: `why`,
# `install` per platform, `then`), so the message a command gives, what
# `nustro module check` prints and what the installer says are one text
# from one file, and a module documents its own way back.
#
# A module reaches it by path — `use ../nustro/missing.nu *` — rather than
# through `use nustro`: this file is forty lines, nustro whole is 34 ms
# of parse (2026-09-20, `nu -n -c 'use nustro; use terminal *'` against
# `use terminal *` alone), and a lazy module pays its imports on first use.

const DISTRO_MODULES = (path self | path dirname | path dirname)

# The module's meta.nuon: shipped, or one of the user's.
def meta-of [module: string]: nothing -> record {
  [
    ($DISTRO_MODULES | path join $module meta.nuon)
    ($nu.config-path | path dirname | path join modules $module meta.nuon)
  ]
  | where {|f| $f | path exists }
  | get -o 0
  | if $in == null { {} } else { try { open $in } catch { {} } }
}

# The `requires` entries for a bin — or, with no bin, every hard one that is
# not installed. A `group` is satisfied by any one member, so with a group
# every member is listed: the choice is the user's.
export def missing-tools [module: string, bin?: string]: nothing -> table {
  let reqs = (meta-of $module | get -o requires | default [])
  if $bin != null { return ($reqs | where {|r| ($r.bin? | default "") == $bin }) }
  $reqs | where {|r| ($r.hard? | default true) and (which ($r.bin? | default "") | is-empty) and not (($r.paths? | default []) | any {|p| $p | path expand | path exists }) }
}

# Raise the error. `--command` names what was typed (the module's name when
# omitted); `bin` narrows it to one tool, otherwise every missing hard one.
export def missing-tool [
  module: string
  bin?: string
  --command: string   # what the user typed, for the first line
]: nothing -> any {
  let what = ($command | default $module)
  let reqs = (missing-tools $module $bin)
  if ($reqs | is-empty) {
    error make --unspanned { msg: $"($what) needs ($bin | default 'a tool'), which is not installed", help: $"nustro module check ($module)" }
  }
  let names = ($reqs | each {|r| $r.bin } | str join " or ")
  let lines = ($reqs | each {|r|
    let install = ($r.install? | get -o $nu.os-info.name | default "")
    [
      $"($r.bin): ($r.why? | default '')"
      (if ($install | is-empty) { null } else { $"  install: ($install)" })
      (if ($r.then? | default "" | is-empty) { null } else { $"  then:    ($r.then)" })
    ] | compact
  } | flatten)
  error make --unspanned {
    msg: $"($what) needs ($names), which is not installed"
    help: ($lines | str join (char nl))
  }
}
