# engine — spec-driven positional completion for external commands
#
# Attach to an extern with Nushell's command-wide completer attribute:
#
#   def "brew complete" [token, place?, buffer?] {
#     nu-complete run (brew spec) (nu-complete spans $token (try { $place }) (try { $buffer }))
#   }
#   @complete "brew complete"
#   export extern brew [...args]
#
# Those parameter names are not decoration: since nushell#18791 a completer is
# handed one record whose fields bind to the parameters it NAMES, from the set
# token / place / buffer. `nu-complete spans` turns them back into the span
# list this file walks — the command name, every argument typed so far and the
# partial token (an empty string at a fresh slot) — and returns the same list
# on 0.115.1, which knows nothing of that record. Nushell does NOT filter what
# a command-wide completer returns, so `run` filters with the user's
# completions.algorithm itself.
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
# spec be plain data (JSON) while the closures live in code. The closure gets
#   { spans, partial, args, positionals, path }
# where `positionals` are the values already typed for this (sub)command and
# `path` is the subcommand chain. Flags declared on the root spec apply
# everywhere; a flag with an `arg` consumes the next token.

# The completer's input, as the span list `run` walks.
#
# A build with #18791 (0.115.2 here, the first after 0.115.1) binds a
# completer's parameters by name from {token, place, buffer}; 0.115.1 hands it
# one positional span list. A completer
# declared `[token, place?, buffer?]` is right on both: the new build fills all
# three by name, and no parameter is named `spans`, which is what its
# compatibility bridge warns about (once a session, in the REPL, after the
# menu closes). 0.115.1 fills only the first, with the span list.
#
# It does not fill the other two with null — it never binds them, so naming
# `$place` there is `variable not found` at runtime, which a completer turns
# into silent file completion. Hence `(try { $place })` at every call site: the
# guard is the version test, and `$token` being a list is the confirmation.
#
# On the new build the list is rebuilt from the buffer, because the record
# carries no token list: `ast --flatten` for the tokens (quote-aware, 30 us),
# `place.target.start` for where the token under the cursor begins, and the
# last command head at or before it for where this command's own tokens start
# (`ls | git ch` must not be handed `ls`). Verified token for token against
# 0.115.1's real spans over quoted arguments, `--flag=value`, pipelines, `;`,
# a fresh slot and an unterminated quote. One difference is deliberate: an
# alias is not expanded here, where Nushell expanded it. `run` drops span 0,
# and carapace expands aliases itself.
export def "nu-complete spans" [token: any, place: any, buffer: any]: nothing -> list<string> {
  if $place == null { return ($token | default []) }      # 0.115.1: already a span list
  let cut = $place.target.start
  let before = (try { ast --flatten $buffer } catch { [] }) | where {|t| $t.span.end <= $cut }
  let heads = ($before | enumerate | where {|r| $r.item.shape in ["shape_external" "shape_internalcall"] })
  let head = if ($heads | is-empty) { 0 } else { $heads | last | get index }
  ($before | skip $head | get content) ++ [$token.text]
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

def run-source [src: any, ctx: record, root: record]: nothing -> any {
  let kind = ($src | describe | str replace --regex '<.*' '')
  match $kind {
    "closure" => (do $src $ctx)
    "list" | "table" => $src
    "string" => {
      if $src == "files" { return null }
      let named = ($root.sources? | default {} | get -o $src)
      if $named == null { [] } else { run-source $named $ctx $root }
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
export def "nu-complete external" [spans: list<string>]: nothing -> any {
  let ext = ($env.config.completions.external.completer? | default null)
  if $ext == null { return null }
  do $ext $spans
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
