# `nustro status` and `nustro repair` against a user directory of the test's
# own, and the shape of the command tree: two words, `nustro` and `terminal`,
# with the plumbing under `nustro bootstrap`.
use lib.nu *
use std/assert

def "test status names what needs attention and the command that settles it" [] {
  let dir = user-dir
  let ran = nu-l $dir 'nustro status | to nuon'
  assert equal $ran.exit_code 0 $ran.stderr
  let s = $ran.stdout | from nuon
  assert equal ($s | select layout yours) { layout: split, yours: $dir.config }
  assert equal $s.version (open ($ROOT | path join nustro.nuon) | get version)
  assert ("nustro" in ($s.modules | split row " ")) $s.modules
  assert ("terminal" in ($s.lazy | split row " ")) $s.lazy
  # A directory with a config.nu and nothing else: the scaffold is the gap.
  let scaffold = $s.attention | where what =~ 'scaffold'
  assert equal ($scaffold | get fix) ["nustro repair"] ($s.attention | to nuon)
  # `nustro` alone is the same record.
  let bare = nu-l $dir 'nustro | columns | to nuon'
  assert equal ($bare.stdout | from nuon) ($s | columns)
}

def "test repair writes what is missing and a second run changes nothing" [] {
  let dir = user-dir
  let first = nu-l $dir 'nustro repair | to nuon | print'
  assert equal $first.exit_code 0 $first.stderr
  let rows = $first.stdout | lines | last | from nuon
  assert equal ($rows | get step) [settings state scaffold tools plugins theme completion harness parse]
  assert equal ($rows | where step == scaffold | get 0.result) done
  assert ($rows | where result == failed | is-empty) ($rows | to nuon)
  assert ($dir.config | path join settings.nu | path exists)
  assert ($dir.config | path join autoload README.md | path exists)
  let again = nu-l $dir 'nustro repair | to nuon | print'
  assert equal $again.exit_code 0 $again.stderr
  assert equal ($again.stdout | lines | last | from nuon | get result | uniq) [ok] $again.stdout
  let after = nu-l $dir 'nustro status | get attention | where fix == "nustro repair" | to nuon'
  assert equal ($after.stdout | from nuon) []
}

def "test repair --dry-run says what it would do and writes nothing" [] {
  let dir = user-dir
  let ran = nu-l $dir 'nustro repair --dry-run | to nuon'
  assert equal $ran.exit_code 0 $ran.stderr
  assert equal ($ran.stdout | from nuon | where step == scaffold | get 0.result) would
  assert not ($dir.config | path join settings.nu | path exists)
  assert not ($dir.data | path join vendor autoload | path exists)
}

def "test a settings.nu and a state directory from before the rename still load and repair moves both" [] {
  let dir = user-dir --settings "const MODULES = [nu-config nu-complete terminal]\nconst MODULES_LAZY = [terminal]\n"
  let old = $dir.data | path join .state nu-config
  mkdir $old
  "{ last_good: \"abc\" }" | save ($old | path join upgrade.nuon)
  # The old name still enables the module, under its new name.
  let before = nu-l $dir '$env.NU_MODULES | to nuon'
  assert equal $before.exit_code 0 $before.stderr
  assert equal ($before.stdout | from nuon) [nustro nu-complete terminal]
  let ran = nu-l $dir 'nustro repair | where step in [settings state] | get result | to nuon | print'
  assert equal $ran.exit_code 0 $ran.stderr
  assert equal ($ran.stdout | lines | last | from nuon) [done done]
  let line = open --raw ($dir.config | path join settings.nu) | lines | where $it =~ '^const MODULES ='
  assert equal $line ["const MODULES = [nustro nu-complete terminal]"]
  assert not ($old | path exists)
  assert equal (open ($dir.data | path join .state nustro upgrade.nuon) | get last_good) abc
}

def "test repair --hard is the installer with every default and --reset wants a terminal" [] {
  let dir = user-dir
  let hard = nu-l $dir 'nustro repair --hard --dry-run'
  assert equal $hard.exit_code 0 $hard.stderr
  assert ($hard.stdout | ansi strip | str contains "dry run — nothing was changed") $hard.stdout
  assert not ($dir.config | path join settings.nu | path exists)
  let both = nu-l $dir 'nustro repair --hard --reset'
  assert ($both.stderr | str contains "one of them") $both.stderr
  # `complete` gives the child a pipe, not a terminal: refused before the installer starts.
  let reset = nu-l $dir 'nustro repair --reset'
  assert ($reset.stderr | str contains "needs a terminal") $reset.stderr
  assert ($dir.config | path join config.nu | path exists)
}

def "test the commands are two words and the plumbing is under bootstrap" [] {
  let dir = user-dir
  let ran = nu-l $dir 'use terminal *; scope commands | where type == custom | get name | to nuon'
  assert equal $ran.exit_code 0 $ran.stderr
  let names = $ran.stdout | from nuon
  for c in ["nustro" "nustro status" "nustro doctor" "nustro repair" "nustro upgrade" "nustro edit" "nustro set" "nustro completion explain" "nustro bootstrap tools setup" "nustro bootstrap scaffold init" "nustro bootstrap upgrade notice" "terminal" "terminal theme" "terminal theme use" "terminal font" "terminal font size"] {
    assert ($c in $names) $"($c) is not a command"
  }
  # What a person types is under one of the two; the old words and the two
  # backends are not commands.
  let old = $names | where $it =~ '^(nu-config|theme|font|ghostty|wezterm)\b'
  assert equal $old []
  for c in ["nustro tools setup" "nustro user init" "nustro upgrade check" "nustro plugins notice" "nustro distro-root"] {
    assert ($c not-in $names) $"($c) should be under bootstrap"
  }
}

def "test completion explain, status and clear answer under nustro completion" [] {
  let dir = user-dir
  let ran = nu-l $dir 'print (nustro completion explain "ls | where " | get layer); nustro completion clear; print (nustro completion status | get 0.what)'
  assert equal $ran.exit_code 0 $ran.stderr
  assert equal ($ran.stdout | lines) [columns "session memo (stor)"]
}
