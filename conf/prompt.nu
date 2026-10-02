# prompt.nu — prompt
#
# Starship owns the prompt when it is installed, and the distro owns starship's
# configuration: a style chosen with `terminal prompt` (powerline, plain, …;
# modules/terminal/prompt.nu generates it), written in the theme's roles and
# rendered by `terminal theme use` into <your dir>/.state/theme/starship.toml.
# STARSHIP_CONFIG points at the rendered file, or at themes/starship.toml — the
# powerline with every option at its default — before the first render: its
# own palette block is the ANSI tier, so the prompt follows the terminal's
# colours from the first start. A ~/.config/starship.toml of your own is not
# read; to change the prompt, `terminal prompt set …`, or for one written by
# hand copy the template to <your dir>/themes/.
# Without starship, Nushell's built-in prompt stays: path on the left, time on
# the right. With `terminal prompt use off` there is no prompt at all: only
# the indicators below, which say which vi mode the line is in.
#
# This is written by hand instead of generated with `starship init nu` on
# purpose. The generated file would land in the vendor autoload dir, which
# loads AFTER this config and would overwrite the indicators below.

# What Nushell reports before any command has run.
const NO_DURATION = "0823"

# What `terminal prompt` chose: the style and the options that differ from
# their defaults. Absent until one is chosen, and then nothing is opened.
const PROMPT_STATE = ($nu.data-dir | path join .state theme prompt.nuon)

def starship-prompt [--right]: nothing -> string {
  let ms = ($env.CMD_DURATION_MS? | default $NO_DURATION)
  let duration = if $ms == $NO_DURATION { 0 } else { $ms }
  let side = if $right { ["--right"] } else { [] }
  ^starship prompt ...$side --cmd-duration $duration $"--status=($env.LAST_EXIT_CODE? | default 0)" --terminal-width (term size).columns --jobs (job list | length)
}

let prompt = (if ($PROMPT_STATE | path exists) { open $PROMPT_STATE } else { {} })
let prompt_off = (($prompt.style? | default powerline) == "off")

if (which starship | is-not-empty) {
  let rendered = ($nu.data-dir | path join .state theme starship.toml)
  let yours = ($USER_ROOT | path join themes starship.toml)
  $env.STARSHIP_CONFIG = (
    if ($rendered | path exists) { $rendered } else if ($yours | path exists) { $yours } else { $DISTRO_ROOT | path join themes starship.toml }
  )
  $env.STARSHIP_SHELL = "nu"
  $env.STARSHIP_SESSION_KEY = (random chars --length 16)
  # Starship's prompt, kept: `terminal prompt use` switches a running session
  # to it and away from it (`terminal prompt apply`), and a module cannot
  # reach `starship-prompt`.
  $env.NUSTRO_PROMPTS = {
    left: {|| starship-prompt }
    right: {|| starship-prompt --right }
    # A closure, so starship is only asked for the continuation prompt when a
    # multi-line command is actually being typed (a call at startup costs ~9 ms).
    multiline: {|| ^starship prompt --continuation }
  }
  if not $prompt_off {
    $env.PROMPT_COMMAND = $env.NUSTRO_PROMPTS.left
    $env.PROMPT_COMMAND_RIGHT = $env.NUSTRO_PROMPTS.right
    $env.PROMPT_MULTILINE_INDICATOR = $env.NUSTRO_PROMPTS.multiline
    $env.config.render_right_prompt_on_last_line = true
  }
} else {
  $env.PROMPT_MULTILINE_INDICATOR = "::: "
}

# Off is off: no path, no clock, nothing on the right. What is left is the
# indicator of the mode.
if $prompt_off {
  $env.PROMPT_COMMAND = ""
  $env.PROMPT_COMMAND_RIGHT = ""
  $env.PROMPT_MULTILINE_INDICATOR = "::: "
}

# ── Indicators ────────────────────────────────────────────────────────────────
# Drawn after the prompt; they are how you see which vi mode you are in.
$env.PROMPT_INDICATOR = ""
$env.PROMPT_INDICATOR_VI_INSERT = ": "
$env.PROMPT_INDICATOR_VI_NORMAL = "〉"

# ── Transient prompt ──────────────────────────────────────────────────────────
# `terminal prompt set transient true`: once a command has run its prompt is
# redrawn as one mark, so scrollback is commands and their output. A string,
# not a closure — nothing is forked for it — in the theme's green as text
# (`$c` is conf/theme.nu's roles), and the mark stands in for the indicators.
# The blank line before a prompt is part of what gets redrawn, so the mark
# carries one of its own — `true` — or the blocks close up — `compact`.
# Not with `off`: there is no prompt to collapse.
let prompt_transient = ($prompt.options?.transient? | default false)
if $prompt_transient != false and not $prompt_off {
  let gap = (if $prompt_transient == "compact" { "" } else { "\n" })
  $env.TRANSIENT_PROMPT_COMMAND = $"($gap)(ansi { fg: $c.text_green, attr: b })\u{276f}(ansi reset) "
  $env.TRANSIENT_PROMPT_COMMAND_RIGHT = ""
  $env.TRANSIENT_PROMPT_INDICATOR = ""
  $env.TRANSIENT_PROMPT_INDICATOR_VI_INSERT = ""
  $env.TRANSIENT_PROMPT_INDICATOR_VI_NORMAL = ""
}
