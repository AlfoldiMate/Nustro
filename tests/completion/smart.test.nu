# The Tab menu source (modules/nu-complete/smart.nu), called the way the menu
# calls it: `nu-complete smart <buffer> <place>`, with the inputs Nushell
# would hand it (`commandline complete --input`). No terminal needed. The
# pipeline probe runs `nu -n -c` in a subprocess with the test's $env.PWD;
# `commandline complete` itself lists files from the process's working
# directory, which a `cd` in a test does not move, so the `cd` fallback runs
# in a child shell started in the empty directory.
use lib.nu *
use std/assert
use nu-complete *

def smart [line: string]: nothing -> list<record> {
  let i = ($line | commandline complete --input)
  nu-complete smart $i.buffer $i.place
}

def kinds [line: string]: nothing -> list<string> {
  smart $line | get kind? | compact | uniq | sort
}

def "test a condition slot offers the columns of the pipeline" [] {
  let got = smart "ls | where "
  assert ([name type size modified] | all {|c| $c in ($got | get value) }) ($got | get value | to nuon)
  assert ($got | where value == size | get 0.description | str starts-with "filesize") "the type is in the description"
}

def "test a column is followed by the operators for its type" [] {
  assert equal (smart "ls | where size " | get value | sort) ["!=" "<" "<=" "==" ">" ">=" in not-in]
  let s = smart "ls | where name " | get value
  assert ("starts-with" in $s and "=~" in $s and "<" not-in $s) ($s | to nuon)
}

def "test an operator is followed by the distinct values of the column" [] {
  assert equal (smart "ls | where type == " | get value | sort) [dir file]
  assert equal (smart "ls | where type == d" | get value) [dir]
}

def "test after and or or the columns come back" [] {
  assert ("name" in (smart "ls | where type == dir and " | get value))
}

def "test a cell-path slot offers columns, nested paths and closure fields" [] {
  let d = scratch
  { package: { name: alpha, version: "1.0" }, deps: [] } | save ($d | path join data.json)
  cd $d
  assert equal (smart "ls | get na" | get value) [name]
  assert equal (smart "ls | select name " | get value) [type size modified]
  assert equal (smart "ls | each {|r| $r.si" | get value) [size]
  assert equal (smart "open data.json | get package." | get value | sort) [name version]
}

def "test a command with no positional stops offering files" [] {
  assert equal (kinds "ps ") []
  assert ("file" in (kinds "ls "))
}

# What the polars plugin defines: under `fuzzy` Nushell matches `ps ` against
# it (p, s, space, in order) and offers it in place of `ps` itself. A real
# subcommand (`bits r` → `bits ror`) starts with the line and must stay.
def "polars agg" [] { }

def "test a command with no positional does not offer a command it fuzzy-matches" [] {
  let was = $env.config.completions.algorithm
  $env.config.completions.algorithm = "fuzzy"
  let stock = ("ps " | commandline complete)
  let got = (smart "ps ")
  let sub = (smart "bits r" | get value)
  $env.config.completions.algorithm = $was
  assert ("polars agg" in $stock) $"the fixture fuzzy-matches: ($stock | to nuon)"
  assert equal $got [] ($got | to nuon)
  assert ("bits ror" in $sub) ($sub | to nuon)
}

def "test a number slot stops offering files, before a pipe too" [] {
  assert equal (kinds "first ") []
  assert equal (kinds "sleep ") []
  assert equal (kinds "ls | first ") []
}

def "test a slot inside a closure or a subexpression is read the same way" [] {
  assert equal (kinds "echo (first ") []
  assert equal (kinds "ls | each {|r| first ") []
  assert equal (kinds "echo (ps ") []
}

def "test a flag slot and a flag value keep the Nushell answer" [] {
  assert equal (smart "cd --" | get value) [--help --physical]
}

def "test the probe never runs a command that writes" [] {
  let d = scratch
  let line = $"[1] | save ($d)/marker | where "
  let got = smart $line
  assert ("marker" not-in (ls $d | get name | path basename)) "save ran"
  assert ($got | all {|r| $r.kind? != null }) "no invented columns"
}

# What Nushell itself offers after `where ` differs between releases (files
# on 0.115.2, nothing on 0.115.1), so these assert that no column was
# invented — every item is Nushell's own, with a kind — not what was.
def "test an external at the head is never run" [] {
  let got = smart "^ls | where "
  assert ($got | all {|r| $r.kind? != null }) ($got | to nuon)
}

def "test NU_COMPLETE_EVAL off leaves the line alone" [] {
  $env.NU_COMPLETE_EVAL = "off"
  let got = smart "ls | where "
  assert ($got | all {|r| $r.kind? != null }) ($got | to nuon)
}

def "test no candidate is listed twice" [] {
  let got = smart "ls | where "
  assert equal ($got | get value | length) ($got | get value | uniq | length)
  let base = smart "l"
  assert equal ($base | get value | length) ($base | get value | uniq | length)
}

def "test cd in a folder with nothing to enter offers parents and places" [] {
  let d = scratch
  cd $d
  let code = $"const NU_LIB_DIRS = [($ROOT | path join modules | to nuon)]; use nu-complete *; let i = \('cd ' | commandline complete --input\); nu-complete smart $i.buffer $i.place | select value description | to nuon"
  let out = ^$nu.current-exe -n -c $code | complete
  assert equal $out.exit_code 0 $out.stderr
  let got = $out.stdout | from nuon
  assert equal ($got | first 3 | get value) [".." "~" "-"]
  assert equal ($got | first 3 | get description) [parent home "previous directory"]
}

# ── What 2026-10-01 added ─────────────────────────────────────────────────────

def "test the first call of a session offers columns, with nothing warmed" [] {
  # The signature table a background job used to fill: a Tab before it was
  # done found it empty and offered files. A child, so nothing is cached.
  let code = $"const NU_LIB_DIRS = [($ROOT | path join modules | to nuon)]; use nu-complete *; let i = \('ls | where ' | commandline complete --input\); nu-complete smart $i.buffer $i.place | get value | to nuon"
  let out = ^$nu.current-exe -n -c $code | complete
  assert equal $out.exit_code 0 $out.stderr
  assert equal ($out.stdout | from nuon) [name type size modified]
}

def "test a pipeline with where in it is run, not cut back to its head" [] {
  # `where` is a keyword to `scope commands`, and counted as not built-in.
  assert equal (smart "[[a b]; [1 2]] | where a > 0 | select a | get " | get value) [a]
}

# A session of its own with variables in it: `scope variables` is what a
# shell has at its prompt, which a `let` inside a test command is not. One
# line of NUON per line asked.
def in-session [lets: string, lines: list<string>]: nothing -> list {
  let asks = $lines | each {|l| $"print \(do {|| let i = \(($l | to nuon) | commandline complete --input\); nu-complete smart $i.buffer $i.place | get value | to nuon }\)" } | str join "\n"
  let code = $"const NU_LIB_DIRS = [($ROOT | path join modules | to nuon)]\nuse nu-complete *\n($lets)\n($asks)"
  let out = ^$nu.current-exe -n -c $code | complete
  assert equal $out.exit_code 0 $out.stderr
  $out.stdout | lines | each {|l| $l | from nuon }
}

def "test a variable of the session has columns" [] {
  let got = in-session 'let tbl = [[name qty when]; [apple 3 2026-01-01] [pear 5 2026-02-01]]' [
    "$tbl | where "
    "$tbl | where qty > 3 | sort-by "
    "$tbl | where name == "
  ]
  assert equal $got.0 [name qty when]
  assert equal $got.1 [name qty when]
  assert equal ($got.2 | sort) [apple pear]
  assert equal (smart "$nope | where " | where kind? == null) [] "an unknown variable invents nothing"
}

def "test a variable named like a local of the engine stays yours" [] {
  # `scope variables` sees the call stack: read anywhere but at the door,
  # `$rows` was the engine's own empty list.
  let got = in-session "let rows = [[k v]; [a 1]]\nlet path = { deep: { x: 1, y: 2 } }" [
    "$rows | where v > 5 | get "
    "$path | get deep."
  ]
  assert equal $got.0 [k v]
  assert equal ($got.1 | sort) [x y]
}

def "test a comparison is followed by round bounds, equality by the values" [] {
  assert equal (smart "ls | where size > " | get value) ["1kb" "10kb" "100kb" "1mb" "10mb" "100mb" "1gb"]
  assert equal (smart "ls | where size >= 10" | get value) ["10kb" "100kb" "10mb" "100mb"]
  let dates = smart "ls | where modified > "
  assert equal ($dates | first | get value) "((date now) - 1hr)"
  assert equal ($dates | first | get description) "the last hour"
  assert equal (smart "ls | where type == " | get value | sort) [dir file]
}

def "test a slot that takes a column without declaring a cell-path" [] {
  assert equal (smart "ls | uniq-by " | get value) [name type size modified]
  assert equal (smart "ls | move name --after " | get value) [type size modified]
  assert equal (smart "ls | histogram ty" | get value) [type]
  assert equal (smart "ls | join [[name]; [a]] na" | get value) [name]
  # The first positional of join is the other table, not a column.
  assert ("name" not-in (smart "ls | join " | get value))
}

def "test explain names the rule that answered" [] {
  assert equal (nu-complete explain "ls | where " | get layer) columns
  assert equal (nu-complete explain "ls | where size " | get layer) operators
  assert equal (nu-complete explain "ls | where size > " | get layer) values
  assert equal (nu-complete explain "ps " | get layer) no-files
  assert equal (nu-complete explain "ls " | get layer) nushell
  let e = nu-complete explain "ls | where type == dir | get "
  assert equal $e.pipeline "ls | where type == dir"
  assert $e.pipeline_runs
  assert equal (nu-complete explain "^ls | where " | get pipeline_runs) false
}

def "test a lazy module offers its words at once and its slots from one child" [] {
  $env.NU_MODULES_LAZY = [terminal]
  $env.NU_MODULES_LOADED = []
  $env.NU_MODULES_TRIGGERS = { terminal: [theme font] }
  $env.NU_LIB_DIRS = [($ROOT | path join modules)]
  let head = smart "the"
  assert equal ($head | first | select value kind) { value: theme, kind: command }
  assert ($head | first | get description | str contains "terminal")
  # ... and its commands beside it, so `the⌶` already shows what there is.
  assert ("theme use" in ($head | get value)) ($head | get value | to nuon)
  assert ($head | where value =~ '^ghostty' | is-empty) "only the words that were typed towards"
  let subs = smart "theme "
  assert ("theme use" in ($subs | get value)) ($subs | get value | to nuon)
  # The same slot with a letter typed: narrowed here, and placed on the token.
  let narrowed = smart "theme u"
  assert equal ($narrowed | get value) ["theme use"]
  # Once loaded, the module is Nushell's own to complete.
  $env.NU_MODULES_LOADED = [terminal]
  assert (smart "the" | where value == theme | is-empty)
}
