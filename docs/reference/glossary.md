# Glossary

The words these pages use in a fixed sense, one or two sentences each, with
the page that defines the thing. Alphabetical.

**bootstrap** — `nustro bootstrap …`: plumbing the installer, the startup
hooks and `repair` run — the scaffold, the tool init files, the update
check, where the two directories are. Not for every day; `nustro repair`
runs the steps in order ([nustro](modules/nustro.md#bootstrap)).

**drop-in** — a `*.nu` file in your `autoload/`, loaded by Nushell at the
end of startup, after the distro and the generated tool files, so it has
the last word. Behaviour goes there; a value the distro ships goes in
`settings.nu` ([Write an autoload drop-in](../cookbook/autoload.md)).

**external completer** — the completer Nushell consults for an external
command that has no completer of its own: carapace, called by hand from
`nu-complete external` with the inputs its closure names. Never consulted
for a command that has a spec ([Completion](../concepts/completion.md#why-not-just-carapace)).

**harness, marketplace, plugin (Claude Code)** — a harness is what runs an
agent; `harness/claude-code/` holds one Claude Code plugin per module, each
a client of the shell command (`nu -l -c "use worktree *; worktree …"`),
plus the `nushell` skill as a plugin of its own. The checkout is the
marketplace: `.claude-plugin/marketplace.json` at its root lists the
plugins, the install registers the path, and `git pull` is the marketplace
update ([Agent harnesses](../concepts/harness.md)). A *Nushell* plugin is a
different thing: a binary registered in `plugin.msgpackz`
([Plugins](../concepts/plugins.md)).

**knob** — a value the distro ships a default for: a line in `defaults.nu`,
or a module's `knobs:` in its `meta.nuon`. You change one by mentioning it
in your `settings.nu`; one you never mention keeps tracking the distro,
including a knob a later pull adds ([Knobs](knobs.md),
[Your first setting](../getting-started/first-setting.md)).

**layout: split, in-place, other** — what `nustro status` reports as
`layout` and `nustro doctor` on its `Layout` line. `split` is the target: the distro is a checkout and your
config directory is elsewhere. `in-place` means the checkout is still
doubling as the config directory (run `nu install.nu`); `other` means
something else is live ([Layout](../concepts/layout.md#where-a-thing-goes)).
Not the worktree layout, below.

**module: eager, lazy, trigger word** — a directory under `modules/` with
`mod.nu`, `load.nu` and `meta.nuon`, adding commands to the shell. An eager
module is sourced at parse time by `conf/modules.nu`; a lazy one
(`MODULES_LAZY`) is sourced by a `pre_execution` hook on the first line
that starts with its name or one of its trigger words (`MODULES_TRIGGERS`:
`expand` for `odata`, the only one — every `terminal` command starts with
`terminal`), so it costs a startup nothing and is interactive-only
([Modules](../concepts/modules.md#lazy-loading)).

**palette, role, tier** — a palette is a file in `themes/palettes/`
(thirty colours, NvChad's 96 and Catppuccin's four). A role is a name a
template asks for instead of a colour — `fg_muted`, `border`, `accent`,
`text_yellow`. The tier is which source decided a role: 1 *ansi* (every
role an ANSI name, what a shell has before its first `terminal theme use`), 2
*derived* (the sixteen as hex, shaded roles blended from them — every one
of Ghostty's 463), 3 *palette* (the shaded roles named exactly). `terminal
theme roles` shows which ([Theming](../concepts/theming.md#roles-and-the-three-tiers)).

**pin: `last_good`, `previous`, rollback** — what `nustro upgrade
status` records beside the fetch result: `last_good`, the HEAD `nustro
doctor` last saw parse; `previous`, the HEAD the last `upgrade` moved off;
`branch`, the branch a rollback detached from. `nustro upgrade rollback`
checks out `last_good`, else `previous`, else the commit you name, and
`upgrade` returns to the branch ([Updating](../getting-started/updating.md)).
The other pin is the Nushell version: 0.116, raised deliberately.

**place** — one of the three inputs Nushell 0.116 hands every completer
(`token`, `place`, `buffer`): the slot at the cursor — its kind, shape,
index, the flag it belongs to, and `command`, the argument list resolved at
the cursor with aliases expanded. Specs walk `$place.command`; the smart
menu reads the slot from it ([Completion](../concepts/completion.md#the-completer-inputs)).

**profile, worktree layout** — the `worktree` module's layout is a
container directory holding `.bare/` (the one real git dir), a `.git`
pointer file, `.profiles/` and one sibling directory per branch. A profile
is a directory under `.profiles/` whose files are placed, symlinked by
default, at the same relative path in every worktree; `dflt` is applied
first. This is a layout of a project, not of the config
([Worktrees](../concepts/worktree.md#the-layout)).

**pushdown** — the `odata` module's translation of the `where`, `select`,
`first`, `skip`, `sort-by` and `length` stages typed after an `odata` call
into `$filter`, `$select`, `$top` and the rest of one request, planned by a
`pre_execution` hook because `where` cannot be overloaded. Every pushed
stage still runs locally, so it can only shrink what is transferred
([OData](../concepts/odata.md)).

**repair** — `nustro repair` re-runs every wiring step in order (settings,
state, scaffold, tools, plugins, theme, completion, harness, parse) and
returns a row per step; it installs nothing and replaces nothing of yours.
`--hard` runs the installer again with every default, `--reset` runs it
from an empty directory after moving yours to `.backup/<stamp>/`
([nustro](modules/nustro.md#repair)).

**scaffold** — the files the installer writes into your directory once and
`nustro repair` (its `scaffold` step, `nustro bootstrap scaffold init`)
writes again when missing: a README per directory,
three `.off` examples and a `settings.nu` with every knob commented out.
The source is `templates/user/`, rendered by `modules/nustro/scaffold.nu`
([Your directory](../cookbook/user-directory.md), [Files](files.md)).

**smart menu, smart Tab** — the third completion layer: a Reedline menu
whose source is `nu-complete smart`, which starts from Nushell's own answer
for the line and rewrites it with what only the whole line reveals —
pipeline columns with a sample value, operators narrowed by type, no files
after `ps`. `const SMART_TAB = false` is Nushell's stock menu
([Completion](../concepts/completion.md#three-layers)).

**spec** — a module in `completions/<tool>.nu` that teaches Tab one tool:
its subcommands, flags with values, positionals, and a `sources` record
naming where each list comes from, run by `modules/nu-complete/engine.nu`
([Completion specs](completion-spec.md)).

**the two directories** — your config directory (`config.nu`,
`settings.nu`, `autoload/`, your completions, themes, modules, plugins, and
every file Nushell writes) and the distro (the checkout: `distro.nu`,
`defaults.nu`, `conf/`, `modules/`). Nushell knows only the first; its
three-line `config.nu` sources the second ([Layout](../concepts/layout.md)).

**value, behaviour** — the rule for where a thing goes. A value is a knob:
`defaults.nu` ships it, your `settings.nu` overrides it. Behaviour is a
hook, a menu, a keybinding, an alias, a `def`: `conf/` ships it, your
`autoload/` adds to it. A `conf/` file never assigns a value `defaults.nu`
owns, because it runs after `settings.nu` and would silently overwrite
yours ([Layout](../concepts/layout.md#values-versus-behaviour)).
