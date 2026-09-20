# terminal — the terminal you are running in: its theme, and its configuration
#
#   theme              pick a palette, the terminal as preview; `theme use <name>` by name
#   font               pick a Nerd Font, install it, and let a new window render it
#   terminal list      the terminals this distro knows: installed, running, how to get one
#   terminal shell     a new window of the terminal starts Nushell
#   ghostty status     what this distro has written into Ghostty's config
#   wezterm status     the same for WezTerm
#
# They belong together because of how this distro does colour: there is one
# theme and it is the terminal's. `theme use` writes the terminal's
# configuration, repaints the running window, and renders the shell's own
# colours — tables, ls, bat, the prompt — from the same palette. theme.nu reads
# and paints, palette.nu resolves and renders, ghostty.nu and wezterm.nu each
# write one terminal's configuration, and registry.nu is the table of the
# terminals — which is installed, which this session runs in, which one the
# commands configure (`terminal target`).
#
# Lazy, and measured: loading these files costs 18 ms (meta.nuon carries the
# number and docs/concepts/modules.md the method), for commands a shell uses once in a
# while. So `theme`, `ghostty`, `wezterm` and `font` are trigger words — see meta.nuon.

export use ghostty.nu *
export use wezterm.nu *
export use theme.nu *
export use registry.nu *
export use palette.nu *
export use font.nu *

# One knob and nothing else to wire: no hooks, no completion providers. Every
# file reads the terminal's own configuration at the moment you ask, so there
# is no state to set up. `default`, never assignment: the user's settings.nu
# was sourced long before this ran (docs/concepts/modules.md).
export def --env "terminal activate" []: nothing -> nothing {
  $env.NERD_FONTS_RELEASE = ($env.NERD_FONTS_RELEASE? | default "https://github.com/ryanoasis/nerd-fonts/releases/latest/download")
}
