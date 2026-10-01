# smart — the Tab menu source
#
# Nushell's own completer sees each command in isolation: `ls | get ⌶` is
# completed without knowing what `ls` returns. A completer can be handed the
# whole line since 0.116 (`buffer`), but only one we attach — the built-ins'
# slots are Nushell's. A menu `source` is the one place that sees both the line
# and Nushell's answer for it, so Tab is bound to a menu whose source is
# `nu-complete smart`, which starts from what Nushell would offer —
# `commandline complete --detailed`, 0.1-0.6 ms, including every extern and
# carapace — and then:
#
#   1. Columns.   `ls | where ⌶`, `get`, `select`, `sort-by`, `update` and every
#                 other cell-path or condition slot offers the columns of the
#                 pipeline so far, typed and with a sample value. Nested paths
#                 (`get package.⌶`) and closure params (`each {|r| $r.⌶}`) too.
#   2. Operators. `where size ⌶` narrows Nushell's operator list to the ones
#                 that make sense for the column's type.
#   3. Values.    `where type == ⌶` offers the distinct values of that column
#                 as Nushell literals.
#   4. No noise.  A command that takes no positional (`ps ⌶`, 216 built-ins)
#                 stops offering the files in the directory.
#   5. No twins.  A shadowed built-in is listed once, not twice.
#   6. Somewhere. `cd ⌶` in a folder with nothing to enter offers `..`, `~`,
#                 `-` and zoxide's most-used directories instead of
#                 NO RECORDS FOUND; `cd nus⌶` matches ~/.config/nushell.
#
#   7. Your data. `$rows | where ⌶` reads the columns of a variable of this
#                 session, without it leaving the shell as anything but NUON.
#
# 1-3 need the pipeline's output. It is produced by running the pipeline up
# to the current command in a subprocess (`nu -n -c`, ~20 ms, memoised for
# 45 s per directory) — only when every command in it is a read-only
# built-in; see `safe-to-eval`. $env.NU_COMPLETE_EVAL turns it off ("off") or
# extends it to your own commands ("all", loads the config, ~80 ms).
#
# The source runs again on every keystroke while the menu is open, and a menu
# source runs on the line editor's own thread: what it costs is how long a
# key takes to appear (a completer attached with `@complete` runs on a
# background worker since 0.115; a menu source does not — measured 2026-10-01
# with a 700 ms source, the next key echoed after 1.4 s). So everything here
# is cached, and the only external it runs itself, zoxide for a `cd` with
# nothing local to enter, is memoised too.
#
# What is NOT here any more (2026-10-01): a table of every command's
# signature in `stor`. It was how the slot under the cursor was read before
# Nushell said so itself; `place.shape` is that answer now, `which` says what
# kind of command a word is, and the one thing left — a built-in's category,
# for the safety check — is one `scope commands` (4 ms) inside the memoised
# probe. The table cost 305 ms to build in a background job at startup, and a
# Tab pressed before it finished found it empty and offered files for
# `ls | where ⌶`.

use engine.nu *
use cache.nu *

# ── Tokenising the line ───────────────────────────────────────────────────────

# The pipe-separated segments of the last top-level statement in `buf`,
# ignoring pipes inside quotes, parens, brackets and braces.
def segments [buf: string]: nothing -> list<string> {
  mut depth = 0
  mut quote = ""
  mut esc = false
  mut segs = []
  mut cur = ""
  for c in ($buf | split chars) {
    if $quote != "" {
      $cur += $c
      if $esc { $esc = false } else if $c == "\\" and $quote == '"' { $esc = true } else if $c == $quote { $quote = "" }
    } else if $c in ['"' "'" '`'] {
      $quote = $c
      $cur += $c
    } else if $c in ["(" "[" "{"] {
      $depth += 1
      $cur += $c
    } else if $c in [")" "]" "}"] {
      $depth = ([($depth - 1) 0] | math max)
      $cur += $c
    } else if $depth == 0 and $c == "|" {
      $segs ++= [$cur]
      $cur = ""
    } else if $depth == 0 and ($c == ";" or $c == "\n") {
      $segs = []
      $cur = ""
    } else {
      $cur += $c
    }
  }
  $segs ++ [$cur]
}

# Whitespace-separated words of one segment (quotes and brackets kept
# together), and whether the segment ends in whitespace — a fresh slot.
def words [seg: string]: nothing -> record<tokens: list<string>, fresh: bool> {
  mut depth = 0
  mut quote = ""
  mut esc = false
  mut toks = []
  mut cur = ""
  mut fresh = false
  for c in ($seg | split chars) {
    if $quote != "" {
      $cur += $c
      $fresh = false
      if $esc { $esc = false } else if $c == "\\" and $quote == '"' { $esc = true } else if $c == $quote { $quote = "" }
    } else if $c in ['"' "'" '`'] {
      $quote = $c
      $cur += $c
      $fresh = false
    } else if $c in ["(" "[" "{"] {
      $depth += 1
      $cur += $c
      $fresh = false
    } else if $c in [")" "]" "}"] {
      $depth = ([($depth - 1) 0] | math max)
      $cur += $c
      $fresh = false
    } else if $depth == 0 and ($c == " " or $c == "\t") {
      if $cur != "" { $toks ++= [$cur]; $cur = "" }
      $fresh = true
    } else {
      $cur += $c
      $fresh = false
    }
  }
  if $cur != "" { $toks ++= [$cur] }
  { tokens: $toks, fresh: $fresh }
}

# ── Running the pipeline so far ───────────────────────────────────────────────

# Read-only built-ins outside the always-safe categories.
const SAFE_EXTRA = [ps "sys cpu" "sys disks" "sys host" "sys mem" "sys net" "sys temp" "sys users" which whoami uname ls open glob du cd pwd version history "date now" "date list-timezone" do each "par-each" if match try describe table "help commands" "help modules" "help aliases" "scope commands" "scope aliases" "scope modules" "scope variables" "scope externs" "scope engine-stats" random "random int" "random float" "random bool" "random chars" "random uuid" "random dice"]
const SAFE_CATEGORIES = [filters strings conversions math date path formats hash bits bytes generators default core env debug history viewers]
const NEVER = ["odata" "into sqlite" "stor export" "stor import" "stor reset" "stor create" "stor insert" "stor delete" "stor update" save explore "config reset" "config nu" "config env" "history import" "history session" "load-env" "hide-env" "commandline edit" "commandline set-cursor" "commandline set-prompt" "keybindings listen" "term query" "input" "input listen" "input list" "input listen" clear sleep "view source" "view files" "view blocks" "view ir" "view span" "nu-check" "nu-highlight" "ansi link" "start" "run-external" exec kill "job spawn" "job kill" "job send" "job recv" "job flush" "job tag" "job unfreeze" "overlay use" "overlay new" "overlay hide" "overlay list" "plugin add" "plugin rm" "plugin stop" "plugin use" "plugin list" "attr" "def" "export" "extern" "module" "source" "source-env" "use" "hide" "alias" "const" "register" "let" "mut" "for" "while" "loop"]
const OK_KEYWORDS = [if else match try catch and or not xor in "not-in"]

# Can `prefix` run without side effects? Every call in it (closures
# included — `ast --flatten` lists them all) must be a read-only built-in, and
# nothing may be external. With NU_COMPLETE_EVAL = "all", your own commands
# pass too and the pipeline runs with the config loaded.
def safe-to-eval [prefix: string]: nothing -> record<ok: bool, custom: bool> {
  let mode = ($env.NU_COMPLETE_EVAL? | default "safe")
  if $mode == "off" { return { ok: false, custom: false } }
  let toks = (try { ast --flatten $prefix } catch { return { ok: false, custom: false } })
  # Name, type and category of every command: one call, 4 ms, and only here —
  # the probe that asks is memoised, so a line pays it once.
  let known = (scope commands | select name type category)
  mut custom = false
  for t in $toks {
    let bad = (match $t.shape {
      "shape_internalcall" => {
        if $t.content in $NEVER { true } else {
          let c = ($known | where name == $t.content | get -o 0)
          if $c == null { true } else if $c.type not-in ["built-in" "keyword"] { $custom = true; $mode != "all" } else {
            not (($c.category in $SAFE_CATEGORIES) or ($t.content in $SAFE_EXTRA))
          }
        }
      }
      "shape_keyword" => ($t.content not-in $OK_KEYWORDS)
      "shape_external" | "shape_externalarg" | "shape_garbage" | "shape_redirection" | "shape_raw_string" => true
      # A row's column in a condition (`where size > 1kb`) is a variable to
      # the parser, without the `$`.
      "shape_variable" => ($t.content not-in ["$env" "$nu" "$in" "$it"] and not ($t.content =~ '^\$?[A-Za-z_][\w-]*$'))
      _ => false
    })
    if $bad { return { ok: false, custom: $custom } }
  }
  { ok: true, custom: $custom }
}

# `ll | where` — an alias at the head of a segment is replaced by what it
# stands for, so the safety check and the subprocess see real commands.
def expand-aliases [prefix: string]: nothing -> string {
  let aliases = (scope aliases)
  if ($aliases | is-empty) { return $prefix }
  segments $prefix | each {|seg|
    let head = ($seg | str trim | split row " " | first)
    let hit = ($aliases | where name == $head)
    if ($hit | is-empty) { $seg } else { $seg | str replace $head $hit.0.expansion }
  } | str join "|"
}

# The variables of this session, read at the door (`nu-complete smart`)
# before this file declares a single local: `scope variables` sees the call
# stack, so inside these commands a `$rows` or a `$path` of the user's is
# hidden behind the local of that name — found 2026-10-01, when `$rows |
# where qty > 30 | get ⌶` offered nothing and `$tbl | …` did. `$buffer` and
# `$place` cannot be told from the source's own inputs and are left out.
# Only when the line names a variable at all; 56 µs then.
def session-vars [buffer: string]: nothing -> table {
  if not ($buffer | str contains "$") { return [] }
  scope variables | where name not-in ["$buffer" "$place" "$env" "$nu" "$in" "$it"] | select name value
}

# The ones a pipeline names, for the subprocess: `$rows | where ⌶` has
# columns only if the child knows `$rows`. They go over on stdin as one NUON
# record (not in the `-c` text: a Windows command line ends at 32 kB) — the
# first 200 rows of a list, nothing above 256 kB, nothing NUON cannot write
# (a closure, a custom value). A name that is not a variable here (a
# closure's parameter) is left for the pipeline to define itself. Returns
# the names and the NUON.
const MAX_VAR_NUON = 262144
def captured-vars [prefix: string, vars: table]: nothing -> record<names: list<string>, nuon: string> {
  let none = { names: [], nuon: "" }
  if ($vars | is-empty) or not ($prefix | str contains "$") { return $none }
  let names = (try { ast --flatten $prefix } catch { [] }
    | where shape == "shape_variable" and content =~ '^\$[A-Za-z_][\w-]*$'
    | get content | uniq)
  if ($names | is-empty) { return $none }
  let vals = ($vars | where name in $names | each {|v|
    let text = (try {
      (if ($v.value | describe) =~ '^(list|table)' { $v.value | first 200 } else { $v.value }) | to nuon
    } catch { null })
    if $text == null or ($text | str length) > $MAX_VAR_NUON { null } else { { name: ($v.name | str substring 1..), text: $text } }
  } | compact)
  if ($vals | is-empty) { return $none }
  { names: ($vals | get name), nuon: ("{" + ($vals | each {|v| $"($v.name | to nuon): ($v.text)" } | str join ", ") + "}") }
}

# Rows of the pipeline's output as `describe --detailed` records:
# [{ columns: { name: { type, value } } }]. At most 60 rows, memoised — the
# refusal too, so a line that may not run is checked once, not per keystroke.
def probe [prefix: string, vars: table]: nothing -> list<record> {
  let prefix = (expand-aliases $prefix)
  # A provider (modules/odata (activate): $env.NU_COMPLETE_PROVIDERS) answers for a
  # command whose columns are known without running it. It sees the first
  # segment; the stages after it do not change the columns except `get`,
  # which is left to the probe (and refused for a non-built-in).
  let segs = (segments $prefix)
  let head = ($segs | first | str trim | split row " " | first)
  let provider = ($env.NU_COMPLETE_PROVIDERS? | default {} | get -o $head)
  if $provider != null and not ($segs | skip 1 | any {|s| ($s | str trim) starts-with "get " }) {
    return (nu-complete cache $"provider:($prefix)" 30sec { try { do $provider ($segs | first | str trim) } catch { [] } })
  }
  if ($env.NU_COMPLETE_EVAL? | default "safe") == "off" { return [] }
  let sent = (captured-vars $prefix $vars)
  let key = $"probe:($env.PWD):($sent.nuon | hash md5):($prefix)"
  nu-complete cache $key 45sec {
    let safe = (safe-to-eval $prefix)
    if not $safe.ok { [] } else {
      let lets = (if ($sent.names | is-empty) { "" } else {
        "let __vars = ($in | from nuon); " + ($sent.names | each {|n| $"let ($n) = $__vars.($n | to nuon); " } | str join)
      })
      let code = $"($lets)($prefix) | do { let v = $in; let t = \($v | describe -d\); if $t.type == record { [$v] } else if $t.type in [list stream table] { $v | first 60 } else { [] } } | describe -d | to json -r"
      let out = if $safe.custom { $sent.nuon | ^$nu.current-exe --stdin -l -c $code | complete } else { $sent.nuon | ^$nu.current-exe --stdin -n -c $code | complete }
      if $out.exit_code != 0 { [] } else {
        let d = (try { $out.stdout | from json } catch { {} })
        let rows = ($d.value? | default [])
        $rows | where {|r| ($r.columns? | default null) != null } | each {|r| { columns: $r.columns } }
      }
    }
  }
}

# Rows at `path` inside the pipeline's output. When the pipeline yields no
# rows (a `where` that matches nothing right now), fall back to the pipeline
# without its last stage, whose columns are the same.
def rows-at [prefix: string, path: string, vars: table]: nothing -> list<record> {
  let rows = (if ($path | is-empty) { probe $prefix $vars } else { probe $"($prefix) | get ($path)" $vars })
  if ($rows | is-not-empty) { return $rows }
  let segs = (segments $prefix)
  if ($segs | length) < 2 { return [] }
  rows-at ($segs | drop 1 | str join "|" | str trim) $path $vars
}

# ── Turning rows into candidates ──────────────────────────────────────────────

def sample-text [c: record]: nothing -> string {
  let v = ($c.value? | default null)
  if $v == null { return "" }
  let s = (match $c.type {
    "filesize" => ($v | into filesize | into string)
    "datetime" | "date" => ($v | into string | str substring 0..18)
    "duration" => (try { $v | into duration | into string } catch { $v | into string })
    "record" | "list" | "table" => ($v | to nuon)
    _ => (try { $v | into string } catch { $v | to nuon })
  })
  $s | str replace -a (char nl) " " | str substring 0..48
}

def column-items [rows: list<record>, exclude: list<string>]: nothing -> list<record> {
  if ($rows | is-empty) { return [] }
  let first = ($rows | first | get columns)
  $first | transpose name c | where name not-in $exclude | each {|r|
    # A provider may say what a column is in words (`string · Edm.String · key`).
    let desc = if ($r.c | get -o description) != null { $r.c.description } else if $r.c.type in [record list table] { $r.c.detailed_type | str substring 0..60 } else {
      let sample = (sample-text $r.c)
      if ($sample | is-empty) { $r.c.type } else { $"($r.c.type) · ($sample)" }
    }
    { value: $r.name, description: $desc }
  }
}

# A column value as something you can paste into a condition.
def literal [c: record]: nothing -> any {
  let v = ($c.value? | default null)
  if $v == null { return null }
  match $c.type {
    "string" => (if ($v =~ '^[\w./@:+-]+$') and ($v !~ '^[\d.-]') { $v } else { $v | to json -r })
    "int" | "float" | "bool" => ($v | into string)
    "filesize" => ($v | into filesize | into string | str replace " " "")
    _ => null
  }
}

def value-items [rows: list<record>, col: string]: nothing -> list<record> {
  $rows | each {|r| $r.columns | get -o $col } | compact | each {|c| literal $c } | compact | uniq | each {|v| { value: $v } }
}

# After a comparison the distinct values of the column are the wrong offer —
# sixty file sizes, sixty timestamps — and a round bound is the right one.
const BOUNDS = {
  filesize: ["1kb" "10kb" "100kb" "1mb" "10mb" "100mb" "1gb"]
  duration: ["1ms" "100ms" "1sec" "10sec" "1min" "1hr" "1day"]
  datetime: ["((date now) - 1hr)" "((date now) - 1day)" "((date now) - 1wk)" "((date now) - 4wk)" "((date now) - 52wk)"]
}
const BOUND_ABOUT = { datetime: ["the last hour" "the last day" "the last week" "the last four weeks" "the last year"] }
const COMPARISONS = ["<" "<=" ">" ">="]

def bound-items [type: string]: nothing -> list<record> {
  let t = (if $type == "date" { "datetime" } else { $type })
  let about = ($BOUND_ABOUT | get -o $t | default [])
  $BOUNDS | get -o $t | default [] | enumerate | each {|b|
    { value: $b.item, description: ($about | get -o $b.index | default $t) }
  }
}

const OPS = {
  string: ["==" "!=" "=~" "!~" like not-like starts-with ends-with not-starts-with not-ends-with in not-in]
  number: ["==" "!=" "<" "<=" ">" ">=" in not-in]
  bool: ["==" "!=" and or xor]
  list: [has not-has in not-in "==" "!="]
}

def ops-for [type: string]: nothing -> list<string> {
  match $type {
    "string" => $OPS.string
    "int" | "float" | "number" | "filesize" | "duration" | "datetime" | "date" => $OPS.number
    "bool" => $OPS.bool
    _ => (if ($type =~ '^(list|table)') { $OPS.list } else { [] })
  }
}

def dedupe []: list<record> -> list<record> { uniq-by value }

def replace-span [position: int, len: int]: nothing -> record { { start: ($position - $len), end: $position } }

# ── Directories to go to when the current one has none ────────────────────────

# `..`, `~`, `-` and zoxide's ranking (`zoxide query -l`, 12 ms, memoised 30 s
# per directory), matched on the whole path or on the last component so that
# `cd nus` finds ~/.config/nushell. Paths with spaces are backtick-quoted the
# way Nushell's own file completer does it.
def dir-fallback [partial: string, position: int]: nothing -> list<record> {
  let fixed = [
    { value: "..", description: "parent" }
    { value: "~", description: "home" }
    { value: "-", description: "previous directory" }
  ]
  let frecent = if (which zoxide | is-empty) { [] } else {
    nu-complete cache $"zoxide:($env.PWD)" 30sec {
      ^zoxide query -l --exclude $env.PWD | lines | first 20
    } | each {|d| { value: ($d | str replace $env.HOME "~"), description: "zoxide" } }
  }
  let by_path = ($fixed ++ $frecent | nu-complete filter $partial)
  let by_name = ($frecent | where {|r| [{ value: ($r.value | path basename) }] | nu-complete filter $partial | is-not-empty })
  $by_path ++ $by_name | uniq-by value | each {|r|
    let v = if ($r.value =~ '\s') { $"`($r.value)`" } else { $r.value }
    { value: $v, description: $r.description, span: (replace-span $position ($partial | str length)), kind: directory }
  }
}

# ── Lazy modules ──────────────────────────────────────────────────────────────
#
# `font use ⌶` in a shell that has not said `font` yet: conf/modules.nu loads
# a lazy module from a pre_execution hook, which fires on Enter, so at Tab
# time Nushell knows neither the command nor its completers and `fon⌶` does
# not even offer `font`.
#
# The word itself needs nothing but the list of trigger words. What follows
# it comes from a child `nu -n` that sources the module's own load.nu and
# runs the same `commandline complete` — once per slot, not per keystroke:
# the child is asked for the slot with nothing typed in it, the answer is
# memoised for a minute, and what is typed narrows it here. It was asked on
# every keystroke until 2026-10-01: 134 ms for the first `theme ⌶` in a pty,
# 30 ms each after. Only until the first Enter loads the module for good.

# The pending lazy module a segment addresses, if any: its first word is one
# of the module's trigger words (`head: false`), or the segment is a single
# unfinished word some trigger word starts with (`head: true` — the words
# are candidates, alongside whatever Nushell already offers).
def lazy-module [w: record<tokens: list<string>, fresh: bool>]: nothing -> any {
  let loaded = ($env.NU_MODULES_LOADED? | default [])
  let triggers = ($env.NU_MODULES_TRIGGERS? | default {})
  let pending = ($env.NU_MODULES_LAZY? | default [] | where {|m| $m not-in $loaded })
  if ($pending | is-empty) or ($w.tokens | is-empty) { return null }
  let first = ($w.tokens | first)
  let head = (($w.tokens | length) == 1 and not $w.fresh)
  for m in $pending {
    let words = ([$m] ++ ($triggers | get -o $m | default []))
    if $first in $words { return { module: $m, head: false, words: $words } }
    if $head and ($words | any {|t| $t != $first and ($t | str starts-with $first) }) { return { module: $m, head: true, words: $words } }
  }
  null
}

# What Nushell would offer for `line` with module `m` loaded. The child gets
# the parent's NU_LIB_DIRS as a const, because a list-valued environment
# variable does not reach a child process, and the line on stdin, so nothing
# in it needs quoting.
def lazy-child [m: string, line: string]: nothing -> list<record> {
  let dirs = ($env.NU_LIB_DIRS? | default [])
  let loader = ($dirs | each {|d| $d | path join $m load.nu } | where {|p| $p | path exists } | get -o 0)
  if $loader == null { return [] }
  let script = $"const NU_LIB_DIRS = ($dirs | to nuon); source ($loader | to nuon); $in | commandline complete --detailed | to nuon"
  let out = ($line | ^$nu.current-exe --stdin -n -c $script | complete)
  if $out.exit_code != 0 { return [] }
  try { $out.stdout | from nuon } catch { [] }
}

# The slot under the cursor, answered by the module: the child completes the
# line up to the token (memoised per slot and directory), the token narrows
# it here. A path being typed is the exception — its candidates depend on
# the directory typed so far — and asks the child for the line as it is.
def lazy-complete [m: string, buffer: string, place: record]: nothing -> list<record> {
  let partial = ($buffer | str substring $place.target.start..<$place.cursor)
  if ($partial =~ '[/\\~]') { return (lazy-child $m $buffer) }
  let stem = ($buffer | str substring 0..<$place.target.start)
  let all = (nu-complete cache $"lazy:($m):($env.PWD):($stem)" 1min { lazy-child $m $stem })
  # A candidate replaces from where the child said — a subcommand is the
  # whole `theme use`, from the start of `theme` — up to the cursor, and is
  # matched against the text it would replace.
  $all | each {|r| $r | upsert span { start: ([($r.span?.start? | default $place.target.start) $place.target.start] | math min), end: $place.cursor } }
  | group-by {|r| $r.span.start | into string } | values
  | each {|g| $g | nu-complete filter ($buffer | str substring ($g.0.span.start)..<$place.cursor) } | flatten
}

# ── Slots that take a column and do not say so ────────────────────────────────
#
# `place.shape` is `cell-path` for get, select, sort-by, update … and those
# need no list. These declare `string` or `any` and mean a column all the
# same: the command, and the positional indices that are one ([from to]).
const COLUMN_POSITIONALS = {
  "uniq-by": [0 99]
  histogram: [0 0]
  compact: [0 99]
  flatten: [0 99]
  move: [0 99]
  "split-by": [0 0]
  join: [1 2]
}
# ... and the flags whose value is a column.
const COLUMN_FLAGS = {
  move: [after before]
}

# How many words of `toks` name a command whose first positional is a
# condition (`where` 1, `take while` 2), or null. `which` knows a command
# from a column in 10 µs; the shape is one `scope commands` (4.6 ms) per
# command name and session, memoised.
def condition-head [toks: list<string>]: nothing -> any {
  for n in [2 1] {
    if ($toks | length) < $n { continue }
    let name = ($toks | first $n | str join " ")
    if (which $name | where type != "external" | is-empty) { continue }
    let cond = (nu-complete cache $"condition:($name)" 1day {
      scope commands | where name == $name | get -o 0.signatures | default {} | values | get -o 0 | default []
      | where parameter_type == "positional" | get -o 0.syntax_shape | default "" | $in =~ 'condition'
    })
    return (if $cond { $n } else { null })
  }
  null
}

# ── The menu source ───────────────────────────────────────────────────────────

# Candidates for `buffer` at `place`, the record Nushell hands every completer
# since 0.116 (`commandline complete --input` shows it for any line).
#
# `place` answers what this file used to work out from the words: the slot's
# shape (`first ⌶` wants `oneof<int, filesize>`, `where ⌶` a condition, `ps ⌶`
# has none because `ps` takes no positional), whether it is a flag's value,
# and where the token under the cursor starts — resolved by Nushell itself, so
# it is right inside a closure or a subexpression (`echo (first ⌶`) too. What
# it does not give is the pipeline before the command, which is what columns
# are read from, nor the parts of a `where` condition, which it hands over as
# one word; those still come from `segments` and `words` (`std/util
# structure` was tried for both on 2026-10-01: it drops `;`, so `ls; ps |
# where ⌶` would read `ls` as the head of the pipeline). `buffer` is cut at
# the cursor: a menu source is given the whole recorded line. Offsets are
# bytes (`str length` and `str substring` are byte-indexed, like `place`).
export def "nu-complete smart" [buffer: string, place: record]: nothing -> list<record> {
  answer $buffer $place (session-vars $buffer) | get items
}

# Which rule answered a line, what it offered and what each stage cost —
# the same code path as Tab, for a slot that offers the wrong thing or is
# slow. `layer` is one of: nushell (its own answer, deduplicated), lazy (a
# module not loaded yet), field (a closure parameter's field), directories
# (the `cd` fallback), columns, operators, values, no-files.
export def "nu-complete explain" [
  line: string   # the line up to the cursor, as typed
]: nothing -> record {
  let vars = (session-vars $line)
  let i = ($line | commandline complete --input)
  let base_time = (timeit { $line | commandline complete --detailed | ignore })
  let segs = (segments $line)
  let prefix = ($segs | drop 1 | str join "|" | str trim)
  let first = (timeit { answer $i.buffer $i.place $vars | ignore })
  let again = (timeit { answer $i.buffer $i.place $vars | ignore })
  let a = (answer $i.buffer $i.place $vars)
  {
    line: $line
    place: $i.place
    layer: $a.layer
    candidates: ($a.items | length)
    first: ($a.items | first 5 | get value)
    pipeline: $prefix
    pipeline_runs: (if ($prefix | is-empty) { null } else { (safe-to-eval (expand-aliases $prefix)).ok })
    cost: { nushell: $base_time, first_call: $first, next_call: $again }
  }
}

def answer [buffer: string, place: record, vars: table]: nothing -> record<layer: string, items: list<record>> {
  let position = $place.cursor
  let buffer = ($buffer | str substring 0..<$position)
  let segs = (segments $buffer)
  let seg = ($segs | last)
  let prefix = ($segs | drop 1 | str join "|" | str trim)
  let w = (words $seg)
  # A custom completer's values (`theme use Cat⌶` → `Catppuccin Macchiato`)
  # arrive unquoted and would be inserted as two arguments; files and
  # carapace's values arrive quoted already.
  let base = (try { $buffer | commandline complete --detailed } catch { [] } | nu-complete quote)
  let lazy = (lazy-module $w)
  if $lazy != null {
    if $lazy.head {
      # The words themselves from the list, at once; the module's commands
      # (`font dir`, `font use` …) from the child, asked once per first
      # letter and narrowed here.
      let typed = ($w.tokens | first)
      let span = { start: $place.target.start, end: $position }
      let words = ($lazy.words | where {|t| $t | str starts-with $typed } | each {|t|
        { value: $t, description: $"($lazy.module) — loads on first use", span: $span, kind: command }
      })
      let letter = ($typed | str substring 0..<1)
      let theirs = (nu-complete cache $"lazy:($lazy.module):head:($letter)" 1min { lazy-child $lazy.module $letter }
        | where {|r| $lazy.words | any {|t| ($r.value | into string) == $t or ($r.value | into string | str starts-with $"($t) ") } }
        | nu-complete filter $typed | each {|r| $r | upsert span $span })
      return { layer: "lazy", items: ($words ++ $theirs ++ $base | nu-complete quote | dedupe) }
    }
    return { layer: "lazy", items: (lazy-complete $lazy.module $buffer $place | nu-complete quote | dedupe) }
  }
  if ($w.tokens | is-empty) { return { layer: "nushell", items: ($base | dedupe) } }
  let partial = ($buffer | str substring $place.target.start..<$position)
  let shape = ($place.shape? | default "")
  let no_files = ($base | where kind not-in [file directory])
  let nushell = { layer: "nushell", items: ($base | dedupe) }

  # A closure parameter's field: `each {|r| $r.na⌶}` → columns.
  let field = ($partial | parse --regex '^\$(?<var>\w+)\.(?<path>[\w.]*)$' | get -o 0)
  if $place.kind == "cell-path" and $field != null and $field.var != "it" and ($prefix | is-not-empty) and ($field.var in ($seg | parse --regex '\{\s*\|\s*(?<p>\w+)' | get p)) {
    let parts = ($field.path | split row ".")
    let sub = ($parts | drop 1 | str join ".")
    let last = ($parts | last)
    let items = (column-items (rows-at $prefix $sub $vars) [] | nu-complete filter $last | each {|r| $r | insert span (replace-span $position ($last | str length)) })
    return (if ($items | is-empty) { $nushell } else { { layer: "field", items: $items } })
  }

  # `cd ⌶` in a leaf folder: parents and the places you go, not NO RECORDS FOUND.
  if $shape == "directory" and ($base | where kind == directory | is-empty) {
    let items = (dir-fallback $partial $position)
    if ($items | is-not-empty) { return { layer: "directories", items: $items } }
  }

  # A flag whose value is a column: `move name --after ⌶`.
  let head = ($place.command | get -o 0 | default "")
  let column_flag = ($place.kind == "flag-value" and ($place.flag? | default "") in ($COLUMN_FLAGS | get -o $head | default []))

  # A positional slot the command does not have (`ps ⌶`, `first 3 ⌶`) or one
  # that wants a number (`first ⌶`) refuses files, before a pipe too (the
  # tests found the number rule applied only after one, 2026-09-19). A flag,
  # a flag's value, or nothing before the command: no columns to offer.
  let full = ($place.kind == "positional" and ($place.shape? == null))
  let bare = ($place.kind == "positional")
  if (not $column_flag) and ($place.kind in [flag-name flag-value] or ($partial | str starts-with "-") or ($prefix | is-empty)) {
    return (if $bare and ($full or (wants-number $shape)) { { layer: "no-files", items: ($no_files | in-slot $buffer $place | dedupe) } } else { $nushell })
  }

  # where / any / all / take while …: column, operator, value, and again after
  # and/or. `place` does not say "inside a condition" — it is `operator` after
  # the column, `variable` with a one-word command while the column is being
  # typed, and the condition is one word to it — so the command is read from
  # the words of this segment and asked whether its first positional is one.
  let before = if $w.fresh { $w.tokens } else { $w.tokens | drop 1 }
  let ntok = (condition-head $before)
  if $ntok != null {
    let cond = ($before | skip $ntok)
    let rows = (rows-at $prefix "" $vars)
    if ($rows | is-empty) { return $nushell }
    let cols = ($rows | first | get columns | columns)
    let last = ($cond | last | default "")
    let prev = ($cond | drop 1 | last | default "")
    let at_start = (($cond | is-empty) or ($last in [and or xor not "(" "and" "or"]))
    let field = ($partial | str replace --regex '^\$it\.' "")
    if $at_start {
      let items = (column-items $rows [] | nu-complete filter $field | each {|r| $r | insert span (replace-span $position ($field | str length)) })
      return (if ($items | is-empty) { $nushell } else { { layer: "columns", items: ($items ++ ($no_files | where kind != operator)) } })
    }
    let last_col = ($last | str replace --regex '^\$it\.' "")
    if $last_col in $cols and ($partial | is-empty) {
      let type = ($rows | first | get columns | get $last_col | get type)
      let allowed = (ops-for $type)
      let ops = ($base | where kind == operator)
      let narrowed = ($ops | where value in $allowed)
      return (if ($narrowed | is-empty) { $nushell } else { { layer: "operators", items: $narrowed } })
    }
    let prev_col = ($prev | str replace --regex '^\$it\.' "")
    if $prev_col in $cols and ($last | str starts-with "-" | not $in) and ($last in ($OPS | values | flatten)) {
      let raw = ($partial | str trim --left --char '"' | str trim --left --char "'")
      let type = ($rows | first | get columns | get $prev_col | get type)
      let offered = (if $last in $COMPARISONS and (bound-items $type | is-not-empty) { bound-items $type } else { value-items $rows $prev_col })
      let items = ($offered | nu-complete filter $raw | each {|r| $r | insert span (replace-span $position ($partial | str length)) })
      return (if ($items | is-empty) { { layer: "no-files", items: ($no_files | dedupe) } } else { { layer: "values", items: $items } })
    }
    return $nushell
  }

  # Cell-path slots: get, select, reject, sort-by, update, insert, str trim ...
  # and the ones that take a column without saying so (COLUMN_POSITIONALS,
  # COLUMN_FLAGS). A column already named on the line (`select name ⌶`) is
  # not offered again.
  let range = ($COLUMN_POSITIONALS | get -o $head)
  let column_positional = ($range != null and $place.kind == "positional" and ($place.index? | default 0) >= $range.0 and ($place.index? | default 0) <= $range.1)
  if ($shape =~ 'cell-path') or $column_flag or $column_positional {
    let parts = ($partial | split row ".")
    let sub = ($parts | drop 1 | str join ".")
    let last = ($parts | last)
    let used = ($place.command | skip 1 | drop 1 | where {|a| not ($a | str starts-with "-") })
    let items = (column-items (rows-at $prefix $sub $vars) $used | nu-complete filter $last | each {|r| $r | insert span (replace-span $position ($last | str length)) })
    if ($items | is-not-empty) { return { layer: "columns", items: $items } }
    # No columns to read (the pipeline may not run): a declared cell-path
    # still has no use for files; an undeclared one keeps Nushell's answer.
    return (if ($shape =~ 'cell-path') { { layer: "no-files", items: ($no_files | in-slot $buffer $place | dedupe) } } else { $nushell })
  }

  if $full or (wants-number $shape) { return { layer: "no-files", items: ($no_files | in-slot $buffer $place | dedupe) } }
  $nushell
}

# Only what would go into the slot, or extends what is typed. Under `fuzzy`,
# `ps ⌶` makes Nushell match the head and its space against every multiword
# command — `polars agg` and 187 more with the plugin, all spanning {0,3},
# which would replace `ps` itself. `bits r⌶` has the same shape (positional,
# no shape, candidates from 0) and `bits ror` is right: the line so far is
# its prefix. A candidate from before the token that does not start with the
# text it would replace is a rewrite of the command, not a completion
# (2026-09-28; the pty test drives `bits r`).
def in-slot [buffer: string, place: record]: list -> list {
  where {|r|
    let start = ($r.span?.start? | default $place.target.start)
    $start >= $place.target.start or ($r.value | str starts-with ($buffer | str substring $start..<$place.cursor))
  }
}

# `first ⌶`, `skip ⌶`, `sleep ⌶`: a number is wanted, not a file.
def wants-number [shape: string]: nothing -> bool {
  ($shape =~ '^(oneof<)?(int|number|float|duration|filesize|range)[,>]?') and ($shape !~ 'path|string|glob|any')
}
