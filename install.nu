#!/usr/bin/env nu
# install.nu — point Nushell at this distro, and give you a directory of your own
#
#   nu install.nu                 the interactive installer
#   nu install.nu --defaults      the whole thing, no questions: an existing configuration backed
#                                 up, the missing tools and the platform's terminal installed
#   nu install.nu --minimal       nu-config, nu-complete and terminal only; the rest is `nu-config module enable` away
#   nu install.nu --dry-run       print the plan, change nothing
#   nu install.nu --keep-existing leave what is in the config directory where it is; only config.nu is replaced
#   nu install.nu --clean         start from an empty directory, whatever is there: all of it is backed up first
#   nu install.nu --skip-deps --skip-tools --skip-plugins --skip-terminal --skip-harness
#
# Idempotent: safe to re-run after `git pull`, after installing a tool, or
# after upgrading Nushell. `nu uninstall.nu` takes it back.
#
# This file is the front door and nothing else: it checks that the installer
# can run at all — this Nushell is the one nustro.nuon requires, the checkout
# is whole, the installer parses — and says so in a sentence when it cannot.
# The installer itself is bootstrap/installer.nu, which imports the distro's
# modules at parse time: on a Nushell that is too old, or in a clone that was
# interrupted, that is a parse error about a module the reader has never
# heard of, before a single line has run. So nothing here imports anything,
# and the syntax is kept to what Nushell has had for years.

const ROOT = path self | path dirname

def fail [msg: string, ...help: string] {
  print --stderr $"(ansi red_bold)cannot install:(ansi reset) ($msg)"
  for h in $help { print --stderr $"  ($h)" }
  exit 1
}

def --wrapped main [...args: string] {
  if ("--help" in $args) or ("-h" in $args) {
    open --raw ($ROOT | path join install.nu) | lines | skip 1 | take while {|l| ($l starts-with "#") and ($l !~ 'This file is') }
    | each {|l| $l | str replace --regex '^# ?' '' } | str join (char nl) | print
    return
  }

  # 1. The checkout is whole. A clone cut short has some of these and not others.
  let needed = [nustro.nuon distro.nu defaults.nu bootstrap/installer.nu modules/nu-config/mod.nu modules/terminal/mod.nu templates/config.nu]
  let absent = ($needed | where {|f| not ($ROOT | path join $f | path exists) })
  if ($absent | is-not-empty) {
    (fail $"($ROOT) is not a whole checkout — missing ($absent | str join ', ')"
      $"an interrupted clone or a partial copy: `git -C '($ROOT)' status`, then `git -C '($ROOT)' checkout -- .` or clone again")
  }

  # 2. This Nushell is new enough. The version is read as text: the fields of
  # `version` are not the same record on every release this has to refuse.
  let req = (open ($ROOT | path join nustro.nuon) | get requires_nu)
  let have = (version | get version)
  let want = ($req | split row "." | each {|x| $x | into int })
  let got = ($have | split row "." | first 2 | each {|x| $x | into int })
  if ($got.0 < $want.0) or ($got.0 == $want.0 and $got.1 < $want.1) {
    (fail $"this is Nushell ($have) at ($nu.current-exe); the distro needs ($req) or later"
      "upgrade it with what installed it — `brew upgrade nushell`, `winget upgrade Nushell.Nushell`, `cargo install nu --locked` —"
      "or run the bootstrap again, which offers to: bootstrap/install.sh, bootstrap/install.ps1"
      "check which `nu` is first on PATH if you have already upgraded: an older one may be ahead of it")
  }

  # 3. The installer parses with this Nushell. `nu-check` follows its `use`
  # lines into the modules, so this is also the test that they do.
  let installer = ($ROOT | path join bootstrap installer.nu)
  let parsed = (^$nu.current-exe -n -c $"if not \(nu-check --debug ($installer | to nuon)\) { exit 1 }" | complete)
  if $parsed.exit_code != 0 {
    print --stderr ($parsed.stderr | str trim)
    (fail $"the installer in ($ROOT) does not parse with Nushell ($have)"
      $"the checkout has local changes or is mid-update: `git -C '($ROOT)' status`, `git -C '($ROOT)' pull --ff-only`")
  }

  # -n: the installer must not depend on a configuration it is about to
  # replace — a broken env.nu in the target directory is one of the things
  # it exists to clear away.
  try { ^$nu.current-exe -n $installer ...$args } catch { exit ($env.LAST_EXIT_CODE? | default 1) }
}
