# Completion: how Tab works here, and how to teach it a new tool

Verified against Nushell 0.115.1 on 2026-09-10, and against 0.116.0 — the
completer inputs this page is now written for, and which the distro requires —
on 2026-09-27. Every cost below was measured with `timeit` or `hyperfine` on
this machine, on the release it names; nothing is estimated.

## Why not just carapace

Carapace covers ~1000 CLIs and stays as the fallback, but it asks the tool
each time: `brew install <Tab>` took **1.6 s** (it runs Ruby), `git checkout`
60 ms. The data those tools need is already on disk; reading it takes
milliseconds. And carapace, like Nushell's own completer, sees one command at
a time, so it can never know that `ls | where <Tab>` should offer `name`,
`type`, `size`, `modified`.

## Three layers

```
Tab
 └─ smart_menu ── source: nu-complete smart <buffer-up-to-cursor> <cursor>   (modules/nu-complete/smart.nu)
      ├─ 1. commandline complete --detailed          Nushell's own answer, 0.1-0.6 ms
      │      ├─ built-ins, flags, cell paths of known values, files
      │      ├─ @complete externs: brew, git ...     (completions/*.nu, via engine.nu)
      │      │     └─ fallback: external              carapace, for what the spec does not know
      │      └─ carapace for every other external
      └─ 2. rewrite that answer with what only the whole line reveals
             columns / operators / values, no files after `ps`, no duplicates
```

**Layer 1 — Nushell.** Unchanged. It still does most of the work and is what
`nu --ide-complete` and the LSP use.

**Layer 2 — specs for tools** (`modules/nu-complete/engine.nu`). Nushell 0.115
added the command-wide completer attribute: `@complete "name"` before an
`extern` hands `name` the whole argument list. Since 0.116 that list is
`place.command` (command name, every argument, the partial token), resolved
at the cursor — after a pipe, inside a closure, with an alias expanded — and
`nu-complete run <spec> $place.command` walks it through a spec —
subcommands, flags with values, positionals, rest — and asks the right
*source* for candidates. Sources read the tool's own files or run one cheap
command, and cache through `nu-complete cache`. Specs work everywhere Nushell
completes, including editors.

**Layer 3 — the smart menu** (`modules/nu-complete/smart.nu`). Nushell
completes `ls | get ⌶` without knowing what `ls` returns, and the built-ins'
slots are Nushell's, not ours to attach a completer to. A custom Reedline
menu's `source` is the one place that sees both the line and Nushell's answer
for it. The source starts from `commandline complete --detailed` — records
with value, span, description, style, kind — reads the slot from `place`
(its shape, whether it is a flag's value, where the token starts; right
inside closures and subexpressions too, `echo (first ⌶`), and rewrites:

| Situation | What you get | How |
|---|---|---|
| `ls \| where ⌶`, `get`, `select`, `sort-by`, `update`, `str trim` … (any cell-path or condition slot; 78 built-ins) | columns, typed, with a sample: `size  filesize · 6.5 kB` | the pipeline before the command runs in a subprocess, `describe --detailed` |
| `open x.json \| get package.⌶`, `each {\|r\| $r.⌶}`, `where $it.⌶` | nested columns | same, with `get package` appended |
| `ls \| where size ⌶` | only operators valid for a filesize | Nushell's operator list, narrowed by the column's type |
| `ls \| where type == ⌶` | `file`, `dir` | distinct values of the column, as Nushell literals |
| `where … and ⌶` | columns again | |
| `ls \| where size > ⌶`, `where modified > ⌶` | round bounds — `1kb` … `1gb`, `((date now) - 1day)` — instead of sixty file sizes | after `<` `<=` `>` `>=` on a filesize, duration or datetime; `==` still offers the values |
| `$rows \| where ⌶`, `$cfg \| get a.⌶` | the columns of a variable of this session | `scope variables` at the door of the source (56 µs), the value handed to the subprocess as NUON on stdin — the first 200 rows of a list, nothing above 256 kB |
| `ls \| uniq-by ⌶`, `histogram ⌶`, `compact ⌶`, `move name --after ⌶`, `join $t ⌶` | columns, though the slot is declared `string` or `any` | two short lists in `smart.nu`: `COLUMN_POSITIONALS`, `COLUMN_FLAGS` |
| `ps ⌶`, `version ⌶` (216 built-ins take no positional) | nothing, instead of every file in the directory | `place` has no shape: the command has no positional there |
| `first ⌶`, `skip ⌶`, `echo (first ⌶` | nothing, instead of files | `place.shape` wants a number |
| `cd ⌶` in a folder with no subfolders, `cd nus⌶` with no local match | `..`, `~`, `-`, then zoxide's most-used directories (`~/.config/nushell` …) | `place.shape` is `directory` and Nushell found none; `zoxide query -l`, 12 ms, memoised 30 s |
| a shadowed built-in | listed once | `uniq-by value` |
| `theme use Cat⌶` → `"Catppuccin Macchiato"` | a value with a space is one argument | `nu-complete quote`: a `string@completer` value is inserted verbatim by Nushell (both releases, both menus), so the engine quotes what the parser would split, `to nuon` style, and matching still works past the quote. Paths (backticks, Nushell's) and carapace's values (its own `"…"`) arrive quoted already |
| `ll \| where ⌶` | works | aliases are expanded before the pipeline runs |
| `fon⌶`, `font use ⌶`, `theme use Cat⌶` in a shell that has not loaded the lazy `terminal` module yet | `font list`, the fonts, the themes — what the loaded module would offer | the segment's head is a trigger word of a lazy module not in `$env.NU_MODULES_LOADED` ([Modules](modules.md#lazy-loading)), so the word itself comes from the list of trigger words, and what follows it from a child `nu -n` that sources that module's `load.nu` and answers `commandline complete` — once per slot, kept a minute and narrowed here as you type (140 ms for the first `theme ⌶` in a pty, 12-17 ms a key after), until the first Enter loads the module for good |
| everything else | exactly Nushell's answer | |

### Running the pipeline: what is allowed

Column and value completion need the pipeline's output, so `ls | sort-by
size -r` is executed — in a subprocess (`nu -n -c`, **20 ms**, memoised in
`stor` for 45 s per directory and line) and only when `safe-to-eval` says
yes. It tokenises the prefix with `ast --flatten` (0.5 ms, lists calls
inside closures too) and requires every call to be a built-in in a read-only
category (filters, strings, conversions, math, date, path, formats …) or on a
short allow-list (`ps`, `sys *`, `ls`, `open`, `glob`, `du`, `which`,
`version`, `history`, `each`, `do`, `if` …). Any external, any redirection,
any garbage token, and an explicit never-list (`rm`, `save`, `into sqlite`,
`stor export`, `input`, `sleep`, `source`, `use`, `job spawn` …) refuse. The
knob (shipped in `defaults.nu`, overridden in your `settings.nu`):

```nu
$env.NU_COMPLETE_EVAL = "safe"   # built-ins only (default)
                       "all"    # your own commands too, via `nu -l -c` (~80 ms)
                       "off"    # never run anything; Tab still filters and dedupes
```

When the pipeline yields no rows right now (`where` matched nothing), the
columns come from the pipeline without its last stage.

A command whose columns are known without running it can register a
*provider* instead: `$env.NU_COMPLETE_PROVIDERS = { odata: {|segment| …} }`
(`modules/odata`, in its `activate`). `probe` hands the provider the first segment and expects
the same `[{ columns: { name: { type, value, detailed_type, description? } } }]`
rows `describe --detailed` would give — several rows when a column has a
fixed set of values (enum members), a `description` when words beat a
sample. Memoised 30 s per prefix. `odata People | where ⌶` answers in
3-4 ms from the cached `$metadata`, with no request ([OData](odata.md)).

### Costs

| Tab on | first time | again |
|---|---|---|
| `ls \| where ` | 38 ms (subprocess), the very first Tab of a shell included | 3.4 ms |
| `ps \| where ` | 150 ms (`ps` itself is slow) | 2 ms |
| `brew install rip` (200 candidates at most) | 10 ms (after a one-off 0.7 s cache build, in the background) | 10 ms |
| `brew install rgrep` (fuzzy: 6 candidates, ripgrep first) | 12 ms | |
| `brew install "silver sea` (matched in descriptions, as a phrase) | 11 ms | |
| `brew uninstall ` (155 installed, versions read from the Cellar) | 42 ms | 7 ms for ten seconds |
| `docker run --n` (carapace: one process per slot, the answer narrowed here) | 41 ms | 1.4 ms |
| `git ` | 32 ms (`git help -a`) | 4 ms |
| `git checkout ` | 15-220 ms (`git status`, repo size) | 5 ms |
| `git log --one` | 98 ms (carapace) | 7 ms |
| `cargo ` | 28 ms (`cargo --list`) | 4 ms |
| `cargo build -p ` (workspace members, targets, features) | 31-64 ms (`cargo metadata --no-deps` + `cargo build --help`) | 6 ms |
| `cargo add ser` (1.5k crate names from the registry cache) | 80 ms, then memoised for a day | 18 ms |
| `cargo update ` (562 lockfile packages) | 32 ms | 6 ms |
| `theme ` before the lazy module is loaded (a child nu sources it) | 140 ms, once per slot | 12-17 ms a key |

Measured 2026-10-01 with `commandline complete` in a `nu -l -c`, unless a
pty is named.

**What a key costs.** The menu source runs again on every keystroke while
the menu is open, and it runs on the line editor's own thread: a completer
attached with `@complete`, a parameter completer and the external completer
have run on a background worker since 0.115, a menu `source` does not. With
a 700 ms source in a pty, a key typed 100 ms after Tab echoed after 1.4 s;
with the same 700 ms in an `@complete` completer on the stock menu, after
105 ms. So what the source costs is how long a typed character takes to
appear, and a `Tab` chain cannot hand the cheap slots to the stock menu: an
`until` whose first menu's source answers `[]` or `null` does not fall
through to the next (0.116.0, tried 2026-10-01). Everything is therefore
memoised, per slot rather than per keystroke where an external is behind it.
In a pty, with the menu open (before → after 2026-10-01):

| typing | a key |
|---|---|
| `git checkout m…` | 12-25 ms → 10-20 ms |
| `ls \| where s…` | 23 ms → 9-13 ms |
| `docker run --n…` (carapace) | 70-76 ms → 3-10 ms |
| `brew install r…` | 80 ms → 15-29 ms |
| `theme u…`, module not loaded | 30 ms and a child `nu` → 12-17 ms |

`tests/pty/menu.test.nu` holds two of these as bounds. Nushell's own way out
would be the external completer answering for built-ins too
([nushell#18931](https://github.com/nushell/nushell/pull/18931), open): the
columns could then come from a completer on the worker and the menu source
could go.

`nu-complete explain "<line>"` says which of the rules above answered a
line, what it offered, whether its pipeline was allowed to run, and what the
first and the next call cost.

### Filtering

Nushell does not filter what a command-wide completer returns, so the engine
filters a spec's candidates itself, by `$env.config.completions.algorithm`
and `case_sensitive` — `fuzzy` in [defaults.nu](../reference/knobs.md) — and
ranks them in tiers, best first:

1. the value starts with what is typed;
2. it contains it;
3. its letters appear in that order (`fuzzy` only; among these the shortest
   value wins, so `rgrep` is ripgrep before frege-repl);
4. only the description matches, contains before letters in order —
   `brew install "silver sea` finds ripgrep, `brew install --cask "terminal
   emu` the terminals. A quote opened to type a space is not part of what is
   matched; the candidate replaces the whole token.

Descriptions count under `substring` and `fuzzy`, never under `prefix`.
Within a tier the source's order is kept (`sort-by` is stable), which is what
keeps `git checkout` branches by recency. The pass is written column-wise —
`str starts-with` over a list of 2000 strings takes 0.2 ms, the same test in
a per-item closure 9 ms — and costs 4 ms (`prefix`), 9 ms (`substring`) or
15 ms (`fuzzy`) over 2000 candidates with descriptions (measured 2026-09-20).
A source with more candidates than that pre-ranks the same way where it
lives: brew's SQLite query orders by the same tiers before its `limit 200`.

Nushell ranks its own candidates (commands, flags, paths) by match quality
under `fuzzy`; that part is not the engine's.

## Tools with a spec

| Tool | Module | Subcommands and flags | Positionals and flag values | Left to carapace |
|---|---|---|---|---|
| brew | `completions/brew.nu` | Homebrew's zsh completion, parsed once to JSON — nested ones too (`services`, `bundle`, `analytics`…), their aliases hidden | formulae and casks with descriptions (SQLite from the API cache), installed, services, taps, commands (`help`) | nothing it knows better |
| git | `completions/git.nu` | `git help -a`, `git <cmd> -h` | refs by recency, changed files, remotes, stashes | config keys, rev ranges, uncommon flags |
| cargo | `completions/cargo.nu` | `cargo --list` (aliases too), `cargo <cmd> --help` parsed lazily, nested `Commands:` (report, nextest …) | `-p`/`--bin`/`--example`/`--test`/`--bench`/`-F` from `cargo metadata --no-deps`, `--profile` from Cargo.toml, `--target` from rustup, `add`/`install` crate names from the registry cache, `remove` deps, `update`/`tree -i` lockfile, `uninstall` from `.crates.toml`, `+toolchain` | `--config`, `test <name>` (offers nothing), anything else undefined |

## Teaching it a tool

Each tool is a spec in `completions/<tool>.nu` — subcommands, flags with
their values, positionals, and a `sources` record naming where each list comes
from. The format and the rules a spec has to meet are in
[Completion specs](../reference/completion-spec.md); building one, by hand or
with `agent completion <tool>`, is
[Add Tab completion for a tool](../cookbook/add-completion.md). Everything a
completer can be asked and every way to watch it answer headless is in
[Debug Tab](../cookbook/debug-tab.md).

## The completer inputs

Nushell 0.116 ([#18791](https://github.com/nushell/nushell/pull/18791),
[#19054](https://github.com/nushell/nushell/pull/19054),
[#19085](https://github.com/nushell/nushell/pull/19085)) hands every
completer — per-argument, `@complete`, the external closure and a menu
`source` — one record whose fields bind to the parameters it **names**:
`token` (`{text, kind, span}`), `place` (`{cursor, target, kind, index?,
flag?, shape?, command}`) and `buffer`, the line up to the cursor. The distro
requires it; the 0.115 shapes still work there, with a deprecation warning
printed once a session after the menu closes. Every slot in the distro is off
them:

| Where | Declares | Uses |
|---|---|---|
| `completions/*.nu` | `def complete-<tool> [place: record]` | `$place.command`, the span list the spec walks |
| `conf/completions.nu` | `source: {\|buffer, place\| nu-complete smart $buffer $place }` | the line, and the slot at the cursor |
| the generated `vendor/autoload/carapace.nu` | `{\|place\| do $carapace_legacy $place.command }`, appended by `nu-config tools setup`, because carapace 1.8.0 still generates `{\|spans\| …}` | `$place.command` |
| odata, `theme use`, `worktree -p` | `[place: record]`, `[buffer: string]`, `[token: record]` | the command, the whole line (`odata … \| expand ⌶`), the value being typed |

`commandline complete --input` returns the three inputs without running a
completer — the fastest way to see what a slot looks like:

```nu
nu -l -c '"git switch ma" | commandline complete --input'
# {token: {text: ma, kind: value, span: {start: 11, end: 13}},
#  place: {cursor: 13, target: {start: 11, end: 13}, kind: positional, index: 1,
#          shape: any, command: [git, switch, ma]},
#  buffer: "git switch ma"}
```

What 0.116 bought, and what it did not (measured 2026-09-27 on 0.116.0):

- **`place.command` replaced the engine's own rebuild of the span list** from
  the buffer (`ast --flatten`, the last command head before the cursor). It is
  right in more places — inside a closure or a subexpression, and with an
  alias at the head expanded, so `alias gco = git checkout` gets the git spec's
  branches. `nu-complete spans` survives as `$place.command` for completions
  generated before 2026-09-27.
- **`place` replaced the smart menu's own slot resolution** — which positional
  the cursor is on, skipping flags that take a value, and the shape the
  signature wants there. The table of every command's signature that used
  to do it (305 ms to build in a background job, and empty for a Tab pressed
  before it finished) is gone since 2026-10-01: `which` says what kind of
  command a word is, one `scope commands` inside the memoised probe gives the
  categories the safety check reads, and whether a command's first
  positional is a condition is asked once per command and session. A `where`
  condition is still read from the words: `place` hands it over as one word
  (`[where, "size > 10 and", ""]`), is `operator` after the column and
  `variable` while the column is being typed. `std/util structure` was tried
  for the words and left: it has no token for `;`.
- **Partial completion is back on.** The sourced-menu span bug
  ([nushell#19053](https://github.com/nushell/nushell/issues/19053)) is fixed
  in 0.116.0; `tests/pty/menu.test.nu` drives the insert and the Tab after it.
- `options.filter: true` still does **not** narrow a command-wide completer's
  output. `nu-complete filter` stays, and ranks in tiers Nushell does not.
- `fallback: true` in the returned envelope, and a `null` answer, still mean
  "and file completion"; the external completer is never consulted for a
  command that has a completer of its own. `nu-complete external` goes on
  calling carapace by hand — with the inputs its closure names, read from the
  closure's header (0.2 ms) — and the `answered` bookkeeping in `nu-complete
  run` stays with it.
- `$env.config.completions.persistent_menus` keeps the menu open while you
  edit; it works with the smart menu, and ships off, as in Nushell
  ([Knobs](../reference/knobs.md)).
- `@interactive` runs a completer on the line-editor thread with the
  terminal — and makes `commandline complete` refuse it anywhere else
  (`interactive_completer_needs_a_terminal`), which would end every headless
  check of that slot. Nothing here uses it.

## Known limits

- The first Tab on a pipeline pays its subprocess (38 ms for `ls`), and the
  first `ps | …` pays `ps` (150 ms).
- A variable named `$buffer` or `$place` is not seen: those are the names of
  the source's own inputs.
- Externals are never run for column completion, so `^git log | lines |
  where ⌶` gets no columns. `NU_COMPLETE_EVAL = "all"` widens to your own
  commands, not to externals.
- `git <cmd> -h` lists the common flags only; carapace fills the rest on a
  miss (`git log --one` → `--oneline`).
- The `--taps`/`--version` blocks of the zsh file are not subcommands and
  are skipped.
