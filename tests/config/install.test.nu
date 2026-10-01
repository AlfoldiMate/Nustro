# install.nu, headless: `--dry-run` prints the plan and writes nothing;
# `--defaults` writes exactly the scaffold, pointing at this checkout, with
# no override in settings.nu; a second run changes nothing; a configuration
# that is not the distro's moves to `.backup/<stamp>/` whole, or only its
# config.nu with `--keep-existing`; a file that keeps the new shell from
# loading the distro stops the install with its name; the front door refuses
# an older Nushell and a partial checkout before anything is imported. XDG_CONFIG_HOME names the directory
# the installer writes, so each test gets a fresh one, and HOME is the run's
# fake, so nothing here reaches a real Ghostty config.
use lib.nu *
use std/assert

def --env fresh-config-home []: nothing -> string {
  let d = scratch
  $env.XDG_CONFIG_HOME = $d
  # The data dir too: the installer looks there for another setup's init
  # files, and the file's tests would otherwise share one.
  $env.XDG_DATA_HOME = (scratch)
  $d | path join nushell
}

def --wrapped install [...flags: string]: nothing -> record {
  ^$nu.current-exe ($ROOT | path join install.nu) --skip-deps --skip-tools --skip-plugins --skip-terminal --skip-harness ...$flags | complete
}

# Forward slashes: a backslash is an escape in a glob pattern, and the
# paths are compared as the scaffold spells them.
def files-under [dir: string]: nothing -> list<string> {
  if not ($dir | path exists) { return [] }
  let dir = $dir | str replace -a '\' '/'
  glob ($dir + "/**/*") --no-dir | each {|f| $f | path relative-to $dir | str replace -a '\' '/' } | sort
}

const SCAFFOLD = [
  README.md
  autoload/README.md
  autoload/example.nu.off
  completions/README.md
  completions/hello.nu.off
  config.nu
  modules/README.md
  plugins/README.md
  settings.nu
  themes/README.md
  themes/palettes/example.nuon.off
]

def "test --dry-run prints the plan and writes nothing" [] {
  let user = fresh-config-home
  let ran = install --dry-run
  assert equal $ran.exit_code 0 $ran.stderr
  let out = $ran.stdout | ansi strip
  assert ($out | str contains $"writing config.nu → ($ROOT)") $out
  assert ($out | str contains "would write   settings.nu") $out
  assert ($out | str contains "dry run — nothing was changed") $out
  assert equal (files-under $user) []
}

def "test --defaults writes exactly the scaffold, pointing here, with no override" [] {
  let user = fresh-config-home
  let ran = install --defaults
  assert equal $ran.exit_code 0 $ran.stderr
  assert equal (files-under $user) $SCAFFOLD
  let cfg = open --raw ($user | path join config.nu)
  assert ($cfg | str contains ($ROOT | to nuon)) $cfg
  # The shell it wrote: split layout, the scaffold as written, no override.
  let shell = with-env { XDG_DATA_HOME: (scratch) } { ^$nu.current-exe -l -c 'print (nu-config install-status | get state) (nu-config knobs --overridden | length) (nu-config user status | where state != present | length)' | complete }
  assert equal $shell.exit_code 0 $shell.stderr
  assert equal ($shell.stdout | lines) [split "0" "0"]
}

def "test a second run keeps everything as it is" [] {
  let user = fresh-config-home
  install --defaults | ignore
  "# mine\n" | save -a ($user | path join settings.nu)
  let before = files-under $user | each {|f| { file: $f, hash: (open --raw ($user | path join $f) | hash md5) } }
  let ran = install --defaults
  assert equal $ran.exit_code 0 $ran.stderr
  assert ($ran.stdout | ansi strip | str contains "config.nu already points here")
  let after = files-under $user | each {|f| { file: $f, hash: (open --raw ($user | path join $f) | hash md5) } }
  assert equal $after $before
}

# What a machine that already had a Nushell configuration looks like: files
# Nushell reads around config.nu, a directory of the owner's, and the two
# things that are Nushell's own and must not move.
def foreign-config [user: string] {
  mkdir ($user | path join autoload) ($user | path join scripts)
  "# someone else's config\n" | save ($user | path join config.nu)
  "$env.OLD = 1\n" | save ($user | path join env.nu)
  "print old\n" | save ($user | path join autoload old.nu)
  "def a [] {}\n" | save ($user | path join scripts a.nu)
  "ls\n" | save ($user | path join history.txt)
}

def "test an existing configuration moves to .backup whole" [] {
  let user = fresh-config-home
  foreign-config $user
  let ran = install --defaults
  assert equal $ran.exit_code 0 ($ran.stdout + $ran.stderr)
  let files = files-under $user
  # History stayed; nothing of the old configuration is left beside the scaffold.
  assert equal ($files | where $it !~ '^\.backup/') ($SCAFFOLD ++ [history.txt] | sort)
  let backups = ls ($user | path join .backup) | get name
  assert equal ($backups | length) 1
  let b = $backups | first
  assert equal (files-under $b) [.nustro-backup.nuon autoload/old.nu config.nu env.nu scripts/a.nu]
  assert equal (open --raw ($b | path join config.nu)) "# someone else's config\n"
  let m = open ($b | path join .nustro-backup.nuon)
  assert equal $m.entries [autoload config.nu env.nu scripts]
  assert (open --raw ($user | path join config.nu) | str contains ($ROOT | to nuon))
}

def "test --dry-run over an existing configuration moves nothing" [] {
  let user = fresh-config-home
  foreign-config $user
  let before = files-under $user
  let ran = install --dry-run
  assert equal $ran.exit_code 0 ($ran.stdout + $ran.stderr)
  let out = $ran.stdout | ansi strip
  assert ($out | str contains "a configuration that is not this distro's") $out
  assert ($out | str contains "would move  env.nu") $out
  assert equal (files-under $user) $before
}

def "test --keep-existing sets only config.nu aside" [] {
  let user = fresh-config-home
  foreign-config $user
  let ran = install --defaults --keep-existing
  assert equal $ran.exit_code 0 ($ran.stdout + $ran.stderr)
  let b = ls ($user | path join .backup) | get name | first
  assert equal (files-under $b) [.nustro-backup.nuon config.nu]
  for f in [env.nu autoload/old.nu scripts/a.nu history.txt] {
    assert ($user | path join $f | path exists) $"($f) was to stay"
  }
}

def "test init files of another setup in the data dir move too" [] {
  # Off macOS the vendor autoload dir is not under the config dir, and a
  # starship.nu someone generated there would repaint the distro's prompt.
  let user = fresh-config-home
  let vendor = $env.XDG_DATA_HOME | path join nushell vendor autoload
  mkdir $vendor
  "# generated by someone\n" | save ($vendor | path join starship.nu)
  let ran = install --defaults
  assert equal $ran.exit_code 0 ($ran.stdout + $ran.stderr)
  assert not ($vendor | path join starship.nu | path exists)
  let b = ls ($user | path join .backup) | get name | first
  assert ($b | path join .vendor-autoload starship.nu | path exists)
  assert equal (open ($b | path join .nustro-backup.nuon) | get vendor) [starship.nu]
}

def "test a file that breaks the new shell stops the install, named" [] {
  # The failure this installer was reworked for: something beside config.nu
  # fails at startup, the distro never loads, and every later step used to
  # say `nu-config` is not a command.
  let user = fresh-config-home
  mkdir $user
  "source /nowhere/gone.nu\n" | save ($user | path join env.nu)
  let ran = install --defaults --keep-existing
  assert equal $ran.exit_code 1 ($ran.stdout + $ran.stderr)
  let out = $ran.stdout | ansi strip
  assert ($out | str contains "a new shell does not have the distro in it") $out
  assert ($out | str contains "env.nu") $out
  assert ($out | str contains "Stopped.") $out
  assert not ($out | str contains "Done.") $out
  # ... and the default, which clears it away, goes through.
  let again = install --defaults
  assert equal $again.exit_code 0 ($again.stdout + $again.stderr)
  assert ($again.stdout | ansi strip | str contains "loads the distro from") $again.stdout
}

def "test a settings.nu that does not parse stops a re-run, named" [] {
  let user = fresh-config-home
  install --defaults | ignore
  "let x = (\n" | save -a ($user | path join settings.nu)
  let ran = install --defaults
  assert equal $ran.exit_code 1 ($ran.stdout + $ran.stderr)
  let out = $ran.stdout | ansi strip
  assert ($out | str contains "a new shell does not have the distro in it") $out
  assert ($out | str contains "settings.nu") $out
}

# A copy of the front door beside a manifest of the test's own: what
# install.nu says before it has imported anything.
def front-door [manifest: string, ...files: string]: nothing -> record {
  let d = scratch
  cp ($ROOT | path join install.nu) $d
  $manifest | save ($d | path join nustro.nuon)
  for f in $files {
    mkdir ($d | path join $f | path dirname)
    "" | save ($d | path join $f)
  }
  ^$nu.current-exe ($d | path join install.nu) --defaults | complete
}

def "test a Nushell older than nustro.nuon requires is refused" [] {
  let ran = front-door '{ requires_nu: "99.0" }' distro.nu defaults.nu bootstrap/installer.nu modules/nu-config/mod.nu modules/terminal/mod.nu templates/config.nu
  assert equal $ran.exit_code 1
  let err = $ran.stderr | ansi strip
  assert ($err | str contains $"this is Nushell ((version).version)") $err
  assert ($err | str contains "the distro needs 99.0 or later") $err
}

def "test a checkout that is not whole is refused" [] {
  let ran = front-door '{ requires_nu: "0.116" }' distro.nu
  assert equal $ran.exit_code 1
  let err = $ran.stderr | ansi strip
  assert ($err | str contains "is not a whole checkout") $err
  assert ($err | str contains "bootstrap/installer.nu") $err
}

def "test --dry-run names the tools it would install and runs none" [] {
  if $nu.os-info.name == "windows" { skip-test "the fake package manager is a shell script" }
  let user = fresh-config-home
  let fake = fake-brew
  # Only the fake and nu's own directory: every tool is missing, whatever
  # this machine has.
  let ran = with-env { PATH: [$fake.bin ($nu.current-exe | path dirname)] } {
    ^$nu.current-exe ($ROOT | path join install.nu) --dry-run --skip-tools --skip-plugins --skip-terminal --skip-harness | complete
  }
  assert equal $ran.exit_code 0 ($ran.stdout + $ran.stderr)
  let out = $ran.stdout | ansi strip
  assert ($out | str contains "brew can install: starship, zoxide, atuin, carapace, vivid") $out
  assert ($out | str contains "would run starship  brew install starship") $out
  assert equal (brew-calls $fake) []
}

def "test the installer refuses to write into a checkout of the distro" [] {
  # The test is on distro.nu being there, whichever checkout it is.
  let d = scratch
  mkdir ($d | path join nushell)
  "# a checkout\n" | save ($d | path join nushell distro.nu)
  $env.XDG_CONFIG_HOME = $d
  let ran = install --defaults
  assert equal $ran.exit_code 1
  assert ($ran.stderr | str contains "is a checkout of the distro") $ran.stderr
  assert equal (files-under ($d | path join nushell)) [distro.nu]
}
