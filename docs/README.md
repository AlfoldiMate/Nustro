# Documentation

One tree, four kinds of page. Start at the top if the distro is new to you;
jump to a section if it is not.

| | for |
|---|---|
| [Getting started](#getting-started) | the first hour: install it, meet the shell, change one thing, pick a theme, keep it updated |
| [Concepts](#concepts) | how it works and why it is built that way — the design records, with every measured number |
| [Reference](#reference) | what a command takes, what a knob does, what a file holds |
| [Cookbook](#cookbook) | one task per page, in the order you do it, ending with how to check it worked |

Every number in these pages was measured (`timeit`, `nustro
startup-time`, `hyperfine`) on the day stated next to it, on an M-series Mac
unless it says otherwise; nothing is estimated, on the Nushell release it names. The distro requires
Nushell **0.116**.
`assets/` holds the one image the top-level README shows: `demo.gif`, a
hundred seconds of the shipped defaults in a real Ghostty window, recorded
2026-09-19.

## Getting started

1. [Install](getting-started/install.md) — the two bootstrap lines, the seven screens, an existing configuration, what is written where
2. [Your first shell](getting-started/first-shell.md) — `nustro`, `nustro doctor`, the keys, the two directories
3. [Your first setting](getting-started/first-setting.md) — `settings.nu`, knobs, values against behaviour
4. [Your first theme](getting-started/first-theme.md) — `terminal theme`, `terminal font`, `terminal prompt`, `terminal shell`
5. [Updating](getting-started/updating.md) — `nustro upgrade`, the notice, `nustro repair`, after a Nushell upgrade

## Concepts

| | |
|---|---|
| [Layout](concepts/layout.md) | the distro and your directory, the layering by `const` shadowing, values against behaviour, load order, search paths — **the map** |
| [Startup](concepts/startup.md) | what Nushell loads when, where the distro plugs in, the lazy modules and what they save |
| [Modules](concepts/modules.md) | the module contract: `mod.nu`, `load.nu`, `meta.nuon`, `activate`, dependencies, cost |
| [Completion](concepts/completion.md) | the three layers behind Tab, the smart menu, what may run, the unified completer inputs |
| [Theming](concepts/theming.md) | one palette in roles, resolved in three tiers, rendered for every tool; the terminal as the preview; two terminals in one registry; Ghostty's and WezTerm's facts |
| [Agent](concepts/agent.md) | Claude Code inside the shell: one `claude -p` per turn, exec proposes, the checkpoint sweep |
| [OData](concepts/odata.md) | pushing `where`/`select`/`first` to the server through a `pre_execution` hook |
| [Worktrees](concepts/worktree.md) | one bare repository, a directory per branch, the gitignored files kept in profiles and placed into each |
| [Agent harnesses](concepts/harness.md) | the shell inside Claude Code: `harness/`, the nushell skills as a plugin and one plugin per module as a client of the shell command, the marketplace the install registers and `nustro upgrade` keeps current |
| [Plugins](concepts/plugins.md) | why there is no plugin manager, and what `nustro plugins add` is instead |

## Reference

| | |
|---|---|
| [Glossary](reference/glossary.md) | the words these pages use in a fixed sense — knob, drop-in, tier, place, pushdown — each with the page that defines it |
| [Knobs](reference/knobs.md) | every value `defaults.nu` ships, and where the module knobs are |
| [Files and formats](reference/files.md) | every file the distro reads or writes, `.nu` against NUON against JSON |
| [meta.nuon](reference/meta-nuon.md) | every field a module declares, and what `module lint` checks |
| [Completion specs](reference/completion-spec.md) | the spec format, sources, caching, the parse budget, the completer's input |
| [Platforms](reference/platforms.md) | what is proven on macOS, Linux and Windows, and what is not |
| [Tests](reference/tests.md) | `nu tests/run.nu`: the runner, writing a test, `lib.nu`, the isolation, the cost |
| **Modules** | |
| [nustro](reference/modules/nustro.md) | `status`, `doctor`, `repair`, `upgrade`, `edit`, `set`, `knobs`, `module`, `deps`, `plugins`, `completion`, `harness`, `startup-time`; the plumbing under `bootstrap` |
| [nu-complete](reference/modules/nu-complete.md) | the engine behind Tab: `run`, `external`, `smart`, `quote`, `cache`, `status` |
| [terminal](reference/modules/terminal.md) | `terminal`, `terminal theme`, `terminal font`, `terminal prompt` — every command, with costs; the Ghostty and WezTerm backends by file |
| [agent](reference/modules/agent.md) | `ask`, `exec`, `skill`, `command`, `completion`; the exec menu; the knobs |
| [odata](reference/modules/odata.md) | every command and flag, the query-option table, completion, knobs, testing |
| [worktree](reference/modules/worktree.md) | `init`, `add`, `remove`, `apply`, `discard`, `which`; the profile format and its hooks; the rules apply keeps |
| **Claude Code plugins** | |
| [nushell](../harness/claude-code/nushell/README.md) | the `nushell` skill — the language, the config, Nustro when it is the shell — and `nu --lsp` as the session's language server for `.nu` files; install with `claude plugin install nushell@nustro` |
| [worktree](../harness/claude-code/worktree/README.md) | `/worktree:worktree`, `/worktree:doctor`, the two hooks; install with `claude plugin install worktree@nustro` |

## Cookbook

| | |
|---|---|
| [Add Tab completion for a tool](cookbook/add-completion.md) | `agent completion <tool>`, or a spec by hand — `starship` worked through |
| [Override a shipped completion](cookbook/override-completion.md) | copy it into your `completions/`; everything shadows by name |
| [Write an autoload drop-in](cookbook/autoload.md) | an alias, a hook, a keybinding, a secret — and when it is `settings.nu` instead |
| [Your directory](cookbook/user-directory.md) | what is there and whose, switching an example on, getting a README back, the knobs an upgrade added |
| [Pick a theme and make it stick](cookbook/theme.md) | the picker, a palette of your own from six colours, keeping it after a `git pull` |
| [Shape the prompt](cookbook/prompt.md) | `terminal prompt`: pick a style, segments left, right or off, no icons, a transient prompt — and back |
| [Pin a font](cookbook/font.md) | `terminal font use`, and installing one by hand on Linux and Windows |
| [Enable a module, make it lazy, see what it costs](cookbook/modules.md) | `module enable`, `MODULES_LAZY`, `startup-time`, `loaded-files` |
| [Debug Tab](cookbook/debug-tab.md) | `nustro completion explain`, `commandline complete --detailed`, `nu-complete smart`, the error the `try` hides |
| [Test a change to the distro before it is live](cookbook/test-a-change.md) | `nu-check`, `doctor`, `module lint`, a scratch `config.nu` for a second checkout |
| [Run on Linux and Windows](cookbook/other-platforms.md) | what is the same, what is different, what has not been run |
| [Undo the whole thing](cookbook/uninstall.md) | `terminal reset`, `rm config.nu`, the checkout; what is yours and stays |

## Writing a page

A concept page explains a mechanism and the decisions someone would
otherwise re-litigate, with the numbers that decided them. A reference page
follows `templates/module-doc.md`: what it is, every command, configuration,
dependencies, measured costs, files, limits. A cookbook page is one task,
run once as written before it is committed, ending with what was seen. A
measured number moves with its subject and never loses its date. A word
used in a fixed sense is in the [glossary](reference/glossary.md), pointing
at the page that defines it; a new one goes there too.
