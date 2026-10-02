# Your first theme

There is one theme and everything follows it. `terminal theme use` hands the
terminal — Ghostty, or WezTerm — a theme and a matching app icon, repaints
the window you are in (and reloads every open one), and renders the shell's own colours — tables, `ls`, `bat`,
the starship prompt — from the same palette, now and in every shell after.

```nu
terminal theme                 # scroll a hundred palettes — NvChad's 96 and Catppuccin; the live window is the preview
terminal theme --ghostty       # or Ghostty's own 463
terminal theme use tokyonight  # by name, no picker; Tab completes the names
terminal theme roles           # what the shell made of it: each role, its colour, which tier decided it
terminal theme status          # what is rendered, from which theme, and what the terminal was given
terminal theme reset           # the terminal back to what its config had, after a preview
```

The picker lists each theme with its own sixteen colours beside it. Choose
one and the whole terminal — prompt, tables, scrollback — is painted in it
before you are asked whether to keep it. Nothing is written until you say
yes.

There is no `THEME` knob to set: what was rendered last is the theme, and a
new shell reads the render in 0.36 ms. `terminal theme use` needs a terminal it
knows for the writing (`terminal list`) and Ghostty for the 463 `--ghostty`
themes; the palettes list and render without
it, at the ANSI tier ([Theming](../concepts/theming.md)).

## A font

```nu
terminal font                  # the picker: fifteen Nerd Fonts, what is installed, what is current
terminal font preview FiraCode # a new window of the terminal in that font, showing a specimen
terminal font use FiraCode     # install it if needed, then make it the terminal's
```

A font cannot be previewed in the window you are in — there is no escape
sequence for "change font" the way there is for colour — so `terminal font preview`
opens a window of its own. `terminal font use` installs from Homebrew's cask on macOS
and from the Nerd Fonts release archive elsewhere, then reloads the terminal
(Ghostty on macOS, WezTerm anywhere).

## The prompt

```nu
terminal prompt                # the picker: powerline, plain, bracketed and minimal drawn here, then choose
terminal prompt status         # the style, and every option with its value and default
terminal prompt use plain      # by name: coloured text instead of tinted segments; `off` is no prompt at all
terminal prompt set time off   # a segment: left, right or off
terminal prompt set icons false  # for a font without Nerd Font symbols
terminal prompt reset          # the shipped prompt again
```

The theme colours the prompt; this is its shape. Each change is rendered
and switched in the window you typed it in
([Shape the prompt](../cookbook/prompt.md)).

## The terminal starts Nushell

If you said yes on the installer's terminal screen, this is done. Otherwise:

```nu
terminal shell               # a new window of the terminal starts nu; `--reset` hands it back
terminal status              # the config the terminal reads, what the distro wrote into it, the theme it resolves
terminal list                # both terminals: installed, running in, configured; `terminal use` picks between two
```

The distro never edits the terminal's own config beyond one line, added
once — Ghostty's `config-file =`, WezTerm's `pcall(… "/nustro.lua" …)`
before its `return`; everything it sets lives in a file of its own that
`terminal reset` removes.

Next: [Updating](updating.md).
