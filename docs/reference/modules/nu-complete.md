# nu-complete

The completion engine behind Tab: pipeline-aware, spec-driven, and quiet where
Nushell's own completer has nothing useful to say.

```nu
ls | where <Tab>          # name, type, size, modified — typed, with a sample value
brew install <Tab>        # 16,340 formulae and casks with descriptions, in 3 ms
git checkout <Tab>        # branches by recency, then remotes and tags
```

## Commands

| Command | Does |
|---|---|
| `nu-complete run <spec> <spans>` | positional completion for an extern, from a spec (`engine.nu`) |
| `nu-complete external <spans>` | what the external completer (carapace) says for a span list, called with the inputs its closure names (`engine.nu`) |
| `nu-complete spans <token> <place> <buffer>` | `$place.command`: kept for completions generated before Nushell 0.116 was required (`engine.nu`) |
| `nu-complete smart <buffer> <place>` | the Tab menu source: the one place that sees both the line and Nushell's answer for it (`smart.nu`) |
| `nu-complete quote` | quote a candidate the line would otherwise split (`Catppuccin Macchiato` → `"Catppuccin Macchiato"`); `run` and `smart` apply it to spec and `string@completer` values, never to commands, flags or paths (`engine.nu`) |
| `nu-complete cache <key> <ttl> {}` | memoise a slow source for the session (`cache.nu`) |
| `nu-complete status` | what is cached, and where — typed as `nustro completion status` |
| `nu-complete cache clear` | forget the session's memoised answers — typed as `nustro completion clear` |
| `nu-complete explain <line>` | typed as `nustro completion explain`: which rule answered a line (`columns`, `operators`, `values`, `no-files`, `directories`, `field`, `lazy`, or `nushell` for its own answer), the first candidates, whether the pipeline before the command was allowed to run, and what Nushell's answer, the first call and the next call cost |
| `nu-complete activate` | seed defaults |

## Configuration

| Knob | Default | Meaning |
|---|---|---|
| `NU_COMPLETE_EVAL` | `safe` | run the typed pipeline in a subprocess to offer real columns: `safe` (read-only built-ins only), `all`, `off` |

`SMART_TAB` in `defaults.nu` chooses between this engine's Tab menu and
Nushell's stock one. The menu's look and its keybinding are configuration, so
they live in `conf/completions.nu` rather than here.

## Dependencies

`carapace` is soft: it answers any slot a spec has no opinion on
(`fallback: "external"`). Without it those slots fall back to Nushell's own
knowledge and then to file paths.

## Design

Three layers, in the order they answer:

1. Nushell's own completer — built-ins, flags, cell paths, files.
2. `@complete` externs with a spec per tool in `completions/`.
3. The Tab menu source `nu-complete smart`, which sees the whole buffer and so
   can offer columns, operators and values for `where`/`get`/`select`, suppress
   file noise after commands that take no argument, and deduplicate.

A custom menu is the only kind whose `source` closure receives the buffer — a
`source` on the stock `completion_menu` is ignored (0.115.1, and the rebinding
is what 0.116.0 runs) — which is why Tab
is rebound rather than configured.

[Completion](../../concepts/completion.md) has the full design;
[Completion specs](../completion-spec.md) is the contract for a tool spec.

## Measured

Eager by design: it owns the Tab menu, which has to answer on the first
keystroke of the first line, so it cannot be lazy. 2 ms to load — the specs it
runs are parsed by `conf/completions.nu` and are not part of that. Nothing
is built at startup: the table of command signatures a background job used
to fill (305 ms) went on 2026-10-01, when `place.shape` and `which` had made
it unnecessary.

## Files

```
mod.nu       re-exports engine, cache and smart; `nu-complete activate`
engine.nu    the spec runner
cache.nu     three cache tiers: stor memo, cache-dir files, staleness
smart.nu     the Tab menu source
load.nu      `use nu-complete *` + activate
meta.nuon    description, dependencies, knobs
```

## Tests

`nu tests/run.nu completion` — four files under `tests/completion/`, 77
tests (2026-10-01, Nushell 0.116.0): `engine` (the `place.command` contract
the specs walk, `external`, filter, quote, `run` over an inline spec),
`smart` (columns, operators, values and bounds, the no-files rules, the eval
gating with a `save` that must not run, a session's variables, the slots
that take a column undeclared, a lazy module's words and slots, `explain`),
`specs` (brew against `tests/fixtures/brew`, its package database capped at
two hundred, `brew provides`; git and cargo against a scratch repository and
workspace) and `cost` (the
numbers above as upper bounds, ten to twenty times the measurement).
`nu tests/run.nu pty` drives Tab in a real pseudo-terminal
(`tests/pty/menu.test.nu`): the menu completing and inserting under the
shipped defaults, partial completion under prefix matching, where the
insert nushell#19053 broke has a common prefix to make, and what a key
typed with the menu open costs, read from a log the session's menu source
writes.
[Tests](../tests.md) is how to add one.

## Limits

`nu --ide-complete` does not run `@complete` completers, so it proves nothing;
use `commandline complete --detailed`. `nu -l -c` does not load the vendor
autoload dir, where carapace is wired, so the external fallback looks empty
headless even when it works in the REPL.

Nushell 0.116 hands every completer — a spec's, a menu source, the external
one — one record bound by the names it declares (`token`, `place`,
`buffer`); the distro requires it
([Completion](../../concepts/completion.md#the-completer-inputs)).
