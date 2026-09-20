# wezterm — one line in the user's wezterm.lua, and one file the distro owns
#
# The same arrangement as ghostty.nu, in Lua: our settings live in a file of
# our own next to the user's config, and their config applies it with one line.
#
#   <wezterm dir>/nustro.lua     ours, rewritten whole by `wezterm set`
#   pcall(function() dofile(require("wezterm").config_dir .. "/nustro.lua").apply(config) end)
#                                one line put into theirs, once, before its final `return`
#
# Lua has no "include", and nothing can follow `return` in a chunk, so the
# line cannot be appended the way Ghostty's `config-file =` is: it goes in
# front of the last `return <name>` line, and `<name>` is whatever their file
# returns (`config` from `wezterm.config_builder()` nearly always). A file
# that ends some other way is not edited; the line is printed to add by hand.
# When there is no config at all — a fresh Windows machine — one is written.
#
# Verified against WezTerm 20240203-110809 on macOS, 2026-09-20, with
# XDG_CONFIG_HOME pointed at a scratch directory:
#
#   * `wezterm.config_dir` is the directory of the config that WAS loaded —
#     ~/.config/wezterm for wezterm.lua there, ~ for ~/.wezterm.lua — so the
#     `dofile` line above finds our file in either layout. `require("nustro")`
#     would not: package.path holds ~/.config/wezterm and ~/.wezterm, never the
#     home directory.
#   * `pcall` makes a missing nustro.lua a silent no-op, so deleting our file
#     is a complete uninstall even with the line still in place — the `?` of
#     Ghostty's include.
#   * WezTerm watches its config and reloads on every write, in every open
#     window, on every platform: a rewritten nustro.lua recoloured a running
#     window with nothing else done. So `wezterm reload` is a fact, not an act.
#   * A config error (a syntax error, an unknown key through config_builder,
#     a color_scheme that does not exist) is an ` ERROR ` line on stderr from
#     any CLI verb that loads the config, and the exit code stays 0. `validate`
#     runs `ls-fonts` for that reason and reads stderr; 50 ms.
#   * `color_scheme_dirs` takes a directory of `<name>.toml` scheme files,
#     `[metadata] name` naming each, and `color_scheme = <name>` selects one.
#     Our theme files go under the state dir, like Ghostty's.
#   * `--config key=value` on the command line overrides the files for that
#     process only: `wezterm --config 'font=wezterm.font("X")' ls-fonts` names
#     the face X resolves to, or warns "Unable to load a font" and names the
#     built-in JetBrains Mono. `+show-face`, in other words.
#   * `default_prog = { <nu>, "-l" }` starts nu; a bare path gives no login
#     shell (`$nu.is-login` was false), unlike Ghostty's `command`, which goes
#     through `login -flp`.
#   * Every OSC the theme painter uses — 4, 10, 11, 12, 17, 19 and their resets
#     104, 110, 111, 112, 117, 119 — sets and queries back correctly.

const OURS = "nustro.lua"
const MARK = "-- Added by Nustro; `wezterm reset` removes it again."
# `<name>` is replaced by whatever the user's file returns.
const INCLUDE_RE = '^\s*pcall\(function\(\) dofile\(require\("wezterm"\)\.config_dir \.\. "/nustro\.lua"\)\.apply\((?<name>[A-Za-z_][A-Za-z0-9_]*)\) end\)\s*$'
def include-line [name: string]: nothing -> string {
  $"pcall\(function\(\) dofile\(require\(\"wezterm\"\).config_dir .. \"/nustro.lua\"\).apply\(($name)\) end\)"
}
# The keys our file may hold, and how each is rendered. `font_family` is our
# own name: WezTerm's key is `font` and its value a `wezterm.font(...)` call,
# which is what the renderer writes and the parser reads back.
const LUA_HEADER = [
  "-- Written by Nustro (`wezterm set`), which owns this file and"
  "-- rewrites it whole, so put your own settings in wezterm.lua, not here —"
  "-- it is applied from there by one line, after your own, so only the keys"
  "-- below are taken out of your hands. `wezterm reset` undoes the whole"
  "-- arrangement."
  "local wezterm = require 'wezterm'"
  "local M = {}"
  "M.settings = {"
]
const LUA_FOOTER = [
  "}"
  "function M.apply(config)"
  "  for k, v in pairs(M.settings) do config[k] = v end"
  "end"
  "return M"
]

# The WezTerm binary, wherever it is; null when there is none.
#
# Homebrew links `wezterm` into /opt/homebrew/bin, the Windows installer puts
# its directory on PATH, and inside a WezTerm window WEZTERM_EXECUTABLE_DIR
# names it regardless. The app bundle and Program Files are the fallbacks for
# an install that put nothing on PATH.
export def wezterm-bin []: nothing -> any {
  let onpath = (which wezterm | get -o 0.path)
  if $onpath != null { return $onpath }
  let exe = (if $nu.os-info.name == "windows" { "wezterm.exe" } else { "wezterm" })
  [$env.WEZTERM_EXECUTABLE_DIR?
   "/Applications/WezTerm.app/Contents/MacOS"
   ($nu.home-dir | path join Applications "WezTerm.app" Contents MacOS)
   ($env.ProgramFiles? | default "" | path join WezTerm)]
  | compact | where {|d| $d | is-not-empty }
  | each {|d| $d | path join $exe }
  | where {|p| $p | path exists }
  | get -o 0
}

# The XDG config dir, on every platform: WezTerm reads ~/.config/wezterm on
# Windows too (HOME being the profile directory), and it is the directory a
# dotfiles repo manages.
def xdg-dir []: nothing -> path {
  $env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join ".config") | path join wezterm
}

# Every file WezTerm would read, highest priority first. Inside a WezTerm
# window WEZTERM_CONFIG_FILE names the one it did read, which beats guessing.
def candidates []: nothing -> list<path> {
  [$env.WEZTERM_CONFIG_FILE? (xdg-dir | path join wezterm.lua) ($nu.home-dir | path join .wezterm.lua)]
  | compact | where {|p| $p | is-not-empty } | uniq
}

# The config WezTerm reads: the first candidate that exists and is not empty.
# When there is none we write the XDG one, which WezTerm looks at before
# ~/.wezterm.lua.
export def "wezterm config-path" []: nothing -> path {
  let found = (candidates | where {|p| ($p | path exists) and (($p | path type) == file) and ((ls -l $p | get 0.size) > 0b) })
  if ($found | is-empty) { xdg-dir | path join wezterm.lua } else { $found | first }
}

def ours-path []: nothing -> path {
  wezterm config-path | path dirname | path join $OURS
}

# ── our file ──────────────────────────────────────────────────────────────────

# One Lua value. Strings are quoted with backslashes and quotes escaped — a
# Windows path holds backslashes — lists become `{ "a", "b" }`, numbers and
# booleans are themselves.
def lua-value [v: any]: nothing -> string {
  match ($v | describe -d | get type) {
    "string" => ($v | to json)   # JSON's escaping is Lua's for a path or a name
    "list" => ("{ " + ($v | each {|x| lua-value $x } | str join ", ") + " }")
    "bool" => ($v | into string)
    _ => ($v | into string)
  }
}

# The settings the distro currently owns. Our file is ours alone and every
# line of the table is one `key = value,`, so reading it back is a regex.
export def "wezterm settings" []: nothing -> record {
  let f = (ours-path)
  if not ($f | path exists) { return {} }
  open --raw $f
  | lines
  | parse -r '^  (?<key>[a-z_]+) = (?<value>.*),$'
  | reduce -f {} {|it, acc|
      let v = ($it.value | str trim)
      let parsed = (
        if $v =~ '^wezterm\.font\(' { { font_family: ($v | parse -r '^wezterm\.font\((?<s>".*")\)$' | get -o 0.s | default '""' | from json) } }
        else if $v =~ '^\{' { { ($it.key): ($v | str trim -c '{' | str trim -c '}' | str trim | split row ", " | where {|s| $s | is-not-empty } | each {|s| $s | from json }) } }
        else if $v =~ '^"' { { ($it.key): ($v | from json) } }
        else if $v in ["true" "false"] { { ($it.key): ($v == "true") } }
        else if $v =~ '^-?\d+$' { { ($it.key): ($v | into int) } }
        else { { ($it.key): ($v | into float) } }
      )
      $acc | merge $parsed
    }
}

# Write settings into our file and make sure the user's config applies it.
# A null value drops the key. Nothing else in their config is changed.
export def "wezterm set" [
  settings: record   # e.g. { color_scheme: "nustro-onedark", font_family: "Hack Nerd Font" } — null removes a key
]: nothing -> nothing {
  let merged = (wezterm settings | merge $settings | transpose key value | where value != null | sort-by key)
  let body = (
    $LUA_HEADER
    ++ ($merged | each {|s|
        if $s.key == "font_family" { $"  font = wezterm.font\((lua-value $s.value)\)," } else { $"  ($s.key) = (lua-value $s.value)," }
      })
    ++ $LUA_FOOTER ++ [""]
  )
  let f = (ours-path)
  let before = (if ($f | path exists) { open --raw $f } else { null })
  mkdir ($f | path dirname)
  $body | str join (char nl) | save -f $f
  link

  # WezTerm is the judge of its own configuration: a scheme it cannot find or
  # a key config_builder rejects is an ERROR line when any verb loads it. Put
  # the file back rather than leave a broken include behind.
  let check = (validate)
  if not $check.ok {
    if $before == null { rm $f } else { $before | save -f $f }
    error make { msg: "WezTerm rejected that configuration", label: { text: $check.err, span: (metadata $settings).span } }
  }
}

# Remove everything the distro put in WezTerm's configuration: our file, and
# the two lines in theirs. The backup of their config is left in place.
export def "wezterm reset" []: nothing -> nothing {
  let cfg = (wezterm config-path)
  let f = (ours-path)
  if ($f | path exists) { rm $f; print $"removed ($f)" }
  if ($cfg | path exists) and (includes? $cfg) {
    open --raw $cfg
    | lines
    | where {|l| not (($l | str trim) == $MARK or ($l =~ $INCLUDE_RE)) }
    | str join (char nl)
    | $in + (char nl)
    | save -f $cfg
    print $"removed the two lines from ($cfg)"
  }
  print "WezTerm reloads its configuration by itself; every window shows its own again"
}

# Where things stand.
export def "wezterm status" []: nothing -> record {
  let cfg = (wezterm config-path)
  {
    installed: ((wezterm-bin) != null)
    config: $cfg
    config_exists: ($cfg | path exists)
    also_present: (candidates | where {|p| $p != $cfg and ($p | path exists) })
    ours: (ours-path)
    included: (if ($cfg | path exists) { includes? $cfg } else { false })
    settings: (wezterm settings)
    live_theme: (wezterm live color_scheme)
    shell: (wezterm live default_prog)
  }
}

# ── the shell ─────────────────────────────────────────────────────────────────

# Make Nushell what a new WezTerm window starts, or hand that back. `-l`,
# because WezTerm runs the program as it is — no `login` in between, so a
# bare path gave `$nu.is-login == false` (verified 2026-09-20) — and a login
# nu is what a terminal window should hold.
export def "wezterm shell" [
  nu_path?: path     # the nu to start — `terminal nu-path` for the one on PATH
  --reset            # drop our `default_prog`, so WezTerm starts the platform's shell again
]: nothing -> nothing {
  if $reset {
    wezterm set { default_prog: null }
  } else {
    if $nu_path == null { error make { msg: "wezterm shell <path to nu> — `terminal shell` finds it" } }
    wezterm set { default_prog: [($nu_path | into string) "-l"] }
  }
  let now = (wezterm live default_prog)
  print (if $now == null { "new WezTerm windows start its own default shell" } else { $"new WezTerm windows start ($now | str join ' ')" })
}

# WezTerm watches its config file and reloads every open window when it
# changes, on every platform, so a write has already reached them by the
# time this is asked. True, then, whenever WezTerm is installed at all.
export def "wezterm reload" []: nothing -> bool {
  (wezterm-bin) != null
}

# What one key resolves to. WezTerm has no `show-config`, so for the keys we
# own this is our file; `font_family` is the one thing it can be asked about
# — `ls-fonts` names the face the loaded configuration resolves to, the
# user's own `font` included. 116 ms.
export def "wezterm live" [key: string]: nothing -> any {
  if $key == "font_family" { return (primary-font) }
  wezterm settings | get -o $key
}

# The face a family resolves to when it is the only thing configured — the
# family itself when it is installed, WezTerm's built-in "JetBrains Mono"
# when it is not (and a warning on stderr, which is dropped). Null when
# WezTerm is not installed. 50 ms.
export def "wezterm face" [family: string]: nothing -> any {
  let w = (wezterm-bin)
  if $w == null { return null }
  let r = (^$w --config $"font=wezterm.font\(($family | to json)\)" ls-fonts | complete)
  $r.stdout | parse-primary
}

def primary-font []: nothing -> any {
  let w = (wezterm-bin)
  if $w == null { return null }
  let r = (^$w --config-file (wezterm config-path) ls-fonts | complete)
  $r.stdout | parse-primary
}

# `ls-fonts` prints the primary font as a `wezterm.font_with_fallback({ ... })`
# block whose first quoted entry is the family that resolved.
def parse-primary []: string -> any {
  $in
  | lines
  | skip until {|l| $l starts-with "Primary font:" }
  | skip 1
  | where {|l| ($l | str trim) starts-with '"' }
  | get -o 0
  | default null
  | if $in == null { null } else { $in | str trim | str trim -c ',' | from json }
}

# Open a new window in a font, running a program — the font preview. The
# same `--config` override `face` uses, so what the window shows is what a
# `font_family` in our file would. Nothing is written.
export def "wezterm preview" [family: string, size: number, argv: list<string>]: nothing -> nothing {
  let w = (wezterm-bin)
  if $w == null { error make { msg: "wezterm is not installed — `terminal install wezterm`" } }
  ^$w --config $"font=wezterm.font\(($family | to json)\)" --config $"font_size=($size)" --config "initial_cols=78" --config "initial_rows=16" start --always-new-process -- ...$argv
}

# The keys `font use` and `font size` write, in this terminal's vocabulary.
export def "wezterm font-keys" [family?: string, size?: number]: nothing -> record {
  { font_family: $family, font_size: $size }
}

# ── internals ─────────────────────────────────────────────────────────────────

def includes? [cfg: path]: nothing -> bool {
  open --raw $cfg | lines | any {|l| $l =~ $INCLUDE_RE }
}

# Put the line into their config, once, before its final `return <name>`,
# after backing the file up. Creating the config when there is none is part
# of the job: a machine that has never had one still gets the theme.
def link []: nothing -> nothing {
  let cfg = (wezterm config-path)
  if not ($cfg | path exists) {
    mkdir ($cfg | path dirname)
    [
      "-- WezTerm configuration. https://wezterm.org/config/files.html"
      $"-- The two lines before `return` pull in ($OURS), which `nu-config` writes."
      "local wezterm = require 'wezterm'"
      "local config = wezterm.config_builder()"
      ""
      $MARK
      (include-line "config")
      "return config"
      ""
    ] | str join (char nl) | save -f $cfg
    print $"created ($cfg)"
    return
  }
  if (includes? $cfg) { return }
  let lines = (open --raw $cfg | lines)
  # The last line that is not blank has to be `return <name>`.
  let last = ($lines | enumerate | where {|l| $l.item | str trim | is-not-empty } | last)
  let name = ($last.item | parse -r '^\s*return\s+(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*$' | get -o 0.name)
  if $name == null {
    error make { msg: $"($cfg) does not end with `return <name>`, so the line that applies ($OURS) cannot be placed", help: $"add this before whatever it returns, with the returned table's name in place of `config`:\n  (include-line 'config')" }
  }
  let backup = $"($cfg).backup-(date now | format date '%Y%m%d-%H%M%S')"
  cp $cfg $backup
  ($lines | take $last.index) ++ [$MARK (include-line $name)] ++ ($lines | skip $last.index)
  | str join (char nl) | $in + (char nl)
  | save -f $cfg
  print $"($cfg | path basename) now applies ($OURS) — backup at ($backup | path basename)"
}

# Load the whole chain the way WezTerm will and read its complaints. Silent
# when WezTerm is not installed: a theme can be chosen before the terminal
# is there.
def validate []: nothing -> record<ok: bool, err: string> {
  let w = (wezterm-bin)
  if $w == null { return { ok: true, err: "" } }
  let r = (^$w --config-file (wezterm config-path) ls-fonts | complete)
  let errors = ($r.stderr | lines | where {|l| $l =~ ' ERROR ' } | each {|l| $l | str replace -r '^.*? ERROR +\S+ > ' '' } | uniq)
  { ok: ($errors | is-empty), err: ($errors | str join (char nl)) }
}
