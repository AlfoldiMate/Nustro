# installer.nu — the installer `nu install.nu` runs, once it has checked that
# this file can run at all (the Nushell version, the checkout, the parse).
# Run it through install.nu; the flags are listed there and on `main` below.
#
# The order, and why it holds up on a machine that already had a Nushell
# configuration:
#
#   1. look      what is in the target directory, the tools, the terminal — nothing written
#   2. ask       the screens; one yes at the end
#   3. clear     a configuration that is not this distro's is moved, whole, to
#                <config dir>/.backup/<stamp>/ — an env.nu or a drop-in left
#                beside the new config.nu is loaded by every new shell, and
#                one that fails takes `nu-config` down with it
#   4. write     config.nu and the scaffold
#   5. prove     a new shell is started and asked whether the distro loaded
#                in it. Everything after this runs in such a shell, so a
#                failure here stops with the error and the file it names
#                instead of five steps each saying `nu-config` is not a command
#   6. install   the missing tools, with the machine's package manager
#   7. wire      terminal, theme, tool init files, plugins, Claude Code — one
#                shell each, so that one failing step is one line in the
#                summary and the rest still happen
#
# What it builds
#
#   <config dir>/config.nu     three lines, pointing here      ← Nushell loads this
#   <config dir>/settings.nu   every knob, commented out — and ONLY your overrides live
#   <config dir>/README.md     what every file and directory is, and whose
#   <config dir>/autoload/     your drop-ins, with a README and an example
#   <config dir>/completions/  what you fetch or write later, same
#   <config dir>/themes/ modules/ plugins/   yours, each with a README
#
# The config dir is Nushell's own (~/.config/nushell on Linux, ~/Library/
# Application Support/nushell on macOS, %APPDATA%\nushell on Windows), because
# Nushell derives history, the plugin registry and the autoload dirs from it.
# This checkout stays out of it: nothing you own is ever written in here, so
# `git pull` is always clean.
#
# The test that the layering is right: accept every default and your
# settings.nu ends up with no live assignment in it at all — `nu-config knobs
# --overridden` comes back empty. Every knob IS in it, commented out at its
# shipped value, so the file is the list; a commented line is not a mention,
# and what you never mention keeps its shipped value, including values added
# by a later `git pull`.
#
# Migrating from the older layout, where this checkout WAS the config dir, is
# handled: history, the plugin registry and autoload/ are moved out, and the
# symlink is replaced by a real directory.

const ROOT = path self | path dirname | path dirname

# A script loads no config, so the module search path has to be declared here
# or nu-config's own imports (`use nu-complete *`) cannot resolve.
const NU_LIB_DIRS = [($ROOT | path join modules)]
use nu-config
# The pickers. They are the same ones the installed shell gets — `theme`,
# `font`, `terminal shell`, `terminal list` — so the installer is a demonstration
# of the thing it installs rather than a second implementation of it.
use terminal *
# The shipped values, so a choice can be compared against them and only the
# differences written down. Sourcing beats restating them: one file owns them.
source ($ROOT | path join defaults.nu)

# What `--minimal` enables: the distro itself, Tab, and the terminal it
# configures. Everything else in MODULES is a toolbox a `module enable` adds.
const CORE_MODULES = [nu-config nu-complete terminal]

# What Nushell keeps in its config directory by itself, whoever configured it:
# never moved, never backed up. `.backup` is where this script puts the rest.
const KEPT = [history.txt history.sqlite3 history.sqlite3-wal history.sqlite3-shm plugin.msgpackz .backup]

def main [
  --dry-run       # print what would be done
  --defaults      # no questions; the whole install — an existing configuration backed up, missing tools and the platform's terminal installed
  --minimal       # the core modules only — nu-config, nu-complete, terminal — and no question about them
  --keep-existing # leave the files of an existing configuration in place; only its config.nu is set aside
  --clean         # start from an empty directory whatever is there — this distro's own configuration too: all of it moves to .backup/<stamp>/
  --skip-deps     # do not install missing tools (starship, zoxide, atuin, carapace, vivid)
  --skip-tools    # do not generate tool init files
  --skip-plugins  # do not register plugins
  --skip-terminal # do not install a terminal (CI, the tests)
  --skip-harness  # do not register the checkout with Claude Code (the tests)
] {
  print $"(ansi cyan_bold)Nustro(ansi reset)  ($ROOT)  (ansi dark_gray)Nushell ((version).version)(ansi reset)"
  print ""
  # One stamp for the run: the backup directory the plan names is the one
  # `apply` makes.
  let stamp = (date now | format date '%Y%m%d-%H%M%S')

  # A terminal on both ends is what the pickers need. A script is never
  # "interactive" even when you launched it from a shell, so this is the test —
  # and it is also what makes `curl … | sh` fall back to defaults by itself.
  let ask = (not $defaults) and (is-terminal --stdin) and (is-terminal --stdout)
  if (not $ask) and (not $defaults) {
    print $"(ansi yellow)no terminal on stdin/stdout — taking every default(ansi reset)"
    print ""
  }

  if $clean and $keep_existing {
    error make --unspanned { msg: "--clean and --keep-existing are opposites: one moves everything out of the config directory, the other nothing but config.nu" }
  }
  let where = (screen-where --ask=$ask --keep=$keep_existing --clean=$clean --stamp=$stamp)
  if $where.existing.mode == "stop" {
    print "nothing was changed"
    return
  }
  let plan = (
    $where
    | merge (screen-modules --ask=($ask and not $minimal))
    | merge (screen-terminal --ask=$ask --dry-run=$dry_run --skip=$skip_terminal)
  )
  # --minimal: the shell, Tab and the terminal; agent, odata and worktree are
  # a `nu-config module enable` away, each lazy, so nothing is lost but the
  # questions. The lazy set follows, as screen 2 would have made it.
  let plan = (if $minimal {
    $plan | upsert modules { enabled: $CORE_MODULES, lazy: ($MODULES_LAZY | where {|m| $m in $CORE_MODULES }) }
  } else { $plan })
  # Screens 4 and 5 configure the terminal screen 3 chose, through `terminal
  # target` like every command; screen 3 set NUSTRO_TERMINAL for this process
  # so they agree, and nothing is pinned on disk until the plan is applied.
  let plan = (
    $plan
    | merge (screen-theme --ask=$ask --terminal=$plan.terminal)
    | merge (screen-font --ask=$ask --dry-run=$dry_run --terminal=$plan.terminal)
  )
  # Screen 3 may have turned the terminal module off; that lands in the
  # MODULES line of screen 2's answer, whichever it was.
  let plan = (if ($plan.disable_terminal? | default false) {
    let enabled = (($plan.modules? | default null | get -o enabled | default $MODULES) | where $it != "terminal")
    $plan | upsert modules { enabled: $enabled, lazy: ($MODULES_LAZY | where {|m| $m in $enabled }) }
  } else { $plan })
  let plan = ($plan | merge (screen-tools --ask=$ask --skip=$skip_deps --modules (($plan.modules? | default null | get -o enabled) | default $MODULES)))
  if $ask and (not (confirm $plan)) {
    print "nothing was changed"
    return
  }

  apply $plan --dry-run=$dry_run --skip-tools=$skip_tools --skip-plugins=$skip_plugins --skip-harness=$skip_harness
}

# ── 1. Where ──────────────────────────────────────────────────────────────────

def screen-where [--ask, --keep, --clean, --stamp: string]: nothing -> record {
  print $"(ansi cyan_bold)1. Where(ansi reset)"
  # Nushell's own answer, not a re-derivation of it: this is the directory a
  # new shell will read, XDG_CONFIG_HOME and every platform rule included. It
  # used to be a question ("somewhere else"), and any answer but this one
  # wrote a config.nu no shell ever loaded — the steps that follow then ran
  # in a shell without the distro and failed on `nu-config`.
  let user = $nu.default-config-dir
  print $"  this checkout   ($ROOT)"
  print $"  your config     ($user)"
  print $"  (ansi dark_gray)Nushell reads config.nu from that directory and derives history, the(ansi reset)"
  print $"  (ansi dark_gray)plugin registry and the autoload dirs from it. To have it elsewhere, set(ansi reset)"
  print $"  (ansi dark_gray)XDG_CONFIG_HOME for every shell first \(it becomes <that>/nushell\), then run this again.(ansi reset)"
  # Two checks, because the obvious one is not enough: `path expand` keeps a
  # trailing separator, so a plain `==` against $ROOT silently passed a path
  # that WAS this checkout and wrote a config.nu into the repository.
  # `path split | path join` normalises; distro.nu catches any checkout.
  let same = (($user | path expand --no-symlink | path split | path join) == ($ROOT | path expand --no-symlink | path split | path join))
  if $same or (($user | path join distro.nu) | path exists) {
    error make { msg: $"($user) is a checkout of the distro. Your configuration has to live somewhere else — that separation is the whole point, and it is what keeps `git pull` clean and your history out of version control." }
  }
  let existing = (screen-existing $user --ask=$ask --keep=$keep --clean=$clean --stamp=$stamp)
  print ""
  { user: $user, existing: $existing }
}

# What is in the target directory already, and what happens to it.
#
#   none     nothing but what Nushell keeps there itself (history, the plugin registry)
#   ours     its config.nu points at this checkout: a re-run, nothing is moved
#   foreign  anything else — someone's config.nu, an env.nu, a login.nu,
#            scripts, generated init files in vendor/autoload
#
# A foreign configuration is not merged with: every new shell reads env.nu
# before config.nu, login.nu after it, then vendor/autoload/ and autoload/,
# whoever wrote them, and one line in any of those that no longer works —
# a `source` of a file that moved, a completer in the pre-0.116 shape — is
# an error at every start, or the distro not loading at all. So the default
# is to move the lot into `.backup/<stamp>/`, where `nu uninstall.nu` finds
# it again, and to start from a directory that holds only the scaffold.
def scan-existing [user: path]: nothing -> record {
  let cfg = ($user | path join config.nu)
  let entries = (if ($user | path exists) { ls --all $user | get name | path basename | where $it not-in $KEPT | sort } else { [] })
  # Off macOS the data dir is not the config dir, and the vendor autoload
  # directory in it is loaded all the same.
  let vendor_dir = ($nu.data-dir | path join vendor autoload)
  let inside = (($vendor_dir | path expand --no-symlink) | str starts-with ($user | path expand --no-symlink))
  let vendor = (if $inside or (not ($vendor_dir | path exists)) { [] } else { ls $vendor_dir | where type == file and name =~ '\.nu$' | get name | path basename | sort })
  let ours = (($cfg | path exists) and (points-here (open --raw $cfg) $ROOT))
  # The distro's own state — the theme render, the terminal pin, the update
  # check — which is under the config dir on macOS and beside the vendor
  # directory elsewhere. Part of "everything" for --clean.
  let state_dir = ($nu.data-dir | path join .state)
  {
    state: (if $ours { "ours" } else if ($entries | is-empty) and ($vendor | is-empty) { "none" } else { "foreign" })
    entries: $entries
    vendor: $vendor
    vendor_dir: $vendor_dir
    state_dir: (if $inside or (not ($state_dir | path exists)) { null } else { $state_dir })
  }
}

def screen-existing [user: path, --ask, --keep, --clean, --stamp: string]: nothing -> record {
  let found = (scan-existing $user)
  let backup = ($user | path join .backup $stamp)
  # --clean: no question, and no exception for a configuration that is this
  # distro's own — the way to see a first install on a machine that has had
  # one, and the way out of a directory nobody can say the state of.
  if $clean and $found.state != "none" {
    print $"  existing        (ansi yellow)(if $found.state == 'ours' { "this distro's" } else { "a configuration that is not this distro's" }) — --clean(ansi reset)"
    print $"  (ansi dark_gray)                all of it moves to ($backup): settings.nu, your drop-ins, the theme and the terminal pin with it.(ansi reset)"
    print $"  (ansi dark_gray)                History and the plugin registry stay. (if $found.state == 'ours' { 'To have any of it back, move it back from there' } else { '`nu uninstall.nu` puts it back' }).(ansi reset)"
    return ($found | insert mode "clean" | insert backup $backup)
  }
  match $found.state {
    "none" => { print $"  existing        (ansi green)nothing there(ansi reset) — a first configuration" }
    "ours" => {
      print $"  existing        (ansi green)this distro's(ansi reset) — a re-run: what is there stays, what is missing is written"
      # The two files Nushell reads around config.nu and the distro never
      # writes. Yours to have; named, because they are the first suspects
      # when a re-run is what someone does about a shell that will not start.
      let extra = ([env.nu login.nu] | where $it in $found.entries)
      if ($extra | is-not-empty) { print $"  (ansi dark_gray)                also read at every start, and not the distro's: ($extra | str join ', ')(ansi reset)" }
    }
    _ => {
      print $"  existing        (ansi yellow)a configuration that is not this distro's(ansi reset)"
      for e in ($found.entries | first 12) { print $"                    ($e)" }
      if ($found.entries | length) > 12 { print $"                    … and (($found.entries | length) - 12) more" }
      for v in $found.vendor { print $"                    ($found.vendor_dir | path join $v)" }
    }
  }
  if $found.state != "foreign" { return ($found | insert mode "none" | insert backup $backup) }

  let mode = (
    if $keep { "keep" }
    else if not $ask { "clean" }
    else {
      match ([
        "back it up and start clean"
        "keep the files, replace config.nu"
        "stop"
      ] | input list "Nushell loads env.nu, login.nu and every autoload file next to the new config.nu — what should happen to these?") {
        "back it up and start clean" => "clean"
        "keep the files, replace config.nu" => "keep"
        _ => "stop"
      }
    }
  )
  match $mode {
    "clean" => { print $"  (ansi dark_gray)                all of it moves to ($backup) — history and the plugin registry stay; `nu uninstall.nu` puts it back(ansi reset)" }
    "keep" => { print $"  (ansi dark_gray)                left in place; config.nu alone moves to ($backup). If a new shell then fails to load the distro, the installer says which file did it(ansi reset)" }
    _ => { }
  }
  $found | insert mode $mode | insert backup $backup
}

# ── 2. Modules ────────────────────────────────────────────────────────────────

def screen-modules [--ask]: nothing -> record {
  print $"(ansi cyan_bold)2. Modules(ansi reset)"
  let all = (nu-config module list)
  for m in $all {
    let dep = (if $m.deps == "—" { "" } else { $"  ($m.deps)" })
    let cost = (if $m.cost == 0ns { "" } else { $"($m.cost)" })
    print $"  ($m.module | fill --width 12) ($cost | fill --width 7) ($m.description)($dep)"
  }
  print $"  (ansi dark_gray)cost is what the module adds to startup when it loads; a lazy one pays it(ansi reset)"
  print $"  (ansi dark_gray)on the first line that mentions it, not at every shell start(ansi reset)"

  if not $ask { print ""; return { modules: null } }

  let chosen = if (yes-no "choose which modules to enable?" --default-no) {
    # nu-config is not offered: it is how you repair everything else.
    let optional = ($all | where module != "nu-config")
    let picked = (
      $optional
      | input list --multi --display {|m| $"($m.module | fill --width 12) ($m.cost)  ($m.description)" } "space to toggle, enter to accept"
    )
    (["nu-config"] ++ ($picked | get module))
  } else { $MODULES }

  # Lazy is the shipped answer for everything that has a trigger word, and the
  # question "should this cost you 97 ms at every start" has one sensible reply.
  let lazy = ($MODULES_LAZY | where {|m| $m in $chosen })
  print ""
  { modules: (if ($chosen | sort) == ($MODULES | sort) { null } else { { enabled: $chosen, lazy: $lazy } }) }
}

# ── 3. Terminal ───────────────────────────────────────────────────────────────
#
# Which terminal the distro configures. Two are known (`terminal list`):
# Ghostty, the one the theme, icon and font work were built on, and WezTerm,
# the same features on Windows too. The one this session runs in is the
# answer when it is one of them; otherwise the choice is made here and pinned
# with `terminal use`, and `--defaults` takes the platform's own (Ghostty,
# WezTerm on Windows) — installing it when nothing is installed and the plan
# is a command, because the theme, the font and the shell are all the
# terminal's, so a distro without one is half a distro.

def --env screen-terminal [--ask, --dry-run, --skip]: nothing -> record {
  print $"(ansi cyan_bold)3. Terminal(ansi reset)"
  let rows = (terminal list)
  for t in $rows {
    let state = (if $t.installed { $"installed at ($t.path)" } else { "not installed" })
    let mark = (if $t.running { $"  (ansi green)← you are running in it(ansi reset)" } else { "" })
    print $"  ($t.terminal | fill --width 10) ($state)($mark)"
  }
  let here = (terminal current)
  if $here != null {
    print $"  (ansi green)the theme preview below will be real(ansi reset)"
  } else {
    print $"  (ansi yellow)this session is in neither(ansi reset) — a theme can still be chosen and written,"
    print $"  (ansi yellow)but the live preview would paint a terminal that is not the one being(ansi reset)"
    print $"  (ansi yellow)configured, so it is a lie and it is skipped(ansi reset)"
  }

  # Nothing installed: offer the platform's default, or a named one.
  if ($rows | where installed | is-empty) {
    let want = (if $ask {
      let options = ($rows | each {|t| $"($t.terminal) — ($t.what)" } | append "neither")
      let pick = ($options | input list "install a terminal? (Enter takes the first)")
      if $pick == null or $pick == "neither" { null } else { $pick | split row " — " | first }
    } else { terminal default })
    if $want != null {
      let plan = (terminal install-plan $want)
      print $"  install ($want):  ($plan.command | default $plan.note)"
      if (not $dry_run) and (not $skip) and $plan.runnable {
        terminal install $want --yes
      }
    }
  }

  # Re-read: the install above may just have changed the answer. Then decide
  # which one is configured: the one we are in, else the only one, else ask.
  let installed = (terminal list | where installed | get terminal)
  let chosen = (
    if ($installed | is-empty) { null }
    else if $here != null and ($here.terminal in $installed) { $here.terminal }
    else if ($installed | length) == 1 { $installed | first }
    else if $ask { $installed | input list "which one should `theme`, `font` and `terminal shell` configure?" | default ($installed | first) }
    else if ((terminal default) in $installed) { terminal default }
    else { $installed | first }
  )
  if $chosen != null and ($installed | length) > 1 { print $"  configuring ($chosen)" }
  # For the rest of this process; `apply` pins it with `terminal use`.
  if $chosen != null { $env.NUSTRO_TERMINAL = $chosen }

  let disable = (if $chosen != null { false } else {
    print $"  (ansi yellow)without a terminal this distro knows(ansi reset)"
    for l in (without-terminal-lines) { print $"    ($l)" }
    print $"  (ansi dark_gray)later: install one \(`terminal install`\), open a new shell, `terminal shell` and `theme`(ansi reset)"
    # The module is lazy, so leaving it on costs nothing at startup; turning
    # it off only takes `theme`, `font` and `terminal` out of the way.
    $ask and (yes-no "disable the terminal module? (it loads only when you type theme, font, ghostty, wezterm or terminal; nothing is saved at startup)" --default-no)
  })
  { terminal: $chosen, in_terminal: ($here != null), shell: (screen-shell --ask=$ask --terminal=$chosen), disable_terminal: $disable }
}

# What a shell without a known terminal does not get, stated once so the
# choice is made with it in view. Everything else — Tab, the prompt, the
# modules — is the same.
def without-terminal-lines []: nothing -> list<string> {
  [
    "theme    stays at the ANSI tier: the shell uses your terminal's own sixteen colours by name; `theme use` can still"
    "         render a palette for tables, ls, bat and the prompt, but only Ghostty or WezTerm gets it written into its"
    "         config and painted into every open window; the app icon is Ghostty's, and Ghostty's own 463 themes need it"
    "font     nothing: the fifteen Nerd Fonts are installed, previewed and kept through the terminal's config"
    "shell    nothing: `terminal shell` is what makes a new window start Nushell; here your terminal decides"
    "alt      on macOS, Alt+E / Alt+Enter / Alt+arrows depend on your terminal sending Option as Alt"
  ]
}

# What a new window starts. Left alone, Ghostty runs SHELL and then the
# passwd shell — zsh on a stock Mac — and WezTerm the platform's default —
# PowerShell on Windows — so a Nushell distro that has configured the terminal
# and then leaves it opening something else has not installed anything. This
# is why it is the one question here whose default is yes, and why `--defaults`
# and a `curl … | sh` run do it unasked: it is the distro's own file in the
# terminal's config (`terminal shell --reset` takes it out again), not an
# override in settings.nu, so the "no overrides" test the other screens live
# by is not touched. Returns true when the shell is to be written.
def screen-shell [--ask, --terminal: any]: nothing -> bool {
  if $terminal == null { print ""; return false }
  let want = (terminal nu-path)
  # `nu` by whichever path: what is there already does the job, so nothing is
  # asked. Ghostty reports the resolved `command`, their config included;
  # WezTerm's `default_prog` is a list, ours or nothing.
  let now = (terminal live (terminal-shell-key $terminal))
  let now_s = (if $now == null { null } else if ($now | describe) =~ '^list' { $now | first } else { $now })
  if $now_s != null and ($now_s | path basename | str replace -r '\.exe$' '') == "nu" {
    print $"  shell      a new ($terminal) window starts ($now_s) already"
    print ""
    return false
  }
  print $"  shell      a new ($terminal) window starts its own default shell"
  let yes = if $ask { yes-no $"start Nushell instead? \(($want)\)" } else { true }
  print ""
  $yes
}

# The key each terminal keeps its start-up program under, for the check above.
def terminal-shell-key [terminal: string]: nothing -> string {
  match $terminal { "wezterm" => "default_prog", _ => "command" }
}

# ── 4. Theme ──────────────────────────────────────────────────────────────────
#
# One theme for everything: a palette is written to the terminal as a theme
# (and an icon, for Ghostty), and rendered for the shell — tables, `ls`, bat
# and the prompt — by `theme use`, which is what `apply` runs for the choice
# made here. Nothing chosen means the ANSI tier: the shell follows whatever
# sixteen colours the terminal paints.

def screen-theme [--ask, --terminal: any]: nothing -> record {
  print $"(ansi cyan_bold)4. Theme(ansi reset)"
  print $"  (ansi dark_gray)a hundred palettes \(NvChad's and Catppuccin\), rendered for the terminal, its icon, Nushell, ls, bat and the prompt; `theme` changes it later, `theme --ghostty` picks among Ghostty's own 463(ansi reset)"
  if not $ask { print ""; return { theme: null } }

  mut theme = null
  if $terminal != null {
    # Default no, like every question here but the shell: pressing Enter
    # through the whole installer has to end with nothing written.
    if (yes-no "pick a theme?" --default-no) {
      $theme = (pick-theme)
    }
  } else {
    print $"  (ansi dark_gray)no terminal to write it to: the shell uses the terminal's sixteen colours by name(ansi reset)"
  }
  print ""
  { theme: $theme }
}

# The theme picker, but choosing only: nothing is written here, because the
# whole plan is confirmed before anything is. `theme preview` paints the live
# terminal and `theme reset` hands it back, so the preview costs nothing either.
# The list is the palettes — NvChad's and the hand-made ones — the same list
# `theme` shows; Ghostty's own 463 are a `theme --ghostty` away afterwards.
def pick-theme []: nothing -> any {
  let rows = (theme list --swatches | select theme colours)
  mut chosen = null
  mut picking = true
  while $picking {
    let pick = ($rows | input list --fuzzy --display {|r| $"($r.theme) ($r.colours)" } "theme")
    if $pick == null { $picking = false; continue }
    theme preview $pick.theme
    match ([$"keep ($pick.theme)" "pick another" "leave it as it was"] | input list $"($pick.theme) — this is it") {
      $a if ($a | default "" | str starts-with "keep") => { $chosen = $pick.theme; $picking = false }
      "pick another" => { theme reset }
      _ => { theme reset; $picking = false }
    }
  }
  # The paint is left on the screen when a theme was kept; the write happens in
  # `apply`, so a cancelled confirmation still leaves the terminal's config alone.
  if $chosen == null { theme reset }
  $chosen
}

# ── 5. Font ───────────────────────────────────────────────────────────────────

def screen-font [--ask, --dry-run, --terminal: any]: nothing -> record {
  print $"(ansi cyan_bold)5. Font(ansi reset)"
  if $terminal == null {
    print "  no terminal to set a font on"
    print ""
    return { font: null }
  }
  let rows = (font list)
  # What the terminal is using, whoever configured it — not only what we wrote.
  let now = (terminal live (terminal target | get font_key))
  print $"  current   ($now | default "the terminal's own built-in JetBrains Mono")"
  print $"  installed ((($rows | where installed | get font) | str join ', ') | default 'none of the fifteen')"
  if (not $ask) or $dry_run {
    if $dry_run { print $"  (ansi dark_gray)a font has to be downloaded to be seen, so the picker is skipped on a dry run(ansi reset)" }
    print ""
    return { font: null }
  }
  if not (yes-no "pick a Nerd Font?" --default-no) { print ""; return { font: null } }

  mut chosen = null
  mut picking = true
  while $picking {
    let pick = (
      font list
      | input list --fuzzy --display {|r|
          let mark = (if $r.installed { "✓ " } else { "  " })
          $"($mark)($r.font | fill --width 16) ($r.what)"
        } "Nerd Font"
    )
    if $pick == null { $picking = false; continue }
    if not $pick.installed { font install $pick.font }
    let row = (font list | where font == $pick.font | get 0)
    if not $row.installed { continue }
    match ([$"keep ($row.family)" "see it in a new window" "pick another"] | input list $row.family) {
      $a if ($a | default "" | str starts-with "keep") => { $chosen = $row.family; $picking = false }
      "see it in a new window" => { font preview $pick.font }
      "pick another" => { }
      _ => { $picking = false }
    }
  }
  print ""
  { font: $chosen }
}

# ── 6. Tools ──────────────────────────────────────────────────────────────────
#
# The five tools the distro is built around (`nu-config deps status`), and
# the offer to install the missing ones with the package manager the machine
# already has — the same `nu-config deps install` a user runs later, after
# the plan is confirmed, never here. `--defaults` takes all of them: a prompt
# without starship and a Tab without carapace is half of what was asked for.
# Where no manager is known the tool's install page is printed and nothing
# runs. The second half is the modules' own dependencies: a module left
# enabled without its tool costs nothing (every such module is lazy —
# `module lint` insists) and its commands say what is missing; this is where
# the choice not to install one is made with the consequence in view.

def screen-tools [--ask, --skip, --modules: list<string>]: nothing -> record {
  print $"(ansi cyan_bold)6. Tools(ansi reset)"
  let rows = (nu-config deps status)
  for t in $rows {
    let mark = (if $t.installed { $"(ansi green)ok(ansi reset)" } else { $"(ansi dark_gray)--(ansi reset)" })
    print $"  ($mark) ($t.tool | fill --width 9) ($t.what)"
  }
  let missing = ($rows | where not installed)
  let can = ($missing | where command != null)
  for t in ($missing | where command == null) {
    print $"  (ansi dark_gray)($t.tool): no package manager here that carries it — ($t.url)(ansi reset)"
  }
  let deps = (
    if ($can | is-empty) { [] }
    else if $skip {
      print $"  (ansi dark_gray)not installed: ($can | get tool | str join ', ') — `nu-config deps install` does it later(ansi reset)"
      []
    } else {
      let manager = ($can | first | get manager)
      print $"  ($manager) can install: ($can | get tool | str join ', ')"
      if not $ask { $can | get tool } else {
        match ([$"install all ($can | length)" "choose" "none"] | input list "the missing tools") {
          "none" | null => []
          "choose" => ($can | input list --multi --display {|t| $"($t.tool | fill --width 9) ($t.what)" } "space to toggle, a for all, enter to accept" | default [] | get tool)
          _ => ($can | get tool)
        }
      }
    }
  )
  # The modules' dependencies. `missing` only: a group's spare member (the
  # other terminal) is not a gap.
  let gaps = (
    nu-config module list
    | where module in $modules
    | each {|m| nu-config module info $m.module | get requires | where state == "missing" | insert module $m.module }
    | flatten
  )
  if ($gaps | is-not-empty) {
    print ""
    print $"  (ansi yellow)modules whose tool is not installed(ansi reset) — enabled, lazy, and their commands will say so until it is:"
    for g in $gaps {
      print $"  (ansi yellow)!!(ansi reset) ($g.bin | fill --width 9) ($g.module): ($g.why)"
      if ($g.install | is-not-empty) { print $"     (ansi dark_gray)install:(ansi reset) ($g.install)" }
      if ($g.then | is-not-empty) { print $"     (ansi dark_gray)then:(ansi reset)    ($g.then)" }
    }
  }
  print ""
  { deps: $deps }
}

# ── 7. Confirm ────────────────────────────────────────────────────────────────

def confirm [plan: record]: nothing -> bool {
  print $"(ansi cyan_bold)7. The plan(ansi reset)"
  for line in (plan-lines $plan) { print $"  ($line)" }
  print ""
  yes-no "apply this?"
}

def plan-lines [plan: record]: nothing -> list<string> {
  let settings = (settings-block $plan)
  ([
    (match $plan.existing.mode {
      "clean" => $"move the existing configuration \(($plan.existing.entries | length) entries(if ($plan.existing.vendor | is-empty) { '' } else { $', ($plan.existing.vendor | length) vendor init files' })\) to ($plan.existing.backup)"
      "keep" => $"leave the existing files in place; config.nu alone moves to ($plan.existing.backup)"
      _ => null
    })
    $"write ($plan.user | path join config.nu), pointing at ($ROOT)"
    "the scaffold: settings.nu with every knob commented out, a README per directory, the examples"
    (if ($settings | is-empty) {
      "settings.nu: no overrides — every value stays the distro's"
    } else {
      $"settings.nu: ($settings | length) override\(s\)"
    })
  ]
  ++ ($settings | each {|l| $"  ($l)" })
  ++ [
    (if ($plan.terminal? | default null) != null { $"terminal use ($plan.terminal) — what `theme`, `font` and `terminal shell` configure" })
    (if ($plan.shell? | default false) { $"terminal shell — a new ($plan.terminal) window starts Nushell \((terminal nu-path)\)" })
    (if ($plan.theme? | default null) != null { $"theme ($plan.theme) — ($plan.terminal), its icon on Ghostty, and the shell's colours" })
    (if ($plan.font? | default null) != null { $"font use ($plan.font) — ($plan.terminal)'s font" })
    (if ($plan.deps? | default [] | is-not-empty) { $"install ($plan.deps | str join ', ') — nu-config deps install" })
    "start a new shell and check the distro loaded in it; then render the theme, generate tool init files, register plugins"
  ]) | compact
}

# The lines that go into settings.nu, and nothing else. A choice equal to the
# shipped value produces no line at all — that is what makes an untouched knob
# keep tracking the distro across a `git pull`.
def settings-block [plan: record]: nothing -> list<string> {
  ([
    (if ($plan.modules? | default null) != null {
      $"const MODULES = [($plan.modules.enabled | str join ' ')]"
    })
    (if ($plan.modules? | default null) != null {
      $"const MODULES_LAZY = [($plan.modules.lazy | str join ' ')]"
    })
  ] | compact)
}

# ── Applying ──────────────────────────────────────────────────────────────────

def apply [plan: record, --dry-run, --skip-tools, --skip-plugins, --skip-harness]: nothing -> nothing {
  let user = $plan.user

  let migrated = (unlink-old-layout $user --dry-run=$dry_run)
  clear-existing $plan.existing $user --dry-run=$dry_run
  make-user-dir $user (settings-block $plan) --dry-run=$dry_run --fresh=($migrated or $plan.existing.mode == "clean") --existing $plan.existing

  # Everything below runs in a new shell that loads what was just written:
  # $nu.plugin-path and the autoload dirs were computed by THIS process
  # before the directory existed, and `theme use`, `tools setup` and the rest
  # are the distro's own commands. So first: does such a shell have them?
  if not $dry_run {
    let loaded = ((prove-it-loads $user) or (set-suspects-aside $plan.existing $user))
    if not $loaded {
      print $"(ansi red_bold)Stopped.(ansi reset) config.nu and the scaffold are written; the terminal, theme, tools and plugins steps were not run."
      print "Fix what the error above names, then `nu install.nu` again — it picks up where this stopped."
      exit 1
    }
  }

  # The tools, in this process: a package manager's progress belongs on this
  # terminal, and what it installs is on PATH for the shells started below.
  if ($plan.deps? | default [] | is-not-empty) {
    print $"(ansi cyan_bold)Tools(ansi reset)"
    for r in (nu-config deps install ...$plan.deps --no-setup --dry-run=$dry_run) {
      let colour = (match $r.action { "installed" | "present" => (ansi green), "failed" => (ansi red), _ => (ansi dark_gray) })
      print $"  ($colour)($r.action | fill --width 9)(ansi reset) ($r.tool | fill --width 9) ($r.detail)"
    }
    print ""
  }

  # The theme is first after the terminal: `theme use` writes Ghostty's theme
  # and icon, paints this window, and renders tables, ls, bat and the prompt
  # from it. No theme chosen re-renders whatever was chosen before, or the
  # ANSI tier on a first install — never a reset.
  let theme_name = (if ($plan.theme? | default null) != null { $plan.theme | to nuon } else { "" })
  # The terminal: the pin (`terminal use`), which `theme use` below writes
  # through; then the shell and the font, in the terminal's own vocabulary
  # through the same commands a user types.
  let terminal_step = (if ($plan.terminal? | default null) == null { null } else {
    let name = ($plan.terminal | to nuon)
    [
      "use terminal *"
      (if $dry_run { $"print '  terminal use ($plan.terminal)'" } else { $"terminal use ($name)" })
      (if ($plan.shell? | default false) { (if $dry_run { "print '  terminal shell — a new window starts Nushell'" } else { "terminal shell" }) })
      (if ($plan.font? | default null) != null { (if $dry_run { $"print '  font use ($plan.font)'" } else { $"font use ($plan.font | to nuon)" }) })
    ] | compact | str join "; "
  })
  # Each step: a title, the code, and the line that repeats it by hand.
  let steps = ([
    (if $terminal_step != null { { title: $"Terminal  ($plan.terminal)", code: $terminal_step, again: $"terminal use ($plan.terminal)" } })
    {
      title: "Theme"
      code: (if $dry_run {
        'use terminal *; theme resolve ' + (if $theme_name == "" { "(theme current | default {} | get -o name)" } else { $theme_name }) + ' | select name tier bat | print'
      } else {
        'use terminal *; ' + (if $theme_name == "" { "theme sync" } else { "theme use " + $theme_name })
      })
      again: (if $theme_name == "" { "theme sync" } else { $"theme use ($theme_name)" })
    }
    (if not $skip_tools { {
      title: "Tool init files"
      code: (if $dry_run { 'nu-config tools status | select tool installed state | print' } else { 'print $"  → (nu-config tools dir)"; nu-config tools setup' })
      again: "nu-config tools setup"
    } })
    (if not $skip_plugins { {
      title: "Plugins"
      code: (if $dry_run { 'nu-config plugins list | select name registered | print' } else { 'nu-config plugins add' })
      again: "nu-config plugins add"
    } })
    # The checkout is also a Claude Code plugin marketplace (harness/). Guarded
    # on claude, idempotent, and it only registers: which plugin to install is
    # printed, not decided — a plugin adds hooks to every session.
    (if not ($skip_harness or (which claude | is-empty)) { {
      title: "Claude Code"
      code: (if $dry_run { 'nu-config harness status | select marketplace registered | print' } else { 'nu-config harness register' })
      again: "nu-config harness register"
    } })
  ] | compact)

  # One shell per step. They used to be one `-c` joined with `;`, and the
  # first step to fail — a theme, a plugin that will not register — took
  # every later one with it, with the reason scrolled off the top.
  let failed = ($steps | each {|s|
    print $"(ansi cyan_bold)($s.title)(ansi reset)"
    let ok = (try {
      if $dry_run {
        # -n: report against this checkout without loading anything. NU_LIB_DIRS
        # has to be handed over, because a config-less nu has no search path.
        with-env { NU_LIB_DIRS: ($ROOT | path join modules) } { ^$nu.current-exe -n -c $"use nu-config; ($s.code)" }
      } else {
        ^$nu.current-exe -l -c $s.code
      }
      true
    } catch { false })
    print ""
    if $ok { null } else { $s }
  } | compact)

  if $dry_run {
    print $"(ansi yellow)dry run — nothing was changed(ansi reset)"
    return
  }
  if ($failed | is-empty) {
    print $"(ansi green_bold)Done.(ansi reset) Open a new terminal, then run `nu-config doctor`."
  } else {
    print $"(ansi yellow_bold)Installed, with ($failed | length) step\(s\) that did not finish.(ansi reset) The shell itself loads; in a new terminal:"
    for s in $failed { print $"  ($s.again | fill --width 28) (ansi dark_gray)# ($s.title | str trim)(ansi reset)" }
    exit 1
  }
}

# Move a configuration that is not ours out of the way, whole (mode `clean`).
# `keep` moves nothing here: make-user-dir sets the foreign config.nu aside.
# A manifest goes with it, so `nu uninstall.nu` can put every entry back
# where it was — the vendor init files included, which off macOS came from
# another directory.
def clear-existing [existing: record, user: path, --dry-run]: nothing -> nothing {
  if $existing.mode != "clean" { return }
  print $"(ansi cyan_bold)Existing configuration(ansi reset)  → ($existing.backup)"
  for e in $existing.entries { print $"  (if $dry_run { 'would move' } else { 'moved' })  ($e)" }
  for v in $existing.vendor { print $"  (if $dry_run { 'would move' } else { 'moved' })  ($existing.vendor_dir | path join $v)" }
  if $existing.state_dir != null { print $"  (if $dry_run { 'would move' } else { 'moved' })  ($existing.state_dir)" }
  if not $dry_run {
    mkdir $existing.backup
    for e in $existing.entries { mv ($user | path join $e) ($existing.backup | path join $e) }
    if ($existing.vendor | is-not-empty) {
      mkdir ($existing.backup | path join .vendor-autoload)
      for v in $existing.vendor { mv ($existing.vendor_dir | path join $v) ($existing.backup | path join .vendor-autoload $v) }
    }
    if $existing.state_dir != null { mv $existing.state_dir ($existing.backup | path join .data-state) }
    write-manifest $existing $user $existing.entries
  }
  print ""
}

# What a backup directory holds and where it came from; uninstall.nu reads it.
def write-manifest [existing: record, user: path, entries: list<string>]: nothing -> nothing {
  {
    made: (date now)
    by: $ROOT
    from: $user
    # This distro's own configuration, set aside by --clean: not what
    # uninstall.nu means by "what was there before".
    ours: ($existing.state == "ours")
    entries: $entries
    vendor: (if $existing.mode == "clean" { $existing.vendor } else { [] })
    vendor_dir: $existing.vendor_dir
    state_dir: (if $existing.mode == "clean" { $existing.state_dir } else { null })
  } | to nuon --indent 2 | save -f ($existing.backup | path join .nustro-backup.nuon)
}

# The new shell failed and this is a re-run over our own config.nu, where
# nothing was cleared: env.nu and login.nu are the two files Nushell reads
# around config.nu that the distro never writes, left by whatever was here
# before (or by an install with --keep-existing). Moved to the backup
# directory — no manifest, they are not a configuration to restore — and the
# shell is asked again. Not with --keep-existing, which is the instruction to
# leave them. True when the second shell loads.
def set-suspects-aside [existing: record, user: path]: nothing -> bool {
  let suspects = ([env.nu login.nu] | where {|f| $user | path join $f | path exists })
  if $existing.mode == "keep" or ($suspects | is-empty) { return false }
  print $"(ansi cyan_bold)Setting aside(ansi reset)  ($suspects | str join ', ') → ($existing.backup)"
  print $"  (ansi dark_gray)the distro writes neither; a new shell reads both. Moved, not deleted — then the shell is tried again(ansi reset)"
  mkdir $existing.backup
  for f in $suspects { mv ($user | path join $f) ($existing.backup | path join $f) }
  print ""
  prove-it-loads $user
}

# Start the shell the user is about to get and ask it one thing: is this
# distro loaded in you, from this directory? Printed either way, because
# "nu-config is not a command" five times over is what it replaces.
def prove-it-loads [user: path]: nothing -> bool {
  print $"(ansi cyan_bold)A new shell(ansi reset)"
  # `scope commands`, not a call of nu-config: a command that is not there is
  # a parse error of the whole line, with nothing printed to tell from.
  let code = '{ distro: (scope commands | where name == "nu-config doctor" | is-not-empty), config: $nu.config-path } | to nuon | print'
  let r = (^$nu.current-exe -l -c $code | complete)
  let said = (try { $r.stdout | lines | last | from nuon } catch { null })
  let errors = ($r.stderr | str trim)
  let here = ($user | path join config.nu)
  let same = ($said != null and (($said.config | path expand) == ($here | path expand)))
  if $r.exit_code == 0 and $said != null and $said.distro and $same {
    print $"  (ansi green)ok(ansi reset) loads the distro from ($here)"
    if ($errors | is-not-empty) {
      # Loaded, but something beside it complained: a drop-in, an init file.
      print $"  (ansi yellow)??(ansi reset) and printed this on the way — every new terminal will:"
      print ($errors | lines | each {|l| $"     ($l)" } | str join (char nl))
    }
    print ""
    return true
  }
  print $"  (ansi red)!!(ansi reset) a new shell does not have the distro in it"
  if ($errors | is-not-empty) { print ($errors | lines | each {|l| $"     ($l)" } | str join (char nl)) }
  if $said != null and (not $same) {
    print $"     it read ($said.config), not ($here): XDG_CONFIG_HOME differs between this process and a new shell"
  }
  # What a shell reads, in order, and which of those exist: the error above
  # names one of them, and this says whose it is.
  print "     what a new shell reads, in order:"
  let autoload = ($user | path join autoload)
  let vendor = ($nu.data-dir | path join vendor autoload)
  let count = {|d| if ($d | path exists) { ls $d | where name =~ '\.nu$' | length } else { 0 } }
  for f in [
    [file whose];
    [($user | path join env.nu) "not the distro's — Nushell reads it first"]
    [$here "the distro's pointer"]
    [($user | path join settings.nu) "yours — your overrides, sourced by the distro"]
    [($user | path join login.nu) "not the distro's — read by a login shell"]
  ] {
    if ($f.file | path exists) { print $"       ($f.file)  (ansi dark_gray)($f.whose)(ansi reset)" }
  }
  if (do $count $vendor) > 0 { print $"       ($vendor)/*.nu  (ansi dark_gray)(do $count $vendor) generated init file\(s\)(ansi reset)" }
  if (do $count $autoload) > 0 { print $"       ($autoload)/*.nu  (ansi dark_gray)(do $count $autoload) drop-in\(s\), yours(ansi reset)" }
  print $"     `nu-check --debug <file>` on the one the error names says where it breaks; `nu install.nu` without"
  print $"     --keep-existing moves a configuration that is not the distro's — env.nu and login.nu included — out of the way."
  print ""
  false
}

# Does this config.nu source THIS checkout? The path appears in it as a Nushell
# string literal, so on Windows it is backslash-escaped and a plain `str
# contains` of the raw path misses it.
def points-here [text: string, root: path]: nothing -> bool {
  ($text | str contains $root) or ($text | str contains ($root | to nuon))
}

# ── Asking ────────────────────────────────────────────────────────────────────

# `input list` rather than a typed y/n: it needs one keystroke, it cannot be
# mistyped, and Esc means no without a special case.
def yes-no [question: string, --default-no]: nothing -> bool {
  let options = if $default_no { ["no" "yes"] } else { ["yes" "no"] }
  ($options | input list $question) == "yes"
}

# ── The user directory ────────────────────────────────────────────────────────

# The previous layout symlinked the config dir at this checkout. Replace that
# link with a real directory and carry the state that lived in here out to it.
# Returns true when the old layout was found, so the caller knows the user
# directory is starting empty.
def unlink-old-layout [user: path, --dry-run]: nothing -> bool {
  if not ($user | path exists) { return false }
  # `path type` reports the link itself; `path expand` resolves it.
  if ($user | path type) != "symlink" or ($user | path expand) != $ROOT { return false }

  print $"(ansi cyan_bold)Previous layout(ansi reset)"
  print $"  ($user) is a link to this checkout — replacing it with a directory of your own"
  if not $dry_run {
    if $nu.os-info.name == "windows" { ^cmd /c rmdir $user } else { ^rm $user }
    mkdir $user
  }
  # State Nushell wrote into the checkout through that link.
  for f in [history.txt history.sqlite3 history.sqlite3-wal history.sqlite3-shm plugin.msgpackz] {
    let src = ($ROOT | path join $f)
    if ($src | path exists) {
      print $"  moving ($f) out of the checkout"
      if not $dry_run { mv $src ($user | path join $f) }
    }
  }
  for d in [autoload vendor .state plugins] {
    let src = ($ROOT | path join $d)
    # A pre-split checkout ships a plugins/.gitkeep; only move the directory
    # when it holds something other than that.
    let has = (($src | path exists) and ((try { ls -a $src | where name !~ '\.gitkeep$' } catch { [] }) | is-not-empty))
    if $has {
      print $"  moving ($d)/ out of the checkout"
      if not $dry_run { mv $src ($user | path join $d) }
    }
  }
  print ""
  true
}

def make-user-dir [user: path, overrides: list<string>, --dry-run, --fresh, --existing: record] {
  print $"(ansi cyan_bold)Your configuration(ansi reset)  ($user)"

  let cfg = ($user | path join config.nu)
  # After a migration or a clean-up the directory is brand new; on a dry run
  # it has not been emptied yet, so anything still in it is on its way out.
  let existing_cfg = if $fresh { null } else if ($cfg | path exists) { open --raw $cfg } else { null }

  # Both spellings: the path as written on Unix, and the backslash-escaped
  # literal on Windows. Checking only one makes a re-run rewrite a config.nu
  # that was already correct.
  if $existing_cfg != null and (points-here $existing_cfg $ROOT) {
    print "  config.nu already points here"
  } else {
    if $existing_cfg != null {
      # `--keep-existing`: the one file that has to go, to the same place a
      # clean-up would have put it, with the same manifest.
      print $"  config.nu exists and points somewhere else — keeping it as ($existing.backup | path join config.nu)"
      if not $dry_run {
        mkdir $existing.backup
        mv $cfg ($existing.backup | path join config.nu)
        write-manifest $existing $user [config.nu]
      }
    }
    print $"  writing config.nu → ($ROOT)"
    if not $dry_run {
      mkdir $user
      open --raw ($ROOT | path join templates config.nu)
      # `to nuon`, not the bare path: a DOUBLE-quoted Nushell string processes
      # escapes, so a Windows checkout at D:\a\Nustro turned \a into
      # BEL and \n into a newline and the sourced path did not exist. CI found
      # it on the first Windows run. `to nuon` emits a valid literal, quotes
      # included, and handles an apostrophe in the path too.
      | str replace --all "@DISTRO@" ($ROOT | to nuon)
      | save -f $cfg
    }
  }

  # The scaffold — settings.nu, a README per directory, the examples — is
  # `nu-config user init`, the same command a user runs after an upgrade or
  # after deleting a README, so the installer and the command cannot drift.
  # It writes what is missing and nothing else; on a dry run over a layout
  # being replaced (--fresh) the directory is about to be empty, whatever the
  # old symlink still shows.
  for r in (nu-config user init --dir $user --dry-run=$dry_run --fresh=$fresh) {
    let note = (if ($r.note | is-empty) { "" } else { $"  ($r.note)" })
    print $"  ($r.action | fill --width 13) ($r.file)($note)"
  }

  # The overrides, each replacing the knob's commented line in its own section
  # — so an installed settings.nu reads as the knob list with your choices
  # live in it, not as a template with a tail. A choice equal to the shipped
  # value produced no line at all (settings-block), which is what keeps an
  # untouched knob tracking the distro across a `git pull`.
  if ($overrides | is-not-empty) {
    print $"  settings.nu: ($overrides | length) override\(s\)"
    for o in $overrides {
      if $dry_run { print $"    ($o)" } else { nu-config user set --dir $user $o }
    }
  }
  print ""
}
