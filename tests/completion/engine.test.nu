# The completion engine (modules/nu-complete/engine.nu) without a terminal:
# the span list a completer is handed, filtering, quoting, and `run` walking
# a spec. The spec here is inline and small; the shipped ones are in
# specs.test.nu.
use lib.nu *
use std/assert
use nu-complete *

# ── the span list: place.command ─────────────────────────────────────────────

# A completer walks `place.command`, which Nushell (0.116) resolves at the
# cursor. These pin the parts of that contract the engine relies on — the
# cases its own rebuild from the buffer was checked against before 0.116.
def command-at [line: string]: nothing -> list<string> {
  ($line | commandline complete --input).place.command
}

alias gco = git checkout

def "test place.command is the command at the cursor" [] {
  assert equal (command-at "git checkout ch") [git checkout ch]
  assert equal (command-at "ls | git ch") [git ch]
  assert equal (command-at "echo a; git ch") [git ch]
  assert equal (command-at "ls | each {|r| git ch") [git ch]
  assert equal (command-at "echo (git ch") [git ch]
}

def "test place.command keeps a quoted argument and a flag=value as one word" [] {
  assert equal (command-at 'git commit -m "a b" fi') [git commit -m '"a b"' fi]
  assert equal (command-at "git log --oneline=x ma") [git log --oneline=x ma]
  assert equal (command-at 'git commit -m "ab') [git commit -m '"ab']
}

def "test place.command ends a fresh slot with an empty word" [] {
  assert equal (command-at "git checkout ") [git checkout ""]
}

def "test place.command expands an alias at the head" [] {
  assert equal (command-at "gco ma") [git checkout ma]
}

def "test spans still serves a completion written from the old template" [] {
  let i = ("git checkout ma" | commandline complete --input)
  assert equal (nu-complete spans $i.token (try { $i.place }) (try { $i.buffer })) [git checkout ma]
}

# ── external ──────────────────────────────────────────────────────────────────

def "test external hands the completer the inputs it names" [] {
  $env.config.completions.external.completer = {|place| [($place.command | str join ",")] }
  assert equal (nu-complete external [git log --one]) ["git,log,--one"]
  $env.config.completions.external.completer = {|buffer: string, token: record| [$buffer $token.text $token.kind] }
  assert equal (nu-complete external [git log --one]) ["git log --one" --one flag]
  $env.config.completions.external.completer = {|spans| $spans }
  assert equal (nu-complete external [git ch]) [git ch]
  $env.config.completions.external.completer = { [none] }
  assert equal (nu-complete external [git ch]) [none]
}

def "test external without a completer is null" [] {
  $env.config.completions.external.completer = null
  assert equal (nu-complete external [git ch]) null
}

# ── normalize · filter ────────────────────────────────────────────────────────

def "test normalize wraps strings and keeps records" [] {
  assert equal ([a { value: b, description: d }] | nu-complete normalize) [{ value: a } { value: b, description: d }]
  assert equal (null | nu-complete normalize) []
  assert equal ([1 2] | nu-complete normalize) [{ value: "1" } { value: "2" }]
}

def items [] { [{ value: alpha } { value: Beta } { value: gamma-beta }] }

def "test filter follows the completion algorithm" [] {
  $env.config.completions.case_sensitive = false
  $env.config.completions.algorithm = "prefix"
  assert equal (items | nu-complete filter "be" | get value) [Beta]
  $env.config.completions.algorithm = "substring"
  assert equal (items | nu-complete filter "be" | get value) [Beta gamma-beta]
  $env.config.completions.algorithm = "fuzzy"
  assert equal (items | nu-complete filter "gba" | get value) [gamma-beta]
  assert equal (items | nu-complete filter "" | length) 3
}

def "test filter ranks by tier: prefix, substring, letters in order, description" [] {
  $env.config.completions.case_sensitive = false
  $env.config.completions.algorithm = "fuzzy"
  let items = [
    { value: zeta, description: "has beta inside" }
    { value: eta, description: "b, e, t, a — in order only" }
    { value: "b-e-t-a-long" }
    { value: gamma-beta }
    { value: bxexta }
    { value: Beta }
    { value: alpha, description: "the first" }
  ]
  # Tiers, and within the letters-in-order tier the shortest first.
  assert equal ($items | nu-complete filter "beta" | get value) [Beta gamma-beta bxexta "b-e-t-a-long" zeta eta]
  # A description matches under substring too, never under prefix.
  $env.config.completions.algorithm = "substring"
  assert equal ($items | nu-complete filter "beta" | get value) [Beta gamma-beta zeta]
  $env.config.completions.algorithm = "prefix"
  assert equal ($items | nu-complete filter "beta" | get value) [Beta]
  assert equal ([] | nu-complete filter "x") []
}

def "test filter keeps the source order within a tier" [] {
  $env.config.completions.algorithm = "fuzzy"
  let by_recency = [{ value: feature/b } { value: main } { value: feature/a }]
  assert equal ($by_recency | nu-complete filter "fe" | get value) [feature/b feature/a]
  assert equal ($by_recency | nu-complete filter "ur" | get value) [feature/b feature/a]
}

def "test filter honours case sensitivity" [] {
  $env.config.completions.algorithm = "prefix"
  $env.config.completions.case_sensitive = true
  assert equal (items | nu-complete filter "be" | get value) []
  assert equal (items | nu-complete filter "Be" | get value) [Beta]
  $env.config.completions.case_sensitive = false
  assert equal (items | nu-complete filter "be" | get value) [Beta]
}

# ── quote ─────────────────────────────────────────────────────────────────────

def "test quote makes a value with a space one argument" [] {
  assert equal ([{ value: "Catppuccin Macchiato" }] | nu-complete quote | get 0.value) '"Catppuccin Macchiato"'
  assert equal ([{ value: "a|b" } { value: 'x$y' }] | nu-complete quote | get value) ['"a|b"' '"x$y"']
}

def "test quote leaves plain, already quoted and trailing-space values alone" [] {
  assert equal ([{ value: plain } { value: "a-b_c.d/e" }] | nu-complete quote | get value) [plain "a-b_c.d/e"]
  assert equal ([{ value: '"a b"' } { value: "`a b`" } { value: "'a b'" }] | nu-complete quote | get value) ['"a b"' "`a b`" "'a b'"]
  # carapace's trailing space means "and a space after it": kept, outside the quotes.
  assert equal ([{ value: "a b " }] | nu-complete quote | get 0.value) '"a b" '
}

def "test quote never touches a command, flag or path" [] {
  let items = [
    { value: "str trim", kind: command }
    { value: "--flag x", kind: flag }
    { value: "a b", kind: file }
    { value: "a b", kind: directory }
    { value: "a b", kind: value }
  ]
  assert equal ($items | nu-complete quote | get value) ["str trim" "--flag x" "a b" "a b" '"a b"']
}

# ── run ───────────────────────────────────────────────────────────────────────

def spec [] {
  {
    description: "a tool"
    fallback: "external"
    flags: [
      { name: "--verbose", short: "-v", description: "more" }
      { name: "--config", short: "-c", description: "a file", arg: "files" }
      { name: "--level", description: "how much", arg: [low high] }
    ]
    positionals: [ [alpha beta] ]
    subcommands: {
      build: {
        description: "build it"
        flags: [
          { name: "--target", description: "for", arg: {|ctx| [$"($ctx.partial)m64" x86] } }
          { name: "--verbose", description: "the build's own" }
        ]
        positionals: [named]
        rest: "files"
      }
      run: { description: "run it", positionals: [[one two]] }
      r: { description: "run it", positionals: [[one two]], hidden: true }
    }
    sources: { named: {|ctx| [{ value: n1, description: first } n2] } }
  }
}

def --wrapped walk [...spans: string] { nu-complete run (spec) $spans }

def "test run offers subcommands and the first positional together" [] {
  let got = walk tool ""
  assert equal ($got | get value) [build run alpha beta]
  assert equal ($got | where value == build | get 0.description) "build it"
  assert equal (walk tool b | get value) [build beta]
}

def "test run resolves a hidden subcommand but never offers it" [] {
  assert equal (walk tool r | get value) [run]
  assert equal (walk tool r "" | get value) [one two]
}

def "test run offers flags with their shorts, and no shorts after --" [] {
  assert equal (walk tool "-" | get value) [--verbose --config --level -v -c]
  assert equal (walk tool "--" | get value) [--verbose --config --level]
  assert equal (walk tool "--v" | get 0.description) more
}

def "test run offers a flag value after it and in flag=value form" [] {
  assert equal (walk tool --level "" | get value) [low high]
  assert equal (walk tool --level h | get value) [high]
  assert equal (walk tool --level=h | get value) [--level=high]
  # The value consumed, the positional is next.
  assert equal (walk tool --level low "" | get value) [build run alpha beta]
}

def "test run hands a files slot to Nushell" [] {
  assert equal (walk tool --config "") null
  assert equal (walk tool build n1 "") null
}

def "test run walks into a subcommand and runs a named source" [] {
  let got = walk tool build ""
  assert equal ($got | get value) [n1 n2]
  assert equal ($got | get 0.description) first
  assert equal (walk tool run "" | get value) [one two]
}

def "test run gives a subcommand its own flags plus the roots, its own winning" [] {
  let got = walk tool build "--"
  assert equal ($got | get value) [--target --verbose --config --level]
  assert equal ($got | where value == --verbose | get 0.description) "the build's own"
}

def "test run gives a flag closure the partial" [] {
  assert equal (walk tool build --target ar | get value) [arm64]
}

def "test run asks the external completer when the spec has no opinion" [] {
  $env.config.completions.external.completer = {|spans| [{ value: $"ext:($spans | str join ' ')" }] }
  assert equal (walk tool run one "" | get 0.value) "ext:tool run one "
  # A flag the spec does not know: outside too.
  assert equal (walk tool --unknown | get 0.value) "ext:tool --unknown"
  # Not a flag it does know.
  assert equal (walk tool --verb | get value) [--verbose]
}

def "test run answers null without an external completer" [] {
  $env.config.completions.external.completer = null
  assert equal (walk tool run one "") null
  assert equal (walk tool --unknown) null
}

def "test run filters the way the settings say and quotes what it hands out" [] {
  $env.config.completions.algorithm = "fuzzy"
  assert equal (walk tool bta | get value) [beta]
  $env.config.completions.algorithm = "prefix"
  let s = { positionals: [[{ value: "a b" } plain]] }
  assert equal (nu-complete run $s [tool ""] | get value) ['"a b"' plain]
}

def "test run matches past a quote the user opened" [] {
  $env.config.completions.algorithm = "fuzzy"
  let s = { positionals: [[{ value: "a b" } { value: ab } other]] }
  assert equal (nu-complete run $s [tool '"a b'] | get value) ['"a b"']
  assert equal (nu-complete run $s [tool "'a b'"] | get value) ['"a b"']
}

def "test run treats a lone command as a fresh slot" [] {
  assert equal (nu-complete run (spec) [tool] | get value) [build run alpha beta]
}

def "test run has the built-in sources by name, the spec own first" [] {
  let d = scratch
  mkdir ($d | path join alpha) ($d | path join beta)
  "" | save ($d | path join afile.txt)
  let spec = { subcommands: { go: { positionals: [directories] }, own: { positionals: [directories] } } }
  let got = nu-complete run $spec [tool go ($d + "/")]
  assert equal ($got | get value | each {|v| $v | path basename } | sort) [alpha beta] ($got | to nuon)
  assert ($got | all {|r| $r.span? == null }) "spans into the token are dropped"
  assert equal (nu-complete run ($spec | insert sources { directories: [mine] }) [tool own ""] | get value) [mine]
}
