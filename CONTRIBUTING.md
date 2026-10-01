# Contributing

This checkout is a live shell configuration. A user's `config.nu` sources
`distro.nu`, so an edit takes effect in the next terminal they open, and a
parse error breaks every new terminal — on whichever platform the change was
not written on. Everything below follows from that.

## Verify before you say it works

```nu
nu-check distro.nu                       # parse, following every `source` — the check that would break terminals
nu -l -c 'nu-config doctor'              # loads the config for real; every section ok
nu -n -c '<snippet>'                     # one snippet, no config at all
nu tests/run.nu [pattern]                # the suite; every shell it starts has a config directory of its own
```

`nu -c` deliberately loads no config, so it proves nothing about any of
this; `nu -l -c` does. `nu -n` has no `NU_LIB_DIRS`, so `nu-check` on a file
that imports a module reports `false` there for reasons unrelated to the
file — use `nu -l -c 'nu-check <file>'`. `nu-check distro.nu` never reaches a
lazy module, which a hook sources at runtime; `nu -l -c 'nu-config module
lint'` is the only check that does. Which check each kind of change needs,
and how to test a second clone without making it live, is
[Test a change](docs/cookbook/test-a-change.md).

CI (`.github/workflows/ci.yml`) runs on every push and pull request, on
macOS, Linux and Windows, with Nushell pinned at 0.116.0: the real installer
(`nu install.nu --defaults --skip-plugins --skip-terminal --skip-deps`), the layout is
`split`, `nu-check distro.nu`, `module lint`, `doctor`, the suite, no
override left behind by a default install, the scaffold's three examples
once renamed, and both bootstrap scripts parse. Neither Ghostty nor WezTerm
is on a runner, so the terminal side is proven only to the point of
"not installed" ([Platforms](docs/reference/platforms.md)).

## Where a thing goes

- **Values in `defaults.nu`, behaviour in `conf/`.** A setting is a leaf
  assignment (`$env.config.a.b = …`), never a whole record and never
  `$env.config = {…}`. A `conf/` file must never assign a value
  `defaults.nu` owns: it runs after the user's `settings.nu` and would
  silently overwrite it. One concern per `conf/` file; `distro.nu` only
  wires them in order ([Layout](docs/concepts/layout.md#values-versus-behaviour)).
- **Nothing a user owns is written inside the checkout.** State keys off
  `$nu.data-dir`, the user's config dir, never the distro.
- **Paths are parse-time constants derived from `$ROOT`** (`path self`).
  Never a hard-coded home directory.
- **Generated files live in the user's directory**, never here:
  `vendor/autoload/*.nu`, `plugin.msgpackz`, history, `autoload/*`. Change
  the generator (`modules/nu-config/tools.nu`), never a generated file. The
  same for the user directory's scaffold: edit `templates/user/` or
  `modules/nu-config/scaffold.nu`, never a rendered file, and test with
  `nu -l --config <scratch>/config.nu -c 'nu-config user init'`.
- **Optional tools are guarded with `which`.** `alias` and `extern` are
  parse-time and cannot sit inside an `if`.

## Modules

[Modules](docs/concepts/modules.md) is the contract; `nu-config module
lint` enforces it, and CI runs it. In short: `mod.nu` + `load.nu` +
`meta.nuon`, code only; wiring in `activate`, with `default` and never
assignment, so the user's `settings.nu` wins; knobs declared in `meta.nuon`,
not `defaults.nu`; the documentation is `docs/reference/modules/<name>.md`,
named by `docs:` in `meta.nuon` and shaped by `templates/module-doc.md`. A
module with a hard dependency is lazy and errors through `missing-tool`
(`modules/nu-config/missing.nu`) from its `meta.nuon` (`why`, `install`,
`then`). A lazy module is interactive-only: `pre_execution` does not fire
for `nu -c` or a script.

## Docs

One tree under `docs/`: `getting-started/`, `concepts/` (design records),
`reference/` (commands, knobs, files), `cookbook/` (one task per page).
[docs/README.md](docs/README.md) is the map and says what each kind of page
holds. No README in `modules/`, `themes/` or `completions/`. A cookbook page
is run as written before it is committed and ends with what was seen. A
word used in a fixed sense goes in the [glossary](docs/reference/glossary.md).

## Numbers

A number in a comment or a page is measured (`timeit`, `nu-config
startup-time`, `hyperfine`) and carries the date it was measured, never an
estimate. A measured number moves with its subject and keeps its date.
Comments explain why, not what.

## Nushell

Nushell makes breaking changes at minor versions; the distro is verified
against 0.116 and the pin is raised deliberately. `help <cmd>` and `config
nu --doc` on the installed binary beat memory and web snippets.

## Tests

`tests/<concern>.test.nu`, one `def "test <name>"` per case on `std assert`,
`use lib.nu *` for `scratch`, `user-dir`, `nu-l` and `skip-test`. A name
holds letters, digits, spaces and `._+/=:,-` only. Never name a helper after
a built-in (`complete`, `skip`): a file's defs shadow it inside every module
the file `use`s. Fixtures under `tests/fixtures/`; `tests/pty/` drives Tab
in a pseudo-terminal. Every shell a test starts runs against `user-dir`,
its own XDG directories under the run's scratch, never against yours.
[Tests](docs/reference/tests.md) is how to write one. Run `nu tests/run.nu`
before every commit.

## The odd corners

- **Completion** lives in `modules/nu-complete` and `completions/<tool>.nu`
  ([Completion](docs/concepts/completion.md)). Test it without a terminal:
  `nu -l -c '"brew install rip" | commandline complete --detailed'` for a
  spec, `nu -l -c '"ls | where " | commandline complete --input |
  nu-complete smart $in.buffer $in.place'` for the smart menu
  ([Debug Tab](docs/cookbook/debug-tab.md)). `nu --ide-complete` does not
  run `@complete` completers.
- **OData**: `where` cannot be overloaded, so a `pre_execution` hook plans
  the pushdown ([OData](docs/concepts/odata.md)). Test without real state:
  `nu -n` + `use modules/odata *` + `$env.ODATA_SERVICES = {…}`; the hook
  only in a pty.
- **Theme**: templates in `themes/` are written in roles, never hex;
  `themes/palettes/nvchad/` is generated by its `import.nu`, never edited.
  `theme resolve <name>` and `theme roles <name>` show a resolution without
  writing; `theme sync` re-renders after a template edit
  ([Theming](docs/concepts/theming.md)). The terminal registry in
  `modules/terminal/registry.nu` is data plus `match` verbs, never a table
  of closures (130 ms of eager startup, measured 2026-09-20).
