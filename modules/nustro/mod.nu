# nustro — the distro's own command: where it stands, and how to fix it
#
#   nustro                     = nustro status
#   nustro status              one screen: version, behind or not, what needs attention
#   nustro doctor              the full health check: roots, tools, plugins, parse
#   nustro repair              re-run every wiring step; `--hard` re-runs the installer
#   nustro upgrade             pull the distro, then the Claude Code plugins; `upgrade status | rollback` around it
#   nustro edit                open your own config directory in $EDITOR; `edit distro` the checkout
#   nustro set <assignment>    one knob into your settings.nu, in its place
#   nustro knobs               every knob, its shipped default, and your value
#   nustro module …            list | info | check | help | enable | disable | lint
#   nustro deps …              the tools (starship, zoxide, atuin, carapace, vivid): status | install
#   nustro plugins …           the plugins shipped next to `nu`: status | add
#   nustro completion …        Tab: explain | status | clear | fetch
#   nustro harness …           the Claude Code marketplace this checkout is: status | register | update
#   nustro startup-time        time cold starts; `loaded-files` finds a slow import
#   nustro bootstrap …         what the installer, the startup hooks and `repair` run — not for every day
#
# `help nustro` lists everything.

# Where the two directories are: `root`, `user-root`, `layout`, `config-dir`.
use roots.nu *
# Tool init files, for `doctor` and `status`; the commands are `nustro bootstrap tools …`.
use tools.nu *
# The scaffold, for `edit` and `doctor`; `nustro set` is the one a person types.
use user.nu *
export use user.nu ["set"]
# The tools themselves: `nustro deps status | manager | install`
export use deps.nu *
# Is the checkout behind its remote: `nustro upgrade`, `upgrade status`, `upgrade rollback`
use upstream.nu *
export use upstream.nu [upgrade "upgrade status" "upgrade rollback"]
# The plugins beside nu: `nustro plugins status | add`
use plugins.nu *
export use plugins.nu ["plugins status" "plugins add"]
# The Claude Code marketplace this checkout is: `nustro harness status | register | update`
export use harness.nu *
# Tab, as a person asks about it: `nustro completion explain | status | clear | fetch`
export use completion.nu *
# Everything else the files export: `nustro bootstrap …`
export use bootstrap.nu
# Completion caches, for `doctor`.
use nu-complete *

# `nustro` alone is `nustro status`.
export def main []: nothing -> record { status }

# One screen: where the distro stands and what needs attention, each line of
# `attention` with the command that settles it. State files, PATH and one
# `nu -n` for the scaffold (20 ms) — no network, no git, no `claude`; `doctor`
# is the long form.
export def status []: nothing -> record {
  let inst = (layout)
  let up = (upgrade status)
  let req = ((manifest).requires_nu? | default "0.0")
  let mods = (mod-list | where enabled)
  let theme_file = ($nu.data-dir | path join .state theme theme.nuon)
  let theme = (if ($theme_file | path exists) { open $theme_file } else { null })
  let settings = ($inst.user | path join settings.nu)
  let detached = ($up.branch? != null and (upgrade branch) == null)
  let attention = ([
    (if (nu-older-than $req) { { what: $"Nushell ((version).version) is older than the ($req) the distro needs", fix: "upgrade nu" } })
    (if $inst.state != "split" { { what: $"layout is ($inst.state), not a user directory of its own", fix: $"nu ($inst.distro | path join install.nu)" } })
    (if $detached { { what: $"rolled back, off ($up.branch)", fix: "nustro upgrade" } })
    (if (not $detached) and $up.error == null and $up.behind > 0 and $up.head == (upgrade head) { { what: $"($up.behind) commit\(s\) behind ($up.upstream)", fix: "nustro upgrade" } })
    (if ($settings | path exists) and not (do -i { nu-check $settings } | default false) { { what: "settings.nu does not parse — a new shell starts without the distro", fix: "nustro edit" } })
    (do { let n = (try { scaffold status | where state == "missing" | length } catch { 0 }); if $n > 0 { { what: $"($n) scaffold file\(s\) missing", fix: "nustro repair" } } })
    (do { let t = (tools status | where state !~ '^(ok|not installed)$' | get tool); if ($t | is-not-empty) { { what: $"init file out of step: ($t | str join ', ')", fix: "nustro repair" } } })
    (do { let t = (deps status | where not installed | get tool); if ($t | is-not-empty) { { what: $"not installed: ($t | str join ', ')", fix: "nustro deps install" } } })
    (do { let p = (plugins status | where not registered and name not-in $DEV_PLUGINS | get name); if ($p | is-not-empty) { { what: $"plugins not registered: ($p | str join ', ')", fix: "nustro plugins add" } } })
    ...($mods | where deps =~ 'missing' | each {|m| { what: $"($m.module): a tool it needs is missing", fix: $"nustro module check ($m.module)" } })
    (if $theme != null and (($theme.rendered? | default (date now)) < (ls ($inst.distro | path join themes) | get modified | math max)) { { what: "a theme template is newer than the render", fix: "nustro repair" } })
  ] | compact)
  {
    version: ((manifest).version? | default "?")
    head: ((upgrade head) | default "" | str substring 0..<7)
    upstream: (if $up.error != null { $up.error } else if $up.behind == 0 { $"up to date with ($up.upstream)" } else { $"($up.behind) behind ($up.upstream)" })
    checked: $up.checked
    nushell: (version).version
    layout: $inst.state
    distro: $inst.distro
    yours: $inst.user
    modules: ($mods | where not lazy | get module | str join " ")
    lazy: ($mods | where lazy | get module | str join " ")
    theme: ($theme | get -o name)
    attention: $attention
  }
}

# Health check for the whole setup.
export def doctor []: nothing -> nothing {
  let ok = $"(ansi green)ok(ansi reset)"
  let bad = $"(ansi red)!!(ansi reset)"
  let inst = (layout)

  # The oldest Nushell the distro runs on is nustro.nuon's: every completer
  # takes the inputs 0.116 binds by name (`place.command`), and on 0.115 a
  # spec's Tab silently falls back to files. CI pins the same version.
  let v = (version)
  let req = ((manifest).requires_nu? | default "0.0")
  let need = (if (nu-older-than $req) { $"  (ansi red)the distro needs ($req) or later — Tab for brew, git and cargo offers only files here(ansi reset)" } else { "" })
  print $"(ansi cyan_bold)Nushell(ansi reset) ($v.version)  ($nu.current-exe)($need)"
  let up = (upgrade status)
  let behind = (if $up.error == null and $up.behind > 0 { $"  (ansi yellow)($up.behind) behind ($up.upstream) — nustro upgrade(ansi reset)" } else { "" })
  print $"(ansi cyan_bold)Distro(ansi reset)  ($inst.distro)($behind)"
  print $"(ansi cyan_bold)Yours(ansi reset)   ($inst.user)"
  let mark = (match $inst.state { "split" => $ok, _ => $"(ansi yellow)??(ansi reset)" })
  print $"(ansi cyan_bold)Layout(ansi reset)  ($mark) ($inst.state)"
  if $inst.state == "in-place" {
    print $"          (ansi yellow)the checkout is doubling as the config dir — `nu install.nu` splits them(ansi reset)"
  }
  print ""

  print $"(ansi cyan_bold)Files(ansi reset)"
  print $"  config    ($nu.config-path)"
  print $"  settings  ((user-root) | path join settings.nu)"
  print $"  history   ($nu.history-path)"
  print $"  plugins   ($nu.plugin-path)"
  print $"  autoload  ($nu.user-autoload-dirs | str join ', ')"
  # Compare resolved paths: a symlinked config dir comes back resolved in
  # $nu.data-dir while $nu.vendor-autoload-dirs keeps the unresolved spelling.
  let vdir = (tools dir)
  let vmark = if ($nu.vendor-autoload-dirs | any {|d| ($d | path expand) == ($vdir | path expand) }) { $ok } else { $bad }
  print $"  vendor    ($vmark) ($vdir)"
  # The scaffold: the READMEs, the examples and settings.nu that `scaffold init`
  # writes, judged by content against the templates, never by mtime.
  let missing = (scaffold status | where state == "missing" | length)
  if $missing == 0 {
    print $"  scaffold  ($ok) complete"
  } else {
    print $"  scaffold  (ansi yellow)??(ansi reset) ($missing) file(if $missing == 1 { '' } else { 's' }) missing — nustro repair"
  }
  print ""

  print $"(ansi cyan_bold)Search paths(ansi reset)  \(yours first\)"
  # $env, not the const: this module is also imported by install.nu, which
  # runs as a script and so has none of the config's parse-time constants.
  for d in ($env.NU_LIB_DIRS? | default []) {
    let m = if ($d | path exists) { $ok } else { $"(ansi dark_gray)--(ansi reset)" }
    print $"  ($m) ($d)"
  }
  print ""

  print $"(ansi cyan_bold)Parse(ansi reset)"
  let parsed = (do -i { nu-check ((root) | path join distro.nu) } | default false)
  print $"  (if $parsed { $ok } else { $bad }) distro.nu and everything it sources"
  # what `upgrade rollback` returns to
  if $parsed { upgrade good }
  print ""

  print $"(ansi cyan_bold)Tools(ansi reset)"
  for t in (tools status) {
    let m = (match $t.state {
      "ok" => $ok
      "not installed" => $"(ansi dark_gray)--(ansi reset)"
      _ => $"(ansi yellow)??(ansi reset)"
    })
    print $"  ($m) ($t.tool | fill --width 9) ($t.state)"
  }
  # The ones with no init file — starship, vivid — and the line that gets
  # any missing one: `deps status` is five `which` calls, 1.2 ms (`timeit`, 2026-10-01).
  let deps = (deps status)
  let absent = ($deps | where not installed)
  for t in ($deps | where tool not-in (tools status | get tool)) {
    if $t.installed {
      print $"  ($ok) ($t.tool | fill --width 9) ok"
    } else {
      print $"  (ansi dark_gray)--(ansi reset) ($t.tool | fill --width 9) not installed"
    }
  }
  if ($absent | is-not-empty) { print $"  (ansi dark_gray)install the missing ones with: nustro deps install(ansi reset)" }
  print ""

  # The theme is read from its state file rather than through the terminal
  # module, which is lazy: this must not be what loads it.
  print $"(ansi cyan_bold)Theme(ansi reset)"
  let theme_file = ($nu.data-dir | path join .state theme theme.nuon)
  if ($theme_file | path exists) {
    let t = (open $theme_file)
    let stale = (($t.rendered? | default (date now)) < (ls ((root) | path join themes) | get modified | math max))
    print $"  ($ok) ($t.name | default 'no theme') — tier ($t.tier), bat ($t.bat), rendered ($t.rendered? | default '?' | format date '%Y-%m-%d %H:%M')"
    if $stale { print $"  (ansi yellow)a template is newer than the render — `terminal theme sync`(ansi reset)" }
  } else {
    print $"  (ansi dark_gray)--(ansi reset) nothing rendered: the terminal's sixteen colours by name — `terminal theme use <name>`"
  }
  print ""

  print $"(ansi cyan_bold)Plugins(ansi reset)"
  let pl = (plugins status)
  if ($pl | is-empty) {
    print "  none found next to nu"
  } else {
    for p in $pl {
      let m = if $p.registered { $ok } else { $"(ansi dark_gray)--(ansi reset)" }
      print $"  ($m) ($p.name)"
    }
    if ($pl | where not registered and name not-in $DEV_PLUGINS | is-not-empty) {
      print $"  (ansi dark_gray)not registered, or registered from a file that is gone: nustro plugins add(ansi reset)"
    }
  }
  print ""

  # The harness side: is this checkout registered with Claude Code as a
  # plugin marketplace, and does each plugin match its module. Two `claude`
  # calls, 2026-09-20: 0.35 s together, the one slow line here — and skipped
  # entirely when claude is not on PATH.
  print $"(ansi cyan_bold)Claude Code(ansi reset)"
  if (which claude | is-empty) {
    print $"  (ansi dark_gray)-- claude not on PATH; the marketplace in .claude-plugin/ waits for it(ansi reset)"
  } else {
    let h = (harness status)
    match $h.registered {
      true => { print $"  ($ok) marketplace ($h.marketplace) is this checkout" }
      false => { print $"  (ansi dark_gray)--(ansi reset) marketplace ($h.marketplace) not registered — nustro harness register" }
      $other => { print $"  (ansi yellow)??(ansi reset) marketplace ($h.marketplace) is another checkout: ($other) — nustro harness register" }
    }
    for p in $h.plugins {
      let m = (if $p.installed and ($p.enabled != false) { $ok } else if $p.installed { $"(ansi yellow)??(ansi reset)" } else { $"(ansi dark_gray)--(ansi reset)" })
      let behind = (if $p.installed and $p.available != null and $p.version != $p.available { $", ($p.available) here — nustro harness update" } else { "" })
      let how = (if $p.installed and ($p.enabled == false) { $"installed ($p.version)($behind), module disabled" } else if $p.installed { $"installed ($p.version)($behind)" } else if $p.enabled == false { "module disabled; not installed" } else { $p.install })
      print $"  ($m) ($p.plugin | fill --width 12) ($how)"
    }
  }
  print ""

  print $"(ansi cyan_bold)Completion(ansi reset)"
  print $"  smart Tab  ($env.NU_SMART_TAB? | default '?')   eval ($env.NU_COMPLETE_EVAL? | default 'safe')"
  for c in (nu-complete status | skip 1) {
    print $"  ($ok) ($c.what | fill --width 18) ($c.size | fill --width 9) ($c.age | str replace --regex ' \d+ms.*' '' ) old"
  }
  if (nu-complete status | length) == 1 { print $"  (ansi dark_gray)no caches yet — they appear on first use(ansi reset)" }
  print ""

  print $"(ansi cyan_bold)Modules(ansi reset)"
  for m in (mod-list) {
    let mark = (if not $m.enabled { $"(ansi dark_gray)--(ansi reset)" } else if $m.loaded { $ok } else { $"(ansi cyan)zz(ansi reset)" })
    let how = (if not $m.enabled { "disabled" } else if $m.lazy { (if $m.loaded { "lazy, loaded" } else { "lazy, not yet loaded" }) } else { "eager" })
    let cost = (if $m.cost == 0ns { "" } else { $m.cost | into string })
    print $"  ($mark) ($m.module | fill --width 12) ($how | fill --width 22) ($cost | fill --width 7) ($m.deps)"
  }
  let broken = (mod-list | where enabled and deps =~ 'missing')
  if ($broken | is-not-empty) {
    print $"  (ansi yellow)($broken | get module | str join ', '): a required tool is missing — `nustro module check <name>`(ansi reset)"
  }
  print ""

  let st = if $nu.startup-time >= 0ns { $"($nu.startup-time)" } else { "n/a" }
  print $"(ansi cyan_bold)Startup(ansi reset) ($st)"
}

# Every knob you can set, and whether your settings.nu overrides it.
#
# Two sources, neither of them a second list to keep in sync: the assignments
# in defaults.nu, and the `knobs` record each module declares in its meta.nuon.
# A knob added by a `git pull` shows up here with nothing else changed.
export def knobs [
  --overridden (-o)   # only the ones you have changed
]: nothing -> table<knob: string, kind: string, owner: string, yours: bool, about: string> {
  let mine = ((user-root) | path join settings.nu)
  let mine_src = if ($mine | path exists) { open --raw $mine } else { "" }
  # A knob counts as overridden only when the line mentioning it is live.
  let mine_live = ($mine_src | lines | where {|l| not ($l | str trim | str starts-with "#") } | str join (char nl))

  let from_defaults = (
    open --raw ((root) | path join defaults.nu)
    | lines
    | each {|l|
        let c = ($l | parse --regex '^const (?<name>[A-Z_][A-Z0-9_]*)\s*=' | get -o 0.name)
        let e = ($l | parse --regex '^\$env\.(?<name>[A-Za-z_][\w.]*)\s*=' | get -o 0.name)
        # `else` must stay on the closing brace's line: on a new line it
        # parses as an external command and fails at runtime.
        if $c != null { { knob: $c, kind: "const", owner: "distro", about: "" } } else if $e != null { { knob: $e, kind: "env", owner: "distro", about: "" } } else { null }
      }
    | compact
  )

  let from_modules = (
    module-dirs | each {|m|
      let meta = (module-meta $m.path)
      ($meta.knobs? | default {}) | transpose knob spec | each {|k|
        { knob: $k.knob, kind: "env", owner: $m.name, about: ($k.spec.about? | default "") }
      }
    } | flatten
  )

  $from_defaults ++ $from_modules
  | insert yours {|r| $mine_live =~ $'\b($r.knob)\b' }
  | if $overridden { where yours } else { $in }
}

# Time N cold interactive startups.
export def startup-time [n: int = 5]: nothing -> table<run: int, time: duration> {
  0..<$n | each {|i|
    let out = (^$nu.current-exe -l -c '$nu.startup-time' | complete)
    { run: ($i + 1), time: ($out.stdout | str trim | into duration) }
  }
}

# Files parsed in this session (find a slow import).
export def loaded-files []: nothing -> table {
  view files
  | where filename !~ '^std' and filename !~ '^entry'
  | select filename size
}

def editor-argv []: nothing -> list<string> {
  $env.EDITOR? | default "vi" | split row " "
}

# Open your own config directory in $EDITOR — settings.nu, autoload/,
# completions/, themes/ are all yours and belong in one view — after the
# scaffold is written, so that settings.nu and the README in every directory
# are there when the editor opens. Nothing you have is touched; what was
# written is printed.
export def edit []: nothing -> nothing {
  let root = (user-root)
  for r in (scaffold init | where action != "kept") { print $"  ($r.action) ($r.file)  ($r.note)" }
  let ed = (editor-argv)
  ^($ed | first) ...($ed | skip 1) $root
  # What the editor left has to parse: a settings.nu or a drop-in that does
  # not takes the whole distro down at the next start — Nushell then runs its
  # stock shell, without `nustro doctor` in it to say so.
  let drop_ins = (try { ls ($root | path join autoload) | where name ends-with ".nu" | get name } catch { [] })
  for f in ([($root | path join settings.nu)] ++ $drop_ins | where ($it | path exists)) {
    if not (do -i { nu-check $f } | default false) {
      print $"(ansi red)($f) does not parse — a new shell would start without the distro; `nu-check --debug` on it says where(ansi reset)"
    }
  }
}

# Open the distro checkout in $EDITOR — to read defaults.nu, or to work on it.
export def "edit distro" []: nothing -> nothing {
  let ed = (editor-argv)
  ^($ed | first) ...($ed | skip 1) (root)
}

# ── Repair ────────────────────────────────────────────────────────────────────
# Put the wiring back the way an install leaves it.
#
#   nustro repair              every step below, in order; nothing installed, nothing of yours replaced
#   nustro repair --hard       the installer again, taking every default: config.nu, the scaffold,
#                              the missing tools, the terminal, theme, init files, plugins, Claude Code
#   nustro repair --reset      the installer from an empty directory: everything of yours moves to
#                              <config dir>/.backup/<stamp>/ first, and it asks before it does
#   nustro repair --dry-run    what would be done
#
# The soft one is what `doctor` and `status` point at: each step is a
# `nustro bootstrap …` command that writes what is missing or stale and leaves
# the rest alone, so running it on a healthy setup changes nothing. A step
# that fails is one row, and the ones after it still run.
#
#   settings   a MODULES line that still says nu-config (the module's name before 2026-10-02)
#   state      .state/nu-config/ from that time, moved to .state/nustro/
#   scaffold   the READMEs, the examples, settings.nu: what is missing is written
#   tools      init files for the installed tools regenerated, stale ones removed
#   plugins    registered again when one is missing or names a file that is gone
#   theme      the last theme rendered again from the templates as they are now
#   completion the session's memoised answers dropped
#   harness    the Claude Code plugins brought to the version the checkout ships
#   parse      distro.nu and everything it sources; a pass is what `upgrade rollback` returns to

# One step: its row, whatever happens in it.
def step [name: string, work: closure]: nothing -> record<step: string, result: string, note: string> {
  try {
    let r = (do $work)
    { step: $name, result: $r.0, note: $r.1 }
  } catch {|e|
    { step: $name, result: "failed", note: $e.msg }
  }
}

# The installer, on this terminal: its screens and its questions are its own.
def reinstall [flags: list<string>]: nothing -> nothing {
  ^$nu.current-exe (root | path join install.nu) ...$flags
}

# Put the wiring back the way an install leaves it. Soft by default: nothing
# is installed and nothing of yours is replaced. `--hard` is the installer
# again over what is there; `--reset` is the installer from an empty directory.
export def repair [
  --hard      # run the installer again with every default: what is there stays, what is missing is written and installed
  --reset     # run the installer from an empty directory: everything of yours moves to .backup/<stamp>/ first
  --dry-run   # say what would be done, change nothing
]: nothing -> table<step: string, result: string, note: string> {
  if $hard and $reset { error make --unspanned { msg: "--hard keeps what is there, --reset moves it all aside: one of them" } }
  if $reset {
    # The installer asks before it applies only on a terminal; without one it
    # would take every default, and this is not a default to take unasked.
    if not ((is-terminal --stdin) and (is-terminal --stdout)) {
      error make --unspanned { msg: "repair --reset moves your whole configuration to .backup/ and asks first; it needs a terminal on both ends" }
    }
    reinstall (["--clean"] ++ (if $dry_run { ["--dry-run"] } else { [] }))
    return []
  }
  if $hard {
    reinstall (["--defaults"] ++ (if $dry_run { ["--dry-run"] } else { [] }))
    return []
  }

  let user = (user-root)
  let settings = ($user | path join settings.nu)
  let state = ($nu.data-dir | path join .state)
  let did = {|what: string| if $dry_run { ["would" $what] } else { ["done" $what] } }
  [
    (step settings {||
      let line = (if ($settings | path exists) { open --raw $settings | lines | where $it =~ '^const MODULES\s*=.*\bnu-config\b' | get -o 0 } else { null })
      if $line == null { return ["ok" ""] }
      let new = ($line | str replace --regex '\bnu-config\b' 'nustro')
      if not $dry_run { set $new }
      do $did "MODULES names nustro, not nu-config"
    })
    (step state {||
      let old = ($state | path join nu-config)
      if not ($old | path exists) { return ["ok" ""] }
      let new = ($state | path join nustro)
      if not $dry_run {
        if ($new | path exists) { rm -rf $old } else { mv $old $new }
      }
      do $did $".state/nu-config → .state/nustro"
    })
    (step scaffold {||
      let rows = (scaffold init --dry-run=$dry_run | where action != "kept")
      if ($rows | is-empty) { ["ok" ""] } else { do $did ($rows | each {|r| $"($r.action) ($r.file)" } | str join ", ") }
    })
    (step tools {||
      let off = (tools status | where state !~ '^(ok|not installed)$' | get tool)
      # Regenerated whether or not one is out of step: a generator the last
      # pull changed shows only in the file's content.
      if not $dry_run { tools setup --quiet }
      if ($off | is-empty) { ["ok" ""] } else { do $did ($off | str join ", ") }
    })
    (step plugins {||
      let off = (plugins status | where not registered and name not-in $DEV_PLUGINS | get name)
      if ($off | is-empty) { return ["ok" ""] }
      if not $dry_run { plugins add }
      do $did ($off | str join ", ")
    })
    (step theme {||
      let f = ($state | path join theme theme.nuon)
      if not ($f | path exists) { return ["ok" "nothing rendered — `terminal theme use <name>`"] }
      let name = (open $f | get -o name | default "the ANSI tier")
      if $dry_run { return ["would" $"render ($name) again"] }
      # The terminal module is lazy and this one must not be what loads it
      # into every shell: a shell of its own, which also reads the theme the
      # way a new window will.
      let r = ("" | ^$nu.current-exe -l -c 'use terminal *; terminal theme sync --quiet | ignore' | complete)
      if $r.exit_code != 0 { error make { msg: ($r.stderr | str trim | lines | last 1 | get -o 0 | default "terminal theme sync failed") } }
      ["done" $"($name) rendered again"]
    })
    (step completion {||
      if not $dry_run { nu-complete cache clear }
      ["ok" ""]
    })
    (step harness {||
      if (which claude | is-empty) { return ["ok" "claude is not on PATH"] }
      let h = (harness status)
      if $h.registered != true { return ["ok" "not registered — `nustro harness register`"] }
      let behind = ($h.plugins | where installed and available != null and version != available | get plugin)
      if ($behind | is-empty) { return ["ok" ""] }
      if not $dry_run { harness update }
      do $did ($behind | str join ", ")
    })
    (step parse {||
      if (do -i { nu-check (root | path join distro.nu) } | default false) {
        if not $dry_run { upgrade good }
        ["ok" ""]
      } else {
        ["failed" "distro.nu does not parse — `nu-check --debug` on it says where; `nustro upgrade rollback` goes back"]
      }
    })
  ]
}

# ── Modules ───────────────────────────────────────────────────────────────────
# docs/concepts/modules.md is the contract. Everything here reads meta.nuon at the
# moment you ask, never at startup: a shell that does not run these commands
# pays nothing for them.

# Every module directory, yours shadowing the distro's on a name clash.
def module-dirs []: nothing -> table<name: string, path: string, source: string> {
  [[dir source]; [((user-root) | path join modules) "yours"] [((root) | path join modules) "distro"]]
  | each {|d|
      if not ($d.dir | path exists) { return [] }
      ls $d.dir | where type == dir | get name | each {|p| { name: ($p | path basename), path: $p, source: $d.source } }
    }
  | flatten
  | uniq-by name
}

def module-meta [path: string]: nothing -> record {
  let f = ($path | path join meta.nuon)
  if not ($f | path exists) { return {} }
  try { open $f } catch { {} }
}

# Is a declared dependency present on this machine?
#
# `paths` is checked when PATH misses, because a GUI application is installed
# without being on PATH: Ghostty on macOS lives in the app bundle and is only
# on PATH inside a Ghostty window, so `which` alone would call it missing on a
# machine where it is plainly there.
def dep-present [d: record]: nothing -> bool {
  (
    (which ($d.bin? | default "") | is-not-empty)
    or (($d.paths? | default []) | any {|p| $p | path expand | path exists })
  )
}

# Every dependency of a module with its state. A `group` is one need with
# several answers — `terminal` wants Ghostty or WezTerm — so a member that is
# absent while another member is present is `alt`, not `missing`: nothing is
# broken, there is just a second terminal to be had.
def dep-states [requires: list]: nothing -> table {
  let present = ($requires | each {|d| dep-present $d })
  $requires | enumerate | each {|e|
    let d = $e.item
    let here = ($present | get $e.index)
    let hard = ($d.hard? | default true)
    let group = ($d.group? | default null)
    let group_ok = ($group != null and ($requires | enumerate | any {|o| ($o.item.group? | default null) == $group and ($present | get $o.index) }))
    {
      bin: ($d.bin? | default "?")
      present: $here
      hard: $hard
      group: $group
      why: ($d.why? | default "")
      install: ($d.install? | get -o $nu.os-info.name | default "")
      then: ($d.then? | default "")
      state: (if $here { "ok" } else if $group_ok { "alt" } else if $hard { "missing" } else { "optional" })
    }
  }
}

# conf/modules.nu publishes the enabled list as $env.NU_MODULES. This fallback
# only matters in a shell that imported this module without the config, such as
# install.nu running as a script.
const MODULES_FALLBACK = [nustro nu-complete agent odata]

# Private, like mod-info and mod-check: `module` is a Nushell keyword, so an
# exported `module list` cannot be called from inside this file.
def mod-list []: nothing -> table {
  module-dirs | each {|m|
    let meta = (module-meta $m.path)
    let enabled = ($m.name in ($env.NU_MODULES? | default $MODULES_FALLBACK))
    let deps = (dep-states ($meta.requires? | default []))
    # What this shell did, not what meta.nuon suggests: MODULES_LAZY in the
    # user's settings.nu decides, and a module moved out of it is eager here.
    let lazy = (if ($env.NU_MODULES_LAZY? == null) { $meta.lazy? | default false } else { $m.name in $env.NU_MODULES_LAZY })
    {
      module: $m.name
      from: $m.source
      enabled: $enabled
      lazy: $lazy
      # A lazy module is loaded only once something mentioned it; an eager
      # one was loaded at startup if it is enabled at all.
      loaded: (if $lazy { $m.name in ($env.NU_MODULES_LOADED? | default []) } else { $enabled })
      deps: (if ($deps | is-empty) { "—" } else { $deps | each {|d| $"($d.bin):($d.state)" } | str join " " })
      cost: ($meta.cost? | default 0ns)
      description: ($meta.description? | default "")
    }
  }
}

# `module` is a Nushell keyword, so `module info ...` cannot be called from
# inside this file even though it is a perfectly good exported name. The body
# lives in a private command that other commands here can reach.
def mod-info [name: string]: nothing -> record {
  let dir = (module-dirs | where name == $name | get -o 0)
  if $dir == null { error make { msg: $"no module named '($name)'" } }
  let meta = (module-meta $dir.path)
  {
    module: $name
    path: $dir.path
    from: $dir.source
    description: ($meta.description? | default "")
    lazy: ($meta.lazy? | default false)
    cost: ($meta.cost? | default 0ns)
    requires: (dep-states ($meta.requires? | default []))
    knobs: ($meta.knobs? | default {})
    docs: (module-docs $dir $meta)
  }
}

# Where a module's documentation is. `docs:` in meta.nuon is a path from the
# root the module came from — docs/reference/modules/<name>.md for a shipped
# one — but a module of yours may keep a README.md beside its code, so the
# module directory is tried first. Empty when meta.nuon names nothing.
def module-docs [dir: record, meta: record]: nothing -> string {
  let rel = ($meta.docs? | default "")
  if ($rel | is-empty) { return "" }
  let local = ($dir.path | path join $rel | path expand)
  if ($local | path exists) { return $local }
  let root = (if $dir.source == "distro" { root } else { user-root })
  $root | path join $rel | path expand
}

# Private for the same reason as mod-info: `module` is a Nushell keyword.
def mod-check [name: string]: nothing -> nothing {
  let info = (mod-info $name)
  let ok = $"(ansi green)ok(ansi reset)"
  print $"(ansi cyan_bold)($name)(ansi reset)  ($info.description)"
  if ($info.requires | is-empty) { print "  no dependencies"; return }
  let groups = ($info.requires | where group != null | get group | uniq)
  for g in $groups {
    let members = ($info.requires | where group == $g)
    print $"  one of these \(($members | get bin | str join ', ')\):"
  }
  for d in $info.requires {
    let mark = (match $d.state {
      "ok" => $ok
      "missing" => $"(ansi red)!!(ansi reset)"
      _ => $"(ansi yellow)--(ansi reset)"
    })
    print $"  ($mark) ($d.bin | fill --width 10) ($d.why)"
    if not $d.present and ($d.install | is-not-empty) {
      print $"     (ansi dark_gray)install:(ansi reset) ($d.install)"
    }
    # The way back, once it is installed — stated for a missing tool, and
    # for an `alt` too: it is what installing the other terminal would add.
    if not $d.present and ($d.then | is-not-empty) {
      print $"     (ansi dark_gray)then:(ansi reset)    ($d.then)"
    }
  }
}

# What modules exist, and what this shell has done with them.
export def "module list" []: nothing -> table { mod-list }

# Everything meta.nuon says about one module, plus its dependency report.
export def "module info" [name: string@module-names]: nothing -> record { mod-info $name }

# Dependency report for one module. Installs nothing, loads nothing.
export def "module check" [name: string@module-names]: nothing -> nothing { mod-check $name }

# A module's documentation page, before the module has loaded: `help terminal`
# says nothing until the first line that mentions `terminal` sources it,
# but the page `docs:` names in meta.nuon is there from the start. Rendered
# by `glow` when installed, else paged through $PAGER; `--path` prints where
# it is instead.
export def "module help" [
  name: string@module-names
  --path (-p)   # the file's path, nothing else
]: nothing -> nothing {
  let info = (mod-info $name)
  if ($info.docs | is-empty) { error make { msg: $"($name) names no documentation in its meta.nuon \(docs:\)" } }
  if not ($info.docs | path exists) { error make { msg: $"($name)'s documentation is missing: ($info.docs)" } }
  if $path { print $info.docs; return }
  if (which glow | is-not-empty) { ^glow -p $info.docs; return }
  let pager = ($env.PAGER? | default "less" | split row " ")
  ^($pager | first) ...($pager | skip 1) $info.docs
}

def module-names []: nothing -> list<string> { module-dirs | get name }

# The enabled set and the lazy set as this shell sees them.
def module-sets []: nothing -> record<enabled: list<string>, lazy: list<string>> {
  {
    enabled: ($env.NU_MODULES? | default $MODULES_FALLBACK)
    lazy: ($env.NU_MODULES_LAZY? | default [])
  }
}

# `const NAME = [a b c]` into your settings.nu, in place: `nustro set` replaces
# the knob's line, commented or live, so the value lands in its own section.
def set-const-list [name: string, values: list<string>]: nothing -> nothing {
  set $"const ($name) = [($values | str join ' ')]"
}

# Turn a module on. `--lazy` loads it on first mention instead of at startup.
export def "module enable" [
  name: string@module-names
  --lazy      # load on first mention (interactive shells only)
  --eager     # load at startup
]: nothing -> nothing {
  if $lazy and $eager { error make { msg: "--lazy and --eager are opposites" } }
  if ($name not-in (module-names)) { error make { msg: $"no module named '($name)'" } }
  # conf/modules.nu can source a module of yours only lazily: the eager
  # `source` lines are parse-time and name the distro's. Lazy is what it
  # gets, said so; eager is a `use` in settings.nu.
  let mine = ((module-dirs | where name == $name | get 0.source) == "yours")
  if $mine and $eager {
    error make { msg: $"($name) is yours, and the distro loads a module of yours on first mention only — for startup, `use ($name)` in settings.nu" }
  }
  let lazy = ($lazy or $mine)
  let sets = (module-sets)
  print $"(ansi cyan_bold)enabling ($name)(ansi reset)(if $mine { ' — yours, so on first mention' } else { '' })"
  set-const-list "MODULES" ($sets.enabled | append $name | uniq)
  if $lazy { set-const-list "MODULES_LAZY" ($sets.lazy | append $name | uniq) }
  if $eager { set-const-list "MODULES_LAZY" ($sets.lazy | where $it != $name) }
  mod-check $name
  print "  restart your shell to pick it up"
}

# Turn a module off. Its files stay where they are.
export def "module disable" [name: string@module-names]: nothing -> nothing {
  let sets = (module-sets)
  if $name in ["nustro"] {
    error make { msg: "nustro is how you repair everything else; disabling it would leave no way back" }
  }
  print $"(ansi cyan_bold)disabling ($name)(ansi reset)"
  set-const-list "MODULES" ($sets.enabled | where $it != $name)
  print "  restart your shell to drop it"
}

# Check every module against the contract in docs/concepts/modules.md.
#
# A contract nothing checks drifts the first time one is added in a hurry,
# and a module that half-conforms fails in ways that look like Nushell bugs.
#
# The parse check is here because nothing else covers a LAZY module: `nu-check
# distro.nu` follows `source`, and a lazy module is sourced by a hook string at
# runtime, so a syntax error in it survives every startup and surfaces only when
# someone finally types its name. That is exactly how `agent` shipped broken.
export def "module lint" []: nothing -> table<module: string, problem: string> {
  module-dirs | each {|m|
    let meta_file = ($m.path | path join meta.nuon)
    let meta = (module-meta $m.path)
    let lazy = ($meta.lazy? | default false)
    let problems = ([
      (if not ($meta_file | path exists) { "no meta.nuon" })
      (if ($meta_file | path exists) and ($meta | is-empty) { "meta.nuon does not parse" })
      (if ($meta.description? | default "" | is-empty) { "meta.nuon has no description" })
      (if ($meta.cost? | default 0ns) == 0ns { "meta.nuon has no measured cost" })
      (if not (($m.path | path join mod.nu) | path exists) { "no mod.nu" })
      (if not (($m.path | path join load.nu) | path exists) { "no load.nu — conf/modules.nu has nothing to source" })
      (if ($meta.docs? | default "" | is-empty) { "meta.nuon has no docs" } else if not ((module-docs $m $meta) | path exists) { $"docs page ($meta.docs) does not exist" })
      (if ((($m.path | path join load.nu) | path exists) and not ((do -i { nu-check ($m.path | path join load.nu) } | default false))) { "load.nu does not parse — the module would fail on first use" })
      ($meta.requires? | default [] | each {|d|
          if ($d.bin? | default "" | is-empty) { "a requires entry has no bin" } else if ($d.why? | default "" | is-empty) { $"requires ($d.bin) has no why" } else if (["macos" "linux" "windows"] | any {|o| ($d.install? | get -o $o | default "" | is-empty) }) { $"requires ($d.bin) is missing an install line for some platform" } else if ($d.hard? | default true) and ($d.then? | default "" | is-empty) { $"requires ($d.bin) has no then — what to do once it is installed" } else { null }
        } | compact)
      # A tool that is not there must never cost a startup: a module that
      # cannot work without one is loaded on first use, where the error
      # names the tool, not at every shell start.
      (if (not $lazy) and ($meta.requires? | default [] | any {|d| $d.hard? | default true }) { "has a hard dependency but is not lazy — a missing tool would cost every startup" })
    ] | flatten | compact)
    $problems | each {|p| { module: $m.name, problem: $p } }
  } | flatten
}
