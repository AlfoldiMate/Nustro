# `nustro bootstrap tools setup | status | remove`: the init files generated for
# installed tools land in the vendor autoload dir of the user directory
# under test, parse, and are removed again for a tool that is gone. Which
# tools exist is the machine's business: the generators run only for what
# is on PATH, and a runner with none of them still checks that nothing is
# written.
use lib.nu *
use std/assert

def "test setup writes a parsing file per installed tool and nothing else" [] {
  let dir = user-dir
  let ran = nu-l $dir 'nustro bootstrap tools setup; nustro bootstrap tools status | to nuon'
  assert equal $ran.exit_code 0 $ran.stderr
  let status = $ran.stdout | lines | last | from nuon
  let vendor = $dir.data | path join vendor autoload
  let files = if ($vendor | path exists) { ls $vendor | get name | path basename | sort } else { [] }
  assert equal $files ($status | where installed | get tool | each {|t| $"($t).nu" } | sort)
  assert ($status | all {|t| $t.state in [ok "not installed"] }) ($status | to nuon)
  for f in $files {
    let check = nu-l $dir $"nu-check ($vendor | path join $f | to nuon)"
    assert equal ($check.stdout | str trim) "true" $"($f) does not parse"
  }
}

def "test the generated files are what a shell loads after config.nu" [] {
  let dir = user-dir
  let ran = nu-l $dir 'print (nustro bootstrap tools dir) ($nu.vendor-autoload-dirs | last)'
  assert equal $ran.exit_code 0 $ran.stderr
  let lines = $ran.stdout | lines
  assert equal ($lines | first) ($lines | last) "tools dir is the last vendor autoload dir"
  assert ($lines | first | str starts-with $dir.data) "under the user directory's data dir"
}

def "test a second setup changes nothing and remove takes one file out" [] {
  let dir = user-dir
  nu-l $dir 'nustro bootstrap tools setup' | ignore
  let again = nu-l $dir 'nustro bootstrap tools setup'
  assert equal $again.exit_code 0 $again.stderr
  let out = $again.stdout | ansi strip
  assert not ($out | str contains "created") $out
  assert not ($out | str contains "file(s) changed") $out
  let installed = nu-l $dir 'nustro bootstrap tools status | where installed | get tool | to nuon' | get stdout | from nuon
  if ($installed | is-empty) { skip-test "no tool with an init file is installed here" }
  let tool = $installed | first
  let removed = nu-l $dir $"nustro bootstrap tools remove ($tool); nustro bootstrap tools status | where tool == ($tool) | get 0.state"
  assert ($removed.stdout | str contains "missing: run `nustro repair`") $removed.stdout
  assert not ($dir.data | path join vendor autoload $"($tool).nu" | path exists)
}

# A carapace that answers from a script and counts its calls: the generated
# file is tested for what it does with carapace's answers, not for carapace.
def fake-carapace []: nothing -> record {
  if $nu.os-info.name == "windows" { skip-test "the fake carapace is a shell script" }
  let root = scratch
  let bin = $root | path join bin
  mkdir $bin
  # $1 the command, $2 `nushell`, then the spans; the last one is the token.
  $"#!/bin/sh
echo \"$*\" >> ($root | path join log | to nuon)
for last; do :; done
case \"$1\" in
  broken\) printf '[{\"value\":\"ERR\",\"display\":\"ERR\",\"description\":\"it broke\"},{\"value\":\"_\",\"display\":\"_\"}]' ;;
  *\) case \"$last\" in
       -*\) printf '[{\"value\":\"--name \"},{\"value\":\"--network \"},{\"value\":\"--rm \"}]' ;;
       zz*\) printf '[{\"value\":\"ZZ-only-carapace-finds-this\"}]' ;;
       *\) printf '[{\"value\":\"alpha\",\"description\":\"first\"},{\"value\":\"beta\"}]' ;;
     esac ;;
esac
" | save ($bin | path join carapace)
  ^chmod +x ($bin | path join carapace)
  { bin: $bin, log: ($root | path join log) }
}

def "test the carapace file asks carapace once per slot and narrows it itself" [] {
  let fake = fake-carapace
  let dir = user-dir
  $env.PATH = ($env.PATH | prepend $fake.bin)
  let made = nu-l $dir 'nustro bootstrap tools setup --quiet'
  assert equal $made.exit_code 0 $made.stderr
  let f = $dir.data | path join vendor autoload carapace.nu
  let text = open --raw $f
  assert ($text | str contains "CARAPACE_BRIDGES") "the bridges"
  assert not ($text | str contains "$env.config = ") "no whole-record assignment"
  # Standalone: no config, no nu-complete module — and sourced twice, the way
  # a REPL has it after a `tools setup`.
  let run = {|code: string| ^$nu.current-exe -n -c $"source ($f | to nuon); source ($f | to nuon); let c = $env.config.completions.external.completer; ($code)" | complete }
  let calls = {|| if ($fake.log | path exists) { open --raw $fake.log | lines } else { [] } }
  let typed = do $run 'print (do $c { command: [docker run ""] } | get value | to nuon) (do $c { command: [docker run a] } | get value | to nuon) (do $c { command: [docker run al] } | get value | to nuon)'
  assert equal $typed.exit_code 0 $typed.stderr
  assert equal ($typed.stdout | lines) ["[alpha, beta]" "[alpha]" "[alpha]"]
  assert equal (do $calls) ["docker nushell docker run "] "three keystrokes, one carapace"
  # The dashes are a slot of their own; a token nothing local matches goes
  # to carapace as it is.
  let more = do $run 'print (do $c { command: [docker run --n] } | get value | to nuon) (do $c { command: [docker run zzq] } | get value | to nuon)'
  assert equal ($more.stdout | lines) ['["--name ", "--network "]' "[ZZ-only-carapace-finds-this]"] $more.stderr
  assert ("docker nushell docker run --" in (do $calls))
  assert ("docker nushell docker run zzq" in (do $calls))
  # The command word alone, and an error carapace reports as candidates,
  # are Nushell's to answer.
  let declined = do $run 'print (do $c { command: [docker] } | to nuon) (do $c { command: [broken ""] } | to nuon)'
  assert equal ($declined.stdout | lines) ["null" "null"] $declined.stderr
}

def "test an unknown command is looked up without starting brew" [] {
  # The hook used to run `brew which-formula`: 275 ms before the prompt came
  # back after a typo. The fake brew logs every call; there must be none.
  if $nu.os-info.name == "windows" { skip-test "the fake brew is a shell script" }
  let fake = fake-brew
  let cache = scratch
  mkdir ($cache | path join api internal)
  "ripgrep(14.1.0):rg\nfirst-one:twice other\nsecond-one:twice\n" | save ($cache | path join api internal executables.txt)
  let dir = user-dir
  let ask = {|cmd: string| with-env { PATH: ($env.PATH | prepend $fake.bin), HOMEBREW_CACHE: $cache } { nu-l $dir $"do $env.config.hooks.command_not_found ($cmd) | default '-' | ansi strip" } }
  let rg = do $ask rg
  assert equal $rg.exit_code 0 $rg.stderr
  assert equal ($rg.stdout | str trim) "rg is available via Homebrew: brew install ripgrep"
  assert equal (do $ask twice | get stdout | str trim) "twice is available via Homebrew: brew install first-one (also in second-one)"
  assert equal (do $ask nonesuch | get stdout | str trim) "-"
  assert equal (brew-calls $fake) []
  # A lazy module's word still gets its own answer first.
  assert (do $ask expand | get stdout | str contains "lazy `odata` module")
}

# `nu` reached through two symlinks, the plugins beside the second: the list
# is found by following the links, and an entry in the registry whose file
# does not exist is not registered.
def "test plugins are found through the symlinks nu is reached by" [] {
  if $nu.os-info.name == "windows" { skip-test "symlinks need a privilege on Windows"; return }
  let d = scratch
  let first = $d | path join first
  let second = $d | path join second
  mkdir $first $second
  ^ln -s $nu.current-exe ($second | path join nu)
  ^ln -s ($second | path join nu) ($first | path join nu)
  "#!/bin/sh\n" | save ($second | path join nu_plugin_fake)
  let mods = $ROOT | path join modules
  let r = ^($first | path join nu) -n -c $"const NU_LIB_DIRS = [($mods | to nuon)]; use nustro; nustro plugins status | to nuon" | complete
  assert equal $r.exit_code 0 $r.stderr
  assert equal ($r.stdout | from nuon) [{ name: fake, registered: false, path: ($second | path join nu_plugin_fake) }]
}

# A registry whose plugin file was deleted, as an upgrade leaves it: one line
# naming the plugin and the fix. With nothing wrong: silence, and the marker
# that makes the next start skip the check.
def "test a plugin registered from a file that is gone is one line at the start" [] {
  let plugin = $nu.current-exe | path expand | path dirname | path join (if $nu.os-info.name == "windows" { "nu_plugin_inc.exe" } else { "nu_plugin_inc" })
  if not ($plugin | path exists) { skip-test "no nu_plugin_inc next to nu"; return }
  let d = scratch
  let copy = $d | path join ($plugin | path basename)
  let registry = $d | path join plugin.msgpackz
  let config = $d | path join config.nu
  cp $plugin $copy
  ^$nu.current-exe -n -c $"plugin add --plugin-config ($registry | to nuon) ($copy | to nuon)"
  $"const NU_LIB_DIRS = [($ROOT | path join modules | to nuon)]\nuse nustro\n" | save $config
  let run = {|| with-env { XDG_DATA_HOME: ($d | path join data) } { ^$nu.current-exe --plugin-config $registry --config $config -c 'nustro bootstrap plugins notice' | complete } }
  let fine = do $run
  assert equal ($fine.stdout | str trim) "" $fine.stderr
  rm $copy
  # The marker of the run above says this version was fine: still silent.
  assert equal ((do $run).stdout | str trim) ""
  rm -r ($d | path join data)
  let gone = do $run
  assert ($gone.stdout | ansi strip | str contains "plugins: inc registered from files that are gone") ($gone.stdout + $gone.stderr)
  assert ($gone.stdout | ansi strip | str contains "nustro plugins add")
}
