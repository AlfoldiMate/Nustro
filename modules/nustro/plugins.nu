# plugins — the plugins shipped next to `nu`, and the registry that names them
#
#   nustro plugins status             each plugin beside nu, and whether it is registered
#   nustro plugins add                register every one (again after a Nushell upgrade)
#   nustro bootstrap plugins notice   the startup line when a registered plugin's file is gone

# Developer examples that ship with nu; never worth registering.
export const DEV_PLUGINS = [example custom_values stress_internals]

# Plugins shipped next to the nu binary, and whether each is registered.
#
# `--registry --plugin-config` reads the registry FILE rather than the engine:
# a plain `plugin list` reports what this process loaded, which is nothing
# under `nu -n` — the installer's dry run runs there and used to report every
# plugin as unregistered. The flag needs the path spelled out, because a
# config-less nu knows $nu.plugin-path but refuses to default to it.
export def "plugins status" []: nothing -> table<name: string, registered: bool, path: string> {
  # A registry entry whose file is gone is not registered: Homebrew's Cellar
  # path carries the version, so the entries of 0.115.1 named files that an
  # upgrade to 0.116.0 deleted, and `gstat` was "Unable to spawn plugin"
  # while this listed it as fine (2026-10-02).
  let registered = (
    do -i { plugin list --registry --plugin-config $nu.plugin-path | where {|p| $p.filename | path exists } | get name } | default []
  )
  let dir = (plugin-dir)
  if $dir == null { return [] }
  ls $dir
  | where name =~ 'nu_plugin_'
  | get name
  | each {|p|
      let short = ($p | path basename | str replace 'nu_plugin_' '' | str replace --regex '\.exe$' '')
      { name: $short, registered: ($short in $registered), path: $p }
    }
}

# The directory the plugins are in: beside `nu`, following the symlinks `nu`
# is reached through one hop at a time and stopping at the first directory
# that holds any. ~/.local/bin/nu → /opt/homebrew/bin/nu → the Cellar: the
# first has none, and the list was empty there ("no plugins found next to
# nu", 2026-10-02). Null when no hop has any. `plugin add` records the file
# behind the link whichever directory it is given, so a Homebrew upgrade
# still leaves the entries naming a Cellar that is gone: `plugins status` then
# shows them unregistered, and `plugins add` is the fix.
def plugin-dir []: nothing -> any {
  mut exe = $nu.current-exe
  for _ in 1..8 {
    let dir = ($exe | path dirname)
    if (ls $dir | where name =~ 'nu_plugin_' | is-not-empty) { return $dir }
    let target = (ls -l $exe | get -o 0.target)
    if ($target | default "" | is-empty) { return null }
    $exe = ($dir | path join $target | path expand --no-symlink)
  }
  null
}

# Register every plugin next to the nu binary, except the developer examples.
#
# Nushell has no plugin MANAGER: `plugin add/list/rm/use/stop` only maintain a
# registry file and never fetch, build or version anything, and `plugin add`
# needs a binary already on disk. This is that same built-in mechanism, run
# over whatever your package manager installed alongside `nu`.
#
# Re-run after every Nushell upgrade: the registry is protocol-versioned.
export def "plugins add" []: nothing -> nothing {
  let todo = (plugins status | where name not-in $DEV_PLUGINS)
  if ($todo | is-empty) { print "no plugins found next to nu"; return }
  # Every one, registered or not: `plugin add` replaces an entry of the same
  # name, which is what refreshes one left by the previous Nushell.
  mut failed = []
  for p in $todo {
    let r = (try { plugin add $p.path; null } catch {|e| $e.msg })
    print (if $r == null { $"  plugin add ($p.name)" } else { $"  (ansi red)failed(ansi reset)     ($p.name): ($r)" })
    if $r != null { $failed = ($failed ++ [$p.name]) }
  }
  print (if ($failed | is-empty) { "done — restart Nushell, or `plugin use <name>` now" } else { $"($failed | length) of ($todo | length) could not be registered" })
}

# One line at an interactive start when a registered plugin's file is gone —
# what a Nushell upgrade leaves behind, since the registry names the versioned
# file (`gstat`: "Unable to spawn plugin", with nothing saying why, 2026-10-02).
# The check is `plugin list` and a `path exists` each, 1.7 ms, so it runs
# until it passes once for this Nushell version and leaves a marker; after
# that a start pays one `path exists` (µs) until the version changes.
export def "plugins notice" []: nothing -> nothing {
  let marker = ($nu.data-dir | path join .state nustro $"plugins-ok-((version).version)")
  if ($marker | path exists) { return }
  let gone = (plugin list | where {|p| not ($p.filename | path exists) } | get name)
  if ($gone | is-empty) {
    mkdir ($marker | path dirname)
    touch $marker
    return
  }
  print $"(ansi dark_gray)plugins: ($gone | str join ', ') registered from files that are gone \(a Nushell upgrade\) — (ansi reset)(ansi cyan)nustro plugins add(ansi reset)"
}

