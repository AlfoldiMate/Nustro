#!/usr/bin/env nu
# uninstall.nu — take the distro out of Nushell again, and put back what was there
#
#   nu uninstall.nu               show what will be undone, ask once, do it
#   nu uninstall.nu --yes         no question
#   nu uninstall.nu --dry-run     the plan only
#   nu uninstall.nu --no-restore  do not put the configuration install.nu backed up back in place
#   nu uninstall.nu --purge       also set aside settings.nu and the rest of your directory's scaffold
#   nu uninstall.nu --skip-terminal --skip-harness
#
# Nothing is deleted except caches. Everything the distro wrote — the
# pointer config.nu, `.state/`, the generated init files — is MOVED to
# <config dir>/.backup/nustro-<stamp>/, so an uninstall you regret is a `mv`
# back, and one you do not is a single `rm -rf` of that directory. The
# configuration the installer moved away (`.backup/<stamp>/`, with its
# manifest) is moved back where it was.
#
# What it does not touch: this checkout (the last line printed is the `rm`
# for it), Nushell itself, the tools and fonts that were installed along the
# way — they are your package manager's — and history and the plugin
# registry, which are Nushell's own.
#
# Like install.nu's front door this imports nothing: it has to run when the
# checkout is half gone or the modules no longer parse. The two steps that
# need a module (the terminal's include line, the Claude Code marketplace)
# run in a child each and are reported, not required.

const ROOT = path self | path dirname

# What the scaffold put at the top of your directory (templates/user/).
const SCAFFOLD = [settings.nu README.md autoload completions themes modules plugins]
# The init files `nu-config tools setup` generates (modules/nu-config/tools.nu).
const GENERATED = [zoxide.nu atuin.nu carapace.nu]

def main [
  --yes (-y)       # do not ask
  --dry-run        # print the plan, change nothing
  --no-restore     # leave a backed-up previous configuration in .backup/
  --purge          # set aside settings.nu, the READMEs and your drop-ins too
  --skip-terminal  # leave the terminal's configuration alone
  --skip-harness   # leave the Claude Code marketplace registered
] {
  let user = $nu.default-config-dir
  let cfg = ($user | path join config.nu)
  let data = $nu.data-dir
  print $"(ansi cyan_bold)Nustro(ansi reset)  ($ROOT)"
  print $"  your config     ($user)"

  let text = (if ($cfg | path exists) { open --raw $cfg } else { "" })
  # Both spellings, as install.nu wrote one of them: the bare path, and the
  # backslash-escaped literal of a Windows checkout.
  let ours = (($text | str contains $ROOT) or ($text | str contains ($ROOT | to nuon)))
  if ($cfg | path exists) and (not $ours) {
    print $"  (ansi yellow)($cfg) does not point at this checkout(ansi reset) — it is some other configuration, and it is left alone."
    print "  nothing was changed"
    return
  }

  let stamp = (date now | format date '%Y%m%d-%H%M%S')
  let aside = ($user | path join .backup $"nustro-($stamp)")
  let previous = (if $no_restore { null } else { previous-config $user })
  # Restoring a whole configuration needs the scaffold out of its way; one
  # made with --keep-existing only ever gave up its config.nu, and the rest of
  # it is still in place between the scaffold's files.
  let whole = ($purge or ($previous != null and $previous.kind == "manifest" and $previous.full))

  # ── The plan: (what, from, to) rows, nothing done yet ───────────────────────
  let moves = (
    [
      (if ($cfg | path exists) { { what: "the pointer", from: $cfg, to: ($aside | path join config.nu) } })
      (if ($data | path join .state | path exists) { { what: "theme render, update check, agent sessions, OData registry", from: ($data | path join .state), to: ($aside | path join .state) } })
    ]
    ++ ($GENERATED | each {|f|
        let p = ($data | path join vendor autoload $f)
        if ($p | path exists) { { what: "generated init file", from: $p, to: ($aside | path join vendor-autoload $f) } }
      })
    ++ (if $whole {
        $SCAFFOLD | each {|f|
          let p = ($user | path join $f)
          if ($p | path exists) { { what: "your directory's scaffold", from: $p, to: ($aside | path join $f) } }
        }
      } else { [] })
    | compact
  )
  let caches = ([nu-complete odata] | each {|c| $nu.cache-dir | path join $c } | where {|p| $p | path exists })
  let restores = (if $previous == null { [] } else { $previous.moves })

  if ($moves | is-empty) and ($restores | is-empty) and ($caches | is-empty) {
    print "  nothing of the distro's is here — nothing to undo"
    return
  }

  print ""
  print $"(ansi cyan_bold)The plan(ansi reset)"
  if not $skip_terminal { print "  the terminal: remove the distro's file and include line from Ghostty's / WezTerm's config, where it is there" }
  if (not $skip_harness) and (which claude | is-not-empty) { print "  Claude Code: uninstall the plugins installed from this checkout's marketplace and remove the marketplace, if it is this checkout" }
  if ($moves | is-not-empty) {
    print $"  set aside in ($aside):"
    for m in $moves { print $"    ($m.from)  (ansi dark_gray)($m.what)(ansi reset)" }
  }
  for c in $caches { print $"  delete the cache ($c)" }
  if ($restores | is-not-empty) {
    print $"  put back the configuration from ($previous.dir):"
    for m in $restores { print $"    ($m.to)" }
  }
  if not $whole {
    let left = ($SCAFFOLD | where {|f| $user | path join $f | path exists })
    if ($left | is-not-empty) { print $"  (ansi dark_gray)left where it is, yours: ($left | str join ', ') — nothing reads them once config.nu is gone \(--purge sets them aside too\)(ansi reset)" }
  }
  print $"  (ansi dark_gray)untouched: history, the plugin registry, this checkout, nu, and every tool and font installed along the way(ansi reset)"
  print ""

  if $dry_run {
    print $"(ansi yellow)dry run — nothing was changed(ansi reset)"
    return
  }
  if not $yes {
    if not ((is-terminal --stdin) and (is-terminal --stdout)) {
      print --stderr "no terminal to ask on — `nu uninstall.nu --yes` does it without asking"
      exit 2
    }
    if (["no" "yes"] | input list "undo the install?") != "yes" {
      print "nothing was changed"
      return
    }
  }

  # ── Doing it ────────────────────────────────────────────────────────────────
  # The two module steps first, while `.state` — the terminal's pin, among
  # other things — is still where the modules look for it.
  let lib = { NU_LIB_DIRS: ($ROOT | path join modules) }
  if not $skip_terminal {
    print $"(ansi cyan_bold)Terminal(ansi reset)"
    let code = 'use terminal *; let done = (terminal list | where configured | get terminal); for t in $done { match $t { "ghostty" => { ghostty reset }, "wezterm" => { wezterm reset } } }; if ($done | is-empty) { print "  nothing of the distro in a terminal config" }'
    try { with-env $lib { ^$nu.current-exe -n -c $code } } catch {
      print $"  (ansi yellow)could not be undone from here(ansi reset) — the include line is one line: docs/cookbook/uninstall.md, step 1"
    }
  }
  if (not $skip_harness) and (which claude | is-not-empty) {
    print $"(ansi cyan_bold)Claude Code(ansi reset)"
    let code = 'use nu-config; let h = (nu-config harness status); if $h.registered == true { for p in ($h.plugins | where installed) { print $"  claude plugin uninstall ($p.plugin)@($h.marketplace)"; "" | ^claude plugin uninstall $"($p.plugin)@($h.marketplace)" | complete | ignore }; print $"  claude plugin marketplace remove ($h.marketplace)"; "" | ^claude plugin marketplace remove $h.marketplace | complete | ignore } else { print "  the marketplace is not this checkout — left alone" }'
    try { with-env $lib { ^$nu.current-exe -n -c $code } } catch {
      print $"  (ansi yellow)could not be undone from here(ansi reset) — `claude plugin marketplace list` shows what is registered"
    }
  }

  if ($moves | is-not-empty) {
    print $"(ansi cyan_bold)Set aside(ansi reset)  → ($aside)"
    for m in $moves {
      mkdir ($m.to | path dirname)
      mv $m.from $m.to
      print $"  moved     ($m.from)"
    }
  }
  for c in $caches { rm -rf $c; print $"  deleted   ($c)" }

  if ($restores | is-not-empty) {
    print $"(ansi cyan_bold)Put back(ansi reset)  ← ($previous.dir)"
    for m in $restores {
      if ($m.to | path exists) {
        # Only when the scaffold was left in place and a name collides; the
        # backed-up one stays in the backup, and the line says so.
        print $"  (ansi yellow)kept in the backup(ansi reset) ($m.from) — ($m.to) exists"
      } else {
        mkdir ($m.to | path dirname)
        mv $m.from $m.to
        print $"  restored  ($m.to)"
      }
    }
    if $previous.kind == "manifest" {
      rm -f ($previous.dir | path join .nustro-backup.nuon)
      # Empty now, unless something was kept back above.
      for d in [($previous.dir | path join .vendor-autoload) $previous.dir] {
        if ($d | path exists) and (ls --all $d | is-empty) { rm $d }
      }
    }
  }

  print ""
  print $"(ansi green_bold)Undone.(ansi reset) A new shell is (if ($restores | is-empty) { "Nushell with no configuration" } else { "the configuration you had before" })."
  if ($moves | is-not-empty) { print $"  what the distro had written is in ($aside) — delete it when you are sure" }
  print $"  the checkout is still at ($ROOT): (ansi dark_gray)rm -rf ($ROOT | to nuon)(ansi reset) removes it"
}

# The configuration install.nu moved out of the way, newest first: a
# `.backup/<stamp>/` with a manifest, or — from installs before 2026-10-01 —
# a `config.nu.backup-<stamp>` beside config.nu. Null when there is neither.
def previous-config [user: path]: nothing -> any {
  let root = ($user | path join .backup)
  let dirs = (if ($root | path exists) {
    ls $root | where type == dir | get name
    | where {|d| ($d | path basename) !~ '^nustro-' and ($d | path join .nustro-backup.nuon | path exists) }
    # A backup `install.nu --clean` made of this distro's own configuration
    # is not a configuration to go back to: restoring it would install the
    # distro again.
    | where {|d| not (open ($d | path join .nustro-backup.nuon) | get -o ours | default false) }
    | sort --reverse
  } else { [] })
  if ($dirs | is-not-empty) {
    let dir = ($dirs | first)
    let m = (open ($dir | path join .nustro-backup.nuon))
    return {
      kind: "manifest"
      dir: $dir
      full: ($m.entries != ["config.nu"])
      moves: (
        ($m.entries | each {|e| { from: ($dir | path join $e), to: ($user | path join $e) } })
        ++ ($m.vendor? | default [] | each {|v| { from: ($dir | path join .vendor-autoload $v), to: ($m.vendor_dir | path join $v) } })
        # The distro's state from beside the vendor directory (`install.nu --clean`, off macOS).
        ++ (if ($m.state_dir? | default null) != null { [{ from: ($dir | path join .data-state), to: $m.state_dir }] } else { [] })
        | where {|r| $r.from | path exists }
      )
    }
  }
  let legacy = (if ($user | path exists) { ls $user | get name | where {|f| ($f | path basename) =~ '^config\.nu\.backup-' } | sort --reverse } else { [] })
  if ($legacy | is-empty) { return null }
  { kind: "legacy", dir: $user, moves: [{ from: ($legacy | first), to: ($user | path join config.nu) }] }
}
