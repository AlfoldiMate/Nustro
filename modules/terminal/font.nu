# font — pick a Nerd Font, install it, and let the terminal render the preview
#
#   font                    the picker: fifteen popular Nerd Fonts, install and keep
#   font list               what is in the registry, and what is installed here
#   font install <name>     download and install it, after asking
#   font preview <name>     a real window of the terminal in that font, showing a specimen
#   font specimen           the sample text, in the font this terminal is using now
#   font use <name> [-s N]  install if needed, then keep it in the terminal's config, at a size
#   font size [N|--reset]   the point size alone: show, set, or hand it back to the terminal
#
# The terminal is `terminal target` (registry.nu): Ghostty or WezTerm, whichever
# this session runs in or was pinned. Each answers the two questions a font
# needs — "which face does this family resolve to" (`face`) and "open a window
# in it" (`preview`) — in its own way, and writes the family under its own key.
#
# Why a new window is the preview
#
# You cannot preview a font you have not installed — the terminal renders with
# the fonts it has, and a name in a list tells you nothing. Nor can you preview
# one you HAVE installed in the window you are sitting in without keeping it:
# there is no escape sequence for "change font" the way OSC 4 is "change
# colour", which is what makes the theme picker able to repaint in place, and
# a reload of the written configuration is a choice, not a preview.
#
# What both terminals have is the font on their own command line (Ghostty's
# `--font-family`, WezTerm's `--config font=`), so a new window can be opened
# in the candidate font running a specimen. That is a real preview: the
# terminal's own rasterizer and shaper, the actual ligatures and the actual
# Nerd Font glyphs, at the size you will use. It costs one window you close.
#
# The alternative the design started with was pre-rendered PNG samples pushed
# over the Kitty graphics protocol, which Ghostty supports. It was dropped:
# nothing on a stock machine can rasterize a font file (no ImageMagick, no PIL,
# and macOS `qlmanage -t` returns a generic "Aa" icon, not a specimen), so the
# images would have to be built elsewhere and shipped or fetched — ~450 kB that
# can go stale against a Nerd Fonts release, to show something less true than
# the terminal itself already shows.

use registry.nu *

# ── The registry ──────────────────────────────────────────────────────────────
#
# Fifteen, by download count on the Nerd Fonts releases. Four fields do the work:
#
#   asset   the release asset base name — <asset>.zip / <asset>.tar.xz
#   stem    the exact file stem to install out of it. An asset holds every
#           variant (Mono, Propo, NL, and whole sub-families), so this picks one
#           — MesloLGS out of six Meslo variants, MonaspiceNe out of five.
#   family  what the terminal calls it once installed. Nerd Fonts RENAMES several
#           fonts to avoid trademark collisions (CascadiaCode → CaskaydiaCove,
#           SourceCodePro → SauceCodePro, Monaspace → Monaspice, Terminus →
#           Terminess), so this is never derived from the name.
#   cask    Homebrew's cask, which is the fast path on macOS.
#
# `family` is a claim about the installed font, so nothing trusts it: a font
# counts as installed only when the terminal resolves the family to itself
# (`font face`), and this value is only the pattern used to ask.
def registry []: nothing -> table {
  [
    { name: "JetBrainsMono"   asset: "JetBrainsMono"   stem: "JetBrainsMonoNerdFont"   family: "JetBrainsMono Nerd Font"   cask: "font-jetbrains-mono-nerd-font"   what: "ligatures, the most installed of them all — and the built-in font of Ghostty and WezTerm" }
    { name: "FiraCode"        asset: "FiraCode"        stem: "FiraCodeNerdFont"        family: "FiraCode Nerd Font"        cask: "font-fira-code-nerd-font"        what: "the original programming ligatures" }
    { name: "Hack"            asset: "Hack"            stem: "HackNerdFont"            family: "Hack Nerd Font"            cask: "font-hack-nerd-font"            what: "no ligatures, very legible small" }
    { name: "Meslo"           asset: "Meslo"           stem: "MesloLGSNerdFont"        family: "MesloLGS Nerd Font"        cask: "font-meslo-lg-nerd-font"        what: "Menlo with adjustable line gap; what powerlevel10k recommends" }
    { name: "CascadiaCode"    asset: "CascadiaCode"    stem: "CaskaydiaCoveNerdFont"   family: "CaskaydiaCove Nerd Font"   cask: "font-caskaydia-cove-nerd-font"   what: "Microsoft's terminal font, ligatures, cursive italics" }
    { name: "SourceCodePro"   asset: "SourceCodePro"   stem: "SauceCodeProNerdFont"    family: "SauceCodePro Nerd Font"    cask: "font-sauce-code-pro-nerd-font"    what: "Adobe's, conservative and quiet" }
    { name: "IosevkaTerm"     asset: "IosevkaTerm"     stem: "IosevkaTermNerdFont"     family: "IosevkaTerm Nerd Font"     cask: "font-iosevka-term-nerd-font"     what: "narrow: more columns per screen, terminal-tuned" }
    { name: "Iosevka"         asset: "Iosevka"         stem: "IosevkaNerdFont"         family: "Iosevka Nerd Font"         cask: "font-iosevka-nerd-font"         what: "the same, at the normal width" }
    { name: "UbuntuMono"      asset: "UbuntuMono"      stem: "UbuntuMonoNerdFont"      family: "UbuntuMono Nerd Font"      cask: "font-ubuntu-mono-nerd-font"      what: "warm and round, tight vertical rhythm" }
    { name: "RobotoMono"      asset: "RobotoMono"      stem: "RobotoMonoNerdFont"      family: "RobotoMono Nerd Font"      cask: "font-roboto-mono-nerd-font"      what: "Google's, neutral, many weights" }
    { name: "Monaspace"       asset: "Monaspace"       stem: "MonaspiceNeNerdFont"     family: "MonaspiceNe Nerd Font"     cask: "font-monaspice-nerd-font"     what: "GitHub's superfamily; Neon is the grotesque one" }
    { name: "Terminus"        asset: "Terminus"        stem: "TerminessNerdFont"       family: "Terminess Nerd Font"       cask: "font-terminess-ttf-nerd-font"       what: "bitmap-derived, crisp at small sizes" }
    { name: "DejaVuSansMono"  asset: "DejaVuSansMono"  stem: "DejaVuSansMNerdFont"     family: "DejaVuSansM Nerd Font"     cask: "font-dejavu-sans-mono-nerd-font"     what: "the Linux default; enormous Unicode coverage" }
    { name: "Inconsolata"     asset: "Inconsolata"     stem: "InconsolataNerdFont"     family: "Inconsolata Nerd Font"     cask: "font-inconsolata-nerd-font"     what: "humanist, a classic" }
    { name: "Noto"            asset: "Noto"            stem: "NotoMonoNerdFont"        family: "NotoMono Nerd Font"        cask: "font-noto-nerd-font"        what: "Google's no-tofu family, monospace cut" }
  ]
}

const NERD_FONTS_RELEASE = "https://github.com/ryanoasis/nerd-fonts/releases/latest/download"

# Where the archives come from: the release, or NERD_FONTS_RELEASE in the
# environment — a mirror's URL, or a directory holding the assets for a
# machine without GitHub (and for the tests, which install from a fixture).
def release-source []: nothing -> string {
  $env.NERD_FONTS_RELEASE? | default $NERD_FONTS_RELEASE
}

# The four faces a terminal needs. Everything else in the archive — Mono, Propo,
# NL, the other weights — is left there, which is why one font is a few MB
# installed out of an archive that can be a few hundred.
const FACES = ["Regular" "Bold" "Italic" "BoldItalic"]

# ── What is installed ─────────────────────────────────────────────────────────

# The face the terminal would actually use for a family, which is the only
# test that means anything: the terminal is what has to find the font, and it
# answers in the spelling its own font key wants. Ghostty answers through
# `+show-face`, WezTerm through `ls-fonts` (each backend says how, and why);
# both fall back silently to their built-in "JetBrains Mono" for a family they
# cannot find, so the test is whether the face named is the family asked for.
# Null without a terminal to ask.
export def "font face" [family: string]: nothing -> any {
  terminal face $family
}

def installed? [family: string]: nothing -> bool {
  let face = (font face $family)
  $face != null and ($face | str starts-with $family)
}

# The registry, with what is true on this machine. One terminal spawn per
# font, in parallel: 15 sequential Ghostty calls are 400 ms, `par-each` brings
# that under 100.
#
# `current` is judged by what the terminal reports it is using, not by what
# this distro wrote: a family in the user's own config is just as current, and
# the variant they chose ("JetBrainsMono Nerd Font Mono") is the same font.
export def "font list" []: nothing -> table<font: string, installed: bool, current: bool, family: string, what: string> {
  let t = (terminal target)
  let now = (if $t == null { "" } else { terminal live $t.font_key | default "" })
  registry | par-each {|f|
    let face = (if $t == null { null } else { terminal face $f.family })
    {
      font: $f.name
      installed: ($face != null and ($face | str starts-with $f.family))
      current: ($now | str starts-with $f.family)
      family: $f.family
      what: $f.what
    }
  } | sort-by {|r| registry | get name | enumerate | where item == $r.font | get 0.index }
}

def font-names []: nothing -> list<string> { registry | get name }

def entry [name: string]: nothing -> record {
  let f = (registry | where name == $name | get -o 0)
  if $f == null { error make { msg: $"no font called '($name)' — `font list`" } }
  $f
}

# ── Installing ────────────────────────────────────────────────────────────────

# Where a user's own fonts go on this platform.
export def "font dir" []: nothing -> path {
  match $nu.os-info.name {
    "macos" => ($nu.home-dir | path join Library Fonts)
    "windows" => ($env.LOCALAPPDATA | path join Microsoft Windows Fonts)
    _ => ($nu.home-dir | path join .local share fonts)
  }
}

# Install one font. Homebrew's cask is preferred on macOS because it is what
# will also upgrade the font later; everywhere else the release archive is
# fetched and exactly four files are taken out of it.
export def "font install" [
  name: string@font-names
  --yes (-y)      # do not ask
  --archive       # skip the package manager and use the release archive
]: nothing -> nothing {
  let f = (entry $name)
  if ((font list | where font == $name | get 0.installed)) {
    print $"($name) is already installed"
    return
  }
  let brew = ($nu.os-info.name == "macos" and (which brew | is-not-empty) and not $archive)
  let how = if $brew { $"brew install --cask ($f.cask)" } else { $"download ($f.asset) from the Nerd Fonts release into (font dir)" }
  if not $yes {
    if not ((is-terminal --stdin) and (is-terminal --stdout)) {
      error make { msg: $"($name) is not installed, and there is no terminal to ask on — `font install ($name) --yes`" }
    }
    if ([$how "no"] | input list $"install ($name)?") != $how { print "left alone"; return }
  }
  if $brew {
    ^brew install --cask $f.cask
  } else {
    install-from-archive $f
  }
  let t = (terminal target)
  if $t == null {
    print $"($name) installed into (font dir) — no terminal here to check it with"
  } else if not (settled? $f.family) {
    print $"(ansi yellow)installed, but ($t.name) still resolves '($f.family)' to ((font face $f.family)) — the Nerd Fonts naming may have changed(ansi reset)"
  } else {
    print $"($name) installed — ($t.name) renders it as '($f.family)'"
  }
}

# macOS registers a font file some time after it lands: measured 2026-09-19,
# `brew install --cask font-hack-nerd-font` returned 1.7 s before Ghostty
# resolved 'Hack Nerd Font' to itself (an uninstall lags the same way). A single
# check straight after the install therefore said "not installed", and `font
# use` refused to write the family it had just installed. Poll instead; each
# try is one terminal spawn, 30–50 ms.
def settled? [family: string]: nothing -> bool {
  for _ in 1..50 {
    if (installed? $family) { return true }
    sleep 200ms
  }
  false
}

# Fetch the release archive and take the four faces out of it.
#
# The archive is extracted whole into a temporary directory and then thinned,
# rather than asking tar for four members by name: the .zip variants run to
# hundreds of MB (Iosevka is 403 MB) and a streaming .tar.xz would have to be
# decompressed twice to do it in two passes. The temporary directory is removed
# either way, including when the download fails.
def install-from-archive [f: record]: nothing -> nothing {
  # .zip on macOS and Windows, whose `tar` is libarchive/bsdtar and reads zip;
  # .tar.xz on Linux, whose GNU tar does not.
  let ext = if $nu.os-info.name == "linux" { "tar.xz" } else { "zip" }
  let source = (release-source)
  let url = $"($source)/($f.asset).($ext)"
  let tmp = (mktemp -d -t nerd-font-XXXXXX)
  let archive = ($tmp | path join $"($f.asset).($ext)")
  try {
    if ($source | str starts-with "http") {
      print $"  downloading ($url)"
      # Streams to disk rather than through a variable: these archives are large.
      http get $url | save -f $archive
    } else {
      print $"  copying ($url)"
      cp $url $archive
    }
    print $"  unpacking ((ls $archive | get 0.size))"
    ^tar -xf $archive -C $tmp
    let dest = (font dir)
    mkdir $dest
    let wanted = ($FACES | each {|face| $"($f.stem)-($face).ttf" })
    # Nerd Fonts archives are flat today, but a glob costs nothing and a
    # subdirectory tomorrow would otherwise look like "naming has changed".
    # Forward slashes: a backslash is an escape in a glob pattern.
    let found = (glob (($tmp | str replace -a '\' '/') + "/**/*.ttf") | where {|p| ($p | path basename) in $wanted })
    if ($found | is-empty) {
      error make { msg: $"($f.asset).($ext) holds no ($f.stem)-*.ttf — the Nerd Fonts naming may have changed" }
    }
    for file in $found { cp $file $dest }
    print $"  installed ($found | length) faces into ($dest)"
    register-fonts $found
  } catch {|e|
    rm -rf $tmp
    error make { msg: $"could not install ($f.name): ($e.msg)" }
  }
  rm -rf $tmp
}

# What each platform needs after the files land. macOS needs nothing: it scans
# ~/Library/Fonts. Linux needs the fontconfig cache rebuilt, and fc-cache is
# not always there. Windows needs a registry value per file, or the font is
# visible only until the next sign-out — this branch is written from the
# documented behaviour and has NOT been run.
def register-fonts [files: list<path>]: nothing -> nothing {
  match $nu.os-info.name {
    "linux" => {
      if (which fc-cache | is-not-empty) { ^fc-cache -f (font dir) } else {
        print "  fontconfig's fc-cache is not installed — the font may not appear until you log in again"
      }
    }
    "windows" => {
      for file in $files {
        let name = ($file | path basename)
        # `\(TrueType\)` escaped: bare parentheses inside an interpolated
        # string are a subexpression, and this one has to be literal text.
        ^reg add 'HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts' /v $"($name | str replace --regex '\.ttf$' '') \(TrueType\)" /t REG_SZ /d $name /f
      }
    }
    _ => {}
  }
}

# ── Previewing ────────────────────────────────────────────────────────────────

# The specimen: what a terminal font actually has to get right. The glyphs are
# written as \u escapes rather than pasted, so this file reads the same in an
# editor that has no Nerd Font — which is most of them, before you install one.
#
#   e0a0-e0b3  powerline (Ghostty draws the separators itself, from sprites,
#              so those two are the control: they look right in ANY font)
#   e7xx       devicons     f0xx-f1xx  Font Awesome
def specimen-lines [family: string]: nothing -> list<string> {
  [
    $"  ($family)"
    ""
    "  ABCDEFGHIJKLM abcdefghijklm 0123456789"
    "  the quick brown fox jumps over the lazy dog"
    "  0O o0 1lI i1 !|\u{a6} '\"` {} [] \(\) <> ;:,."
    "  -> => != !== <= >= := |> <|  ... ++ --"
    "  ls | where size > 1mb | get name"
    ""
    $"  nerd font  \u{e0a0} \u{f07b} \u{f121} \u{f09b} \u{f17c} \u{e7a8} \u{e73c} \u{e718} \u{f023} \u{f017}"
    $"  powerline  \u{e0b0}\u{e0b1} \u{e0b2}\u{e0b3}   \(these two are sprites, and look right in any font\)"
  ]
}

# Print the specimen in whatever font this terminal is using. Honest about it:
# unless the font named IS the current one, this shows your font, not that one.
export def "font specimen" []: nothing -> nothing {
  let t = (terminal target)
  let now = (if $t == null { null } else { terminal settings | get -o $t.font_key } | default "your terminal's current font")
  specimen-lines $now | each {|l| print $l }
  print ""
}

# Open a new window of the terminal in this font, showing the specimen. The
# window is yours to close; it is a separate instance and touches no config.
export def "font preview" [name: string@font-names]: nothing -> nothing {
  let f = (entry $name)
  let row = (font list | where font == $name | get 0)
  if not $row.installed {
    error make { msg: $"($name) is not installed, and a font cannot be rendered before it exists — `font install ($name)`" }
  }
  let t = (terminal require)
  let script = (specimen-lines $row.family | each {|l| $"print '($l | str replace --all "'" "''")'" } | str join "; ")
  terminal preview $row.family 14 [$nu.current-exe "-n" "-c" $"($script); print ''; input 'press Enter to close '"]
  print $"opened a ($t.name) window in ($row.family) — close it when you have seen enough"
}

# ── Choosing one ──────────────────────────────────────────────────────────────

# Keep a font: the terminal's config, then a reload so every open window
# takes it — WezTerm always, Ghostty on macOS through AppleScript; elsewhere
# the window you are in keeps the font it started with.
export def "font use" [
  name: string@font-names
  --size (-s): number   # the point size as well, written next to the family
]: nothing -> nothing {
  let t = (terminal require)
  let row = (font list | where font == $name | get 0)
  if not $row.installed { font install $name }
  let after = (font list | where font == $name | get 0)
  if not $after.installed { error make { msg: $"($name) is still not installed; nothing was written" } }
  if $size != null { check-size $size }
  terminal set (terminal font-keys $after.family $size)
  let what = ($after.family + (if $size == null { "" } else { $" at ($size)" }))
  print (if (terminal reload) { $"font is ($what) — every open ($t.name) window and new ones" } else { $"font is ($what) — new ($t.name) windows will use it; this one keeps the font it started with" })
}

# The size alone, in points, kept in our file next to the family so a reset
# takes it out with everything else. `--reset` removes the key and the
# terminal falls back to its own default (13 in Ghostty 1.3.1, 12 in WezTerm)
# or to the user's config. A size on the command line is the one thing ⌘+/⌘-
# lose on the next window, which is why it is a setting and not a keystroke.
export def "font size" [
  size?: number   # points; halves are fine (14.5)
  --reset         # remove the key
]: nothing -> nothing {
  let t = (terminal require)
  if $reset {
    terminal set { ($t.size_key): null }
    print (if (terminal reload) { $"font size is ($t.name)'s own again — every open window and new ones" } else { $"font size is ($t.name)'s own again — in new windows" })
    return
  }
  if $size == null {
    print (terminal live $t.size_key | default $"($t.name)'s own default")
    return
  }
  check-size $size
  terminal set (terminal font-keys null $size)
  print (if (terminal reload) { $"font size is ($size) — every open window and new ones" } else { $"font size is ($size) — new windows will use it" })
}

# Neither terminal rejects a size (`+validate-config` and config_builder take
# any number), so the guard is ours: below 4 the window is unreadable, above
# 72 it is a poster.
def check-size [size: number]: nothing -> nothing {
  if $size < 4 or $size > 72 { error make { msg: $"font size ($size) is outside 4..72" } }
}

# The picker. Installed fonts are marked, because an uninstalled one costs a
# download before it can be seen, and that is the only real difference between
# the rows.
export def main []: nothing -> nothing {
  if not ((is-terminal --stdin) and (is-terminal --stdout)) {
    error make { msg: "`font` is the interactive picker; `font use <name>` is not" }
  }
  mut picking = true
  while $picking {
    let rows = (font list)
    let pick = (
      $rows
      | input list --fuzzy --display {|r|
          let mark = (if $r.current { "● " } else if $r.installed { "✓ " } else { "  " })
          $"($mark)($r.font | fill --width 16) ($r.what)"
        } "font"
    )
    if $pick == null { print "unchanged"; return }

    if not $pick.installed {
      font install $pick.font
      if not (font list | where font == $pick.font | get 0.installed) { continue }
    }
    let row = (font list | where font == $pick.font | get 0)

    match ([$"keep ($pick.font)" "see it in a new window" "pick another" "leave it as it was"] | input list $"($row.family)") {
      $a if ($a | default "" | str starts-with "keep") => {
        font use $pick.font
        $picking = false
      }
      "see it in a new window" => { font preview $pick.font }
      "pick another" => { }
      _ => { print "unchanged"; $picking = false }
    }
  }
}
