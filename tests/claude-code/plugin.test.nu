# The Claude Code marketplace in .claude-plugin/ and the plugins under
# harness/claude-code/: the manifests agree with each other and with the
# module tree, every hook a plugin declares exists and parses, the worktree
# plugin's two hooks answer a real layout the way a session would see them
# (deny, context, silence), and `claude plugin validate` passes when claude
# is on the machine. `nu-config harness status` reads the same manifest.
use lib.nu *
use std/assert
use worktree *

const MARKETPLACE = $ROOT | path join .claude-plugin marketplace.json
const PLUGIN = $ROOT | path join harness claude-code worktree
const HOOKS = $PLUGIN | path join hooks

# A hook run the way Claude Code runs it: `nu -n --stdin <script>` with the
# JSON payload on stdin. Returns stdout; a hook never fails, so the exit code
# is asserted here rather than returned.
def hook [script: string, payload: record]: nothing -> string {
  let r = $payload | to json -r | ^$nu.current-exe -n --stdin ($HOOKS | path join $script) | complete
  assert equal $r.exit_code 0 $"($script): ($r.stderr)"
  $r.stdout
}

# git with an identity of the test's own, so a commit never asks for one.
def --wrapped git-in [dir: string, ...args: string]: nothing -> string {
  let r = ^git -C $dir -c user.name=test -c user.email=test@test -c init.defaultBranch=main -c commit.gpgsign=false ...$args | complete
  if $r.exit_code != 0 { error make -u { msg: $"git ($args | str join ' '): ($r.stderr)" } }
  $r.stdout | str trim
}

# A layout with a committed `main` worktree and a `ci` profile. Returns the root.
def layout []: nothing -> string {
  let root = scratch
  cd $root
  worktree init
  worktree add main
  "hi\n" | save ($root | path join main README.md)
  git-in ($root | path join main) add . | ignore
  git-in ($root | path join main) commit -qm init | ignore
  mkdir ($root | path join .profiles ci)
  $root
}

def "test the marketplace lists plugins that exist, each named after its module or without hooks" [] {
  let m = open $MARKETPLACE
  assert equal $m.name "nustro"
  assert ($m.plugins | is-not-empty)
  for p in $m.plugins {
    let dir = $ROOT | path join $p.source
    assert equal ($dir | path type) dir $"($p.name): ($p.source)"
    let manifest = open ($dir | path join .claude-plugin plugin.json)
    assert equal $manifest.name $p.name "plugin.json and marketplace.json agree on the name"
    # A plugin that is not a module's client (the nushell skill) is prose only:
    # a hook runs in every session, and only a module's user has asked for one.
    if ($ROOT | path join modules $p.name | path type) != "dir" {
      assert not ($dir | path join hooks | path exists) $"($p.name) has no module, so it may not have hooks"
    }
    assert ($dir | path join README.md | path exists) $"($p.name) ships a README"
  }
}

def "test the nushell plugin ships the one copy of the skill, linked from .claude/skills" [] {
  let shipped = $ROOT | path join harness claude-code nushell skills nushell
  assert equal ($shipped | path join SKILL.md | path type) file
  # Git checks the link out as a file holding its target on Windows (no
  # core.symlinks there); the skill is still one copy, only the link is not one.
  let link = $ROOT | path join .claude skills nushell
  if $nu.os-info.name != "windows" {
    assert equal ($link | path type) symlink $"($link) is not a symlink"
    assert equal ($link | path expand) ($shipped | path expand)
  }
  # this-setup.md is the distro's, not one machine's: no home directory in it.
  let setup = open --raw ($shipped | path join references this-setup.md)
  assert not ($setup | str contains "~/.config/nushell") "this-setup.md names one machine's checkout"
  assert not ($setup | str contains "Application Support") "this-setup.md names one machine's user directory"
}

def "test every hook a plugin declares is a script that exists and parses" [] {
  for p in (open $MARKETPLACE | get plugins) {
    let dir = $ROOT | path join $p.source
    let hooks_file = $dir | path join hooks hooks.json
    if not ($hooks_file | path exists) { continue }
    let cmds = open $hooks_file | get hooks | transpose event groups | get groups | flatten | get hooks | flatten | get command
    assert ($cmds | is-not-empty)
    for c in $cmds {
      let script = $c | parse -r '\$\{CLAUDE_PLUGIN_ROOT\}/(?<rel>[^"]+)' | get -o 0.rel
      assert ($script != null) $"($c): a hook names its script through CLAUDE_PLUGIN_ROOT"
      assert ($c starts-with "nu -n ") $"($c): a hook loads no config"
      let path = $dir | path join $script
      assert ($path | path exists) $path
      assert (nu-check $path) $"($path) parses"
    }
  }
}

def "test a skill description stays short enough to survive a tight skill listing" [] {
  # Claude Code renders every skill into one listing with a character budget
  # (8000 chars on a 200k-context model, `skillListingBudgetFraction`); over
  # it, descriptions are kept by priority and the rest are listed name-only,
  # and a freshly installed plugin skill is the lowest priority there. On a
  # machine with 28 other skills and haiku, 230 characters was the most a
  # new skill kept (2026-09-20) — the number is that machine's, the rule is
  # that a plugin's description competes for a budget it does not own.
  for f in (glob ($ROOT | path join harness "**" SKILL.md)) {
    let desc = open --raw $f | lines | where ($it starts-with "description:") | get -o 0 | default "" | str replace "description:" "" | str trim
    assert ($desc | is-not-empty) $"($f): a description"
    assert (($desc | str length) <= 230) $"($f): description is ($desc | str length) chars, over the cap"
  }
}

def "test the guard denies raw git worktree add in a layout and points at the skill" [] {
  let root = layout
  for cmd in ["git worktree add ../fix-42 -b fix-42" "cd .. && git worktree remove main" "git -C . worktree move main other"] {
    let out = hook pre-worktree-guard.nu { cwd: ($root | path join main), tool_input: { command: $cmd } }
    assert ($out | is-not-empty) $"($cmd): denied"
    let o = $out | from json | get hookSpecificOutput
    assert equal $o.permissionDecision deny
    assert ($o.permissionDecisionReason =~ "/worktree:worktree") "the reason names the skill"
    assert ($o.permissionDecisionReason | str contains $root) "the reason names the root"
  }
  # from the root itself, not only from a worktree
  let out = hook pre-worktree-guard.nu { cwd: $root, tool_input: { command: "git worktree add x" } }
  assert ($out | is-not-empty) "denied at the root too"
}

def "test the guard is silent for read-only worktree commands, quoted mentions and plain repositories" [] {
  let root = layout
  let inside = $root | path join main
  for cmd in ["git worktree list" "git worktree prune" "echo \"git worktree add x\"" "ls" "git status"] {
    assert equal (hook pre-worktree-guard.nu { cwd: $inside, tool_input: { command: $cmd } }) "" $cmd
  }
  # a plain repository: nothing to protect
  let plain = scratch
  git-in $plain init -q | ignore
  assert equal (hook pre-worktree-guard.nu { cwd: $plain, tool_input: { command: "git worktree add x" } }) ""
  # no payload at all
  let r = "" | ^$nu.current-exe -n --stdin ($HOOKS | path join pre-worktree-guard.nu) | complete
  assert equal $r.exit_code 0
  assert equal $r.stdout ""
}

def "test session start names the root, the worktree, the profiles, and stays silent elsewhere" [] {
  let root = layout
  let ctx = hook session-start-layout.nu { cwd: ($root | path join main) } | from json | get hookSpecificOutput
  assert equal $ctx.hookEventName SessionStart
  assert ($ctx.additionalContext | str contains $"root ($root)")
  assert ($ctx.additionalContext | str contains "in worktree `main` (branch main)")
  assert ($ctx.additionalContext | str contains "Worktrees: main.")
  assert ($ctx.additionalContext | str contains "Profiles: dflt, ci.") "dflt first, then the rest by name"
  let at_root = hook session-start-layout.nu { cwd: $root } | from json | get hookSpecificOutput.additionalContext
  assert ($at_root | str contains "at the root (the container), not in a worktree")
  let plain = scratch
  git-in $plain init -q | ignore
  assert equal (hook session-start-layout.nu { cwd: $plain }) ""
  assert equal (hook session-start-layout.nu { cwd: (scratch) }) "" "not even a repository"
}

def "test claude plugin validate passes for the marketplace and every plugin" [] {
  if (which claude | is-empty) { skip-test "claude is not on PATH" }
  let r = ^claude plugin validate --strict $MARKETPLACE | complete
  assert equal $r.exit_code 0 $r.stdout
  for p in (open $MARKETPLACE | get plugins) {
    let r = ^claude plugin validate --strict ($ROOT | path join $p.source) | complete
    assert equal $r.exit_code 0 $r.stdout
  }
}

def "test harness status reads the manifest and pairs each plugin with its module" [] {
  let dir = user-dir
  let r = nu-l $dir 'nu-config harness status | to nuon'
  assert equal $r.exit_code 0 $r.stderr
  let st = $r.stdout | from nuon
  assert equal $st.marketplace "nustro"
  assert equal ($st.plugins | get plugin) ["worktree" "nushell"]
  assert equal ($st.plugins | get module) ["worktree" null]
  # worktree is in the shipped MODULES, so a shell against this checkout has it enabled
  assert equal ($st.plugins | get enabled) [true null]
  assert (($st.plugins | get install | get 0) == "claude plugin install worktree@nustro")
  # `available` is what the checkout ships, read from each plugin.json.
  for p in $st.plugins {
    let manifest = open ($ROOT | path join harness claude-code $p.plugin .claude-plugin plugin.json)
    assert equal $p.available $manifest.version $p.plugin
  }
}

def "test harness update is quiet when the marketplace is not this checkout" [] {
  # A user directory of the test's own is not the registered marketplace
  # (that is the live checkout, or nothing), so update must do nothing and
  # say why only when asked.
  let dir = user-dir
  let quiet = nu-l $dir 'nu-config harness update'
  assert equal $quiet.exit_code 0 $quiet.stderr
  let st = nu-l $dir 'nu-config harness status | get registered | to nuon' | get stdout | from nuon
  if $st == true { skip-test "this checkout is the registered marketplace on this machine" }
  assert equal ($quiet.stdout | str trim) ""
  let loud = nu-l $dir 'nu-config harness update --verbose' | get stdout | ansi strip
  assert (($loud | str contains "not on PATH") or ($loud | str contains "not this checkout")) $loud
}
