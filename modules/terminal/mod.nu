# terminal — the terminal you are running in: which one, its theme, its font
#
#   terminal               what is configured: the terminal, what the distro wrote into its config
#   terminal list          the terminals this distro knows: installed, running, how to get one
#   terminal use <name>    pin the one the commands below configure
#   terminal shell         a new window of the terminal starts Nushell
#   terminal theme         pick a palette, the terminal as preview; `terminal theme use <name>` by name
#   terminal font          pick a Nerd Font, install it, and let a new window render it
#
# One word, because of how this distro does colour: there is one theme and it
# is the terminal's. `terminal theme use` writes the terminal's
# configuration, repaints the running window, and renders the shell's own
# colours — tables, ls, bat, the prompt — from the same palette. theme.nu reads
# and paints, palette.nu resolves and renders, ghostty.nu and wezterm.nu each
# write one terminal's configuration, and registry.nu is the table of the
# terminals — which is installed, which this session runs in, which one the
# commands configure (`terminal target`).
#
# What is exported is what a person types. The rest — `ghostty set`,
# `wezterm live`, `terminal theme paint`, `terminal write-theme` — is how the
# files talk to each other, and the installer and the tests reach it by file
# (`use terminal/registry.nu *`).
#
# Lazy, and measured: loading these files costs 18 ms (meta.nuon carries the
# number and docs/concepts/modules.md the method), for commands a shell uses once in a
# while. `terminal` is the one word that loads it.

export use registry.nu [
  "terminal list" "terminal current" "terminal target" "terminal default" "terminal use"
  "terminal install" "terminal shell" "terminal option"
  "terminal status" "terminal settings" "terminal set" "terminal reset" "terminal reload" "terminal live"
]
export use palette.nu [
  "terminal theme" "terminal theme use" "terminal theme list" "terminal theme preview"
  "terminal theme sync" "terminal theme icon" "terminal theme current" "terminal theme roles"
  "terminal theme resolve" "terminal theme status"
]
export use theme.nu ["terminal theme reset" "terminal theme slug"]
export use font.nu [
  "terminal font" "terminal font use" "terminal font list" "terminal font install"
  "terminal font preview" "terminal font size" "terminal font specimen" "terminal font dir"
]
use registry.nu ["terminal status"]

# What is configured: the terminal the commands write to and what the distro
# has put into its config — `terminal status`.
export def main []: nothing -> record { terminal status }

# One knob and nothing else to wire: no hooks, no completion providers. Every
# file reads the terminal's own configuration at the moment you ask, so there
# is no state to set up. `default`, never assignment: the user's settings.nu
# was sourced long before this ran (docs/concepts/modules.md).
export def --env "terminal activate" []: nothing -> nothing {
  $env.NERD_FONTS_RELEASE = ($env.NERD_FONTS_RELEASE? | default "https://github.com/ryanoasis/nerd-fonts/releases/latest/download")
}
