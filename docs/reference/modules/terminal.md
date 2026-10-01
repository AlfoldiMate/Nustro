# terminal

The terminal you are running in: its theme, its font, and its configuration.
Two terminals are known — Ghostty (macOS, Linux) and WezTerm (macOS, Linux,
Windows) — and the commands configure whichever one you are in, or the one
you pinned.

```nu
terminal list                  # which terminals this distro knows, and what is true here
terminal use wezterm           # pin the one the commands below configure
terminal theme                 # pick from a hundred palettes, the terminal is the preview
terminal theme --ghostty       # or from Ghostty's own 463
terminal font                  # pick a Nerd Font, install it, see it in a real window
terminal theme use tokyonight  # or name one; Tab completes them
terminal theme roles           # what the shell made of it: every role, its colour, which tier
terminal shell                 # a new window of the terminal starts Nushell
terminal option left           # which Option key is Alt: none (the base), left, right, both
terminal font use JetBrainsMono --size 15   # or `terminal font size 15` on its own
terminal status                # what this distro has written into the terminal's config
```

They belong in one module because of how this distro does colour: there is
one theme and it is the terminal's. `terminal theme use` writes the terminal's
configuration, repaints the window you are sitting in, and renders the
shell's own colours — tables, `ls`, bat, the prompt — from the same palette,
so they follow in this window now and in every shell after. `theme.nu` reads
and paints, `palette.nu` resolves and renders, `ghostty.nu` and `wezterm.nu`
each write one terminal's configuration, and `registry.nu` is the table of
terminals and the verbs that dispatch on the one being configured
(`terminal target`).

## Which terminal

`terminal target` decides, in this order: `NUSTRO_TERMINAL` in the
environment when it names an installed one; the terminal this session runs
in (`TERM_PROGRAM`), when it is installed; the one pinned by `terminal use`
(which the installer does for the choice made on its terminal screen); the
first installed one in registry order; else none — and then `terminal theme use`
still renders the shell's colours and says there was nothing to write to,
while `terminal font use` and `terminal shell` error with what to install and what
follows. A session inside Ghostty configures Ghostty even when WezTerm is
pinned: painting the window you look at is only honest for the terminal you
are in.

## Commands

What is exported is what a person types; every one starts with `terminal`,
the one word that loads the module.

The terminal:

| Command | Does |
|---|---|
| `terminal` / `terminal status` | the terminal the commands configure, the config it reads, what we own in it, and the theme and shell it resolves |
| `terminal list` | every terminal in the registry: installed, running, configured, where its binary is |
| `terminal current` | the row for the terminal this session runs in, or null |
| `terminal target` | the registry row for the terminal the commands configure, or null |
| `terminal use <name>` | pin one; kept in `<your dir>/.state/terminal/target.nuon` |
| `terminal default` | the platform's: `ghostty`, `wezterm` on Windows |
| `terminal install [name]` | install one, after asking; the platform's default when unnamed |
| `terminal shell [--reset]` | make Nushell what a new window of the target starts, or hand it back. On Ghostty on macOS this also makes both Option keys the layout's (neither is Alt) unless your config already says (`macos-option-as-alt`); `--reset` hands both back |
| `terminal option [side]` | which Option (Alt) key the shell gets as Alt, the other typing the layout's characters: `none` (the base: both type characters, as in iTerm2), `left`, `right`, `both`, or `default` to drop ours. Written to our file, so it wins over yours, and reloaded into the open windows. Nothing given: what it is now. Alt+E, Alt+B/F/D and the other Alt+letter bindings need a key that is Alt, so with `none` they do not work; Alt+Enter, Alt+arrows and Alt+Backspace work whatever is set |
| `terminal settings` | our keys in the target's configuration |
| `terminal set <record>` | write keys into our own file in the target's configuration, in its vocabulary — Ghostty's `font-family`, WezTerm's `font_family`; a null value removes one |
| `terminal reset` | remove our file and the line that includes it; their config is left as it was |
| `terminal reload` | reload the target's open windows; true when they took it (Ghostty: macOS, AppleScript; WezTerm reloads by itself) |
| `terminal live <key>` | what the target resolves for a key, their config included |

The theme:

| Command | Does |
|---|---|
| `terminal theme [--ghostty]` | the picker: the hundred palettes (or Ghostty's 463) with their own colours beside them, then paint, then keep or not |
| `terminal theme list [--ghostty] [--swatches]` | the palettes, or Ghostty's own themes with their files; `--swatches` adds the sixteen colours |
| `terminal theme preview <name> [--ghostty]` | paint this session, change nothing on disk |
| `terminal theme reset` | hand the palette back to the terminal's config — the way out of a preview |
| `terminal theme use <name> [--ghostty] [--no-icon]` | write the terminal's theme (and the icon, on Ghostty), paint, reload every window, render the shell's colours |
| `terminal theme icon [--off]` | render the app icon for the current theme again, or remove the icon keys — Ghostty only |
| `terminal theme current` | what was rendered last, or null before the first `terminal theme use` |
| `terminal theme roles [name]` | every role, its resolved colour and the tier that decided it, with a swatch |
| `terminal theme status` | what is rendered, from which theme, at which tier, and what the terminal was given (`terminal`, `terminal_theme`) |
| `terminal theme sync [name]` | re-resolve and re-render — after a `git pull` changed a template, or `--none` to forget the theme |
| `terminal theme resolve [name]` | the resolved theme as data, nothing written |
| `terminal theme slug <name>` | the file name a palette has: `Catppuccin Macchiato` → `catppuccin-macchiato` |

The font:

| Command | Does |
|---|---|
| `terminal font` | the picker: fifteen Nerd Fonts, install what you choose, keep it |
| `terminal font list` | the registry, and what is installed here — as the terminal being configured sees it |
| `terminal font install <name>` | Homebrew's cask on macOS, the release archive otherwise |
| `terminal font preview <name>` | a new window of the terminal in that font, showing a specimen |
| `terminal font specimen` | the sample text in the font this terminal is using now |
| `terminal font use <name> [--size N]` | install if needed, then keep it — with a point size, when given |
| `terminal font size [N] [--reset]` | the size alone: show what the terminal uses, set it (halves are fine, 4..72), or `--reset` to hand it back |
| `terminal font dir` | where a user's own fonts go on this platform |

Theme names are Tab-completable everywhere they are taken: the palettes, or
Ghostty's once `--ghostty` is on the line.

### Internal (by file)

Not exported, so not typed at the prompt: how the files talk to each other.
The commands above dispatch to these on the target's name, so they never
name a terminal. The installer, the tests and a script reach one by file —
`use terminal/ghostty.nu *`, `use terminal/registry.nu *`. The Measured,
Limits and Tests sections below, and [Theming](../../concepts/theming.md),
name them where the cost or the behaviour is one backend's.

`ghostty.nu` — the Ghostty backend:

| Command | Does |
|---|---|
| `ghostty status` | the config Ghostty reads, what we own in it, and the theme and shell Ghostty resolves |
| `ghostty settings` | our keys in our included file |
| `ghostty set <record>` | write keys into our own included file (a null value removes one) |
| `ghostty reset` | remove our file and the one include line; their config is left as it was |
| `ghostty shell [--reset]` | make Nushell what a new Ghostty window starts, and on macOS both Option keys the layout's unless your config already says; `--reset` hands both back |
| `ghostty option [side]` | `macos-option-as-alt` in our file, reloaded into the open windows |
| `ghostty nu-path` | the nu that `shell` writes: the one on PATH, not the running binary (`terminal nu-path` is the same) |
| `ghostty reload` | reload Ghostty's config in every open window (macOS, AppleScript); true when it did |
| `ghostty live <key>` | what Ghostty resolves for a key, their config included (`+show-config`) |
| `ghostty face <family>` | the face Ghostty would actually use for a family (`+show-face`) |
| `ghostty preview` / `ghostty config-path` | the preview window; the config file Ghostty reads |

`wezterm.nu` — the WezTerm backend:

| Command | Does |
|---|---|
| `wezterm status` | the config WezTerm reads, what we own in it, the scheme and shell we set |
| `wezterm settings` | our keys in `nustro.lua` |
| `wezterm set <record>` | write keys into our `nustro.lua` (a null value removes one); `font_family` is our name for its `font` |
| `wezterm reset` | remove our file and the two lines that apply it; their config is left as it was |
| `wezterm shell <nu> [--reset]` | `default_prog = { <nu>, "-l" }` in our file; `--reset` drops it |
| `wezterm option [side]` | the two `send_composed_key_when_{left,right}_alt_is_pressed` booleans; its own default is `left`, so `default` drops both keys |
| `wezterm reload` | true: WezTerm reloads its configuration by itself on every write |
| `wezterm live <key>` | `font_family`: the face `ls-fonts` resolves for the loaded config; other keys: ours or null |
| `wezterm face <family>` | the face WezTerm resolves a family to (`--config font=… ls-fonts`) |
| `wezterm preview` / `wezterm font-keys` / `wezterm config-path` | the preview window; a family and size in WezTerm's keys; the config file it reads |

`registry.nu` — the dispatch the exported verbs share:

| Command | Does |
|---|---|
| `terminal install-plan [name]` | what this platform would have to run, and whether it can |
| `terminal require` | the target's row, or the error that says what to install |
| `terminal nu-path` | the nu a terminal should start: the one on PATH |
| `terminal face` / `preview` / `font-keys` / `write-theme` | the target's own, dispatched on its name — what `terminal theme use` and `terminal font use` call |

`theme.nu`, `palette.nu`, `font.nu`:

| Command | Does |
|---|---|
| `ghostty themes [--swatches]` | every theme Ghostty can find, with its file — behind `terminal theme list --ghostty` |
| `ghostty names` / `terminal theme names [--ghostty]` | the names alone — Ghostty's, or the palettes: what Tab on a `<name>` offers |
| `terminal theme palettes` | every palette file: name, dark, kind, the Ghostty theme it extends — behind `terminal theme list` |
| `terminal theme palette <name>` | one Ghostty theme file as data: `palette` 0-15 and the named colours |
| `terminal theme paint` / `apply` / `read` / `swatch` / `state-dir` / `ghostty-file` / `wezterm-file` / `starship-palette` | the steps of `terminal theme use`: OSC painting, the state, a palette as each terminal's theme file |
| `terminal font face <family>` | the face the terminal would actually use for a family |

## Configuration

One knob, `NERD_FONTS_RELEASE`: where `terminal font install --archive` takes the
archives from — the Nerd Fonts release by default, a mirror's URL, or a
directory that already holds the assets (an offline machine; the tests).
Two pieces of state: what `terminal theme use` renders into `<your
dir>/.state/theme/` — `theme.nuon`, `starship.toml`, `ls_colors`, a Ghostty
theme file (`ghostty/<slug>`) or a WezTerm scheme (`wezterm/nustro-<slug>.toml`)
and an icon per palette used — which `conf/theme.nu`, `conf/prompt.nu` and
the terminal read (`terminal theme status` shows it); and the pin, `<your
dir>/.state/terminal/target.nuon`, written by `terminal use`.
A terminal's own configuration is read at the moment you ask, never cached.
The templates being rendered live in `themes/` ([Theming](../../concepts/theming.md)),
and a copy in your own `themes/` is the one used.

## Dependencies

One of `ghostty` and `wezterm`, hard — a `group` in `meta.nuon`, so with
either present the other is `alt`, not `missing` (`nustro module check
terminal` prints both, with the install line and what follows for the
absent one). Without either the palettes still list and resolve (at tier
three, with no window to paint), `terminal theme use` renders the shell's colours and
says there was nothing to write to, `terminal font use` and `terminal shell` error
with what to install and what follows, and `terminal theme reset` still works — OSC
is the terminal's, so the escape sequences are understood by any terminal
that implements them. Ghostty's own 463 themes (`--ghostty`) need Ghostty
whichever terminal is being configured; a WezTerm target is handed them as
a scheme file written from the sixteen Ghostty's file holds.

## Design

Why the theme is the terminal's, why the picker paints the window instead of
drawing swatches, why a font is previewed in a window of its own, why the
registry is data and verbs rather than closures, and every Ghostty and
WezTerm fact the module rests on: [Theming](../../concepts/theming.md).

## Measured

Nushell 0.115.1, Ghostty 1.3.1, WezTerm 20240203, macOS, 2026-09-18 unless dated.

| What | Cost |
|---|---|
| the module, loaded | 31 ms — 93.1 ms of startup with it eager against 61.8 ms with it lazy, medians of 25 cold starts, 2026-09-20 with the WezTerm backend and the registry; 18 ms the day before with Ghostty alone (78.4 against 60.1) |
| parsing the module | 20.8 ms — `nu -n -c 'use terminal *'` against an empty run, medians of 21, 2026-09-20; 15.3 ms for the Ghostty-only module the same day, so WezTerm and the registry are 5.5 ms of parse |
| a registry of closures | 130 ms of eager startup, 2026-09-20 — the first registry was thirty-four closures in a table, 28 ms to parse after `nustro` was in scope and worse in the whole distro, because a closure is analysed for captures against everything visible; the verbs are `match` arms now, which cost nothing measurable |
| `wezterm ls-fonts` | 116 ms with the config loaded (`wezterm live font_family`), 50 ms with `--config font=…` alone (`wezterm face`), 2026-09-20 |
| `wezterm set` | one `ls-fonts` to validate, 50 ms; the reload is WezTerm's own file watcher |
| `terminal theme list --ghostty` (`ghostty themes`) | 31 ms — it spawns `ghostty +list-themes` |
| `terminal theme list --ghostty --swatches` | 333 ms, reading all 463 theme files |
| `terminal theme list` | 24 ms: a hundred palette files opened; 133 ms with `--swatches` (the four Catppuccins read Ghostty's files, through one listing) |
| `terminal theme names` | 55 ms: the palettes plus Ghostty's list — what Tab pays on `terminal theme use ` |
| `terminal theme resolve <name>` | 40 ms for a Ghostty theme, of which 31 ms is `terminal theme palette` spawning `ghostty +list-themes` to find the file; a palette with its own `terminal` block spawns nothing |
| `terminal theme sync` | 44 ms: the resolve, vivid, three files written |
| `terminal theme use` | 320 ms: the resolve, the icon through AppKit (`rasterize.js`, 100 ms), `ghostty set` validating through `+validate-config`, the paint, `ghostty reload` through osascript, then the render |
| `ghostty reload` finding its Ghostty | 15 ms: `ps -o ppid=,comm=` once per ancestor from the shell up to the app, five hops from a login shell |
| reading the render at startup | 0.36 ms for `theme.nuon` (1 kB), 0.09 ms for `ls_colors` (6 kB), medians of 21 |
| reading all 463 files | 39 ms; `(?m)` over the whole file rather than `lines` halves the parse, 49 ms against 109 ms |
| one swatch | bit shifts rather than splitting the hex into pairs: 95 ms over all 463 against 380 ms |
| `ghostty +show-config` | 18 ms |
| `ghostty +show-face` | 26 ms per call; `terminal font list` runs fifteen through `par-each` in 103 ms |
| a font landing on macOS | `brew install --cask font-hack-nerd-font` returned 1.7 s before Ghostty resolved `Hack Nerd Font` to itself (2026-09-19); `terminal font install` polls `+show-face` every 200 ms, up to 10 s, before it reports — a single check said "not installed" and `terminal font use` refused the font it had just installed |
| installing Inconsolata from the archive | 8 MB downloaded, two faces (it has no italic) into `~/Library/Fonts` |

## Files

```
mod.nu       exports what a person types from each file, and `terminal activate` (one knob's default)
load.nu      `use terminal *` + activate
meta.nuon    description, the ghostty-or-wezterm dependency group, one knob
theme.nu     listing, reading and painting Ghostty's themes; a palette as a Ghostty or WezTerm theme file
palette.nu   roles, the three tiers, rendering, the picker, `terminal theme use`
font.nu      the Nerd Font registry, installing, and the preview window
ghostty.nu   finding Ghostty and its config, the one line we add to it, the shell, faces, the preview window
wezterm.nu   the same for WezTerm: nustro.lua, the line before `return`, `ls-fonts` for faces
registry.nu  the terminal registry: installed, running, the target, and the verbs that dispatch on it
```

## Limits

- Lazy, therefore interactive-only: `terminal theme use X` in a script needs `use
  terminal *` first, because `pre_execution` does not fire for `nu -c`.
- A hand-written `~/.config/starship.toml` is not read any more: the distro
  owns starship's configuration and points `STARSHIP_CONFIG` at the rendered
  one. The way to change the prompt is a copy of `themes/starship.toml` in your
  own `themes/`.
- The user's copy of a template is picked at parse time for `terminal theme use` in the
  running session (`source` needs a constant), so a `themes/nushell.nu` dropped
  in after the module loaded is seen by the next shell.
- Tier two blends in sRGB, not linear light. For the small steps between a
  background and its foreground the difference is invisible; it is noted here
  in case someone measures.
- Ghostty and WezTerm only. The OSC painting would work in any terminal that
  implements OSC 4/10/11/12/17/19, but the theme files and the config writing
  are per terminal: a third one is a row in `registry.nu`, a backend file and
  one arm in each verb.
- Ghostty has no Windows build yet, so `terminal install ghostty` on Windows
  prints where the port stands and runs nothing; the Windows default is WezTerm.
- The app icon is Ghostty's (`macos-custom-icon`); WezTerm has no such key,
  so `terminal theme icon` errors when WezTerm is the target and `terminal theme use` skips it.
- Ghostty's own 463 themes are read from Ghostty's files, so `--ghostty` needs
  Ghostty installed whichever terminal is being configured; WezTerm's 1000+
  built-in schemes are not listed (there is no CLI for them), so with WezTerm
  the list is the hundred palettes.
- WezTerm's `wezterm.lua` is Lua, and nothing can follow `return`: the line
  that applies our file goes before the final `return <name>`. A config that
  ends any other way is left alone and the line is printed to add by hand.
- Off macOS `terminal reload` does nothing for Ghostty (it is AppleScript), so a Ghostty
  write reaches new windows only; the running one is repainted over OSC
  instead. WezTerm reloads itself everywhere.
- WezTerm's last stable release is 20240203 (nightlies since); everything
  here was verified against it.
- `cursor-text` in a theme file is ignored: there is no OSC for it.
- Off macOS a font takes effect in new windows only: no reload, and no
  escape sequence for changing font.
- That the preview window renders in the requested family is Ghostty's
  documented CLI behaviour (`ghostty --help` gives `--font-family="Fira Code"`
  as its own example) and the window was verified to open and run the specimen;
  it has not been checked pixel by pixel.
- `terminal font install` without Homebrew downloads the whole release archive and throws
  most of it away, because a GitHub release asset cannot be extracted in part.
  Iosevka is 402 MB and Noto is 620 MB for four files.
- `terminal font install` and `terminal font use` of a font that is not installed ask before
  downloading, so headless (a script, `nu -c`) they refuse and say to pass
  `--yes` to `terminal font install`.
- The Windows branch of `terminal font install` — the per-file `HKCU\...\Fonts` registry
  value a user-installed font needs — is written from the documented behaviour
  and has not been run.
- Untested on Linux and Windows by hand. The config candidates and the
  resources directory are derived per platform; the tests below run the XDG
  paths on the Linux runner, and the Application Support path on macOS.

## Tests

`nu tests/run.nu terminal` — 70 tests in `tests/terminal/` (4.4 s on an
M-series Mac, 2026-09-20) against a fake `ghostty` (`tests/fixtures/ghostty/fake.nu`,
put first on PATH by `fake-ghostty` in `tests/lib.nu`) that answers
`+show-config` from the config chain the way Ghostty settles it,
`+show-face` from a list of families, `+validate-config` from the themes it
"ships" and `+list-themes` from the same, and logs every call; a fake
`osascript` beside it answers `ghostty reload` and passes the icon
rasterizer through to the real one. HOME and XDG_CONFIG_HOME are the run's
own, so `ghostty set` and `terminal font install` write into a scratch directory.
The `ghostty` tests cover the config path precedence, `set`/`reset`/`live`/`shell`/
`reload`; the `theme` tests the three tiers, Ghostty theme files both ways, `terminal theme
use`/`sync` end to end and the icon's pixels (macOS); the `font` tests the `+show-face`
argument order, the registry, an install from a fixture archive with the
temporary directory checked gone, and `terminal font use`. `wezterm` runs the same
against a fake `wezterm` (`tests/fixtures/wezterm/fake.nu`, `fake-wezterm`)
that answers `ls-fonts` the way the real one does and logs `start`: the
config search, the line before `return` (and the refusal when there is no
named return), `set`/`reset`/`live`/`shell`, the Lua escaping of a Windows
path, validation through `ls-fonts`, and `terminal theme use`/`terminal font use`/`terminal font
preview` with WezTerm as the target. `registry` covers the target order
(`NUSTRO_TERMINAL`, the session's terminal, the pin, the first installed)
and the error without one — two of its tests skip on a machine that has a
real terminal installed. Nothing here needs a Ghostty or a WezTerm
installed. [Tests](../tests.md) is the harness.
  That includes `terminal shell` on Ghostty: whether Ghostty on Linux starts a bare
  `command` as a login shell has not been checked, only that it starts it.
