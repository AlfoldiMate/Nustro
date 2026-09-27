# brew — Homebrew completion, native and fast
#
# Carapace answers `brew install <Tab>` in about 1.6 s because it asks Ruby.
# Homebrew already keeps everything needed on disk, so this module reads that:
#
#   subcommands, flags, positional kinds   $HOMEBREW_PREFIX/completions/zsh/_brew,
#                                          parsed once into a JSON spec, redone
#                                          when Homebrew updates the file
#   every formula and cask, with desc      the API payload in Homebrew's cache,
#                                          parsed once into a SQLite file in the
#                                          background; names come from the
#                                          plain-text name lists (1 ms) until
#                                          that is ready
#   installed packages                     directory names under Cellar/Caskroom
#   taps                                   directory names under Library/Taps
#
# Measured on 2026-09-10: `brew install rip<Tab>` answers in 3-5 ms with
# descriptions. `brew install` is not special-cased; every subcommand in the
# zsh file gets its own positional and flag completion.

use nu-complete *

# ── Where Homebrew keeps things ───────────────────────────────────────────────

# `which brew` answers with this file: the extern below shadows the binary, and
# an extern's `path` is the module it was declared in. `-a` lists both, and
# the binary is the one that is not a `.nu` file. Found 2026-09-20: `brew
# uninstall <Tab>` had offered nothing since the extern was named `brew`,
# while `brew install` kept working because the API cache lives elsewhere.
def prefix []: nothing -> path {
  $env.HOMEBREW_PREFIX? | default (
    which -a brew | where ($it.path | path parse | get extension) != "nu"
    | get -o 0.path | default "/opt/homebrew/bin/brew" | path dirname | path dirname
  )
}

def api-dir []: nothing -> path {
  let cache = ($env.HOMEBREW_CACHE? | default (
    if $nu.os-info.name == "macos" { $nu.home-dir | path join Library Caches Homebrew } else { $nu.home-dir | path join .cache Homebrew }
  ))
  $cache | path join api
}

def read-lines [f: path]: nothing -> list<string> {
  if ($f | path exists) { %open --raw $f | lines --skip-empty } else { [] }
}

# ── The spec: parsed from Homebrew's zsh completion ───────────────────────────

# Sources named in the zsh file → sources of this module.
def helper-source [helper: string]: nothing -> string {
  match $helper {
    "__brew_formulae" => "formulae"
    "__brew_casks" => "casks"
    "__brew_installed_formulae" | "__brew_outdated_formulae" => "installed_formulae"
    "__brew_services" => "services"
    "__brew_installed_casks" | "__brew_outdated_casks" => "installed_casks"
    "__brew_any_tap" | "__brew_tapped" | "__brew_official_taps" => "taps"
    "__brew_internal_commands" | "__brew_commands" => "commands"
    "__brew_installed" => "installed"
    "_files" | "_directories" => "files"
    _ => "none"
  }
}

# One `_arguments` body (a subcommand's, or one arm of a nested `case`) as a
# node: its flags, and the source of its `*:` slot and of its `1:` slot.
def node-from-body [body: list<string>, desc: string]: nothing -> record {
  let flags = ($body
    | parse --regex r#''(?:\([^)]*\))?(?<name>--[\w-]+)=?\[(?<desc>.*)\]''#
    | uniq-by name
    | each {|f| { name: $f.name, description: ($f.desc | str replace -a "'\\''" "'") } })
  let pos = ($body | parse --regex r#''(?<slot>\*|\d+):[\w-]*:(?<helper>__brew_\w+|_files|_directories)''#)
  let rest_kinds = ($pos | where slot == "*" | get helper | each {|h| helper-source $h } | uniq | where $it != "none")
  let rest = (match $rest_kinds {
    [] => null
    [$one] => $one
    _ => (if ("formulae" in $rest_kinds and "casks" in $rest_kinds) { "packages" }
          else if ("installed_formulae" in $rest_kinds and "installed_casks" in $rest_kinds) { "installed" }
          else { $rest_kinds | first })
  })
  let node = ({ description: $desc, flags: $flags } | merge (if $rest == null { {} } else { { rest: $rest } }))
  # A command like `brew help` completes other commands; `1:` slots.
  let firsts = ($pos | where slot == "1" | get helper | each {|h| helper-source $h } | where $it != "none")
  if ($firsts | is-empty) { $node } else { $node | insert positionals [($firsts | first)] }
}

# The `'name:desc'` entries of a zsh array literal that starts at `$start`.
def described-list [lines: list<string>, start: int]: nothing -> record {
  $lines | skip ($start + 1) | take while {|l| $l !~ '^\s*\)' }
  | parse --regex r#'^\s+'(?<name>[\w.-]+):(?<desc>.*)'\s*$'#
  | reduce -f {} {|r, acc| $acc | upsert $r.name ($r.desc | str replace -a "'\\''" "'") }
}

# Bump when the parser's output changes shape: a cached spec is regenerated
# when Homebrew's zsh file is newer, or when it was written by an older parser
# (2: nested subcommands, `services`).
const PARSER = 2

# Parse the zsh completion into a serialisable spec (sources by name).
export def "nu-complete brew spec-from-zsh" [file: path]: nothing -> record {
  let lines = (%open --raw $file | lines)

  # `__brew_internal_commands` holds every subcommand with its description.
  let cmd_start = ($lines | enumerate | where item =~ '^__brew_internal_commands\(\)' | get -o 0.index | default (-1))
  let descs = if $cmd_start < 0 { {} } else { described-list $lines $cmd_start }

  # One `_brew_<name>() { ... }` block per subcommand.
  # (`_brew_--taps`-style blocks are flags of `brew` itself, not subcommands.)
  let starts = ($lines | enumerate | where item =~ '^_brew_[A-Za-z][\w-]*\(\) \{' | select index item)
  let subcommands = ($starts | reduce -f {} {|s, acc|
    let name = ($s.item | parse --regex '^_brew_(?<n>[\w-]+)' | get 0.n | str replace -a "_" "-")
    let body = ($lines | skip ($s.index + 1) | take while {|l| $l !~ '^\}' })
    let desc = ($descs | get -o $name | default "")
    # `brew bundle`, `brew services`: a `subcommands=( 'name:desc' … )` list,
    # then one `name)` … `;;` arm per subcommand under `case "$words[1]"`.
    # The block's own flags come before that `case`; each arm repeats the
    # common ones, so an arm's node is complete on its own. Aliases share a
    # description (`stop`/`unload`/`terminate`/`term`/`t`/`u`): the first
    # name is offered, the rest resolve but stay `hidden`.
    let sub_start = ($body | enumerate | where item =~ '^\s*subcommands=\(' | get -o 0.index)
    let node = if $sub_start == null { node-from-body $body $desc } else {
      let names = (described-list $body $sub_start)
      let own = ($body | take while {|l| $l !~ '^\s*case "\$state"' })
      let arms = ($body | enumerate | where item =~ '^[a-z][\w|-]*\)\s*$' | select index item)
      let by_arm = ($arms | reduce -f {} {|a, acc|
        let arm_body = ($body | skip ($a.index + 1) | take while {|l| $l !~ '^\s*;;\s*$' })
        $a.item | str trim | str replace --regex '\)$' '' | split row "|"
        | reduce -f $acc {|n, acc2| $acc2 | upsert $n $arm_body }
      })
      let nested = ($names | transpose name desc | reduce -f { subs: {}, seen: [] } {|r, acc|
        let n = (node-from-body ($by_arm | get -o $r.name | default []) $r.desc)
        let n = if $r.desc in $acc.seen { $n | insert hidden true } else { $n }
        { subs: ($acc.subs | upsert $r.name $n), seen: ($acc.seen ++ [$r.desc]) }
      } | get subs)
      node-from-body $own $desc | insert subcommands $nested
    }
    $acc | upsert $name $node
  })

  {
    description: "The missing package manager for macOS"
    generated_from: $file
    parser: $PARSER
    subcommands: $subcommands
  }
}

# JSON, where the rest of this config writes NUON, because this file is big
# and sits on the Tab path: 195 kB parses in 1.2 ms as JSON and 7.8 ms as NUON
# (`to nuon --indent 2`: 9.3 ms). Nothing reads it but the completer.
def spec-file []: nothing -> path { nu-complete cache-dir | path join brew-spec.json }

# The spec as data, regenerated when Homebrew ships a new zsh completion.
export def "nu-complete brew spec-data" []: nothing -> record {
  let zsh = (prefix | path join completions zsh _brew)
  let f = (spec-file)
  let cached = if ($f | path exists) { %open $f } else { null }
  let outdated = ($cached == null) or (($cached.parser? | default 0) != $PARSER) or (nu-complete stale $f $zsh)
  if $outdated and ($zsh | path exists) {
    let spec = (nu-complete brew spec-from-zsh $zsh)
    $spec | to json | save -f $f
    $spec
  } else if $cached != null { $cached } else {
    # No zsh file (unusual install): subcommands only, from `brew commands`.
    { description: "Homebrew", subcommands: (^brew commands --quiet --include-aliases | lines | reduce -f {} {|c, acc| $acc | upsert $c {} }) }
  }
}

# ── Package list: Homebrew's API payload → SQLite ─────────────────────────────

# `glob` patterns are forward-slashed: a backslash is an escape in one, so a
# Windows path breaks the pattern (the tests run this fixture there).
def payload-file []: nothing -> any {
  glob ((api-dir | str replace -a '\' '/') + "/internal/packages.*.jws.json.payload") | get -o 0
}

def db-file []: nothing -> path { nu-complete cache-dir | path join brew-packages.db }

# Build the SQLite package table from the API payload (~0.5 s, so it runs in
# a background job and the caller falls back to the name lists meanwhile).
export def "nu-complete brew build-db" []: nothing -> nothing {
  let payload = (payload-file)
  if $payload == null { return }
  let idx = (%open --raw $"($payload).index" | from json)
  let raw = (%open --raw $payload | into binary)
  # First line is the JWS header; offsets in the index are into the second.
  let body = ($raw | bytes at (($raw | bytes index-of 0x[0a]) + 1)..)
  let section = {|key|
    let r = ($idx.top_level | get $key)
    $body | bytes at $r.0..<($r.0 + $r.1) | decode | from json
  }
  let formulae = (do $section formulae | transpose name v | each {|r|
    { name: $r.name, kind: "formula", desc: ($r.v.desc? | default ""), version: ($r.v.stable_version? | default "") }
  })
  let casks = (do $section casks | transpose name v | each {|r|
    { name: $r.name, kind: "cask", desc: ($r.v.desc? | default ""), version: ($r.v.version? | default "") }
  })
  let db = (db-file)
  let tmp = $"($db).tmp"
  rm -f $tmp
  $formulae ++ $casks | into sqlite $tmp -t packages
  mv -f $tmp $db
}

# Make sure the database is fresh; when it is not, start building it in the
# background and say so (the caller then serves names without descriptions).
def ensure-db []: nothing -> bool {
  let db = (db-file)
  let payload = (payload-file)
  if $payload == null { return false }
  if not (nu-complete stale $db $payload) { return true }
  let lock = $"($db).building"
  let busy = (($lock | path exists) and ((date now) - (ls -D $lock | get 0.modified)) < 3min)
  if not $busy {
    touch $lock
    job spawn { try { nu-complete brew build-db }; rm -f $lock } | ignore
  }
  false
}

# Every formula and/or cask matching the partial, with descriptions when the
# database is ready. `kinds` ⊆ [formula cask].
def packages [partial: string, kinds: list<string>]: nothing -> list<record> {
  if (ensure-db) {
    # The same tiers as `nu-complete filter` (prefix, substring, letters in
    # order, then the description, contains before letters in order), so the
    # 2000 rows the query keeps are the best ones and the engine's own pass
    # over them only confirms the order.
    let algo = $env.config.completions.algorithm
    let pre = $"($partial)%"
    let sub = $"%($partial)%"
    let fz = if $algo == "fuzzy" { "%" + ($partial | split chars | str join "%") + "%" } else { $sub }
    let ks = ($kinds | each {|k| $"'($k)'" } | str join ", ")
    let hit = if $algo == "prefix" { "name like :pre" } else { "(name like :fz or desc like :fz)" }
    %open (db-file)
    | query db $"select name as value, desc as description from packages where kind in \(($ks)\) and ($hit) order by case when name like :pre then 0 when name like :sub then 1 when name like :fz then 2 when desc like :sub then 3 else 4 end, case when name like :fz and name not like :sub then length\(name\) else 0 end, name limit 2000" -p { pre: $pre, sub: $sub, fz: $fz }
  } else {
    let api = (api-dir)
    let names = (
      (if "formula" in $kinds { read-lines ($api | path join formula_names.txt) } else { [] })
      ++ (if "cask" in $kinds {
        let f = ($api | path join cask_names.txt)
        read-lines (if ($f | path exists) { $f } else { $api | path join cask_names.before.txt })
      } else { [] })
    )
    $names | wrap value
  }
}

# --cask / --formula narrow what a mixed slot offers.
def kinds-from [ctx: record, default: list<string>]: nothing -> list<string> {
  if "--cask" in $ctx.args { ["cask"] } else if "--formula" in $ctx.args { ["formula"] } else { $default }
}

def installed [kind: string]: nothing -> list<record> {
  let dir = (prefix | path join (if $kind == "formula" { "Cellar" } else { "Caskroom" }))
  if not ($dir | path exists) { return [] }
  ls $dir | where type == dir | each {|d|
    let versions = (ls $d.name | get name | path basename | where $it != ".metadata")
    { value: ($d.name | path basename), description: ($versions | str join ", ") }
  }
}

# Formulae that ship a service: `<Cellar>/<name>/<version>/*.service`, the
# way Homebrew's own `__brew_services` finds them (`brew services` takes only
# these, not every installed formula).
def services []: nothing -> list<record> {
  let dir = (prefix | path join Cellar | str replace -a '\' '/')
  glob ($dir + "/*/*/*.service") | each {|p| $p | path dirname | path dirname | path basename } | uniq | sort | wrap value
}

def taps []: nothing -> list<record> {
  let dir = (prefix | path join Library Taps)
  if not ($dir | path exists) { return [] }
  # Sorted: `glob` returns directory order, which differs by file system.
  let dir = $dir | str replace -a '\' '/'
  glob ($dir + "/*/*") | sort | each {|p| { value: ($p | path relative-to $dir | str replace -a '\' '/' | str replace "homebrew-" "") } }
}

# ── The spec with its sources, as the engine wants it ─────────────────────────

# Where Homebrew's own completion is less than it could be: these slots take
# only installed packages (`brew outdated ripgrep` says nothing about a
# formula that is not there), and `brew help`, which has no block in the zsh
# file, takes a command.
const REFINED = {
  outdated: { rest: installed }
  cleanup: { rest: installed }
  help: { description: "Show help for a command", positionals: [commands] }
  # Shares `install`'s arm and description, but is a verb of its own.
  bundle: { subcommands: { upgrade: { hidden: false } } }
}

export def "nu-complete brew spec" []: nothing -> record {
  let data = (nu-complete brew spec-data)
  # A fix with a description is a whole node (`help`); the others refine a
  # node the zsh file has, and are skipped where it does not.
  let subs = ($REFINED | transpose name fix | reduce -f $data.subcommands {|r, acc|
    if $r.name in ($acc | columns) or $r.fix.description? != null {
      $acc | upsert $r.name { $in | default {} | merge deep $r.fix }
    } else { $acc }
  })
  $data | update subcommands $subs | merge {
    fallback: "external"
    flags: [
      { name: "--help", short: "-h", description: "Show this message" }
      { name: "--verbose", short: "-v", description: "Make some output more verbose" }
      { name: "--debug", short: "-d", description: "Display any debugging information" }
      { name: "--quiet", short: "-q", description: "Make some output more quiet" }
    ]
    sources: {
      packages: {|ctx| packages $ctx.partial (kinds-from $ctx [formula cask]) }
      formulae: {|ctx| packages $ctx.partial [formula] }
      casks: {|ctx| packages $ctx.partial [cask] }
      installed: {|ctx|
        let ks = (kinds-from $ctx [formula cask])
        ($ks | each {|k| installed $k } | flatten)
      }
      installed_formulae: {|ctx| installed formula }
      installed_casks: {|ctx| installed cask }
      services: {|ctx| services }
      taps: {|ctx| taps }
      commands: {|ctx| nu-complete brew spec-data | get subcommands | transpose name s | each {|r| { value: $r.name, description: ($r.s.description? | default "") } } }
      none: []
    }
  }
}

# null on any failure: Nushell then falls back to file completion instead of
# showing nothing. `place.command` is the span list the engine walks
# (engine.nu).
def complete-brew [place: record] {
  try { nu-complete run (nu-complete brew spec) $place.command } catch { null }
}

# `main` so that `use brew.nu *` yields `brew` (a module cannot export an
# extern of its own name any other way).
@complete "complete-brew"
export extern main [...args]
