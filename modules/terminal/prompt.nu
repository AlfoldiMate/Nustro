# prompt — the prompt's shape: a style and a handful of options, generated for starship
#
#   terminal prompt                       the style, and every option with its value and its default
#   terminal prompt use <style>           powerline | plain | off
#   terminal prompt set <option> <value>  one option: `icons false`, `time right`, `git off`
#   terminal prompt reset [option …]      those options back to their defaults; none named: the shipped prompt
#   terminal prompt preview [style]       the styles as they would look here, nothing written
#
# The colours are the theme's (palette.nu): a style is written in ROLES, like
# every template in themes/, so `terminal theme use` recolours whichever style
# is in use. What this file adds is the shape. themes/starship.toml is one
# shape, and "copy it and edit the copy" was the only way to drop the clock or
# live without a Nerd Font; a style and its options are GENERATED instead —
# the format string of a powerline prompt cannot be edited by option, because
# each separator is painted in the colours of both its neighbours.
#
#   powerline   the shipped look: tinted segments joined by separators
#   plain       the same segments in the same hues as coloured text, no surfaces
#   off         no prompt: only Nushell's indicator of the vi mode
#
# `terminal prompt config powerline <defaults>` IS themes/starship.toml — a test
# holds the two equal — so the file stays what a shell reads before the first
# render and what someone copies to write a prompt by hand. A copy in your
# themes/ still wins, and then `use` and `set` say so instead of writing
# something that would not be read.
#
# State is <your dir>/.state/theme/prompt.nuon: the style and the options that
# differ from their defaults, read by conf/prompt.nu at startup (`off`,
# `transient`) and by the render here. Next to theme.nuon because the two are
# rendered into the same starship.toml.

use theme.nu ["terminal theme state-dir"]

const DISTRO_ROOT = (path self | path dirname | path dirname | path dirname)
const SHIPPED = ($DISTRO_ROOT | path join themes starship.toml)

const STYLES = [powerline plain off]

# Every option. `values: null` is a whole number, zero or more.
const OPTIONS = [
  [name default values about];
  [icons      true   [true false]             "Nerd Font symbols; false writes words and no separators, for a font without them"]
  [separator  arrow  [arrow round slant flat] "powerline: the shape between two segments"]
  [lines      2      [1 2]                    "2: you type on a line of your own; 1: after the segments"]
  [newline    true   [true false]             "a blank line before each prompt"]
  [transient  false  [false true compact]     "a prompt that has run collapses to a single mark, so scrollback is commands and output; compact: no blank line between them"]
  [depth      3      null                     "how many directories of the path are shown; 0 for all of it"]
  [os         left   [left right off]         "segment: the operating system's icon"]
  [user       left   [left right off]         "segment: the user name"]
  [directory  left   [left right off]         "segment: the path"]
  [git        left   [left right off]         "segment: the branch and its status"]
  [languages  left   [left right off]         "segment: the toolchain of the project you are in, with its version"]
  [env        left   [left right off]         "segment: the conda environment"]
  [time       left   [left right off]         "segment: the clock"]
  [duration   left   [left right off]         "segment: how long the last command took"]
]

# The segments in the order they are drawn, each with its hue — the tint_ role
# behind it in powerline, the text_ role it is written in in plain — and the
# starship modules it stands for. `duration` is not here: it has no surface,
# it trails the left side or leads the right one.
const SEGMENTS = [
  [name hue vars];
  [os         red         '$os']
  [user       red         '$username']
  [directory  orange      '$directory']
  [git        yellow      '$git_branch$git_status']
  [languages  green       '$c$rust$golang$nodejs$php$java$kotlin$haskell$python']
  [env        teal        '$conda']
  [time       accent_alt  '$time']
]

# Powerline glyphs (U+E0B0…, in every Nerd Font). `lead` opens the left side,
# `between` joins two segments, `end` closes it; `left` is the mirror image,
# which opens every segment on the right side.
const SEPARATORS = {
  arrow: { lead: "\u{e0b6}", between: "\u{e0b0}", end: "\u{e0b4}", left: "\u{e0b2}" }
  round: { lead: "\u{e0b6}", between: "\u{e0b4}", end: "\u{e0b4}", left: "\u{e0b6}" }
  slant: { lead: "\u{e0ba}", between: "\u{e0bc}", end: "\u{e0bc}", left: "\u{e0ba}" }
  flat:  { lead: "", between: "", end: "", left: "" }
}

# A toolchain's starship module, its Nerd Font symbol, and the word that
# stands in for it without one.
const LANGUAGES = [
  [module symbol word];
  [c        "\u{e61e} " c]
  [rust     "\u{e7a8}"  rust]
  [golang   "\u{e627}"  go]
  [nodejs   "\u{e718}"  node]
  [php      "\u{e608}"  php]
  [java     "\u{e256} " java]
  [kotlin   "\u{e634}"  kotlin]
  [haskell  "\u{e61f}"  haskell]
  [python   "\u{e606}"  python]
]

const OS_SYMBOLS = {
  Windows: "\u{e70f}", Ubuntu: "\u{f0548}", SUSE: "\u{f314}", Raspbian: "\u{f043f}", Mint: "\u{f08ed}"
  Macos: "\u{f0035}", Manjaro: "\u{f312}", Linux: "\u{f033d}", Gentoo: "\u{f08e8}", Fedora: "\u{f08db}"
  Alpine: "\u{f300}", Amazon: "\u{f270}", Android: "\u{e70e}", AOSC: "\u{f301}", Arch: "\u{f08c7}"
  Artix: "\u{f08c7}", CentOS: "\u{f304}", Debian: "\u{f08da}", Redhat: "\u{f111b}", RedHatEnterprise: "\u{f111b}"
}

const DIRECTORY_ICONS = {
  Documents: "\u{f0219} ", Downloads: "\u{f019} ", Music: "\u{f075a} ", Pictures: "\u{f03e} ", Developer: "\u{f0c8b} "
}

# The mark is empty on purpose: Nushell's own indicators (conf/prompt.nu) are
# drawn after the prompt and say which vi mode the line is in.
const CHARACTER = {
  disabled: false
  success_symbol: "[](bold fg:text_green)"
  error_symbol: "[](bold fg:text_red)"
  vimcmd_symbol: "[\u{276e}](bold fg:text_green)"
  vimcmd_replace_one_symbol: "[\u{276e}](bold fg:text_accent_alt)"
  vimcmd_replace_symbol: "[\u{276e}](bold fg:text_accent_alt)"
  vimcmd_visual_symbol: "[\u{276e}](bold fg:text_yellow)"
}

# ── State ─────────────────────────────────────────────────────────────────────

def state-file []: nothing -> path { terminal theme state-dir | path join prompt.nuon }

def defaults []: nothing -> record {
  $OPTIONS | reduce -f {} {|o, acc| $acc | insert $o.name $o.default }
}

# A starship.toml of the user's own in their themes/: it is the prompt, and no
# style is generated over it.
def user-template []: nothing -> any {
  let f = ($nu.config-path | path dirname | path join themes starship.toml)
  if ($f | path exists) { $f } else { null }
}

# The style and every option, the saved ones over the defaults. An option the
# file holds and this version does not know is dropped rather than an error.
export def "terminal prompt state" []: nothing -> record {
  let f = (state-file)
  let saved = (if ($f | path exists) { open $f } else { {} })
  let known = ($OPTIONS | get name)
  let kept = ($saved | get -o options | default {} | transpose k v | where k in $known | reduce -f {} {|it, acc| $acc | insert $it.k $it.v })
  let style = ($saved | get -o style | default powerline)
  { style: (if $style in $STYLES { $style } else { "powerline" }), options: (defaults | merge $kept) }
}

# Only what differs from the defaults is written, so a default that changes
# in a later version reaches a prompt that never set it.
def save-state [style: string, options: record]: nothing -> nothing {
  let d = (defaults)
  let changed = ($options | transpose k v | where {|r| $r.v != ($d | get $r.k) } | reduce -f {} {|it, acc| $acc | insert $it.k $it.v })
  mkdir (terminal theme state-dir)
  { style: $style, options: $changed } | to nuon --indent 2 | save -f (state-file)
}

# ── The generator ─────────────────────────────────────────────────────────────

def styled [glyph: string, style: string]: nothing -> string {
  if ($glyph | is-empty) { "" } else { $"[($glyph)]\(($style)\)" }
}

# A connecting word, for a prompt without icons: `on main`, `via rust`.
def word [w: string, on: bool]: nothing -> string {
  if $on { '[' + $w + ' ](fg:fg_muted)' } else { "" }
}

# The segments drawn on one side, in order.
def on-side [o: record, side: string]: nothing -> table {
  $SEGMENTS | where {|s| ($o | get $s.name) == $side }
}

# Neighbours of one hue are one surface: `os` and `user` share the red one.
def runs [segs: table]: nothing -> table {
  $segs | reduce -f [] {|s, acc|
    if ($acc | is-not-empty) and ($acc | last | get hue) == $s.hue {
      $acc | drop | append { hue: $s.hue, vars: (($acc | last | get vars) + $s.vars) }
    } else {
      $acc | append { hue: $s.hue, vars: $s.vars }
    }
  }
}

# The left side: a lead, the surfaces joined by a separator painted in the
# colours of both, an end. Without glyphs the surfaces simply meet.
def powerline-left [segs: table, sep: record]: nothing -> string {
  let r = (runs $segs)
  if ($r | is-empty) { return "" }
  let last = (($r | length) - 1)
  let body = ($r | enumerate | each {|it|
    let join = (if $it.index == $last { "" } else { styled $sep.between $"fg:tint_($it.item.hue) bg:tint_($r | get ($it.index + 1) | get hue)" })
    $it.item.vars + $join
  } | str join)
  let end = (if ($sep.end | is-empty) { " " } else { styled $"($sep.end) " $"fg:tint_($r | last | get hue)" })
  (styled $sep.lead $"fg:tint_($r.0.hue)") + $body + $end
}

# The right side is the mirror: every surface is opened from its left and the
# last one runs to the edge of the window.
def powerline-right [segs: table, sep: record]: nothing -> string {
  let r = (runs $segs)
  $r | enumerate | each {|it|
    let over = (if $it.index == 0 { "" } else { $" bg:tint_($r | get ($it.index - 1) | get hue)" })
    (styled $sep.left $"fg:tint_($it.item.hue)($over)") + $it.item.vars
  } | str join
}

# `os` and `user` sit flush against the lead where the shipped prompt has
# them; on the right, or with no lead, they are padded like every other segment.
def tight [o: record, side: string]: nothing -> bool {
  $side == left and $o.separator != flat
}

def powerline-modules [o: record]: nothing -> record {
  let both = ($o.os != off and $o.os == $o.user)
  let languages = ($LANGUAGES | reduce -f {} {|l, acc|
    let extra = (if $l.module == python { '(\(#$virtualenv\))' } else { "" })
    $acc | insert $l.module {
      symbol: (if $o.icons { $l.symbol } else { $l.word })
      style: "bg:tint_green"
      format: ('[[ $symbol( $version)' + $extra + ' ](fg:on_tint bg:tint_green)]($style)')
    }
  })
  {
    os: ({ disabled: false, style: "bg:tint_red fg:on_tint", symbols: $OS_SYMBOLS }
      | merge (if (tight $o $o.os) { {} } else { { format: (if $both { '[ $symbol]($style)' } else { '[ $symbol ]($style)' }) } }))
    username: {
      show_always: true
      style_user: "bg:tint_red fg:on_tint"
      style_root: "bg:tint_red fg:on_tint"
      format: (if (tight $o $o.user) { if $both { '[ $user]($style)' } else { '[$user]($style)' } } else { '[ $user ]($style)' })
    }
    directory: ({
      style: "bg:tint_orange fg:on_tint"
      format: '[ $path ]($style)'
      truncation_length: $o.depth
      truncation_symbol: "\u{2026}/"
    } | merge (if $o.icons { { substitutions: $DIRECTORY_ICONS } } else { {} }))
    git_branch: {
      symbol: (if $o.icons { "\u{f418}" } else { "" })
      style: "bg:tint_yellow"
      format: (if $o.icons { '[[ $symbol $branch ](fg:on_tint bg:tint_yellow)]($style)' } else { '[[ $branch ](fg:on_tint bg:tint_yellow)]($style)' })
    }
    git_status: { style: "bg:tint_yellow", format: '[[($all_status$ahead_behind )](fg:on_tint bg:tint_yellow)]($style)' }
    conda: {
      symbol: (if $o.icons { " \u{f10c} " } else { " conda " })
      style: "fg:on_tint bg:tint_teal"
      format: '[$symbol$environment ]($style)'
      ignore_base: false
    }
    time: {
      disabled: false
      time_format: "%R"
      style: "bg:tint_accent_alt"
      format: (if $o.icons { "[[ \u{f43a} $time ](fg:on_tint bg:tint_accent_alt)]($style)" } else { '[[ $time ](fg:on_tint bg:tint_accent_alt)]($style)' })
    }
    cmd_duration: {
      show_milliseconds: true
      format: (if $o.icons { "\u{eaf4} in $duration " } else { "took $duration " })
      style: "bg:tint_accent_alt"
      disabled: false
      show_notifications: false
      min_time_to_notify: 45000
    }
  } | merge $languages
}

# The same segments as text: each in the text_ role of its hue, which reads on
# the background of a light theme too (palette.nu), the path in bold.
def plain-modules [o: record]: nothing -> record {
  let words = (not $o.icons)
  let languages = ($LANGUAGES | reduce -f {} {|l, acc|
    let extra = (if $l.module == python { '( \($virtualenv\))' } else { "" })
    $acc | insert $l.module {
      symbol: (if $o.icons { $l.symbol } else { $l.word })
      style: "fg:text_green"
      format: ((word "via" $words) + '[$symbol( $version)' + $extra + ' ]($style)')
    }
  })
  {
    os: { disabled: false, style: "fg:text_red", format: '[$symbol ]($style)', symbols: $OS_SYMBOLS }
    username: { show_always: true, style_user: "fg:text_red", style_root: "bold fg:text_red", format: '[$user ]($style)' }
    directory: ({
      style: "bold fg:text_orange"
      format: ((word "in" ($words and $o.user != off and $o.user == $o.directory)) + '[$path ]($style)')
      truncation_length: $o.depth
      truncation_symbol: "\u{2026}/"
    } | merge (if $o.icons { { substitutions: $DIRECTORY_ICONS } } else { {} }))
    git_branch: {
      symbol: (if $o.icons { "\u{f418}" } else { "" })
      style: "fg:text_yellow"
      format: (if $o.icons { '[$symbol $branch ]($style)' } else { (word "on" true) + '[$branch ]($style)' })
    }
    git_status: { style: "fg:text_yellow", format: '[($all_status$ahead_behind )]($style)' }
    conda: {
      symbol: (if $o.icons { "\u{f10c} " } else { "conda " })
      style: "fg:text_teal"
      format: ((word "via" $words) + '[$symbol$environment ]($style)')
      ignore_base: false
    }
    time: {
      disabled: false
      time_format: "%R"
      style: "fg:text_accent_alt"
      format: (if $o.icons { "[\u{f43a} $time ]($style)" } else { (word "at" true) + '[$time ]($style)' })
    }
    cmd_duration: {
      show_milliseconds: true
      format: (if $o.icons { "[\u{eaf4} $duration ]($style)" } else { (word "took" true) + '[$duration ]($style)' })
      style: "fg:fg_muted"
      disabled: false
      show_notifications: false
      min_time_to_notify: 45000
    }
  } | merge $languages
}

# A style and a full set of options as starship's configuration, written in
# roles and without the palette block (`terminal prompt render` adds it).
# Without icons there is no glyph to draw the OS or a separator with, so `os`
# is off — its table of symbols left out with it — and the separator flat,
# whatever the options say.
export def "terminal prompt config" [style: string, options: record]: nothing -> record {
  let o = (if $options.icons { $options } else { $options | merge { os: off, separator: flat } })
  let left = (on-side $o left)
  let right = (on-side $o right)
  let sides = (if $style == plain {
    { left: ($left | get vars | str join), right: ($right | get vars | str join) }
  } else {
    let sep = ($SEPARATORS | get $o.separator)
    { left: (powerline-left $left $sep), right: (powerline-right $right $sep) }
  })
  let first = ($sides.left + (if $o.duration == left { '$cmd_duration' } else { "" }))
  let format = ($first + (if $o.lines == 2 and ($first | is-not-empty) { '$line_break' } else { "" }) + '$character')
  let right_format = ((if $o.duration == right { '$cmd_duration' } else { "" }) + $sides.right)
  {
    "$schema": "https://starship.rs/config-schema.json"
    format: $format
    palette: "distro"
    line_break: { disabled: false }
    character: $CHARACTER
  }
  | merge (if ($right_format | is-empty) { {} } else { { right_format: $right_format } })
  | merge (if $o.newline { {} } else { { add_newline: false } })
  | merge (if $style == plain { plain-modules $o } else { powerline-modules $o })
  | if $o.icons { $in } else { $in | reject os }
}

# ── Rendering ─────────────────────────────────────────────────────────────────

# The palette block to render with when the caller has none: the one in the
# file rendered last, else the shipped template's, which is the ANSI tier.
def current-palette []: nothing -> record {
  let rendered = (terminal theme state-dir | path join starship.toml)
  let from = (if ($rendered | path exists) { $rendered } else { $SHIPPED })
  open --raw $from | from toml | get -o palettes.distro | default (open --raw $SHIPPED | from toml | get palettes.distro)
}

def with-palette [palette: record]: record -> string {
  upsert palette "distro" | upsert palettes { distro: $palette } | to toml
}

# starship's configuration as the text of the rendered file: the style in use
# — or your own themes/starship.toml, which wins — with `[palettes.distro]`
# filled in. Through `from toml`/`to toml` rather than text, so the block is
# replaced whole whatever a hand-written template did with whitespace;
# comments do not survive, which is fine for a rendered file. `off` renders
# the powerline, so the file stays one starship can read.
export def "terminal prompt render" [
  palette?: record   # roles in starship's spellings (`terminal theme starship-palette`); the last render's when omitted
]: nothing -> string {
  let pal = ($palette | default (current-palette))
  let yours = (user-template)
  if $yours != null { return (open --raw $yours | from toml | with-palette $pal) }
  let s = (terminal prompt state)
  terminal prompt config (if $s.style == off { "powerline" } else { $s.style }) $s.options | with-palette $pal
}

def write-rendered []: nothing -> nothing {
  if (which starship | is-empty) { return }
  mkdir (terminal theme state-dir)
  terminal prompt render | save -f (terminal theme state-dir | path join starship.toml)
}

# Make the saved state this session's: what conf/prompt.nu does at startup,
# with the starship prompt it left in NUSTRO_PROMPTS. False when a style was
# asked for and there is no such prompt — no starship when the shell
# started — and the next shell reads the state instead.
export def --env "terminal prompt apply" []: nothing -> bool {
  let s = (terminal prompt state)
  # The mark is written in the theme's green as it stands now, under a blank
  # line of its own unless `compact`: the one before the prompt is part of
  # what gets redrawn, and without it the blocks close up. Not with `off`:
  # there is no prompt to collapse.
  if $s.options.transient != false and $s.style != off {
    let gap = (if $s.options.transient == compact { "" } else { "\n" })
    let theme = (terminal theme state-dir | path join theme.nuon)
    let green = (if ($theme | path exists) { open $theme | get -o roles.text_green | default green } else { "green" })
    $env.TRANSIENT_PROMPT_COMMAND = $"($gap)(ansi { fg: $green, attr: b })\u{276f}(ansi reset) "
    $env.TRANSIENT_PROMPT_COMMAND_RIGHT = ""
    $env.TRANSIENT_PROMPT_INDICATOR = ""
    $env.TRANSIENT_PROMPT_INDICATOR_VI_INSERT = ""
    $env.TRANSIENT_PROMPT_INDICATOR_VI_NORMAL = ""
  } else {
    hide-env -i TRANSIENT_PROMPT_COMMAND TRANSIENT_PROMPT_COMMAND_RIGHT TRANSIENT_PROMPT_INDICATOR TRANSIENT_PROMPT_INDICATOR_VI_INSERT TRANSIENT_PROMPT_INDICATOR_VI_NORMAL
  }
  # Off is off: no path, no clock, nothing on the right — what is left is
  # Nushell's indicator of the mode.
  if $s.style == off {
    $env.PROMPT_COMMAND = ""
    $env.PROMPT_COMMAND_RIGHT = ""
    $env.PROMPT_MULTILINE_INDICATOR = "::: "
    return true
  }
  let p = ($env.NUSTRO_PROMPTS? | default null)
  if $p == null { return false }
  $env.PROMPT_COMMAND = $p.left
  $env.PROMPT_COMMAND_RIGHT = $p.right
  $env.PROMPT_MULTILINE_INDICATOR = $p.multiline
  $env.config.render_right_prompt_on_last_line = true
  let rendered = (terminal theme state-dir | path join starship.toml)
  if ($rendered | path exists) { $env.STARSHIP_CONFIG = $rendered }
  true
}

# ── Choosing ──────────────────────────────────────────────────────────────────

def styles []: nothing -> table {
  [
    { value: powerline, description: "tinted segments joined by separators — the shipped look" }
    { value: plain, description: "the same segments as coloured text" }
    { value: off, description: "no prompt: only the indicator of the vi mode" }
  ]
}

def option-names []: nothing -> table {
  $OPTIONS | each {|o| { value: $o.name, description: $o.about } }
}

# What a `<value>` completes from: the values of the option already on the line.
def option-values [place: record]: nothing -> list<string> {
  let names = ($OPTIONS | get name)
  let name = ($place.command | where {|w| $w in $names } | get -o 0)
  if $name == null { return [] }
  $OPTIONS | where name == $name | get 0.values | default [] | each {|v| $v | into string }
}

def require-starship []: nothing -> nothing {
  if (which starship | is-empty) {
    error make { msg: "the styles are starship's and starship is not installed — `nustro deps install starship`; `terminal prompt use off` is no prompt at all" }
  }
}

def refuse-yours [what: string]: nothing -> nothing {
  let yours = (user-template)
  if $yours != null {
    error make { msg: $"($yours) is the prompt, and ($what) would change nothing: a starship.toml of your own wins over the styles. Move it away to use them." }
  }
}

# A value as typed — `false`, `right`, `2`, or the same as a string — checked
# against what the option takes.
def checked [name: string, value: any, span: any]: nothing -> any {
  let o = ($OPTIONS | where name == $name | get -o 0)
  if $o == null {
    error make { msg: $"no prompt option called '($name)' — `terminal prompt` lists them", label: { text: "unknown option", span: $span } }
  }
  let v = (if ($value | describe) != "string" { $value } else if $value in [true false] { $value == "true" } else if $value =~ '^\d+$' { $value | into int } else { $value })
  let ok = (if $o.values == null { ($v | describe) == "int" and $v >= 0 } else { $v in $o.values })
  if not $ok {
    let takes = (if $o.values == null { "a whole number, 0 or more" } else { $o.values | each {|x| $x | into string } | str join ", " })
    error make { msg: $"($name) takes ($takes), not ($value)", label: { text: "not a value of this option", span: $span } }
  }
  $v
}

def said [applied: bool]: nothing -> string {
  if $applied { "this session and every shell after" } else { "from the next shell" }
}

# What the prompt is: the style, and every option with its value and default.
export def "terminal prompt" []: nothing -> record {
  let s = (terminal prompt state)
  let yours = (user-template)
  {
    style: (if $yours != null and $s.style != off { "yours" } else { $s.style })
    starship: (which starship | is-not-empty)
    template: $yours
    options: ($OPTIONS | each {|o| { option: $o.name, value: ($s.options | get $o.name), default: $o.default, about: $o.about } })
  }
}

# Choose the style. The options are kept, so `off` and back is the prompt you had.
export def --env "terminal prompt use" [
  style: string@styles   # powerline | plain | off
]: nothing -> nothing {
  if $style not-in $STYLES {
    error make { msg: $"no prompt style called '($style)': ($STYLES | str join ', ')", label: { text: "unknown style", span: (metadata $style).span } }
  }
  if $style != off {
    require-starship
    refuse-yours $"`terminal prompt use ($style)`"
  }
  save-state $style (terminal prompt state | get options)
  write-rendered
  print $"prompt is ($style) — (said (terminal prompt apply))"
}

# Set one option: `terminal prompt set icons false`, `terminal prompt set time right`.
export def --env "terminal prompt set" [
  option: string@option-names   # which one — `terminal prompt` lists them
  value: any@option-values      # its new value
]: nothing -> nothing {
  let v = (checked $option $value (metadata $option).span)
  let s = (terminal prompt state)
  if $option != transient and $s.style != off { refuse-yours $"`terminal prompt set ($option)`" }
  save-state $s.style ($s.options | upsert $option $v)
  write-rendered
  let note = (if $s.style == off { " (the style is off: it shows once a style is in use)" } else { "" })
  print $"($option) is ($v)($note) — (said (terminal prompt apply))"
}

# Options back to their defaults; with none named, the style too — the shipped prompt.
export def --env "terminal prompt reset" [
  ...options: string@option-names   # the options to reset; none: everything
]: nothing -> nothing {
  let s = (terminal prompt state)
  if ($options | is-empty) {
    rm -f (state-file)
  } else {
    let d = (defaults)
    for name in $options { checked $name ($d | get -o $name) (metadata $options).span | ignore }
    save-state $s.style ($options | reduce -f $s.options {|name, acc| $acc | upsert $name ($d | get $name) })
  }
  write-rendered
  let what = (if ($options | is-empty) { "the shipped prompt: powerline, every option at its default" } else { $"($options | str join ', ') back to (if ($options | length) == 1 { 'its default' } else { 'their defaults' })" })
  print $"($what) — (said (terminal prompt apply))"
}

# The styles as starship draws them in this directory, in the theme's colours,
# with the options as they are — or as `--with` would make them. Nothing is
# written: each is rendered to a temporary file starship is pointed at.
export def "terminal prompt preview" [
  style?: string@styles   # one style; both when omitted
  --with: record          # options to try: --with { icons: false, time: right }
]: nothing -> nothing {
  require-starship
  if $style != null and $style not-in $STYLES {
    error make { msg: $"no prompt style called '($style)': ($STYLES | str join ', ')", label: { text: "unknown style", span: (metadata $style).span } }
  }
  let tried = ($with | default {} | transpose k v | reduce -f {} {|it, acc| $acc | insert $it.k (checked $it.k $it.v (metadata $with).span) })
  let o = (terminal prompt state | get options | merge $tried)
  let pal = (current-palette)
  let width = (try { (term size).columns } catch { 80 })
  for st in (if $style == null { [powerline plain] } else { [$style] }) {
    print $"(ansi attr_dimmed)($st)(ansi reset)"
    if $st == off {
      print $"  nothing but the indicator: ($env.PROMPT_INDICATOR_VI_INSERT? | default ': ')"
      continue
    }
    let f = (mktemp --tmpdir --suffix .toml nustro-prompt.XXXXXX)
    terminal prompt config $st $o | with-palette $pal | save -f $f
    let drawn = (with-env { STARSHIP_CONFIG: $f, STARSHIP_SHELL: "nu" } {
      let args = [--terminal-width $width --cmd-duration 2400 --status 0]
      { left: (^starship prompt ...$args), right: (^starship prompt --right ...$args) }
    })
    rm -f $f
    let rows = ($drawn.left | str trim --left --char "\n" | lines)
    let lead = ($rows | drop | each {|l| $l + "\n" } | str join)
    let last = ($rows | last | default "")
    let gap = ($width - ($last | ansi strip | str length --grapheme-clusters) - ($drawn.right | ansi strip | str length --grapheme-clusters))
    print ($lead + $last + (if ($drawn.right | is-empty) { "" } else { ("" | fill -w ([$gap 1] | math max)) + $drawn.right }))
  }
}
