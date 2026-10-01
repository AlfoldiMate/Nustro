# Pick a theme and make it stick

This page was run in Ghostty; with WezTerm being configured (`terminal
target`) every `terminal theme` line is the same, the theme lands in
`.state/theme/wezterm/` as a scheme file, and there is no app icon.

## Pick one

```nu
terminal theme                 # scroll the hundred palettes; the window you are in is the preview
terminal theme --ghostty       # or Ghostty's own 463
terminal theme use tokyonight  # by name — Tab completes them
```

That is the whole of it. `terminal theme use` writes Ghostty's theme and app icon,
repaints this window and reloads every open one, and renders the shell's
colours, `LS_COLORS`, the bat theme and the starship prompt into
`<your>/.state/theme/`, which every new shell reads in 0.36 ms. There is no
knob to set: what was rendered last is the theme.

```nu
terminal theme status          # what is rendered, from which theme, at which tier, and whether Ghostty agrees
terminal theme roles           # every role, its colour, and which tier decided it
terminal theme reset           # only after a `terminal theme preview`: hand the terminal back to Ghostty's config
```

## Make a palette of your own

The shell's colours are written in **roles** — `accent`, `ok`, `warn`, `err`,
`fg_muted`, `border`, and the rest ([Theming](../concepts/theming.md#roles-and-the-three-tiers)).
A palette file names them. The shortest one extends a theme Ghostty already
ships, borrowing its sixteen, and names only the roles you care about:

```nu
# <your dir>/themes/palettes/harbour.nuon
{
  name: Harbour
  ghostty: "Gruvbox Dark"      # the Ghostty theme whose file supplies the sixteen
  dark: true
  colours: {
    sea: "#1d3557"
    foam: "#a8dadc"
    rope: "#e9c46a"
    rust: "#e76f51"
    kelp: "#2a9d8f"
    fog: "#8d99ae"
  }
  roles: {
    accent: foam
    ok: kelp
    warn: rope
    err: rust
    fg_muted: fog
    border: sea
  }
}
```

The file's stem is the slug of its `name` — lowercased, runs of anything but
letters and digits turned into `-`; `terminal theme slug "TokyoNight Storm"` prints
`tokyonight-storm`. A role may name one of your `colours` or carry a hex of
its own. Every role you do not name is blended from the Ghostty theme's own
hexes (tier two), and the sixteen stay the terminal's (tier one), so six
colours is a complete palette.

For a theme that is entirely yours, `<your dir>/themes/palettes/example.nuon.off`
is one already: rename it and `terminal theme use Example` renders it. Its `terminal`
block — all sixteen plus background, foreground, cursor and selection — is
what makes it a Ghostty theme file too; NvChad's
(`themes/palettes/nvchad/tokyonight.nuon` in the checkout) have the same shape.

Check it before you keep it:

```nu
terminal theme list | where theme == Harbour          # kind: yours
terminal theme roles Harbour                          # from: palette for the six, ansi for the sixteen, derived for the rest
terminal theme resolve Harbour | select name by tier  # the record, nothing written
terminal theme use Harbour
```

Run on 2026-09-19 with the file above in a scratch user directory: listed as
`yours`; `accent` `#a8dadc` from `palette`, `red` `red` from `ansi`;
`terminal theme use` took 492 ms and `terminal theme status` then showed `Harbour`, Ghostty
resolving `Gruvbox Dark`, and `icons/harbour.png` rendered.

A palette with the same slug as a shipped one shadows it — the same rule as
a completion ([Override a shipped completion](override-completion.md)).

## Keep it after a `git pull`

Your theme is not in the checkout, so a pull cannot take it away. What a
pull *can* change is a template — `themes/nushell.nu`, `starship.toml`,
`vivid.yml`, `icon.svg` — which the rendered files were made from:

```nu
terminal theme sync            # re-resolve and re-render the current theme from the templates as they are now
nustro repair                  # or every wiring step, this one among them
```

`nustro status` says when to — "a theme template is newer than the render"
under `attention`; `nustro doctor`'s Theme line shows when the render was
made.

To change a template rather than a palette — a different prompt layout, say
— copy it into your `themes/` and edit the copy there. It is picked up over
the shipped one, `terminal theme sync` renders it, and it must be written in roles,
never hexes, so that every theme keeps fitting it. The user's copy is chosen
at parse time for `terminal theme use` in the running session, so a template dropped
in after the module loaded is seen by the next shell.
