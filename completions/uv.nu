# uv — project-aware completion for uv
#
# `uv generate-shell-completion nushell` is 5,839 lines of `export extern`:
# 13 ms to parse in every shell, frozen at the version that printed it, and
# it knows no value — `uv python install ⌶` and `uv remove ⌶` offer the files
# of the directory. Carapace offers nothing for uv at all. Everything below
# comes from uv's own data, read when Tab asks for it:
#
#   subcommands, flags, enums   `uv <path> -h`, parsed            7 ms a level, memoised 1 h
#   Python versions             `uv python list --output-format json`   200 ms, memoised 5 min
#     (`python install/uninstall/pin/find/upgrade`, `--python`)
#   installed tools             `uv tool list`                    9 ms, memoised 30 s
#   scripts, extras, groups,    pyproject.toml of the nearest project   1 ms, memoised 10 s
#     dependencies, indexes       (`run`, `--extra`, `--group`, `remove`, `--index`)
#   locked packages, members    uv.lock, a regex over the raw file      1-2 ms, memoised 10 s
#     (`--package`, `--upgrade-package`, `tree --package` …)
#   environment packages        `.venv/lib/python*/site-packages/*.dist-info`   2 ms
#     (`pip uninstall`, `pip show`)
#
# Measured 2026-10-01 with uv 0.12.19, first Tab in a new shell and again:
# `uv ⌶` 20 ms, 5 ms; `uv run ⌶` 38 ms, 5 ms; `uv pip install --⌶` 56 ms,
# 10 ms; `uv python install ⌶` 250 ms once in five minutes, 6 ms after.
# Parsing this module costs 2.8 ms (cargo.nu, beside it: 2.8 ms). Outside a project the project slots offer
# nothing. Package names for `add`, `pip install` and `tool install` would
# need the network and offer nothing on purpose; a slot the spec does not
# know goes to carapace (`fallback: external`). `uvx` is not covered.

use nu-complete *

# ── Sources ───────────────────────────────────────────────────────────────────

# Nearest pyproject.toml above the current directory, or null (path checks only).
def project-root []: nothing -> any {
  mut d = $env.PWD
  mut hit: any = null
  while $hit == null and $d != ($d | path dirname) {
    if ($d | path join pyproject.toml | path exists) { $hit = $d } else { $d = ($d | path dirname) }
  }
  $hit
}

def pyproject []: nothing -> record {
  let root = (project-root)
  if $root == null { return {} }
  nu-complete cache $"uv:pyproject:($root)" 10sec {
    try { %open ($root | path join pyproject.toml) } catch { {} }
  }
}

# `requests>=2,<3 ; python_version < "3.13"` → `requests`
def requirement-name [req: string]: nothing -> string {
  $req | parse --regex '^\s*(?<n>[A-Za-z0-9][A-Za-z0-9._-]*)' | get -o 0.n | default $req
}

# `[project.scripts]` and `[project.gui-scripts]`: what `uv run <name>` starts.
def scripts []: nothing -> list<record> {
  let p = (pyproject | get -o project | default {})
  [scripts gui-scripts] | each {|k|
    $p | get -o $k | default {} | transpose value target | each {|s| { value: $s.value, description: $"script · ($s.target)" } }
  } | flatten
}

def extras []: nothing -> list<record> {
  pyproject | get -o project.optional-dependencies | default {} | transpose value deps
  | each {|e| { value: $e.value, description: $"extra · ($e.deps | length) dependencies" } }
}

def groups []: nothing -> list<record> {
  pyproject | get -o dependency-groups | default {} | transpose value deps
  | each {|g| { value: $g.value, description: $"group · ($g.deps | length) dependencies" } }
}

# What `uv remove` can take: the project's own requirements, wherever declared.
def dependencies []: nothing -> list<record> {
  let p = (pyproject)
  let main = ($p | get -o project.dependencies | default [] | each {|d| { value: (requirement-name $d), description: $d } })
  let extra = ($p | get -o project.optional-dependencies | default {} | transpose name deps
    | each {|e| $e.deps | each {|d| { value: (requirement-name $d), description: $"($d) · extra ($e.name)" } } } | flatten)
  # A group may include another (`{ include-group = "x" }`): only strings are requirements.
  let grouped = ($p | get -o dependency-groups | default {} | transpose name deps
    | each {|g| $g.deps | where {|d| ($d | describe) == "string" } | each {|d| { value: (requirement-name $d), description: $"($d) · group ($g.name)" } } } | flatten)
  $main ++ $extra ++ $grouped | uniq-by value
}

def indexes []: nothing -> list<record> {
  pyproject | get -o tool.uv.index | default [] | where {|i| ($i | get -o name) != null }
  | each {|i| { value: $i.name, description: ($i | get -o url | default "") } }
}

# Every package in uv.lock with its version, and which of them are the
# workspace's own (an editable or virtual source). A regex over the raw
# file, like cargo.nu's: `from toml` on a lockfile is the slow way.
def lock []: nothing -> list<record> {
  let root = (project-root)
  if $root == null { return [] }
  let f = ($root | path join uv.lock)
  if not ($f | path exists) { return [] }
  nu-complete cache $"uv:lock:($root)" 10sec {
    %open --raw $f
    | parse --regex '(?m)^name = "(?<value>[^"]+)"\nversion = "(?<version>[^"]+)"\nsource = \{ (?<kind>[a-z]+) = '
    | uniq-by value
  }
}

def lock-packages []: nothing -> list<record> {
  lock | each {|p| { value: $p.value, description: $p.version } }
}

def members []: nothing -> list<record> {
  let own = (lock | where kind in [editable virtual] | each {|p| { value: $p.value, description: $"($p.version) · workspace member" } })
  if ($own | is-not-empty) { return $own }
  let name = (pyproject | get -o project.name)
  if $name == null { [] } else { [{ value: $name, description: "this project" }] }
}

# Every Python uv can see or download. 200 ms, so memoised for five minutes:
# long enough for a session of Tabs, short enough that an install shows up.
def python-rows []: nothing -> list<record> {
  nu-complete cache "uv:pythons" 5min {
    let r = (^uv python list --output-format json | complete)
    if $r.exit_code != 0 { [] } else {
      $r.stdout | from json | each {|p|
        let t = (if $p.variant == "freethreaded" { "t" } else { "" })
        let request = (if $p.implementation == "cpython" { $"($p.version)($t)" } else { $"($p.implementation)@($p.version)($t)" })
        { request: $request, key: $p.key, path: $p.path, minor: $"($p.version_parts.major).($p.version_parts.minor)", cpython: ($p.implementation == "cpython" and $t == "") }
      }
    }
  }
}

# `--installed`: only the ones on this machine; `--managed`: only the ones uv
# installed itself, which are the ones it can uninstall or upgrade (their
# path is under `uv python dir`, 7 ms, memoised 1 h). The minor (`3.13`) is
# offered beside the full versions: it is what a request usually says.
def pythons [--installed, --managed]: nothing -> list<record> {
  let dir = (if $managed { nu-complete cache "uv:python-dir" 1hr { ^uv python dir | complete | get stdout | str trim } } else { "" })
  let rows = (python-rows | where {|p|
    if $managed { $p.path != null and ($p.path | str starts-with $dir) } else { (not $installed) or $p.path != null }
  })
  let full = ($rows | each {|p| { value: $p.request, description: (if $p.path == null { $"download · ($p.key)" } else { $"installed · ($p.path)" }), have: ($p.path != null) } }
    | sort-by have --reverse | uniq-by value | reject have)
  let minors = ($rows | where cpython | get minor | uniq | each {|m| { value: $m, description: $"the latest ($m)" } })
  $minors ++ $full
}

def tools []: nothing -> list<record> {
  nu-complete cache "uv:tools" 30sec {
    let r = (^uv tool list | complete)
    if $r.exit_code != 0 { [] } else {
      $r.stdout | lines | parse --regex '^(?<value>[A-Za-z0-9][\w.-]*) v(?<description>\S+)'
    }
  }
}

# The environment's packages, from the directory names pip keeps for them.
def venv-packages []: nothing -> list<record> {
  let root = (project-root)
  let venv = ($env.VIRTUAL_ENV? | default (if $root == null { null } else { $root | path join .venv }))
  if $venv == null or not ($venv | path exists) { return [] }
  nu-complete cache $"uv:venv:($venv)" 10sec {
    # Forward slashes: a backslash is an escape in a glob pattern.
    let v = ($venv | str replace -a '\' '/')
    glob $"($v)/{lib/python*,Lib}/site-packages/*.dist-info" | path basename
    | parse --regex '^(?<value>.+)-(?<description>[^-]+)\.dist-info$'
  }
}

# Nushell's own path completion for the token, to offer beside a spec's
# candidates (`uv run ⌶`: the project's scripts, then files).
def paths [ctx: record]: nothing -> list<record> {
  try { $ctx.partial | commandline complete --detailed --type path | reject -o span } catch { [] }
}

# ── Command surface: `uv <path> -h` ───────────────────────────────────────────

# Flags and nested commands of one command (clap layout; a description on the
# following lines is joined to its flag, `[possible values: …]` becomes the
# flag's enum). `-h`, not `--help`: the long form is paragraphs.
def help-of [path: list<string>]: nothing -> record<flags: list, commands: list> {
  nu-complete cache $"uv:help:($path | str join ' ')" 1hr {
    let r = (^uv ...$path -h | complete)
    let all = ($r.stdout + (char nl) + $r.stderr | lines)
    let blocks = ($all | reduce -f [] {|l, acc|
      if ($l =~ '^\s{2,6}-') { $acc ++ [$l] } else if ($l =~ '^\s{8,}\S') and ($acc | is-not-empty) {
        $acc | update (($acc | length) - 1) {|p| $p + "  " + ($l | str trim) }
      } else { $acc }
    })
    let flags = ($blocks
      | parse --regex '^\s+(?:(?<short>-[A-Za-z]),\s+)?(?<name>--?[\w-]+)(?:\.\.\.)?(?:[ =]\[?<(?<arg>[^>]+)>\]?(?:\.\.\.)?)?\s*(?<desc>.*)$'
      | uniq-by name
      | each {|f|
          let vals = ($f.desc | parse --regex '\[possible values: (?<v>[^\]]+)\]' | get -o 0.v | default "" | split row "," | str trim | where $it != "")
          let desc = ($f.desc | str replace --regex --all '\s*\[(possible values|default|env|aliases): [^\]]*\]' '' | str trim)
          { name: $f.name, short: $f.short, arg: $f.arg, values: $vals, description: $desc }
        })
    let start = ($all | enumerate | where item =~ '^Commands:' | get -o 0.index)
    let commands = if $start == null { [] } else {
      $all | skip ($start + 1) | take while {|l| $l !~ '^\s*$' }
      | parse --regex '^\s{2,4}(?<name>[\w-]+)\s{2,}(?<description>.*)$'
      | each {|c| $c | update description ($c.description | str replace --regex '\s*\[aliases: [^\]]*\]' '') }
    }
    { flags: $flags, commands: $commands }
  }
}

# What a valued flag wants, by its name; enums from help win.
def flag-source [f: record]: nothing -> any {
  if ($f.values | is-not-empty) { return $f.values }
  match $f.name {
    "--python" => {|ctx| pythons }
    "--extra" | "--no-extra" => {|ctx| extras }
    "--group" | "--no-group" | "--only-group" => {|ctx| groups }
    "--package" => {|ctx| let m = (members); if ($m | length) > 1 { $m } else { lock-packages } }
    "--upgrade-package" | "--reinstall-package" | "--refresh-package" | "--no-install-package" | "--no-emit-package" | "--no-binary-package" | "--no-build-package" | "--prune" => {|ctx| lock-packages }
    "--index" | "--default-index" => {|ctx| indexes }
    "--script" | "--env-file" | "--config-file" | "--output-file" | "--requirements" | "--with-requirements" | "--constraints" | "--overrides" | "--build-constraints" | "--excludes" | "--with-editable" => "files"
    "--directory" | "--project" | "--cache-dir" | "--out-dir" | "--install-dir" | "--target" | "--prefix" | "--find-links" => "directories"
    _ => null
  }
}

def flags-of [path: list<string>]: nothing -> list<record> {
  help-of $path | get flags | each {|f|
    let base = ({ name: $f.name, description: $f.description } | merge (if ($f.short | default "") == "" { {} } else { { short: $f.short } }))
    let src = (if ($f.arg | default "") == "" { null } else { flag-source $f })
    # A valued flag the spec has no source for still consumes the next token.
    if $src == null and ($f.arg | default "") != "" { $base | merge { arg: [] } } else if $src == null { $base } else { $base | merge { arg: $src } }
  }
}

# The positional plan: what each command's arguments are, by its path.
def positional-plan []: nothing -> record {
  {
    "run": { positionals: [ {|ctx| (scripts) ++ (paths $ctx) } ], rest: "files" }
    "init": { positionals: [ "directories" ] }
    "venv": { positionals: [ "directories" ] }
    "build": { positionals: [ "directories" ] }
    "publish": { rest: "files" }
    "format": { rest: "files" }
    # A package name is typed, or it is a registry lookup: nothing, not files.
    "add": { rest: [] }
    "remove": { rest: {|ctx| dependencies } }
    "version": { positionals: [ [] ] }
    "help": { rest: {|ctx| help-of [] | get commands | each {|c| { value: $c.name, description: $c.description } } } }
    "python install": { rest: {|ctx| pythons } }
    "python upgrade": { rest: {|ctx| pythons --managed } }
    "python uninstall": { rest: {|ctx| pythons --managed } }
    "python pin": { positionals: [ {|ctx| pythons } ] }
    "python find": { positionals: [ {|ctx| pythons --installed } ] }
    "tool install": { positionals: [ [] ] }
    "tool run": { positionals: [ {|ctx| tools } ], rest: "files" }
    "tool upgrade": { rest: {|ctx| tools } }
    "tool uninstall": { rest: {|ctx| tools } }
    "pip install": { rest: [] }
    "pip uninstall": { rest: {|ctx| venv-packages } }
    "pip show": { rest: {|ctx| venv-packages } }
    "pip compile": { rest: "files" }
    "pip sync": { rest: "files" }
    "cache clean": { rest: {|ctx| lock-packages } }
  }
}

# One node for `uv <path>`: its flags from its own help, lazily, and what its
# positionals are. `ahead` is what was typed after it: the help is read — and
# the nested commands become nodes — only along the path being typed, so
# `uv ⌶` costs one `uv -h` and `uv python install ⌶` three.
def node-for [path: list<string>, description: string, ahead: list<string>, deep: bool]: nothing -> record {
  let base = ({ description: $description, flags: {|| flags-of $path } } | merge ((positional-plan) | get -o ($path | str join " ") | default {}))
  if not $deep { return $base }
  let nested = (help-of $path | get commands)
  if ($nested | is-empty) { return $base }
  $base | merge { subcommands: ($nested | reduce -f {} {|c, acc|
    let at = ($ahead | enumerate | where item == $c.name | get -o 0.index)
    $acc | upsert $c.name (node-for ($path ++ [$c.name]) $c.description (if $at == null { [] } else { $ahead | skip ($at + 1) }) ($at != null))
  }) }
}

# ── The spec ──────────────────────────────────────────────────────────────────

# `spans` is the command as typed (`[uv, python, install, ""]`): the words
# before the one under the cursor say which nodes need their help read.
export def "nu-complete uv spec" [spans: list<string> = []]: nothing -> record {
  let ahead = ($spans | skip 1 | drop 1 | where {|w| not ($w | str starts-with "-") })
  node-for [] "An extremely fast Python package manager" $ahead true
  | merge { fallback: "external" }
}

def complete-uv [place: record] {
  try { nu-complete run (nu-complete uv spec $place.command) $place.command } catch { null }
}

# `main` so that `use uv.nu *` yields `uv`.
@complete "complete-uv"
export extern main [...args]
