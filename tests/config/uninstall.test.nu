# uninstall.nu, headless, against a config directory install.nu wrote in the
# test's own XDG dirs: the plan and nothing else on `--dry-run`; what the
# distro wrote moved to `.backup/nustro-<stamp>/`, never deleted; the
# configuration the installer had moved away put back exactly; a config.nu
# that is not this checkout's left alone; and no terminal means no question,
# so no `--yes` means nothing done.
use lib.nu *
use std/assert

def --env fresh-homes []: nothing -> string {
  let d = scratch
  $env.XDG_CONFIG_HOME = $d
  $env.XDG_DATA_HOME = (scratch)
  $env.XDG_CACHE_HOME = (scratch)
  $d | path join nushell
}

def install []: nothing -> record {
  ^$nu.current-exe ($ROOT | path join install.nu) --defaults --skip-deps --skip-plugins --skip-terminal --skip-harness | complete
}

def --wrapped uninstall [...flags: string]: nothing -> record {
  ^$nu.current-exe ($ROOT | path join uninstall.nu) --skip-harness ...$flags | complete
}

def files-under [dir: string]: nothing -> list<string> {
  if not ($dir | path exists) { return [] }
  let dir = $dir | str replace -a '\' '/'
  glob ($dir + "/**/*") --no-dir | each {|f| $f | path relative-to $dir | str replace -a '\' '/' } | sort
}

def "test uninstall puts the previous configuration back" [] {
  let user = fresh-homes
  mkdir ($user | path join scripts)
  "# theirs\n" | save ($user | path join config.nu)
  "$env.OLD = 1\n" | save ($user | path join env.nu)
  "def a [] {}\n" | save ($user | path join scripts a.nu)
  "ls\n" | save ($user | path join history.txt)
  let before = files-under $user
  let i = install
  assert equal $i.exit_code 0 ($i.stdout + $i.stderr)
  let ran = uninstall --yes
  assert equal $ran.exit_code 0 ($ran.stdout + $ran.stderr)
  assert equal (files-under $user | where $it !~ '^\.backup/') $before
  assert equal (open --raw ($user | path join config.nu)) "# theirs\n"
  # What the distro had written is set aside, not deleted — and only that is left in .backup.
  let aside = ls ($user | path join .backup) | get name
  assert equal ($aside | length) 1
  assert (($aside | first | path basename) starts-with "nustro-")
  assert ($aside | first | path join settings.nu | path exists)
  assert ($aside | first | path join config.nu | path exists)
  assert not ($env.XDG_DATA_HOME | path join nushell .state | path exists)
}

def "test uninstall of a first configuration leaves yours in place" [] {
  let user = fresh-homes
  let i = install
  assert equal $i.exit_code 0 ($i.stdout + $i.stderr)
  let ran = uninstall --yes
  assert equal $ran.exit_code 0 ($ran.stdout + $ran.stderr)
  assert not ($user | path join config.nu | path exists)
  assert ($user | path join settings.nu | path exists)
  assert ($user | path join autoload README.md | path exists)
  # A plain Nushell now: nothing of the distro in a new shell.
  let shell = ^$nu.current-exe -l -c 'scope commands | where name == "nu-config doctor" | length' | complete
  assert equal ($shell.stdout | str trim) "0" $shell.stderr
  # --purge takes the scaffold too; a second run has nothing left to do.
  let purge = uninstall --yes --purge
  assert equal $purge.exit_code 0 ($purge.stdout + $purge.stderr)
  assert not ($user | path join settings.nu | path exists)
  let again = uninstall --yes --purge
  assert ($again.stdout | str contains "nothing to undo") $again.stdout
}

def "test --dry-run prints the plan and changes nothing" [] {
  let user = fresh-homes
  install | ignore
  let before = files-under $user
  let ran = uninstall --dry-run
  assert equal $ran.exit_code 0 ($ran.stdout + $ran.stderr)
  let out = $ran.stdout | ansi strip
  assert ($out | str contains "the pointer") $out
  assert ($out | str contains "dry run — nothing was changed") $out
  assert equal (files-under $user) $before
}

def "test without a terminal and without --yes nothing is done" [] {
  let user = fresh-homes
  install | ignore
  let ran = uninstall
  assert equal $ran.exit_code 2
  assert ($ran.stderr | str contains "--yes") $ran.stderr
  assert ($user | path join config.nu | path exists)
}

def "test a config.nu of another configuration is left alone" [] {
  let user = fresh-homes
  mkdir $user
  "# theirs\n" | save ($user | path join config.nu)
  let ran = uninstall --yes
  assert equal $ran.exit_code 0 ($ran.stdout + $ran.stderr)
  assert ($ran.stdout | ansi strip | str contains "does not point at this checkout") $ran.stdout
  assert equal (files-under $user) [config.nu]
}

def "test a backup from before the manifest is restored" [] {
  # Installs before 2026-10-01 left the old file as config.nu.backup-<stamp>.
  let user = fresh-homes
  install | ignore
  "# theirs\n" | save ($user | path join config.nu.backup-20260901-120000)
  let ran = uninstall --yes
  assert equal $ran.exit_code 0 ($ran.stdout + $ran.stderr)
  assert equal (open --raw ($user | path join config.nu)) "# theirs\n"
  assert ($user | path join settings.nu | path exists)
}
