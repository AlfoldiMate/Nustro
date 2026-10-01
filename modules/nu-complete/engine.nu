# engine — spec-driven positional completion for external commands
#
# Attach to an extern with Nushell's command-wide completer attribute:
#
#   def "brew complete" [place: record] {
#     nu-complete run (brew spec) $place.command
#   }
#   @complete "brew complete"
#   export extern brew [...args]
#
# The parameter name is not decoration: since Nushell 0.116 a completer is
# handed one record whose fields bind to the parameters it NAMES, from the set
# token / place / buffer. `place.command` is the span list this file walks —
# the command name, every argument typed so far and the partial token (an
# empty string at a fresh slot) — resolved by Nushell at the cursor: after a
# pipe or `;`, inside a closure or a subexpression, and with an alias at the
# head expanded (`gco ma` arrives as [git checkout ma]). Nushell does NOT
# filter what a command-wide completer returns (not even with
# `options.filter: true` in the envelope, 0.116.0), so `run` filters with the
# user's completions.algorithm itself.
#
# A spec is a plain record, meant to be read and edited by a person:
#
#   {
#     description: "..."                      # shown next to the subcommand
#     flags: [ { name: "--cask", short: "-c", description: "...", arg: <source> } ]
#                                             # or a closure returning that list
#     positionals: [ <source> <source> ]      # 1st, 2nd ... positional
#     rest: <source>                          # every positional after those
#     subcommands: { install: { <spec> } }    # nested, same shape; `hidden: true`
#                                             # on one resolves it but never offers it (an alias)
#     fallback: "external"                    # ask carapace when the spec has no answer
#   }
#
# A <source> is a list of candidates (strings, or records with value,
# description, style), a closure `{|ctx| ... }` returning such a list, the
# string "files" for Nushell's own path completion, or any other string naming
# an entry of the spec's `sources` record — which is what lets a generated
# spec be plain data (JSON) while the closures live in code — or one of
# Nushell's own completers: "directories", "paths", "commands", "variables",
# "env-vars". The closure gets
#   { spans, partial, args, positionals, path }
# where `positionals` are the values already typed for this (sub)command and
# `path` is the subcommand chain. Flags declared on the root spec apply
# everywhere; a flag with an `arg` consumes the next token.

# The span list, for a completion written before Nushell 0.116 was required:
# `nu-complete run (spec) (nu-complete spans $token (try { $place }) (try
# { $buffer }))`, which is what `agent completion` generated into your
# completions/ until 2026-09-27. It is `$place.command` now; new code says so.
export def "nu-complete spans" [token: any, place?: any, buffer?: any]: nothing -> list<string> {
  if ($place | describe) =~ '^record' { $place.command } else { $token | default [] }
}

# Candidates as records, whatever shape the source used.
export def "nu-complete normalize" []: any -> list<record> {
  let items = $in
  if $items == null { return [] }
  $items | each {|it|
    if ($it | describe) =~ '^record' { $it } else { { value: ($it | into string) } }
  }
}

# Keep the candidates matching `partial` the way the user's completion
# settings say (prefix | substring | fuzzy, case-sensitive or not), best
# first: a value that starts with the partial, then one that contains it,
# then (fuzzy) one that has its letters in that order, and last a candidate
# matched only through its description, again contains before letters in
# order — `brew install "silver sea` finds ripgrep ("Search tool like grep
# and The Silver Searcher") after every formula named *silver sea*.
# Descriptions count under substring and fuzzy, never under prefix.
# Ties keep the source's order (`sort-by` is stable), which is what keeps
# branches by recency by recency — except among letters-in-order matches,
# where the shortest value wins: `rgrep` is ripgrep before frege-repl.
#
# Written column-wise on purpose: `str starts-with` over a list of 2000
# strings takes 0.2 ms, the same test inside a per-item closure 9 ms. 2000
# candidates with descriptions: prefix 4 ms, substring 9 ms, fuzzy 15 ms
# (measured 2026-09-20; the per-item version was 9 ms for prefix alone).
export def "nu-complete filter" [partial: string]: list<record> -> list<record> {
  let items = $in
  if ($partial | is-empty) or ($items | is-empty) { return $items }
  let cfg = $env.config.completions
  let cs = $cfg.case_sensitive
  let algo = $cfg.algorithm
  let p = if $cs { $partial } else { $partial | str lowercase }
  let vals = ($items | get value | into string)
  let vals = if $cs { $vals } else { $vals | str lowercase }
  let starts = ($vals | str starts-with $p)
  if $algo == "prefix" {
    return ($items | wrap item | merge ($starts | wrap keep) | where keep | get item)
  }
  let fuzzy = ($p | split chars | each {|c| $c | str escape-regex } | str join '.*')
  let descs = ($items | get -o description | default "" | into string)
  let descs = if $cs { $descs } else { $descs | str lowercase }
  let within = ($vals | str contains $p)
  let inorder = if $algo == "fuzzy" { $vals | each {|v| $v =~ $fuzzy } } else { $within }
  let d_within = ($descs | str contains $p)
  let d_inorder = if $algo == "fuzzy" { $descs | each {|d| $d =~ $fuzzy } } else { $d_within }
  let lens = ($vals | str length)
  let ranks = ($starts | zip $within | zip $inorder | zip $d_within | zip $d_inorder | zip $lens
    | each {|r| if $r.0.0.0.0.0 { 0 } else if $r.0.0.0.0.1 { 1000 } else if $r.0.0.0.1 { 2000 + $r.1 } else if $r.0.0.1 { 3000 } else if $r.0.1 { 4000 } else { 9000 } })
  $items | wrap item | merge ($ranks | wrap rank) | where rank < 9000 | sort-by rank | get item
}

# Quote every value the line editor would otherwise split or misparse:
# `theme use Catppuccin Macchiato` is two arguments, `"Catppuccin Macchiato"`
# is one. Nushell quotes the paths its own file completer offers (backticks)
# and carapace quotes its own, but a `string@completer` value and a spec
# source are inserted verbatim (0.115.1 and 0.115.2, both menus), so this is
# done once here for everything the engine and the menu hand out. Already
# quoted values pass through, and so does carapace's trailing space, which
# means "and a space after it". Matching still works on a quoted value: both
# releases match `Cat` against `"Catppuccin …"` past the quote. Only a
# candidate with no `kind` (a spec's) or `kind: value` (a custom completer's)
# is touched: `commandline complete --detailed` also lists commands (`str
# trim` is one word to the parser), flags, operators and quoted paths.
const QUOTED = r##'^["'`]'##
const NEEDS_QUOTES = r##'[ \t"'`|;()\[\]{}$#&]'##
export def "nu-complete quote" []: list<record> -> list<record> {
  let items = $in
  if ($items | is-empty) { return $items }
  # One regex over all the values first: a closure per item costs 30 µs, so
  # 2000 formulae would pay 63 ms to find that none of them needs quoting.
  if (($items | get value | into string | str join (char nl)) !~ $NEEDS_QUOTES) { return $items }
  $items | each {|it|
    if ($it.kind? | default "value") != "value" { return $it }
    let v = ($it.value | into string)
    let trailing = if ($v | str ends-with " ") { " " } else { "" }
    let body = ($v | str trim --right --char " ")
    if ($body =~ $QUOTED) or ($body !~ $NEEDS_QUOTES) { $it } else {
      $it | update value (($body | to nuon) + $trailing)
    }
  }
}

# Source names every spec has without declaring them: Nushell's built-in
# completers, one at a time (`commandline complete --type`, 0.116). "files"
# is not here — it hands the whole slot to Nushell, which is still the best
# file completion there is; these are for a slot that is narrower
# ("directories" for `git -C ⌶`) or that mixes them with its own candidates.
const BUILTIN_SOURCES = { directories: "directory", paths: "path", commands: "command", variables: "variable", "env-vars": "env-var" }

def run-source [src: any, ctx: record, root: record]: nothing -> any {
  let kind = ($src | describe | str replace --regex '<.*' '')
  match $kind {
    "closure" => (do $src $ctx)
    "list" | "table" => $src
    "string" => {
      if $src == "files" { return null }
      # A spec's own source of that name wins over the built-in one.
      let named = ($root.sources? | default {} | get -o $src)
      if $named != null { return (run-source $named $ctx $root) }
      let builtin = ($BUILTIN_SOURCES | get -o $src)
      if $builtin == null { [] } else {
        # Nushell's own completer for one kind of thing, on the token alone.
        # Its spans are offsets into that token, not into the line, so they
        # are dropped and the candidate replaces the token like any other.
        try { $ctx.partial | commandline complete --detailed --type $builtin | reject -o span } catch { [] }
      }
    }
    _ => []
  }
}

# `flags` may also be a closure (no arguments), for lists that are slow to
# build and only needed when a `-` is typed.
def resolve-flags [flags: any]: nothing -> list {
  if ($flags | describe) =~ '^closure' { do $flags } else { $flags | default [] }
}

def all-flags [node: record, root: record, is_root: bool]: nothing -> list {
  let own = (resolve-flags ($node.flags? | default []))
  # A subcommand's own definition of a global flag (`cargo build -v`) wins.
  if $is_root { $own } else { $own ++ (resolve-flags ($root.flags? | default [])) | uniq-by name }
}

def find-flag [node: record, root: record, is_root: bool, name: string]: nothing -> any {
  let all = (all-flags $node $root $is_root)
  let hit = ($all | where {|f| $f.name == $name or (($f.short? | default "") == $name) })
  if ($hit | is-empty) { null } else { $hit | first }
}

def flag-items [node: record, root: record, is_root: bool, partial: string]: nothing -> list<record> {
  let all = (all-flags $node $root $is_root)
  let longs = ($all | each {|f| { value: $f.name, description: ($f.description? | default "") } })
  let shorts = if ($partial | str starts-with "--") { [] } else {
    $all | where {|f| ($f.short? | default "") != "" } | each {|f| { value: $f.short, description: ($f.description? | default "") } }
  }
  $longs ++ $shorts
}

# Ask the external completer (carapace) the way Nushell would.
#
# By hand, because nothing in Nushell chains to it: `fallback: true` in a
# declared extern's answer adds file completion, `null` hands the slot to
# file completion and `[]` shows nothing, and the external completer is never consulted for a command
# that has a completer of its own (0.116.0, measured). Nushell binds a
# completer's inputs by the names it declares, which `do` cannot, so the
# closure's own header says which to pass and in what order (`view source`,
# 9 µs). What it is handed is rebuilt from `spans`: `command` exact,
# `buffer` the words joined, cursor and target at its end — enough for
# carapace, which reads only `$place.command`. `spans`, the pre-0.116 name,
# still gets the list.
export def "nu-complete external" [spans: list<string>]: nothing -> any {
  let ext = ($env.config.completions.external.completer? | default null)
  if $ext == null { return null }
  let buffer = ($spans | str join " ")
  let cursor = ($buffer | str length)
  let target = { start: ($cursor - ($spans | last | default "" | str length)), end: $cursor }
  let partial = ($spans | last | default "")
  let inputs = {
    token: { text: $partial, kind: (if ($partial | str starts-with "-") { "flag" } else { "value" }), span: $target }
    place: { cursor: $cursor, target: $target, command: $spans }
    buffer: $buffer
    spans: $spans
  }
  let args = (closure-params $ext | each {|p| $inputs | get -o $p })
  do $ext ...$args
}

# The parameter names in a closure's header: `{|place: record, buffer|` →
# [place buffer]. Types are dropped (angle-bracketed ones first, since they
# may hold commas), so are `?` and `...`.
def closure-params [c: closure]: nothing -> list<string> {
  let head = (view source $c | parse --regex '^\s*\{\s*\|(?<p>[^|]*)\|' | get -o 0.p | default "")
  $head
  | str replace --all --regex '<[^<>]*>' '' | str replace --all --regex '<[^<>]*>' ''
  | str replace --all --regex ':\s*[\w-]+' ''
  | split row --regex '[,\s]+'
  | str replace --regex '^\.\.\.' '' | str trim --right --char '?'
  | where {|p| $p != "" }
}

# Walk `spans` through the spec and return the candidates for the last one.
# Returns null when the slot wants Nushell's file completion.
export def "nu-complete run" [spec: record, spans: list<string>]: nothing -> any {
  let spans = if ($spans | length) < 2 { $spans ++ [""] } else { $spans }
  # A quote the user opened to type a space (`brew install "silver sea`) is
  # not part of what is matched; the candidate replaces the whole token,
  # quotes included, and `nu-complete quote` re-quotes what needs it.
  let partial = ($spans | last | str replace --regex r##'^["'`]'## "" | str replace --regex r##'["'`]$'## "")
  let args = ($spans | skip 1 | drop 1)

  mut node = $spec
  mut positionals = []
  mut path = []
  mut pending: any = null
  for a in $args {
    if $pending != null { $pending = null; continue }
    if ($a | str starts-with "-") and $a != "-" {
      let f = (find-flag $node $spec ($path | is-empty) ($a | split row "=" | first))
      if $f != null and ($f.arg? != null) and not ($a | str contains "=") { $pending = $f }
      continue
    }
    let subs = ($node.subcommands? | default {})
    if ($positionals | is-empty) and ($a in ($subs | columns)) {
      $node = ($subs | get $a)
      $path ++= [$a]
      continue
    }
    $positionals ++= [$a]
  }

  let ctx = { spans: $spans, partial: $partial, args: $args, positionals: $positionals, path: $path }
  let fallback = ($node.fallback? | default ($spec.fallback? | default null))
  let is_flag = ($partial | str starts-with "-")

  # What the slot wants, and whether the spec had an opinion at all.
  let answer = if $pending != null {
    { items: (run-source $pending.arg $ctx $spec), answered: true }
  } else if $is_flag and ($partial | str contains "=") {
    let name = ($partial | split row "=" | first)
    let f = (find-flag $node $spec ($path | is-empty) $name)
    if $f != null and ($f.arg? != null) {
      let sub = ($partial | split row "=" | skip 1 | str join "=")
      let vals = (run-source $f.arg ($ctx | update partial $sub) $spec | nu-complete normalize)
      { items: ($vals | each {|r| $r | update value $"($name)=($r.value)" }), answered: true }
    } else { { items: [], answered: false } }
  } else if $is_flag {
    let items = (flag-items $node $spec ($path | is-empty) $partial)
    # Root flags alone are no answer for a subcommand's flags.
    { items: $items, answered: (($path | is-empty) or (resolve-flags ($node.flags? | default []) | is-not-empty)) }
  } else {
    let subs = ($node.subcommands? | default {})
    # A `hidden` subcommand (an alias) resolves when typed but is not offered.
    let sub_items = if ($positionals | is-empty) {
      $subs | transpose name s | where {|r| not ($r.s.hidden? | default false) }
      | each {|r| { value: $r.name, description: ($r.s.description? | default "") } }
    } else { [] }
    let nth = ($node.positionals? | default [] | get -o ($positionals | length))
    let src = if $nth == null { $node.rest? | default null } else { $nth }
    let from_src = (run-source $src $ctx $spec)
    if $from_src == null and ($sub_items | is-empty) {
      { items: null, answered: true }          # "files": hand the slot to Nushell
    } else {
      { items: ($sub_items ++ ($from_src | nu-complete normalize)), answered: (($sub_items | is-not-empty) or $src != null) }
    }
  }

  if $answer.items == null { return null }
  if not $answer.answered and $fallback == "external" {
    return (nu-complete external $spans)
  }
  let items = ($answer.items | nu-complete normalize | nu-complete filter $partial)
  # A flag the spec does not know (git -h lists only the common ones): ask outside.
  if ($items | is-empty) and $is_flag and $fallback == "external" {
    return (nu-complete external $spans)
  }
  $items | nu-complete quote
}
