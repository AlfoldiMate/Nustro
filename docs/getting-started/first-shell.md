# Your first shell

Open a new terminal. If you let the installer make Nushell what a Ghostty
window starts, that is a Nushell prompt; otherwise type `nu`.

## Check it

```nu
nustro            # = nustro status
nustro doctor
```

`nustro` alone is one record: the distro's version and commit, whether the
checkout is behind, the layout, the modules, the theme, and `attention` — a
row for each thing that is off, with the command that settles it. An empty
`attention` is a healthy setup. `nustro doctor` is the long form: both roots (the checkout and your directory) and the layout state
— `split` is the target; `in-place` means the checkout is still doubling as
the config directory, run `nu install.nu` — then every derived path, a parse
check of everything the distro sources, the tools it found, the theme that is
rendered, the plugins, the completion caches, every module with its state and
cost, and the startup time. Anything wrong is marked and says what to run —
for most of it that is `nustro repair`, which re-runs every wiring step (the
scaffold, tool init files, plugins, the theme's render) and replaces nothing
of yours.

The first thing to know about this shell is that there are two directories
and you only ever edit one of them:

```
YOUR config directory                     THE DISTRO (a git checkout)
  config.nu        3 lines, points here ──▶  distro.nu     entrypoint
  settings.nu      every knob, commented     defaults.nu   every knob, shipped value
  autoload/*.nu    drop-ins, loaded last     conf/  modules/  completions/  themes/
```

`nustro edit` opens yours; its `README.md` says what every file
there is, and each directory has one of its own. The checkout is read-only
to you; `git pull` updates it without touching your files
([Layout](../concepts/layout.md)).

## What is on the keys

| key | does |
|---|---|
| Tab | the completion menu — pipeline-aware: `ls \| where <Tab>` offers columns with a sample value, `brew install <Tab>` every formula in 3 ms, `git checkout <Tab>` branches by recency ([Completion](../concepts/completion.md)) |
| Ctrl+R | atuin's history search, or Nushell's history menu when atuin is absent |
| F1 | the help menu |
| → | accept the inline history hint |
| Ctrl+O | edit the line in `$EDITOR` |
| Ctrl+W | macOS: accept the next word of the inline history hint, or with no hint jump forward over a word — Reedline's Ctrl+Right, which macOS keeps for Mission Control. Deleting the word, which is what Ctrl+W does elsewhere, is Reedline's Ctrl+Backspace (and Alt+Backspace in emacs mode) |
| Alt+E | with the `agent` module: the line you are typing is a task, Claude's proposal replaces it |
| Esc / `i` | vi mode: the cursor is a line while inserting, a block in normal mode. `$env.config.edit_mode = "emacs"` in `settings.nu` if you would rather not |

## What the shell adds

| command | |
|---|---|
| `nustro` | `status`, `doctor`, `repair`, `upgrade`, `edit`, `set`, `knobs`, `module`, `deps`, `plugins`, `completion`, `harness`, `startup-time` — the distro's own command ([reference](../reference/modules/nustro.md)) |
| `terminal` | the terminal you are in — Ghostty or WezTerm: its palette (`terminal theme`), its font (`terminal font`), its config (`terminal status`, `terminal shell`) ([reference](../reference/modules/terminal.md)) |
| `agent` | Claude Code at the prompt: `ask`, `exec`, `skill`, `command`, `completion` ([reference](../reference/modules/agent.md)) |
| `odata` | OData V2/V4 services as tables, with `where`/`select`/`first` run on the server ([reference](../reference/modules/odata.md)) |
| `worktree` | a bare repository with a directory per branch, the gitignored files each checkout needs placed from profiles ([reference](../reference/modules/worktree.md)) |
| `nu-complete` | the engine behind Tab, and the API a completion spec calls; what you type is `nustro completion explain \| status \| clear` ([reference](../reference/modules/nu-complete.md)) |

`terminal`, `agent`, `odata` and `worktree` are lazy: not parsed at startup,
loaded on the first line that starts with the module's word — or, for
`odata`, with its one trigger word, `expand` (39 ms, 18 ms, 97 ms and 10 ms, once — each
module's `meta.nuon`, `terminal` measured 2026-09-20). That is why
startup is 84 ms on an M-series Mac against 47 ms for Nushell with no config
at all, and also why a lazy module is interactive-only — a script has to `use
odata *` itself ([Startup](../concepts/startup.md)).

## One line at the top, sometimes

```
distro: 2 commits behind origin/main · A new Ghostty window starts Nushell — nustro upgrade
```

Once a day a shell runs `git fetch` in the checkout as a background job, and
the next shell to start prints that line when there is something to pull.
[Updating](updating.md) says what to do with it.

Next: [Your first setting](first-setting.md).
