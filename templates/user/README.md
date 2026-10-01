# Your Nushell configuration

Nushell reads `config.nu` from this directory, and `config.nu` sources the
distro: a git checkout at `@DISTRO@` that you never edit — `nustro
upgrade` pulls it. Everything else here is either yours or state the shell
keeps for itself. [Layout](../../docs/concepts/layout.md) is the picture;
`nustro doctor` prints every path below as it is on this machine, and
`nustro` alone says what needs attention.

## What is here

| | whose | what |
|---|---|---|
| `config.nu` | the distro's | three lines: where the checkout is. `nu install.nu` wrote it |
| `settings.nu` | yours | every knob, commented out at its shipped value; uncomment a line to change it. [Your first setting](../../docs/getting-started/first-setting.md) |
| `autoload/` | yours | drop-ins Nushell loads last of all: an alias, a hook, a keybinding, a secret. `example.nu.off` is one; [autoload/README.md](autoload/README.md) |
| `completions/` | yours | one module per tool, for Tab. `hello.nu.off` completes a fictional `hello`; [completions/README.md](completions/README.md) |
| `themes/` | yours | palettes of your own, and a copy of any template you want to change. `palettes/example.nuon.off` is a palette; [themes/README.md](themes/README.md) |
| `modules/` | yours | modules of your own, `use`d from `settings.nu`; [modules/README.md](modules/README.md) |
| `plugins/` | yours | plugin binaries you built or downloaded, first on `NU_PLUGIN_DIRS`; [plugins/README.md](plugins/README.md) |
| `README.md`, one per directory | the distro's | this scaffold. Delete one and `nustro repair` writes it back; edit one and it is left alone |
| `history.sqlite3` | state | Nushell's history |
| `plugin.msgpackz` | state | the plugin registry — `nustro plugins add` after a Nushell upgrade |
| `vendor/autoload/` | state | init files for zoxide, atuin, carapace: `nustro repair` (re)writes them, installation is the switch |
| `.state/` | state | what the modules render or remember: the theme, the update check, agent sessions, the OData registry |

On macOS `vendor/` and `.state/` sit here, next to `config.nu`; on Linux
they are under `~/.local/share/nushell`, and `nustro doctor` says which.
Neither is yours to edit: a `terminal theme use` or a `nustro repair` rewrites
them.

## The examples

Each `*.off` file is complete and working, and inert only because of its
name: Nushell loads `*.nu` from `autoload/`, the palette reader `*.nuon`.
Rename one to switch it on, and read it — every line says why it is where it
is. `nustro bootstrap scaffold status` shows which scaffold files are as
written, which you have edited, and which are gone.

## Where a thing goes

| want to | do |
|---|---|
| change a setting | uncomment it in `settings.nu`, or `nustro set '<assignment>'`; `nustro knobs` lists them all |
| add an alias, a hook, a keybinding, a secret | a file in `autoload/` ([Write an autoload drop-in](../../docs/cookbook/autoload.md)) |
| teach Tab a tool | `agent completion <tool>`, or a spec by hand ([Add Tab completion for a tool](../../docs/cookbook/add-completion.md)) |
| change the theme | `terminal theme`; a palette of your own in `themes/palettes/` ([Pick a theme](../../docs/cookbook/theme.md)) |
| turn a shipped module off, or make one lazy | `nustro module disable <name>`, `MODULES_LAZY` in `settings.nu` ([Modules](../../docs/cookbook/modules.md)) |
| add a plugin | the binary into `plugins/`, `plugin add <name>`, restart ([Plugins](../../docs/concepts/plugins.md)) |
| see what is wrong, and put it right | `nustro` (or `nustro doctor`, the long form); `nustro repair` |
| undo the whole thing | [Undo the whole thing](../../docs/cookbook/uninstall.md) |
