# modules/terminal/registry.nu: which terminal the commands configure, in the
# order the header promises — NUSTRO_TERMINAL, the one this session runs in,
# the pinned one, the first installed — and what a writing command says when
# there is none.
use lib.nu *
use std/assert
use terminal *
# What the module keeps to itself, by file: the two backends and the plumbing.
use terminal/ghostty.nu *
use terminal/wezterm.nu *
use terminal/registry.nu *
use terminal/theme.nu *
use terminal/palette.nu *
use terminal/font.nu *

# Both fakes on PATH, no pin, nothing running: the registry alone decides.
def --env both []: nothing -> record {
  let g = fake-ghostty
  let w = fake-wezterm
  # Neither pinned by the fakes nor "running", and no pin left by an earlier
  # test in this file: the data dir is the file's, not the test's.
  hide-env -i NUSTRO_TERMINAL TERM_PROGRAM
  rm -f ($nu.data-dir | path join .state terminal target.nuon)
  { ghostty: $g, wezterm: $w }
}

def "test list knows both, installed and not running" [] {
  let fakes = both
  let rows = terminal list
  assert equal ($rows | get terminal) [ghostty wezterm]
  assert equal ($rows | get installed) [true true]
  assert equal ($rows | get running) [false false]
  assert equal (terminal current) null
}

def "test the terminal the session runs in is the target" [] {
  let fakes = both
  $env.TERM_PROGRAM = "WezTerm"
  assert equal (terminal current | get terminal) wezterm
  assert equal (terminal target | get name) wezterm
  $env.TERM_PROGRAM = "ghostty"
  assert equal (terminal target | get name) ghostty
}

def "test NUSTRO_TERMINAL beats the terminal the session runs in" [] {
  let fakes = both
  $env.TERM_PROGRAM = "ghostty"
  $env.NUSTRO_TERMINAL = "wezterm"
  assert equal (terminal target | get name) wezterm
  $env.NUSTRO_TERMINAL = "nope"
  assert equal (terminal target | get name) ghostty "an unknown name is ignored"
}

def "test terminal use pins one, and the pin loses to the terminal the session runs in" [] {
  let fakes = both
  assert equal (terminal target | get name) ghostty "first installed, in registry order"
  terminal use wezterm
  assert equal (terminal target | get name) wezterm
  assert (($nu.data-dir | path join .state terminal target.nuon) | path exists)
  $env.TERM_PROGRAM = "ghostty"
  assert equal (terminal target | get name) ghostty
  let err = try { terminal use kitty; null } catch {|e| $e.msg }
  assert ($err | str contains "no terminal called") $err
}

def "test a pinned terminal that is not installed is skipped" [] {
  let fakes = both
  terminal use wezterm
  $env.PATH = ($env.PATH | where {|p| $p != $fakes.wezterm.bin })
  hide-env -i WEZTERM_EXECUTABLE_DIR
  if (which wezterm | is-not-empty) { skip-test "a real wezterm is on PATH beyond the fake" }
  assert equal (terminal target | get name) ghostty
}

def "test without a terminal the writing commands say what to install and what follows" [] {
  let fakes = both
  $env.PATH = ($env.PATH | where {|p| $p not-in [$fakes.wezterm.bin $fakes.ghostty.bin] })
  hide-env -i WEZTERM_EXECUTABLE_DIR GHOSTTY_BIN_DIR
  if (which wezterm | is-not-empty) or (which ghostty | is-not-empty) or ("/Applications/Ghostty.app" | path exists) or ("/Applications/WezTerm.app" | path exists) {
    skip-test "a real terminal is installed on this machine"
  }
  assert equal (terminal target) null
  let err = try { terminal shell; null } catch {|e| $e.details }
  assert ($err.msg | str contains "no terminal") $err.msg
  assert ($err.help | str contains "terminal shell") $err.help
  assert ($err.help | str contains "ghostty") $err.help
  assert ($err.help | str contains "wezterm") $err.help
  # The theme still renders for the shell, and says there was nothing to write to.
  terminal theme use onedark
  assert equal (terminal theme current | get name) onedark
  assert equal (terminal theme status | select terminal terminal_theme) { terminal: null, terminal_theme: null }
}

def "test default is Ghostty, WezTerm on Windows" [] {
  assert equal (terminal default) (if $nu.os-info.name == "windows" { "wezterm" } else { "ghostty" })
}

def "test install-plan names the command for this platform, or its note" [] {
  let fakes = both
  let g = terminal install-plan ghostty
  let w = terminal install-plan wezterm
  assert equal ($g | select terminal installed) { terminal: ghostty, installed: true }
  assert equal ($w | select terminal installed) { terminal: wezterm, installed: true }
  match $nu.os-info.name {
    "macos" => { assert equal ($w.command) "brew install --cask wezterm"; assert equal ($g.command) "brew install --cask ghostty" }
    "windows" => { assert equal ($w.command) "winget install wez.wezterm"; assert equal ($g.command) null; assert ($g.note | str contains "WezTerm") }
    _ => { assert equal ($w.command) null; assert ($w.note | str contains "wezterm.org") }
  }
  assert equal (terminal install-plan | get terminal) (terminal default)
}

def "test the state file is under the data dir, never the checkout" [] {
  let fakes = both
  terminal use ghostty
  let f = $nu.data-dir | path join .state terminal target.nuon
  assert ($f | path exists)
  assert not ($f | str starts-with $ROOT)
  assert equal (open $f | get name) ghostty
}
