# Shape the prompt

The theme colours the prompt ([Pick a theme and make it stick](theme.md));
`terminal prompt` is everything else about it: the style, which segments
are drawn and on which side, whether it needs a Nerd Font. Each change is
rendered and switched in the window it is typed in, and kept for every
shell after.

## Look first

```nu
terminal prompt           # the picker: every style as starship draws it in this directory, then choose one
terminal prompt status    # the style, and every option with its value, its default and what it does
terminal prompt preview   # the drawing alone, nothing asked and nothing written
```

The preview is in the theme's colours, with a made-up 2.4 s command so the
duration shows. `--with` tries options without setting them:

```nu
terminal prompt preview plain --with { icons: false }
terminal prompt preview powerline --with { separator: round, git: right }
```

## A style

```nu
terminal prompt use plain       # the segments as coloured text, the path in bold, no surfaces
terminal prompt use bracketed   # plain, each segment in brackets
terminal prompt use minimal     # only the path, the branch, a failed exit code and the duration
terminal prompt use powerline   # tinted segments joined by separators — the shipped look
terminal prompt use off         # no prompt at all: only the indicator of the vi mode, `: ` and `〉`
```

The options survive a change of style, so `off` and back is the prompt you
had.

## What is drawn, and where

Nine segments are drawn until told otherwise — `os`, `user`, `directory`,
`git`, `languages`, `env`, `time`, `status` (a failed command's exit code,
`✘ 1`; nothing when it succeeded), `duration` — and three are off until
asked for: `docker`, `kubernetes`, `jobs`. Each is `left`, `right` or `off`:

```nu
terminal prompt set time right      # the clock at the right edge
terminal prompt set languages off   # no toolchain versions
terminal prompt set os off          # the name without the logo
terminal prompt set kubernetes left # the current context, before the clock
```

Tab completes the option and then its values. On the right a powerline is
mirrored, each segment opened from its left; a segment that is off takes
its separators with it.

## The rest

```nu
terminal prompt set icons false     # a font without Nerd Font symbols: words, and no separator glyphs
terminal prompt set separator round # powerline: arrow, round, slant or flat
terminal prompt set lines 1         # type after the segments instead of on a line of your own
terminal prompt set newline false   # no blank line before each prompt
terminal prompt set depth 5         # five directories of the path; 0 for all of it
terminal prompt set transient true  # a prompt that has run collapses to ❯, so scrollback is commands and output
terminal prompt set transient compact  # the same, with no blank line between one block and the next
```

## And back

```nu
terminal prompt reset icons time    # those two back to their defaults
terminal prompt reset               # the shipped prompt: powerline, every option at its default
```

## Check

```nu
terminal prompt status | get options | where {|o| $o.value != $o.default }   # what you changed
open ($nu.data-dir | path join .state theme prompt.nuon)              # the same, as it is kept
```

Run on 2026-10-02 in a scratch user directory with the `onedark` palette
rendered and starship 1.26.0: after `use plain`, `set time right`, `set
languages off`, `set icons false` and `set transient true` the four options
were listed against their defaults, `prompt.nuon` held `{style: plain,
options: {icons: false, transient: true, languages: off, time: right}}`, and
the rendered `starship.toml` had `format =
"$username$directory$git_branch$git_status$conda$cmd_duration$line_break$character"`
with `right_format = "$time"` and onedark's colours in its palette block.
The preview drew `Matthew in …/wt on prompt-command !? took 2s400ms` with
`at 01:34` at the right edge. In a pseudo-terminal with `transient true`,
`echo hi` followed by Enter left `❯ echo hi` above its output, a blank
line between one block and the next, and none with `transient compact`;
with `use off` the screen held `: echo hi`, `hi`, and a `: ` waiting. `reset`
removed the file and left nothing listed. The same day, after the styles
and segments grew: `terminal prompt` drew powerline, plain, bracketed
(`[Matthew] […/wt2] [ prompt-more] [!]`) and minimal (`…/wt2  prompt-more
!`) and Enter on the first answered `prompt is powerline`; `^false` put `✘
1` after the segments of the next prompt and a command that succeeded put
nothing.

## A prompt written by hand

The styles are generated; when none of them is the prompt you want, copy
`themes/starship.toml` from the checkout into your `themes/` and edit the
copy — in roles, never hexes, so every theme keeps fitting it — then
`terminal theme sync`. Yours is the prompt from then on, `terminal prompt
status` shows its path as `template`, and `use <style>` and `set` refuse and say
why until it is moved away. `use off` and `set transient` still work: they
are Nushell's, not starship's ([Theming](../concepts/theming.md#the-prompt-has-a-shape-too)).
