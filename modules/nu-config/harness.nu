# harness — the agent harnesses this distro ships plugins for
#
#   nu-config harness status     the harness on PATH, the marketplace registered, each plugin against its module
#   nu-config harness register   register this checkout as a Claude Code marketplace (idempotent)
#
# One harness today, Claude Code: `harness/claude-code/<plugin>/` holds one
# plugin per module that wants one, and `.claude-plugin/marketplace.json` at
# the distro root (where Claude Code looks for it) lists them. A plugin is a
# client of the shell — it runs `nu -l -c "use <module> *; …"` — so nothing
# here copies code, and a plugin is named after its module so that `status`
# can put the two side by side: a plugin installed for a module that is off,
# or a module on with its plugin not installed, is worth one line.
#
# A directory marketplace is used in place (Claude Code records the path and
# reads the manifest from it), so `git pull` updates the marketplace; a
# plugin, though, is copied into Claude Code's cache at its `version`, and a
# change to one is a version bump plus `claude plugin update <name>@<market>`.
# Registering is idempotent: adding the same path again is a no-op, adding
# another path under the same name re-points it (verified 2026-09-20, Claude
# Code 2.1.x), which is what a live checkout replacing a dev one wants.
#
# This file is modules/nu-config/harness.nu; `distro-root` lives in mod.nu,
# which imports this file, so the root is derived here from the file's own
# location instead.

const ROOT = path self | path dirname | path dirname | path dirname
const MARKETPLACE = $ROOT | path join .claude-plugin marketplace.json

# The marketplace manifest: its name and the plugins it lists, each with the
# module of the same name when there is one.
def marketplace []: nothing -> record<name: string, plugins: table> {
  let m = open $MARKETPLACE
  {
    name: $m.name
    plugins: ($m.plugins | each {|p|
      let module = if ($ROOT | path join modules $p.name | path type) == "dir" { $p.name } else { null }
      { name: $p.name, source: ($ROOT | path join $p.source | path expand), module: $module }
    })
  }
}

# `claude plugin marketplace list --json`, or [] without claude.
def registered-marketplaces []: nothing -> list {
  if (which claude | is-empty) { return [] }
  let r = ^claude plugin marketplace list --json | complete
  if $r.exit_code != 0 { return [] }
  try { $r.stdout | from json } catch { [] }
}

# `claude plugin list --json`, or [] without claude.
def installed-plugins []: nothing -> list {
  if (which claude | is-empty) { return [] }
  let r = ^claude plugin list --json | complete
  if $r.exit_code != 0 { return [] }
  try { $r.stdout | from json } catch { [] }
}

# Where things stand: `claude` on PATH (or null), whether this checkout is the
# registered marketplace of that name (`registered`: true, false, or the path
# of another checkout that holds the name), and one row per plugin: its
# module, whether that module is enabled here, whether the plugin is
# installed and at which version, and the command that installs it.
export def "harness status" []: nothing -> record {
  let m = marketplace
  let claude = which claude | get -o 0.path
  let mine = registered-marketplaces | where name == $m.name | get -o 0
  let registered = if $mine == null { false } else if (($mine.path? | default "") | path expand) == $ROOT { true } else { $mine.path? | default $mine.installLocation? }
  let installed = installed-plugins
  let enabled = $env.NU_MODULES? | default []
  {
    harness: "claude-code"
    claude: $claude
    marketplace: $m.name
    registered: $registered
    plugins: ($m.plugins | each {|p|
      let inst = $installed | where id == $"($p.name)@($m.name)" | get -o 0
      {
        plugin: $p.name
        module: $p.module
        enabled: (if $p.module == null { null } else { $p.module in $enabled })
        installed: ($inst != null)
        version: ($inst | get -o version)
        install: $"claude plugin install ($p.name)@($m.name)"
      }
    })
  }
}

# Register this checkout with Claude Code as the marketplace named in
# `.claude-plugin/marketplace.json`. Says so when it already is, re-points
# when another checkout held the name, and prints the install line for each
# plugin whose module is enabled and which is not installed.
export def "harness register" []: nothing -> nothing {
  let st = harness status
  if $st.claude == null {
    print $"(ansi dark_gray)claude is not on PATH — nothing to register(ansi reset)"
    return
  }
  if $st.registered == true {
    print $"  (ansi green)ok(ansi reset) marketplace ($st.marketplace) → ($ROOT)"
  } else {
    if ($st.registered | describe) == "string" {
      print $"  (ansi yellow)re-pointing marketplace ($st.marketplace) from ($st.registered)(ansi reset)"
    }
    let r = ^claude plugin marketplace add $ROOT | complete
    if $r.exit_code != 0 {
      error make --unspanned { msg: $"claude plugin marketplace add ($ROOT): ($r.stderr | str trim)" }
    }
    print $"  (ansi green)ok(ansi reset) marketplace ($st.marketplace) → ($ROOT)"
  }
  for p in ($st.plugins | where not installed) {
    let note = if $p.enabled == false { $" — module ($p.module) is disabled here" } else { "" }
    print $"  (ansi dark_gray)--(ansi reset) ($p.plugin | fill --width 12) ($p.install)($note)"
  }
  for p in ($st.plugins | where installed) {
    print $"  (ansi green)ok(ansi reset) ($p.plugin | fill --width 12) installed ($p.version)"
  }
}
