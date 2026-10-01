# tools.nu — hooks and keybindings for tools that ship no Nushell init file
#
# Tools that DO emit a .nu init file (zoxide, atuin, carapace) are handled by
# `nustro bootstrap tools setup`, which writes them into the vendor autoload dir where
# Nushell loads them after this config. See modules/nustro/tools.nu for the
# registry. vivid and starship are the theme's: `terminal theme use` renders both.
#
# Everything here is guarded with `which`, so a missing binary is a no-op.

# ── An unknown command: a lazy module's, or a Homebrew formula's ──────────────
# One hook, two answers. A lazy module loads on the first interactive line
# that mentions it (conf/modules.nu), but `nu -c '…'` and a script run no
# pre_execution hook, so there `terminal theme status` is "command not found" with
# nothing to say that `use terminal *` is all it takes. MODULES_TRIGGERS names
# the words a module's commands start with; the module's own name is one too.
$env.config.hooks.command_not_found = {|cmd|
  let triggers = ($env.NU_MODULES_TRIGGERS? | default {})
  let lazy = ($env.NU_MODULES_LAZY? | default [] | where {|m| $cmd == $m or ($cmd in ($triggers | get -o $m | default [])) } | get -o 0)
  if $lazy != null {
    return $"(ansi cyan)($cmd)(ansi reset) is a command of the lazy `($lazy)` module, which a shell loads on the first line that mentions it; from `nu -c` or a script, (ansi green)use ($lazy) *(ansi reset) first"
  }
  # Homebrew's executables database, read directly: 0.75 ms. It used to be
  # `brew which-formula`, 275 ms of brew starting up on every typo
  # (completions/brew.nu, `nu-complete brew provides`).
  if (which brew | is-empty) { return null }
  let formulae = (try { nu-complete brew provides $cmd } catch { [] })
  if ($formulae | is-empty) { return null }
  let more = ($formulae | skip 1 | first 4 | str join ", ")
  let also = (if ($more | is-empty) { "" } else { $" \(also in ($more)\)" })
  $"(ansi cyan)($cmd)(ansi reset) is available via Homebrew: (ansi green)brew install ($formulae | first)(ansi reset)($also)"
}

# ── direnv: load .envrc on directory change ───────────────────────────────────
# From the Nushell cookbook. direnv hands PATH back as a string; the std
# conversion turns it into the list Nushell expects.
if (which direnv | is-not-empty) {
  use std/config env-conversions
  $env.config.hooks.env_change.PWD = ($env.config.hooks.env_change.PWD? | default [])
  $env.config.hooks.env_change.PWD ++= [{||
    direnv export json
    | from json
    | default {}
    | update cells --columns [PATH] { do (env-conversions).path.from_string $in }
    | load-env
  }]
}
