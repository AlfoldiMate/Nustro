# Tab in a real terminal: the smart menu driven through tests/pty/harness.py
# (a pseudo-terminal, keys one at a time, the line read back from history),
# under the shipped defaults and again under prefix matching, where partial
# completion always has a common prefix to insert. That insert is what
# nushell#19053 broke in a sourced menu (the 0.115.2 main build turned
# `bits r` Tab Tab Enter into `bits ror o`); 0.116.0 carries the fix, and
# this is the test that says so.
use lib.nu *
use std/assert

const HARNESS = ($ROOT | path join tests pty harness.py)

# Cases as data. `want` is the line as history records it (trailing space
# trimmed); `screen` is what the menu must show for a case that only looks.
const CASES = [
  # The first two run in a shell that has not loaded the lazy terminal module
  # yet: the candidates come from a child nu (smart.nu, "Lazy modules"). The
  # Enter of the second is what loads it.
  { line: "fon", keys: "tab,esc,ctrl-c", screen: ["font dir" "font list" "font use"] }
  { line: "theme use catp", keys: "tab,tab,tab,tab,enter,enter", want: 'theme use "Catppuccin Macchiato"' }
  { line: "bits r", keys: "tab,tab,enter,enter", want: "bits ror" }
  { line: "git cher", keys: "tab,tab,enter,enter", want: "git cherry" }
  { line: "str tr", keys: "tab,enter,enter", want: "str trim" }
  { line: "git checkout ", keys: "tab,enter,enter", want: "git checkout feature" }
  { line: "ls | where ", keys: "tab,esc,ctrl-c", screen: [name type size modified] }
  { line: "echo done", keys: "enter", want: "echo done" }
]

def --env repo []: nothing -> string {
  let d = scratch
  cd $d
  let c = [-c user.name=test -c user.email=test@example.com]
  ^git init -q -b main
  # A file, so `ls | where ` has columns to offer.
  "hello\n" | save ($d | path join README.md)
  ^git add README.md
  ^git ...$c commit -q -m first
  ^git checkout -q -b feature
  ^git ...$c commit -q --allow-empty -m onfeature
  ^git checkout -q main
  $d
}

# One session over every case; returns { history, screens }.
def session [--prefix]: nothing -> record {
  if $nu.os-info.name == "windows" { skip-test "no pty on Windows" }
  if (which python3 | is-empty) { skip-test "python3 is not installed" }
  if (which -a git | where type == external | is-empty) { skip-test "git is not installed" }
  # Under fuzzy (the default) `bits r` has candidates with nothing in common
  # past `bits ` (rol, ror, shr…), so there is no partial insert to test;
  # prefix matching has one.
  let settings = ["const UPDATE_CHECK_EVERY = 0sec"] ++ (if $prefix { ['$env.config.completions.algorithm = "prefix"'] } else { [] }) | str join "\n"
  let dir = user-dir --settings $settings
  let cwd = repo
  let args = $CASES | each {|c| ["--case" $"($c.line)|($c.keys)"] } | flatten
  # A partial insert paints twice — the common prefix, then the menu the
  # source recomputes for the new line (the 0.116 fix) — and under the load of
  # a full run the gap between the two passed the default 0.2 s of quiet, so
  # the second Tab landed mid-computation and was folded into the first
  # (`bits rol` in 2 full runs of 2, never alone; 0.35 s held in 4 of 4, for
  # 5 s more on the suite, 2026-09-27). The shipped defaults have `partial`
  # on too, and failed the same way in a full run (`bits rol`, 1 of 1), so
  # both sessions wait.
  let quiet = ["--quiet" "0.35"]
  let r = ^python3 $HARNESS --nu $nu.current-exe --config-home $dir.env.XDG_CONFIG_HOME --cwd $cwd ...$quiet ...$args | complete
  assert equal $r.exit_code 0 $r.stderr
  $r.stdout | from json
}

# The recorded lines, one per case that ran one, trailing space trimmed.
def recorded [got: record]: nothing -> list<record> {
  let ran = $CASES | where {|c| $c.keys | str ends-with enter }
  assert equal ($got.history | length) ($ran | length) ($got.history | to nuon)
  $ran | zip $got.history | each {|p| { case: $p.0, line: ($p.1 | str trim --right) } }
}

def "test the menu completes and inserts under the shipped defaults" [] {
  let got = session
  for r in (recorded $got | where {|r| $r.case.want? != null }) {
    assert equal $r.line $r.case.want $r.case.line
  }
  for looks in ($CASES | enumerate | where {|c| $c.item.screen? != null }) {
    let screen = $got.screens | get $looks.index
    for col in $looks.item.screen { assert ($screen | str contains $col) $"($col) not on screen: ($screen)" }
  }
}

def "test partial completion inserts the common prefix and the next Tab the right span" [] {
  let got = session --prefix
  for r in (recorded $got | where {|r| $r.case.want? != null }) {
    assert equal $r.line $r.case.want $r.case.line
  }
}
