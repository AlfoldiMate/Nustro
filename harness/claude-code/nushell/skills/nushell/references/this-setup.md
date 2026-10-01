# Nustro: the distro and the user layer

This file applies when the shell's configuration is Nustro, the Nushell
distro (`nu -l -c 'nustro doctor'` succeeds and names both roots). It
describes what the distro is, not one machine: the concrete paths, the
terminal, the edit mode and the theme are what `nustro status`, `nustro
doctor`, `nustro knobs` and `terminal theme status` print on the machine at
hand (`terminal` is a lazy module: in `nu -l -c` say `use terminal *` first).

Nushell is **0.116** (the bootstrap installs it: Homebrew on macOS, winget
on Windows, a release on Linux). The terminal is Ghostty or WezTerm —
`terminal target` says which — with one theme rendered for everything by
`terminal theme use` (`docs/concepts/theming.md`); the prompt is Starship.

## Two directories, and which one to edit

This is a **distro** with a user layer, not a config you edit in place:

```
THE DISTRO (a git checkout)          YOUR config directory
e.g. ~/.local/share/nustro           $nu.config-path | path dirname
  distro.nu    entrypoint      ◀──── config.nu     3 lines, sources the distro
  defaults.nu  every knob            settings.nu   the overrides
  conf/        behaviour             autoload/*.nu drop-ins, loaded last
  modules/ completions/ themes/      completions/ themes/ modules/ plugins/
  docs/ templates/ bootstrap/        history.sqlite3, plugin.msgpackz, vendor/, .state/
```

Nushell only knows the right-hand side: it loads `config.nu` from its own config
directory and derives history, the plugin registry, the autoload dirs and
`$nu.data-dir` from that same place.

- **Changing the distro** — edit the checkout (a developer usually has a
  second clone for that; `docs/cookbook/test-a-change.md`). A parse error
  breaks every new terminal, so `nu-check distro.nu` before reporting
  anything done.
- **Changing one machine only** — a knob goes in the user's `settings.nu`
  (`nustro edit` opens the directory; `nustro set '<assignment>'` writes one
  line in its place), behaviour goes in a file in the user's `autoload/`.
- **Never write user state into the checkout.** History, the plugin registry,
  generated tool files and module state all live in the user directory; the
  `.gitignore` is four lines because of it.

`docs/README.md` is the map of the documentation; `docs/concepts/layout.md`
the layering and load order, `docs/reference/files.md` the formats,
`docs/reference/platforms.md` the per-platform coverage, `docs/concepts/startup.md`
what Nushell loads when.

## The rules that shape the files

- Settings are leaf-key assignments (`$env.config.a.b = ...`), never whole
  records, never `$env.config = {...}`.
- **Values in `defaults.nu`, behaviour in `conf/`.** A `conf/` file must never
  assign a value `defaults.nu` owns: it runs after the user's `settings.nu` and
  would silently overwrite it.
- Paths are parse-time constants derived from `path self`; never a hard-coded
  home directory. `use`/`source` need parse-time paths, which is why an optional
  include is a const `if` around `source null`.
- Optional tools are guarded with `which`; `alias` and `extern` cannot sit
  inside an `if` — they are parse-time.
- `.nu` for anything the parser must see, NUON for anything tooling reads at
  runtime. The two JSON caches that remain are measured and commented.
- Modules follow `docs/concepts/modules.md`: `mod.nu` + `load.nu` + `meta.nuon`,
  code only — the page is `docs/reference/modules/<name>.md` — wiring in
  `activate`, knobs in `meta.nuon`. `nustro module lint` enforces it.

## Commands this config adds

| | |
|---|---|
| `nustro` / `nustro status` | one record: `version`, `head`, `upstream`, `layout`, `distro`, `yours`, `modules`, `lazy`, `theme`, and `attention` — rows of `{what, fix}` |
| `nustro doctor` | the full health check, printed |
| `nustro repair [--dry-run]` | re-runs every wiring step (settings, state, scaffold, tools, plugins, theme, completion, harness, parse); a table of `step`, `result`, `note`. `--hard` runs the installer again with every default; `--reset` runs it from an empty directory, asks first and needs a terminal — never run `--reset` for a user |
| `nustro upgrade`, `upgrade status`, `upgrade rollback` | pull the checkout (checked before it lands); the last check; back to the last version that parsed |
| `nustro edit`, `edit distro` | the user's config directory in `$EDITOR`; the checkout |
| `nustro set '<assignment>'` | one assignment into the user's `settings.nu`, on the knob's own line |
| `nustro knobs [--overridden]` | every knob, its owner, whether the user set it |
| `nustro module list\|info\|check\|help\|enable\|disable\|lint` | the module system |
| `nustro deps status\|manager\|install` | starship, zoxide, atuin, carapace, vivid |
| `nustro plugins status\|add` | the plugins beside `nu`, and registering them |
| `nustro completion explain "<line>"\|status\|clear\|fetch <tool>` | Tab, as a person asks about it |
| `nustro harness status\|register\|update` | the checkout as a Claude Code marketplace |
| `nustro startup-time`, `loaded-files` | cold-start timing; what this session parsed |
| `nustro bootstrap …` | plumbing the installer, the startup hooks and `repair` run: `scaffold init\|status\|render`, `tools setup\|status\|remove\|dir`, `upgrade check\|stale\|notice\|good\|head\|branch`, `plugins notice`, `root`, `user-root`, `layout`, `config-dir`, `in-place?`, `manifest`, `nu-older-than`, `missing-tool`, `missing-tools` |
| `nu-complete` | the Tab engine, the API a spec in `completions/` calls: `run`, `smart`, `external`, `quote`, `cache`, `status`, `explain` |
| `terminal` (lazy) | the terminal itself — Ghostty or WezTerm, `terminal target` says which: `status` (also bare `terminal`), `list`, `current`, `target`, `default`, `use`, `install`, `shell`, `option`, `settings`, `set`, `reset`, `reload`, `live` |
| `terminal theme` (lazy) | the picker (interactive); `use <name>`, `list`, `preview`, `reset`, `sync`, `icon`, `current`, `roles`, `resolve`, `status`, `slug` |
| `terminal font` (lazy) | the picker (interactive); `use <name>`, `list`, `install`, `preview`, `size`, `specimen`, `dir` |
| `agent` | Claude Code in the shell: `ask`, `exec`, `skill`, `command`, `completion` (lazy) |
| `odata` | OData V2/V4 services as tables (lazy) |
| `worktree` | bare repo + a directory per branch, gitignored files from profiles: `init`, `add`, `remove`, `apply`, `discard`, `which` (lazy) |

`nustro status | get attention` is the first thing to read when something
looks wrong — each row names what is off and the command that fixes it —
and `nustro doctor` the long form: both roots, the layout state (`split` is
the target), every derived path, a parse check, tools, plugins, modules and
startup time. `nustro repair` puts the wiring back and replaces nothing of
the user's; reach for a `nustro bootstrap …` command only for one targeted
step.

`nu-config`, `theme`, `font`, `ghostty` and `wezterm` are not command words
any more (0.2.0, 2026-10-02): they are `nustro …` and `terminal …`. `ghostty
set`, `wezterm live` and the like still exist inside the module as its
backends, reachable in a script or a test with `use terminal/ghostty.nu *`;
at the prompt the equivalent is `terminal set`, `terminal live`, `terminal
theme list --ghostty`. The binaries `ghostty` and `wezterm` are the
terminals' own.

## What the defaults set

`defaults.nu` is every knob with its default and the reason; `nustro
knobs` prints them with the user's overrides; `docs/reference/knobs.md` is
the table. The shape, as shipped:

- **Edit mode** vi; cursor `line` in insert, `block` in normal
- **Editor** first of `zed --wait`, `nvim`, `vim`, `vi` that exists
- **Tables** `markdown`, index always, footer at 25 rows
- **Banner** off · **History** sqlite, 1M entries
- **Tab** the smart menu (`SMART_TAB`), pipeline-aware, fuzzy matching
  ranked in tiers and searching descriptions, `NU_COMPLETE_EVAL = "safe"`
- **Theme** whatever `terminal theme use` rendered last into `.state/theme/`
  (no knob); tables, `ls`, bat and the starship prompt all come from it.
  `terminal theme status`, `terminal theme roles`
- **Modules** `nustro` and `nu-complete` eager; `terminal`, `agent`, `odata`,
  `worktree` lazy — loaded by a `pre_execution` hook on the first line that
  starts with the module's word (`expand` also loads `odata`; `terminal` has
  no other trigger word), which means they do **not** load for `nu -c` or a
  script: `use terminal *` first
- **`open`** left alone: it is Nushell's parser. Use `start <path>` to launch a
  file in its app, and `%open` inside completion modules in case a user aliased it

## Tools

Generated into the user's `vendor/autoload/` by `nustro repair` (its `tools`
step, `nustro bootstrap tools setup`), from the registry in
`modules/nustro/tools.nu`: **zoxide**, **atuin**, **carapace**. Installed →
generated, absent → pruned, so presence on PATH is the switch. vivid and
starship are the theme's: `terminal theme use` renders LS_COLORS and a
starship.toml into `.state/theme/`, and starship is wired by hand in
`conf/prompt.nu`. Homebrew's `command_not_found` and direnv are in
`conf/tools.nu`, each guarded with `which`.

`nu -l -c` does **not** load the vendor autoload directory, so carapace and
zoxide are absent there — source the generated file if a test needs one.

## Verifying a change

```nu
nu-check distro.nu                 # parse, follows every `source`
nu -l -c 'nustro doctor'           # loads the config for real
nu -l -c 'nustro module lint'      # the only check that reaches a lazy module
nu -n -c '<snippet>'               # isolated snippet, no config
nu -l -c 'nustro startup-time'     # ~84 ms; regression-check after adding anything
```

`nu -c '...'` and `nu script.nu` load no user config at all and prove nothing
about this config. `nu -n` also has no `NU_LIB_DIRS`, so `nu-check` on a file
that imports a module reports `false` there for reasons unrelated to the file.

## Updating

`nustro upgrade` pulls the checkout (fast-forward only), renders any
scaffold file a release added to the user directory, and — when `claude` is
on PATH and the checkout is the registered marketplace — refreshes the
marketplace and every plugin installed from it (`nustro harness update`
does that part alone). The shell says at start when the checkout is behind,
and `nustro status` says it as `upstream`. After an upgrade, or whenever
`attention` lists something, `nustro repair` re-runs the wiring.

## After `brew upgrade nushell`

```nu
nustro plugins add    # the registry is protocol-versioned against the binary
nustro status         # `attention` is empty when nothing else needs doing
```

Nushell makes breaking changes at minor versions: when the pin moves, the config
is what has to be re-checked. `docs/concepts/plugins.md` explains why there is no plugin
manager to do this for you.
