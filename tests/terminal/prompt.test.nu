# The prompt's shape (modules/terminal/prompt.nu): the generator against the
# shipped template, each option's effect on what starship is handed, the
# state file, the render through `terminal theme sync`, a starship.toml of
# the user's own, and what conf/prompt.nu makes of the state at startup.
use lib.nu *
use std/assert
use terminal *
use terminal/theme.nu *
use terminal/palette.nu *
use terminal/prompt.nu *

# The file's tests share a state directory and a config directory: each one
# starts from the shipped prompt and no template of the user's.
def fresh []: nothing -> record {
  rm -f (terminal theme state-dir | path join prompt.nuon) (terminal theme state-dir | path join starship.toml)
  rm -f ($nu.config-path | path dirname | path join themes starship.toml)
  terminal prompt state | get options
}

def shipped []: nothing -> record {
  open --raw ($ROOT | path join themes starship.toml) | from toml
}

# Anything from the Private Use Areas: where every Nerd Font glyph lives.
const NERD = '[\x{e000}-\x{f8ff}\x{f0000}-\x{10ffff}]'

def "test powerline with every option at its default is themes/starship.toml" [] {
  let o = fresh
  assert equal (terminal prompt config powerline $o) (shipped | reject palettes)
}

def "test a hidden segment takes its separators with it" [] {
  let o = fresh
  let f = terminal prompt config powerline ($o | merge { git: off }) | get format
  assert not ($f | str contains '$git_branch')
  assert ($f | str contains "$directory[\u{e0b0}](fg:tint_orange bg:tint_green)$c") $f
  # The first segment gone: the lead is the next one's colour.
  let g = terminal prompt config powerline ($o | merge { os: off, user: off }) | get format
  assert ($g | str starts-with "[\u{e0b6}](fg:tint_orange)$directory") $g
  # Nothing on the first line: no line break before the mark.
  let none = [os user directory git languages env time duration] | reduce -f $o {|s, acc| $acc | upsert $s off }
  assert equal (terminal prompt config powerline $none | get format) '$character'
}

def "test a segment on the right is drawn mirrored, the duration leading" [] {
  let o = fresh
  let c = terminal prompt config powerline ($o | merge { git: right, time: right, duration: right })
  assert equal $c.right_format "$cmd_duration[\u{e0b2}](fg:tint_yellow)$git_branch$git_status[\u{e0b2}](fg:tint_accent_alt bg:tint_yellow)$time"
  assert not ($c.format | str contains '$time')
  assert ($c.format | str ends-with "$conda[\u{e0b4} ](fg:tint_teal)$line_break$character") $c.format
  assert equal (terminal prompt config powerline $o | get -o right_format) null "nothing on the right, no right_format"
  let p = terminal prompt config plain ($o | merge { time: right })
  assert equal $p.right_format '$time'
}

def "test the separator option changes the three glyphs" [] {
  let o = fresh
  let round = terminal prompt config powerline ($o | merge { separator: round }) | get format
  assert ($round | str contains "[\u{e0b4}](fg:tint_red bg:tint_orange)") $round
  let flat = terminal prompt config powerline ($o | merge { separator: flat }) | get format
  assert not ($flat =~ $NERD) $flat
  assert ($flat | str starts-with '$os$username$directory') $flat
}

def "test without icons no style holds a Nerd Font glyph" [] {
  let o = fresh | merge { icons: false }
  for style in [powerline plain] {
    let c = terminal prompt config $style $o
    assert not (($c | to toml) =~ $NERD) $"($style) without icons still holds a glyph"
    assert not ($c.format | str contains '$os') "the OS is an icon and nothing else"
    assert equal $c.rust.symbol rust
  }
  assert equal (terminal prompt config plain $o | get git_branch.format) '[on ](fg:fg_muted)[$branch ]($style)'
}

def "test plain writes the hues as text and paints no surface" [] {
  let o = fresh
  let c = terminal prompt config plain $o
  assert equal $c.format '$os$username$directory$git_branch$git_status$c$rust$golang$nodejs$php$java$kotlin$haskell$python$conda$time$cmd_duration$line_break$character'
  assert not (($c | to toml) =~ 'bg:|tint_') "no surface in plain"
  assert equal $c.directory.style "bold fg:text_orange"
}

def "test lines, newline and depth reach the keys starship has for them" [] {
  let o = fresh
  let c = terminal prompt config powerline ($o | merge { lines: 1, newline: false, depth: 5 })
  assert not ($c.format | str contains '$line_break')
  assert equal $c.add_newline false
  assert equal $c.directory.truncation_length 5
}

def "test every colour a style names is a role the palette block has" [] {
  let o = fresh
  let roles = shipped | get palettes.distro | columns
  for style in [powerline plain] {
    for opts in [$o ($o | merge { icons: false }) ($o | merge { git: right, time: right })] {
      let used = terminal prompt config $style $opts | to toml | parse -r '(?:fg|bg):(?<role>\w+)' | get role | uniq
      assert equal ($used | where $it not-in $roles) [] $"($style) names a role the palette has not"
    }
  }
}

def "test starship reads what each style generates without complaint" [] {
  if (which starship | is-empty) { skip-test "starship is not installed" }
  let o = fresh
  let dir = scratch
  for it in ([powerline plain] | each {|s| [$o ($o | merge { icons: false, separator: slant }) ($o | merge { git: right, duration: right, lines: 1 })] | each {|x| { style: $s, o: $x } } } | flatten) {
    let f = $dir | path join starship.toml
    terminal prompt config $it.style $it.o | upsert palettes { distro: (shipped | get palettes.distro) } | to toml | save -f $f
    let drawn = [[] [--right]] | each {|side|
      let r = with-env { STARSHIP_CONFIG: $f, STARSHIP_SHELL: nu } { ^starship prompt ...$side --terminal-width 120 --cmd-duration 2400 | complete }
      assert equal $r.exit_code 0 $r.stderr
      assert equal ($r.stderr | str trim) "" $"($it.style): ($r.stderr)"
      $r.stdout | ansi strip
    }
    assert ($drawn | str join | str contains "2s400ms") "the duration is drawn, on one side or the other"
  }
}

def "test set keeps only what differs, reset takes it back" [] {
  fresh
  terminal prompt use plain
  terminal prompt set icons false
  terminal prompt set time "right"
  terminal prompt set depth "4"
  let f = terminal theme state-dir | path join prompt.nuon
  assert equal (open $f) { style: plain, options: { icons: false, time: right, depth: 4 } }
  assert equal (terminal prompt | select style template) { style: plain, template: null }
  assert equal (terminal prompt | get options | where option == time | get 0 | select value default) { value: right, default: left }
  terminal prompt set time left
  assert equal (open $f | get options) { icons: false, depth: 4 }
  terminal prompt reset depth
  assert equal (open $f) { style: plain, options: { icons: false } }
  terminal prompt reset
  assert not ($f | path exists)
  assert equal (terminal prompt state | get style) powerline
}

def "test a wrong style, option or value is an error and nothing is saved" [] {
  fresh
  let msgs = [
    (try { terminal prompt use fancy; null } catch {|e| $e.msg })
    (try { terminal prompt set colour 1; null } catch {|e| $e.msg })
    (try { terminal prompt set icons maybe; null } catch {|e| $e.msg })
    (try { terminal prompt set depth deep; null } catch {|e| $e.msg })
    (try { terminal prompt reset colour; null } catch {|e| $e.msg })
  ]
  assert ($msgs.0 | str contains "no prompt style called 'fancy'") ($msgs | to nuon)
  assert ($msgs.1 | str contains "no prompt option called 'colour'") ($msgs | to nuon)
  assert ($msgs.2 | str contains "icons takes true, false") ($msgs | to nuon)
  assert ($msgs.3 | str contains "a whole number") ($msgs | to nuon)
  assert ($msgs.4 | str contains "no prompt option called 'colour'") ($msgs | to nuon)
  assert not (terminal theme state-dir | path join prompt.nuon | path exists)
}

def "test an option the state file holds and this version lacks is dropped" [] {
  fresh
  mkdir (terminal theme state-dir)
  { style: sideways, options: { icons: false, sparkle: true } } | to nuon | save -f (terminal theme state-dir | path join prompt.nuon)
  let s = terminal prompt state
  assert equal $s.style powerline
  assert equal $s.options.icons false
  assert equal ($s.options | get -o sparkle) null
  fresh
}

def "test the style survives a theme render and takes the colours of the theme" [] {
  if (which starship | is-empty) { skip-test "starship is not installed" }
  fresh
  terminal prompt use plain
  let f = terminal theme state-dir | path join starship.toml
  assert equal (open --raw $f | from toml | get palettes.distro.tint_red) red "no theme yet: the ANSI tier"
  terminal theme sync onedark --quiet
  let toml = open --raw $f | from toml
  assert equal $toml.directory.style "bold fg:text_orange" "still plain"
  assert equal $toml.palettes.distro.orange ((terminal theme current).roles.orange)
  # And a change of style keeps the colours the theme rendered.
  terminal prompt use powerline
  assert equal (open --raw $f | from toml | get palettes.distro.orange) $toml.palettes.distro.orange
  terminal theme sync --none --quiet
  fresh
}

def "test a starship.toml of the user is the prompt and the styles say so" [] {
  if (which starship | is-empty) { skip-test "starship is not installed" }
  fresh
  let yours = $nu.config-path | path dirname | path join themes starship.toml
  mkdir ($yours | path dirname)
  "format = '$directory$character'\n" | save -f $yours
  let toml = terminal prompt render | from toml
  assert equal $toml.format '$directory$character'
  assert equal $toml.palettes.distro.tint_red red
  assert equal (terminal prompt | select style template) { style: yours, template: $yours }
  let err = try { terminal prompt use plain; null } catch {|e| $e.msg }
  assert ($err | str contains "a starship.toml of your own wins") $err
  let set = try { terminal prompt set icons false; null } catch {|e| $e.msg }
  assert ($set | str contains "a starship.toml of your own wins") $set
  # Off is not a style of starship's, and the transient option is Nushell's.
  terminal prompt set transient true
  terminal prompt use off
  assert equal (terminal prompt | get style) off
  fresh
}

def "test a shell starts with the prompt the state names" [] {
  if (which starship | is-empty) { skip-test "starship is not installed" }
  let dir = user-dir
  let before = nu-l $dir 'print (view source $env.PROMPT_COMMAND); print ($env.TRANSIENT_PROMPT_COMMAND? | describe)'
  assert equal $before.exit_code 0 $before.stderr
  assert ($before.stdout | str contains "starship-prompt") $before.stdout
  assert ($before.stdout | str contains "nothing") "no transient prompt by default"
  # Off is no prompt at all, in the shell that chose it and in the one after:
  # both sides empty, and the indicator of the mode left as it was.
  let sides = 'print ([$env.PROMPT_COMMAND $env.PROMPT_COMMAND_RIGHT $env.PROMPT_INDICATOR_VI_INSERT] | to json -r)'
  let chose = nu-l $dir $"use terminal *; terminal prompt use off; ($sides)"
  assert equal $chose.exit_code 0 $chose.stderr
  assert ($chose.stdout | str contains "prompt is off — this session and every shell after") $chose.stdout
  assert ($chose.stdout | str contains '["","",": "]') $chose.stdout
  let after = nu-l $dir $sides
  assert equal ($after.stdout | str trim) '["","",": "]' $after.stderr
  # And there is nothing to collapse: transient waits for a style.
  let waits = nu-l $dir 'use terminal *; terminal prompt set transient true; print ($env.TRANSIENT_PROMPT_COMMAND? | describe)'
  assert ($waits.stdout | str contains "nothing") $waits.stdout
  # With a style the mark carries a blank line of its own, and none when compact.
  let mark = 'print ($env.TRANSIENT_PROMPT_COMMAND | ansi strip | to json); print ($env.TRANSIENT_PROMPT_INDICATOR_VI_INSERT | to json)'
  let back = nu-l $dir $"use terminal *; terminal prompt use powerline; print \(view source $env.PROMPT_COMMAND\); ($mark)"
  assert equal $back.exit_code 0 $back.stderr
  assert ($back.stdout | str contains "starship-prompt") $back.stdout
  assert ($back.stdout | str contains ('"\n' + "\u{276f}" + ' "')) $back.stdout
  let started = nu-l $dir $mark
  assert equal ($started.stdout | lines) [('"\n' + "\u{276f}" + ' "') '""'] $started.stderr
  let compact = nu-l $dir $"use terminal *; terminal prompt set transient compact | ignore; ($mark)"
  assert ($compact.stdout | str contains ('"' + "\u{276f}" + ' "')) $compact.stdout
  let reset = nu-l $dir 'use terminal *; terminal prompt reset; print ($env.TRANSIENT_PROMPT_COMMAND? | describe)'
  assert ($reset.stdout | str contains "nothing") $reset.stdout
}
