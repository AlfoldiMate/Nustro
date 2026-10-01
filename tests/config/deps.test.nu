# `nustro deps status | manager | install`: the five tools the distro is
# built around, and installing the missing ones with the machine's package
# manager — here a fake `brew` (lib.nu) alone on PATH, so every tool is
# missing whatever the machine has and nothing real is ever installed.
use lib.nu *
use std/assert
use nustro

def --env only-the-fake [--fail: list<string> = []]: nothing -> record {
  if $nu.os-info.name == "windows" { skip-test "the fake package manager is a shell script" }
  let fake = fake-brew --fail $fail
  $env.PATH = [$fake.bin]
  $fake
}

def "test status lists the five tools with the line that installs each" [] {
  only-the-fake
  let s = nustro deps status
  assert equal ($s | get tool) [starship zoxide atuin carapace vivid]
  assert ($s | all {|r| not $r.installed })
  assert equal (nustro deps manager) "brew"
  assert equal ($s | get command) ($s | get tool | each {|t| $"brew install ($t)" })
}

def "test without a package manager each tool is by hand, with its page" [] {
  $env.PATH = [(scratch)]
  assert equal (nustro deps manager) null
  let r = nustro deps install --no-setup
  assert equal ($r | get action | uniq) ["by hand"]
  assert ($r | all {|x| $x.detail starts-with "https://" })
}

def "test install runs the manager once per missing tool" [] {
  let fake = only-the-fake
  let r = nustro deps install --no-setup
  assert equal ($r | get action | uniq) [installed]
  assert equal (brew-calls $fake) ([starship zoxide atuin carapace vivid] | each {|t| $"install ($t)" })
  # What arrived is seen at once, and a second run has nothing to do.
  assert (nustro deps status | all {|x| $x.installed })
  assert equal (nustro deps install --no-setup | get action | uniq) [present]
  assert equal (brew-calls $fake | length) 5
}

def "test install of named tools leaves the others alone" [] {
  let fake = only-the-fake
  let r = nustro deps install atuin vivid --no-setup
  assert equal ($r | get tool) [atuin vivid]
  assert equal (brew-calls $fake) ["install atuin" "install vivid"]
  let wrong = try { nustro deps install nonesuch; "" } catch {|e| $e.msg }
  assert ($wrong | str contains "no tool called nonesuch") $wrong
}

def "test one tool failing is one line and the rest still install" [] {
  let fake = only-the-fake --fail [atuin]
  let r = nustro deps install --no-setup
  assert equal ($r | where action == failed | get tool) [atuin]
  assert ($r | where tool == atuin | get 0.detail | str contains "`brew install atuin` failed") ($r | to nuon)
  assert equal ($r | where action == installed | get tool) [starship zoxide carapace vivid]
}

def "test --dry-run prints the lines and runs nothing" [] {
  let fake = only-the-fake
  let r = nustro deps install --dry-run
  assert equal ($r | get action | uniq) ["would run"]
  assert equal (brew-calls $fake) []
}
