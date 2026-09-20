# A wezterm that answers from files, for the terminal tests. lib.nu's
# `fake-wezterm` puts a wrapper for it first on PATH, and WEZTERM_FAKE names
# the root it works from:
#
#   faces        one family per line that `ls-fonts` resolves to itself, on top
#                of any family whose files are in the user's font dir
#                (`HackNerdFont-*.ttf` is “Hack Nerd Font”); anything else
#                resolves to “JetBrains Mono”, WezTerm's built-in font, with
#                the "Unable to load a font" warning the real one prints
#   error        when present, its text is printed as an ` ERROR ` line on
#                stderr by every verb that loads the config — how the real
#                one reports a bad scheme or key (the exit code stays 0)
#   log          every call, one NUON list of arguments per line
#
# What it mimics of the real WezTerm 20240203 (verified 2026-09-20):
#
#   wezterm [--config k=v]... [--config-file f] ls-fonts
#       prints "Primary font:" and a `wezterm.font_with_fallback({ ... })` block
#       whose first quoted entry is the family that resolved. With
#       `--config font=wezterm.font("X")` the answer is about X; otherwise it
#       is the `font_family` our file sets (read from the config chain: the
#       user's wezterm.lua and the nustro.lua it applies), else the built-in.
#   wezterm [--config ...] start [--always-new-process] -- argv
#       logged, runs nothing.

def --wrapped main [...args: string] {
  let root = $env.WEZTERM_FAKE
  ($args | to nuon) + "\n" | save -a ($root | path join log)
  let verb = ($args | where {|a| $a in [ls-fonts start show-keys] } | get -o 0 | default "")
  match $verb {
    "ls-fonts" => { ls-fonts $root $args }
    "start" => { }
    $other => { print -e $"fake wezterm: no answer for ($args | str join ' ')"; exit 2 }
  }
}

def config-path []: nothing -> path {
  let xdg = ($env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join .config) | path join wezterm wezterm.lua)
  if ($xdg | path exists) { $xdg } else { $nu.home-dir | path join .wezterm.lua }
}

# The family our nustro.lua sets, when the user's config applies it.
def configured-family [cfg: path]: nothing -> any {
  if not ($cfg | path exists) { return null }
  let text = (open --raw $cfg)
  if not ($text =~ 'nustro\.lua') { return null }
  let ours = ($cfg | path dirname | path join nustro.lua)
  if not ($ours | path exists) { return null }
  open --raw $ours | parse -r 'font = wezterm\.font\("(?<f>[^"]*)"\)' | get -o 0.f
}

def font-dir []: nothing -> path {
  match $nu.os-info.name {
    "macos" => ($nu.home-dir | path join Library Fonts)
    "windows" => ($env.LOCALAPPDATA | path join Microsoft Windows Fonts)
    _ => ($nu.home-dir | path join .local share fonts)
  }
}

def ls-fonts [root: path, args: list<string>] {
  let err = ($root | path join error)
  if ($err | path exists) { print -e $"12:00:00.000  ERROR  config::config > (open --raw $err | str trim)" }
  let at = ($args | enumerate | where {|a| $a.item == "--config-file" } | get -o 0.index)
  let cfg = (if $at == null { config-path } else { $args | get ($at + 1) })
  let asked = (
    $args | enumerate | where {|a| $a.item == "--config" } | each {|a| $args | get ($a.index + 1) }
    | parse -r '^font=wezterm\.font\("(?<f>[^"]*)"\)$' | get -o 0.f
  )
  let family = ($asked | default (configured-family $cfg))
  let faces = ($root | path join faces)
  let known = (if ($faces | path exists) { open --raw $faces | lines } else { [] })
  let on_disk = ($family != null and (glob (((font-dir) | str replace -a '\' '/') + $"/($family | str replace -a ' ' '')-*.ttf") | is-not-empty))
  let found = ($family != null and (($family in $known) or $on_disk))
  if $family != null and not $found {
    print -e $"Unable to load a font specified by your font=wezterm.font\('($family)'\) configuration. Fallback\(s\) are being used instead"
  }
  let face = (if $found { $family } else { "JetBrains Mono" })
  print "Primary font:"
  print "wezterm.font_with_fallback({"
  print (if $found { $"  -- ((font-dir) | path join $face).ttf, CoreText" } else { "  -- <built-in>, BuiltIn" })
  print $"  ($face | to json),"
  print ""
  print "  -- <built-in>, BuiltIn"
  print '  "Symbols Nerd Font Mono",'
  print ""
  print "})"
}
