# roots — where the two directories are, and how this distro is installed
#
#   nustro bootstrap root         the checkout, the directory holding distro.nu
#   nustro bootstrap user-root    your directory, the one holding the config.nu Nushell loaded
#   nustro bootstrap layout       split, in-place or other — with both paths
#   nustro bootstrap config-dir   where Nushell reads its configuration on this platform
#
# Plumbing: `doctor`, `status`, the installer and the tests ask; a person
# reads the answers in `nustro doctor`.

# `path self` only runs at parse time, so the root is computed here rather
# than inside a command. This file is modules/nustro/roots.nu, two levels down.
const MODULE_DIR = path self | path dirname

# Where the distro checkout lives — the directory holding distro.nu.
export def root []: nothing -> path {
  $MODULE_DIR | path dirname | path dirname | path expand
}

# Where YOUR configuration lives: the directory holding the config.nu Nushell
# loaded. History, the plugin registry and the autoload dirs all hang off it.
export def "user-root" []: nothing -> path {
  $nu.config-path | path dirname | path expand
}

# True while the distro checkout is also serving as the config directory,
# which `nu install.nu` exists to undo.
export def "in-place?" []: nothing -> bool {
  (root) == (user-root)
}

# The directory Nushell reads its configuration from on this platform.
# Nushell honours XDG_CONFIG_HOME on every OS, then falls back to the OS default.
export def config-dir []: nothing -> path {
  if ($env.XDG_CONFIG_HOME? | default "" | is-not-empty) {
    return ($env.XDG_CONFIG_HOME | path join nushell)
  }
  match $nu.os-info.name {
    "macos" => ($nu.home-dir | path join "Library" "Application Support" "nushell")
    "windows" => ($env.APPDATA | path join "nushell")
    _ => ($nu.home-dir | path join ".config" "nushell")
  }
}

# How this distro is installed.
#   "split"     a user directory of its own sources this distro — the target
#   "in-place"  the checkout is still the config directory — run `nu install.nu`
#   "other"     the live config is some other distro or a hand-written one
export def layout []: nothing -> record<state: string, user: string, distro: string> {
  let u = (user-root)
  let d = (root)
  let cfg = ($u | path join config.nu)
  # Two spellings of the same path: as written, and as the backslash-escaped
  # Nushell string literal that a Windows checkout produces. `str contains $d`
  # alone reported "other" for a perfectly good split install on Windows.
  let text = (if ($cfg | path exists) { open --raw $cfg } else { "" })
  let points_here = ($text | str contains $d) or ($text | str contains ($d | to nuon))
  let state = if $u == $d {
    "in-place"
  } else if $points_here {
    "split"
  } else {
    "other"
  }
  { state: $state, user: $u, distro: $d }
}

