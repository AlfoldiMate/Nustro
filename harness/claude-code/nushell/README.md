# nushell plugin for Claude Code

One skill, `nushell`, that keeps a session in Nushell 0.115 rather than in
bash: the language and its parse-time rules, structured data, modules,
plugins, completions, `$env.config`, hooks, keybindings, the standard
library, the built-in MCP server — and
[Nustro](https://github.com/AlfoldiMate/Nustro), the distro, when it is the
shell: the distro/user split, the rules that shape the files, the commands
it adds, how to verify a change.

## Install

```
claude plugin marketplace add AlfoldiMate/Nustro
claude plugin install nushell@nustro
```

Nothing else is needed: the skill is prose, there are no hooks and no
commands. `nu` on PATH is what makes rule 5 (*test snippets before
delivering them*) possible.

## What it adds

| Piece | What it does |
|---|---|
| `nushell` skill | Loads on any Nushell task. Six operating rules, orientation commands, and twelve reference files read on demand: `language`, `data`, `config`, `modules`, `plugins`, `completions`, `interface`, `stdlib`, `gotchas`, `mcp`, `ecosystem`, `this-setup` (Nustro) |

The two most reported failures of shell assistants are bash-in-Nushell and
invented commands; the skill's first rule is *verify against the running
binary* (`help <cmd>`, `config nu --doc`), and `references/gotchas.md`
carries the version drift a snippet found online usually hides.

## Where the file lives

`harness/claude-code/nushell/skills/nushell/` is the one copy. The
distro's own `.claude/skills/nushell` is a symlink to it, so a session in a
checkout of Nustro has the skill as a project skill — Claude Code follows
the link — and the plugin ships the same text without a second copy. A
change to the skill is a bump of `version` here and `claude plugin update
nushell@nustro` on each machine, which `nu-config upgrade` runs.
