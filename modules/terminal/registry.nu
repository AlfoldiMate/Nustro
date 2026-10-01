# registry.nu — the terminals this distro knows, and the one it configures
#
#   terminal list          every terminal in the registry: installed, running, configured, how to get it
#   terminal current       the one this session is running in, or null
#   terminal target        the one `terminal theme`, `terminal font` and `terminal shell` configure, or null
#   terminal use <name>    make one the target, whatever this session runs in
#   terminal install       install the platform's default, or a named one, after asking
#   terminal shell         a new window of the target starts Nushell
#   terminal option        which Option key is Alt: none (the base), left, right, both
#   terminal status        what the target's configuration holds
#   terminal set / reset   the target's own `set` / `reset`
#
# Two different questions, and the installer asks both. "Is it installed?" is
# what decides whether a theme can be written at all. "Are we running in it?"
# is what decides whether the live OSC preview will be visible: painting the
# terminal you are looking at only works if it is the terminal being
# configured — from Terminal.app or an SSH session the preview is a lie.
#
# One more, once there is a second terminal: which one is being configured.
# `terminal target` answers in this order — NUSTRO_TERMINAL in the environment
# when it names an installed one (the installer sets it for its own process,
# a test for a shell); else the terminal this session runs in, when it is
# installed; else the one pinned by `terminal use` (which the installer does
# for the choice made there); else the first installed one in registry
# order; else null, and the commands that write say so. Pinned rather than
# "the one that is installed" because a machine with both should not have
# its WezTerm reconfigured by a `terminal theme` typed in Ghostty.
#
# The registry is a table of DATA — name, how to detect it, how to install
# it, which keys it uses — and the verbs below it dispatch on the name with a
# `match`: `terminal set`, `terminal shell`, `terminal face`, `terminal
# write-theme`… each names the backend command Ghostty's and WezTerm's file
# provide. `terminal theme use`, `terminal font use` and the installer call these verbs and
# never name a terminal, so a third one is a row here, a backend file, and
# one arm in each verb. Not a row of closures: a table of thirty-four
# closures cost 28 ms to parse after `nustro` was loaded (130 ms of
# startup with the module eager, against 20 ms for the module before them,
# 2026-09-20 — every closure is analysed for captures against the whole
# scope), where a `match` arm is a block and costs nothing measurable.
#
#   name, what          the row `terminal list` shows
#   program             what TERM_PROGRAM says inside it
#   install             { <os>: { run: [argv] | null, needs: bin | null, note } }
#   icon                it can show an app icon (Ghostty)
#   theme_key           the key `write-theme` sets, for `terminal theme status`
#   font_key, size_key  the keys `terminal font use` and `terminal font size` set

use ghostty.nu *
use wezterm.nu *
use theme.nu *

def registry []: nothing -> table {
  [
    {
      name: "ghostty"
      what: "GPU-accelerated, 463 themes, the app icon, OSC and Kitty graphics — macOS and Linux"
      # Ghostty exports this into every shell it starts; TERM_PROGRAM alone
      # is not enough to be sure, because a multiplexer inside another
      # terminal keeps it, but it is the answer every terminal here gives.
      program: "ghostty"
      install: {
        macos: { run: [brew install --cask ghostty], needs: "brew", note: "or https://ghostty.org/download" }
        linux: { run: null, needs: null, note: "your distribution's package, or https://ghostty.org/download" }
        # No official build (the port is in progress upstream: ghostty-org/ghostty
        # discussion #2563). The Win32 ports on GitHub are personal forks the
        # Ghostty team has asked not to carry its name and has not endorsed, so
        # nothing is downloaded from one here; a user who installs one puts
        # ghostty.exe on PATH and the module finds it. Checked 2026-09-19.
        windows: { run: null, needs: null, note: "no official Windows build yet (github.com/ghostty-org/ghostty/discussions/2563) — WezTerm is the Windows default here" }
      }
      icon: true
      theme_key: "theme"
      font_key: "font-family"
      size_key: "font-size"
    }
    {
      name: "wezterm"
      what: "GPU-accelerated, Lua-configured, tabs and panes, reloads itself — macOS, Linux and Windows"
      program: "WezTerm"
      install: {
        macos: { run: [brew install --cask wezterm], needs: "brew", note: "or https://wezterm.org/install/macos.html" }
        # Debian's and Ubuntu's own archives do not carry it; Arch, openSUSE
        # and Void do, and WezTerm's apt repository, Flatpak and AppImage cover
        # the rest (https://wezterm.org/install/linux.html, 2026-09-20).
        linux: { run: null, needs: null, note: "your distribution's package, or https://wezterm.org/install/linux.html (apt repository, Flatpak, AppImage)" }
        windows: { run: [winget install wez.wezterm], needs: "winget", note: "or scoop install wezterm, or https://wezterm.org/install/windows.html" }
      }
      icon: false
      theme_key: "color_scheme"
      font_key: "font_family"
      size_key: "font_size"
    }
  ]
}

# ── Detection ─────────────────────────────────────────────────────────────────

# The binary, wherever it is; null when there is none.
def bin-of [name: string]: nothing -> any {
  match $name {
    "ghostty" => (ghostty-bin)
    "wezterm" => (wezterm-bin)
    _ => null
  }
}

# This session runs inside it.
def running-in? [t: record]: nothing -> bool {
  ($env.TERM_PROGRAM? | default "") == $t.program
}

# Our include is in the file it reads.
def configured? [name: string]: nothing -> bool {
  match $name {
    "ghostty" => (ghostty status).included
    "wezterm" => (wezterm status).included
    _ => false
  }
}

# Every terminal this distro knows about, and what is true of it here.
export def "terminal list" []: nothing -> table<terminal: string, installed: bool, running: bool, configured: bool, path: any, what: string> {
  registry | each {|t|
    let bin = (bin-of $t.name)
    {
      terminal: $t.name
      installed: ($bin != null)
      running: (running-in? $t)
      configured: (if $bin == null { false } else { configured? $t.name })
      path: $bin
      what: $t.what
    }
  }
}

# The registry row for one name, or null.
def entry [name: string]: nothing -> any {
  registry | where name == $name | get -o 0
}

def terminal-names []: nothing -> list<string> { registry | get name }

# The terminal this session is running in, as a `terminal list` row — null
# when it is one this distro does not know. Cheap: an environment variable,
# no processes.
export def "terminal current" []: nothing -> any {
  terminal list | where running | get -o 0
}

# Where the pin lives: the user's state, never the checkout.
def target-file []: nothing -> path {
  $nu.data-dir | path join .state terminal target.nuon
}

# The terminal the writing commands configure, as its registry row. See the
# header for the order.
export def "terminal target" []: nothing -> any {
  let named = (entry ($env.NUSTRO_TERMINAL? | default ""))
  if $named != null and ((bin-of $named.name) != null) { return $named }
  let here = (registry | where {|t| (running-in? $t) and ((bin-of $t.name) != null) } | get -o 0)
  if $here != null { return $here }
  let f = (target-file)
  let pinned = (if ($f | path exists) { try { open $f | get -o name } catch { null } } else { null })
  if $pinned != null {
    let t = (entry $pinned)
    if $t != null and ((bin-of $t.name) != null) { return $t }
  }
  registry | where {|t| (bin-of $t.name) != null } | get -o 0
}

# The platform's default: what `--defaults` and a `curl … | sh` install where
# nothing is installed yet. Ghostty where it exists, WezTerm on Windows.
export def "terminal default" []: nothing -> string {
  if $nu.os-info.name == "windows" { "wezterm" } else { "ghostty" }
}

# Pin the terminal the commands configure. Written to the state dir, so it
# survives; a session inside a known terminal still configures that one.
export def "terminal use" [name: string@terminal-names]: nothing -> nothing {
  let t = (entry $name)
  if $t == null { error make { msg: $"no terminal called '($name)' — `terminal list`", label: { text: "unknown terminal", span: (metadata $name).span } } }
  let f = (target-file)
  mkdir ($f | path dirname)
  { name: $name, since: (date now) } | to nuon | save -f $f
  let here = (terminal current)
  print (if $here != null and $here.terminal != $name {
    $"($name) is the terminal `terminal theme`, `terminal font` and `terminal shell` configure from now on — except in a ($here.terminal) window, which configures itself"
  } else {
    $"($name) is the terminal `terminal theme`, `terminal font` and `terminal shell` configure"
  })
}

# What the current platform would have to run to get one, and whether it can.
export def "terminal install-plan" [name?: string@terminal-names]: nothing -> record {
  let name = ($name | default (terminal default))
  let t = (entry $name)
  if $t == null { error make { msg: $"no terminal called '($name)' in the registry" } }
  let plan = ($t.install | get -o $nu.os-info.name | default { run: null, needs: null, note: "" })
  {
    terminal: $name
    installed: ((bin-of $name) != null)
    # A run line is only a plan if what it runs is there.
    runnable: ($plan.run != null and ($plan.needs == null or (which $plan.needs | is-not-empty)))
    command: (if $plan.run == null { null } else { $plan.run | str join " " })
    note: $plan.note
  }
}

# Install it, having asked. Never runs anything on a platform where the plan is
# only a URL: printing the link is the honest outcome there.
export def "terminal install" [
  name?: string@terminal-names   # the platform's default when omitted
  --yes (-y)   # do not ask
]: nothing -> nothing {
  let plan = (terminal install-plan $name)
  let name = $plan.terminal
  if $plan.installed { print $"($name) is already installed"; return }
  if not $plan.runnable {
    print $"($name) has to be installed by hand on ($nu.os-info.name): ($plan.note)"
    return
  }
  if not $yes {
    if ([$"run: ($plan.command)" "no"] | input list $"install ($name)?") != $"run: ($plan.command)" {
      print "left alone"
      return
    }
  }
  let argv = ($plan.command | split row " ")
  ^($argv | first) ...($argv | skip 1)
}

# The target, or the error every writing command gives when there is none:
# what to install, and what happens once it is there.
export def "terminal require" []: nothing -> any {
  let t = (terminal target)
  if $t != null { return $t }
  let plans = (registry | each {|t| terminal install-plan $t.name })
  let how = ($plans | each {|p| $"  ($p.terminal | fill --width 8) (if $p.command != null { $p.command } else { $p.note })" } | str join (char nl))
  error make {
    msg: "no terminal this distro can configure is installed — nothing was written"
    help: $"install one, then open a new shell: `terminal list` shows it found, `terminal shell` starts Nushell in it, `terminal theme` and `terminal font` configure it\n($how)"
  }
}

# The nu a terminal should start. The one on PATH, not `$nu.current-exe`:
# PATH holds the path the user installed — /opt/homebrew/bin/nu,
# ~/.cargo/bin/nu — while the running binary can be the versioned Cellar file
# behind that symlink, which stops existing at the next `brew upgrade`.
export def "terminal nu-path" []: nothing -> path {
  which nu | where type == external | get -o 0.path | default $nu.current-exe
}

# ── The target's configuration ────────────────────────────────────────────────
#
# One verb each, dispatching on the target's name. A verb that writes goes
# through `terminal require`, so without a terminal it is the error above; a
# verb that reads returns null or an empty record instead.

# Make Nushell what a new window of the target starts, or hand that back.
export def "terminal shell" [
  --reset   # let the terminal start its own default shell again
]: nothing -> nothing {
  match (terminal require).name {
    "ghostty" => { if $reset { ghostty shell --reset } else { ghostty shell } }
    "wezterm" => { if $reset { wezterm shell --reset } else { wezterm shell (terminal nu-path) } }
  }
}

def option-sides []: nothing -> list<record> {
  [
    { value: "none", description: "neither is Alt, both type the layout's characters; Alt+letter bindings do not work — the base" }
    { value: "left", description: "the left Option key is Alt, the right one types the layout's characters" }
    { value: "right", description: "the right Option key is Alt, the left one types the layout's characters" }
    { value: "both", description: "both are Alt: no layout characters from Option" }
    { value: "default", description: "drop ours: your terminal config, or the terminal, decides" }
  ]
}

# Which Option (Alt) key the shell gets as Alt; the other one types the
# layout's third level. Nothing given: what it is now.
export def "terminal option" [
  side?: string@option-sides  # left | right | both | none | default
]: nothing -> nothing {
  match (terminal require).name {
    "ghostty" => { ghostty option $side }
    "wezterm" => { wezterm option $side }
  }
}

# The target's configuration as it stands: its file, our keys in it, what it
# resolves. `terminal` names which one it is.
export def "terminal status" []: nothing -> record {
  let t = (terminal target)
  if $t == null { return { terminal: null } }
  { terminal: $t.name } | merge (match $t.name {
    "ghostty" => (ghostty status)
    "wezterm" => (wezterm status)
  })
}

# Our keys in the target's configuration.
export def "terminal settings" []: nothing -> record {
  let t = (terminal target)
  if $t == null { return {} }
  match $t.name {
    "ghostty" => (ghostty settings)
    "wezterm" => (wezterm settings)
  }
}

# Write keys into the target's file — its own vocabulary: Ghostty's
# `font-family`, WezTerm's `font_family`. `terminal font use` and `terminal theme use` know
# which; ghostty.nu and wezterm.nu hold the two `set`s.
export def "terminal set" [settings: record]: nothing -> nothing {
  match (terminal require).name {
    "ghostty" => { ghostty set $settings }
    "wezterm" => { wezterm set $settings }
  }
}

# Take the target's configuration back out.
export def "terminal reset" []: nothing -> nothing {
  match (terminal require).name {
    "ghostty" => { ghostty reset }
    "wezterm" => { wezterm reset }
  }
}

# Reload the target's open windows; true when they took it.
export def "terminal reload" []: nothing -> bool {
  let t = (terminal target)
  if $t == null { return false }
  match $t.name {
    "ghostty" => (ghostty reload)
    "wezterm" => (wezterm reload)
  }
}

# What the target resolves for one key.
export def "terminal live" [key: string]: nothing -> any {
  let t = (terminal target)
  if $t == null { return null }
  match $t.name {
    "ghostty" => (ghostty live $key)
    "wezterm" => (wezterm live $key)
  }
}

# The face a font family resolves to in the target — the family itself when
# it is installed, the terminal's built-in font when it is not. Null without
# a terminal to ask.
export def "terminal face" [family: string]: nothing -> any {
  let t = (terminal target)
  if $t == null { return null }
  match $t.name {
    "ghostty" => (ghostty face $family)
    "wezterm" => (wezterm face $family)
  }
}

# A new window of the target in a font, running argv — the font preview.
export def "terminal preview" [family: string, size: number, argv: list<string>]: nothing -> nothing {
  match (terminal require).name {
    "ghostty" => { ghostty preview $family $size $argv }
    "wezterm" => { wezterm preview $family $size $argv }
  }
}

# The keys a family and a size are written under, in the target's own
# vocabulary, with nothing for what was not given — a `terminal font use` without a
# size must not take a size written earlier back out.
export def "terminal font-keys" [family: any, size: any]: nothing -> record {
  let t = (terminal require)
  { ($t.font_key): $family, ($t.size_key): $size }
  | transpose key value | where value != null | transpose --header-row --as-record
}

# Write a resolved theme (`terminal theme resolve`) into the target's configuration,
# with an icon path for a terminal that takes one.
#
# Ghostty's `theme =` takes one of its own names, or an absolute path to a
# theme file — which is how a palette with its own sixteen is handed over,
# written under the state dir; the icon keys go in the same write. WezTerm
# gets a scheme file per theme under the state dir, `color_scheme_dirs`
# pointing there and `color_scheme` naming it — every theme becomes a file
# there, Ghostty's own included, because WezTerm cannot read those.
export def "terminal write-theme" [t: record, icon: any]: nothing -> nothing {
  match (terminal require).name {
    "ghostty" => {
      let value = (if $t.ghostty != "file" { $t.ghostty } else {
        let dir = (terminal theme state-dir | path join ghostty)
        mkdir $dir
        let f = ($dir | path join (terminal theme slug $t.name))
        terminal theme ghostty-file $t.terminal | save -f $f
        $f
      })
      ghostty set ({ theme: $value } | merge (if $icon == null { {} } else { { macos-icon: "custom", macos-custom-icon: $icon } }))
    }
    "wezterm" => {
      if $t.terminal == null {
        error make { msg: $"($t.name) has no colours WezTerm could be given: it is a Ghostty theme name and Ghostty is not installed here" }
      }
      let dir = (terminal theme state-dir | path join wezterm)
      mkdir $dir
      let name = $"nustro-(terminal theme slug $t.name)"
      terminal theme wezterm-file $t.terminal $name | save -f ($dir | path join $"($name).toml")
      wezterm set { color_scheme: $name, color_scheme_dirs: [$dir] }
    }
  }
}
