# deps — the third-party tools the distro wires in, and getting them installed
#
#   nustro deps status              each tool: installed or not, and the line that installs it here
#   nustro deps manager             the package manager those lines use on this machine
#   nustro deps install             install every missing one, then `tools setup`
#   nustro deps install atuin       only the ones named
#   nustro deps install --dry-run   the lines, nothing run
#
# The distro works without any of them — every use is guarded with `which` —
# but it is built around all five: zoxide, atuin and carapace get an init file
# (tools.nu), starship is the prompt (conf/prompt.nu), vivid is the theme's
# `ls` colours (modules/terminal/palette.nu). The installer offers this list
# and runs this command, so the two cannot drift.
#
# Nothing is downloaded by the distro itself: a tool is installed by the
# package manager the machine already has, which is also what upgrades it
# later. Without one the tool's own install page is printed and nothing runs.
#
# Package names checked on 2026-10-01 against Homebrew core, winget-pkgs,
# Scoop's Main and Extras buckets and Arch's `extra`. Only the Homebrew lines
# have been run; `null` means that manager does not carry the tool.

use tools.nu ["tools setup"]

def registry []: nothing -> table {
  [
    {
      name: "starship"
      what: "the prompt, themed with everything else; without it Nushell's own"
      brew: "starship", winget: "Starship.Starship", scoop: "starship", pacman: "starship"
      url: "https://starship.rs/guide/#step-1-install-starship"
    }
    {
      name: "zoxide"
      what: "frecency cd: `z`, `zi`"
      brew: "zoxide", winget: "ajeetdsouza.zoxide", scoop: "zoxide", pacman: "zoxide"
      url: "https://github.com/ajeetdsouza/zoxide#installation"
    }
    {
      name: "atuin"
      what: "shell history: Ctrl+R full search, Up arrow seeded with the line"
      brew: "atuin", winget: "Atuinsh.Atuin", scoop: "atuin", pacman: "atuin"
      url: "https://docs.atuin.sh/guide/installation/"
    }
    {
      name: "carapace"
      what: "argument completions for ~1000 commands, behind the shipped specs"
      # Scoop carries it in Extras, which `scoop install` reaches by the
      # bucket-qualified name once the bucket is added (install-argv below).
      brew: "carapace", winget: "rsteube.Carapace", scoop: "extras/carapace-bin", pacman: null
      url: "https://carapace-sh.github.io/carapace-bin/install.html"
    }
    {
      name: "vivid"
      what: "`ls` colours from the theme; without it Nushell's own apply"
      brew: "vivid", winget: "sharkdp.vivid", scoop: "vivid", pacman: "vivid"
      url: "https://github.com/sharkdp/vivid#installation"
    }
  ]
}

# The managers this knows a line for, in the order they are tried per platform.
def managers []: nothing -> list<string> {
  match $nu.os-info.name {
    "macos" => [brew]
    "windows" => [winget scoop]
    _ => [brew pacman]
  }
}

# The package manager `deps install` uses here: the first one on PATH that
# this platform is expected to have, or null.
export def "deps manager" []: nothing -> any {
  managers | where {|m| which $m | is-not-empty } | get -o 0
}

# The commands that install one package, in order. More than one only where a
# manager needs a step first.
def install-argv [manager: string, package: string]: nothing -> list<list<string>> {
  match $manager {
    "brew" => [[brew install $package]]
    "winget" => [[winget install --id $package --exact --source winget --accept-package-agreements --accept-source-agreements]]
    "scoop" => (
      if ($package | str contains "/") {
        [[scoop bucket add ($package | split row "/" | first)] [scoop install $package]]
      } else { [[scoop install $package]] }
    )
    "pacman" => [[sudo pacman -S --needed --noconfirm $package]]
    _ => []
  }
}

def tool-names []: nothing -> list<string> { registry | get name }

# Each tool: is it on PATH, and what installs it on this machine.
export def "deps status" []: nothing -> table<tool: string, installed: bool, path: any, manager: any, command: any, what: string, url: string> {
  let manager = (deps manager)
  registry | each {|t|
    let found = (which $t.name | get -o 0.path)
    let package = (if $manager == null { null } else { $t | get -o $manager })
    {
      tool: $t.name
      installed: ($found != null)
      path: $found
      manager: (if $package == null { null } else { $manager })
      command: (if $package == null { null } else { install-argv $manager $package | each {|a| $a | str join " " } | str join "; " })
      what: $t.what
      url: $t.url
    }
  }
}

# Install the missing tools — all of them, or the ones named — with this
# machine's package manager, one at a time so that one failure is one line
# and not the end of the run; then generate the init files for what arrived.
export def "deps install" [
  ...tools: string@tool-names   # which ones; every missing one when none is named
  --dry-run                     # print what would run
  --no-setup                    # do not run `tools setup` afterwards (install.nu does it as its own step)
]: nothing -> table<tool: string, action: string, detail: string> {
  let unknown = ($tools | where $it not-in (tool-names))
  if ($unknown | is-not-empty) {
    error make --unspanned { msg: $"no tool called ($unknown | str join ', ') here — `nustro deps status` lists them" }
  }
  let rows = (deps status | where {|r| ($tools | is-empty) or $r.tool in $tools })
  let results = ($rows | each {|r|
    if $r.installed {
      { tool: $r.tool, action: "present", detail: $r.path }
    } else if $r.command == null {
      { tool: $r.tool, action: "by hand", detail: $r.url }
    } else if $dry_run {
      { tool: $r.tool, action: "would run", detail: $r.command }
    } else {
      print $"  (ansi dark_gray)($r.command)(ansi reset)"
      # Not through `complete`: the manager's own progress is what the user
      # watches. The exit code of the last line is the verdict (a step before
      # it, `scoop bucket add`, fails when it was already done) — `which`
      # afterwards would call a winget install a failure, because this
      # process's PATH is older than the install.
      let lines = ($r.command | split row "; ")
      let ok = (
        $lines | each {|line|
          let argv = ($line | split row " ")
          try { ^($argv | first) ...($argv | skip 1); true } catch { false }
        } | last
      )
      if $ok {
        { tool: $r.tool, action: "installed", detail: (which $r.tool | get -o 0.path | default "installed; on PATH in a new terminal") }
      } else {
        { tool: $r.tool, action: "failed", detail: $"`($lines | last)` failed — ($r.url)" }
      }
    }
  })
  if (not $no_setup) and ($results | where action == "installed" | is-not-empty) {
    tools setup --quiet
  }
  $results
}
