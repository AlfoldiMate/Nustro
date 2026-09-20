# nushell plugin for Claude Code

Two skills and nothing that runs. `nushell` keeps a session in Nushell 0.115
rather than in bash: the language and its parse-time rules, structured data,
modules, plugins, completions, `$env.config`, hooks, keybindings, the
standard library, the built-in MCP server — and
[Nustro](https://github.com/AlfoldiMate/Nustro), the distro, when it is the
shell: the distro/user split, the rules that shape the files, the commands
it adds, how to verify a change. `nustro-completion-build` teaches Tab a
command-line tool: a `completions/<tool>.nu` for Nustro's completion engine,
built from the tool's own help and data and verified headless.

## Install

```
claude plugin marketplace add AlfoldiMate/Nustro
claude plugin install nushell@nustro
```

Nothing else is needed: the skills are prose and a few `nu` scripts, there
are no hooks and no commands. `nu` on PATH is what makes rule 5 (*test
snippets before delivering them*) possible, and a Nustro checkout is what
`nustro-completion-build` writes into.

## What it adds

| Piece | What it does |
|---|---|
| `nushell` skill | Loads on any Nushell task. Six operating rules, orientation commands, and twelve reference files read on demand: `language`, `data`, `config`, `modules`, `plugins`, `completions`, `interface`, `stdlib`, `gotchas`, `mcp`, `ecosystem`, `this-setup` (Nustro) |
| `nustro-completion-build` skill | `/nushell:nustro-completion-build <tool> [hint]`, or `agent completion <tool>` at a Nustro prompt, which runs it on a session of its own. Discovers where the tool's command surface can be read (its own generators, cobra `__complete`, fish/zsh files, `--help`), drafts a spec with the scripts in `scripts/` (`discover`, `help-tree`, `fish-spec`, `cobra-tree`), maps every positional to live data, wires the module and verifies each slot with `verify.nu` against carapace as the oracle. `references/` holds the source catalogue and the module template |

The two most reported failures of shell assistants are bash-in-Nushell and
invented commands; the skill's first rule is *verify against the running
binary* (`help <cmd>`, `config nu --doc`), and `references/gotchas.md`
carries the version drift a snippet found online usually hides.

## Where the files live

`harness/claude-code/nushell/skills/` is the one copy of both skills; the
checkout carries no `.claude/` of its own (that directory is gitignored, a
developer's own session config). A session in a checkout reaches the
skills through the installed plugin, and `agent completion` loads the
checkout's copy directly with `--plugin-dir`, so the build skill that runs
is the one beside the engine it targets. A change to a skill is a bump of
`version` here and `claude plugin update nushell@nustro` on each machine,
which `nu-config upgrade` runs.
