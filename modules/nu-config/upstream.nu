# update — is the distro checkout behind its remote, and pulling it
#
#   nu-config upgrade            git pull --ff-only in the checkout, say what changed, update the Claude Code plugins
#   nu-config upgrade check      fetch now and report where the checkout stands
#   nu-config upgrade status     the last check's result; touches no network
#   nu-config upgrade notice     the one-line "there is an update" the shell prints at start
#   nu-config upgrade rollback   check out the last version that parsed; `upgrade` returns
#
# A pull is checked before it is live. The fetched upstream is checked out into
# a throwaway worktree under the state dir; its nustro.nuon is read against
# `(version)` and its distro.nu is `nu-check`ed — every `source` and `use`
# followed, your settings.nu included — with the `nu` running now. Only then
# is the checkout fast-forwarded. A config that fails to parse gives Nushell's
# stock shell with none of these commands in it, so the check has to happen
# while they still exist. The HEAD left behind is recorded as `previous`, and
# the HEAD `doctor` last saw parse as `last_good`: `rollback` goes to the
# proven one.
#
# The check that runs by itself is wired in conf/update.nu. The network is
# never on the startup path: at an interactive start the LAST result is read
# out of a small state file and, when it says the checkout is behind, one line
# is printed; when that result is older than UPDATE_CHECK_EVERY a fresh check
# runs as a background job (`job spawn`), and its result is what the NEXT start
# reports. A job dies with the shell that spawned it, so a window closed
# within a second or two of opening loses that check — and the next window
# simply runs it again, because the result is still stale.
#
# The state file lives in your directory, `.state/nu-config/upgrade.nuon`,
# never in the checkout: `git pull` has to stay clean. It records the HEAD the
# check was made against, so a pull done by hand — or by `nu-config upgrade` —
# retires the notice at once rather than a day later.
#
# A checkout without a `.git`, without a remote-tracking branch, or without git
# on PATH records why and stays quiet: the notice is for the one case where
# there is something to do.

# This file is modules/nu-config/upstream.nu: a module cannot export a command
# named after itself. And the command is `upgrade`, not `update`, because
# `update` is a built-in and a module that defines one shadows it for
# everything parsed after — `use nu-complete *` in mod.nu stopped parsing.; `distro-root` lives in mod.nu,
# which imports this file and so is not visible from it.
const ROOT = path self | path dirname | path dirname | path dirname

def distro-root []: nothing -> path { $ROOT | path expand }

# `harness update`, for the end of `upgrade`: the plugins Claude Code copied
# out of this checkout are at the version it had before the pull.
use harness.nu *
use tools.nu ["tools setup"]

# `nu-config user init`, without importing user.nu a second time: scaffold.nu
# is a script (docs/concepts/layout.md), run in a `nu -n` the way user.nu's
# scaffold-run does it, and the failure is reported, not raised — an upgrade
# that pulled is done, whatever the scaffold says.
def scaffold-init []: nothing -> table<file: string, action: string, note: string> {
  let script = ($ROOT | path join modules nu-config scaffold.nu)
  let dir = ($nu.config-path | path dirname | path expand --no-symlink)
  let r = (^$nu.current-exe -n $script init --dir $dir | complete)
  if $r.exit_code != 0 {
    print $"(ansi yellow)scaffold not rendered: ($r.stderr | str trim)(ansi reset) — `nu-config user init`"
    return []
  }
  $r.stdout | from nuon
}

def state-path []: nothing -> path {
  $nu.data-dir | path join .state nu-config upgrade.nuon
}

# git, run in the checkout, output captured. The arguments come as a list,
# because a rest parameter would read `--abbrev-ref` as a flag of ours.
# `GIT_TERMINAL_PROMPT=0` so a fetch that wants credentials fails instead of
# asking a background job for a password.
def git-in [args: list<string>]: nothing -> record<stdout: string, stderr: string, exit_code: int> {
  let root = (distro-root)
  with-env { GIT_TERMINAL_PROMPT: "0" } {
    ^git -C $root ...$args | complete
  }
}

# Its stdout, trimmed, or null when git said no.
def git-ok [args: list<string>]: nothing -> any {
  let r = (git-in $args)
  if $r.exit_code == 0 { $r.stdout | str trim } else { null }
}

# What the checkout is a git checkout OF: null with the reason when the check
# cannot be made at all.
def unable []: nothing -> any {
  if (which git | is-empty) { return "git is not on PATH" }
  if not ((distro-root) | path join .git | path exists) { return "the distro is not a git checkout" }
  if (git-ok [rev-parse --abbrev-ref --symbolic-full-name '@{u}']) == null { return "the checked-out branch tracks no remote branch" }
  null
}

# Where HEAD stands against its upstream, from what is already fetched.
def measure []: nothing -> record {
  let counts = (git-ok [rev-list --left-right --count 'HEAD...@{u}'] | default "0\t0" | split row "\t")
  {
    checked: (date now)
    head: (git-ok [rev-parse HEAD])
    upstream: (git-ok [rev-parse --abbrev-ref '@{u}'])
    ahead: ($counts | get 0 | into int)
    behind: ($counts | get 1 | into int)
    # Newest first, the way `git log` lists them.
    log: (git-ok [log --format=%s 'HEAD..@{u}'] | default "" | lines)
    error: null
  }
}

# A check replaces the measurement; the three pins outlive it.
def save-state [s: record]: nothing -> record {
  let f = (state-path)
  let old = (upgrade status)
  let out = { last_good: $old.last_good?, previous: $old.previous?, branch: $old.branch? } | merge $s
  mkdir ($f | path dirname)
  $out | to nuon | save -f $f
  $out
}

# The last check's result, or an empty record when there has never been one.
# `last_good` is the HEAD `doctor` last saw parse, `previous` the HEAD the
# last `upgrade` moved off, `branch` the branch `rollback` detached from.
export def "upgrade status" []: nothing -> record {
  let f = (state-path)
  let none = { checked: null, head: null, upstream: null, ahead: 0, behind: 0, log: [], error: "never checked", last_good: null, previous: null, branch: null }
  # merged over the defaults: a file written before the pins existed lacks them
  if ($f | path exists) { $none | merge (open $f) } else { $none }
}

# The checkout's manifest, nustro.nuon at its root: `{ requires_nu }`. Empty
# for a commit that predates it.
export def manifest [
  root?: path   # another checkout's; the distro's by default
]: nothing -> record {
  let f = ($root | default (distro-root) | path join nustro.nuon)
  if ($f | path exists) { open $f } else { {} }
}

# Is the running Nushell older than `requires_nu`?
export def "nu-older-than" [req: string]: nothing -> bool {
  let want = ($req | split row "." | each { into int })
  let v = (version)
  ($v.major < $want.0) or ($v.major == $want.0 and $v.minor < ($want | get -o 1 | default 0))
}

# Would `target` load on this machine? Null when it would, else why not: a
# throwaway worktree of it under the state dir, its manifest against
# `(version)`, then `nu-check --debug` of its distro.nu in a child `nu` —
# the child's stderr is the parse error, worth the fork (0.24 s in all,
# worktree add to remove, 2026-09-28). The worktree is removed either way.
def preflight [target: string]: nothing -> any {
  let dir = ($nu.data-dir | path join .state nu-config preflight)
  git-in [worktree remove --force $dir] | ignore
  if ($dir | path exists) { rm -rf $dir }
  let w = (git-in [worktree add --detach --force $dir $target])
  if $w.exit_code != 0 { return $"could not check ($target) out for a look: ($w.stderr | str trim)" }
  let why = do {
    let req = (manifest $dir).requires_nu?
    if $req != null and (nu-older-than $req) {
      return $"it needs Nushell ($req) and this is ((version).version) — upgrade nu first"
    }
    let r = (^$nu.current-exe -n -c $"nu-check --debug (($dir | path join distro.nu) | to nuon)" | complete)
    if $r.exit_code != 0 or ($r.stdout | str trim) != "true" {
      let err = ($r.stderr | split row "\nError: nu::shell::error" | first | str trim)
      return $"it does not parse with Nushell ((version).version):\n($err)"
    }
    null
  }
  git-in [worktree remove --force $dir] | ignore
  git-in [worktree prune] | ignore
  $why
}


# Fetch, measure, remember. Silent by design — it is what the background job
# runs — and the record it returns is what `status` will report from now on.
export def "upgrade check" []: nothing -> record {
  let why = (unable)
  if $why != null {
    return (save-state { checked: (date now), head: null, upstream: null, ahead: 0, behind: 0, log: [], error: $why })
  }
  let f = (git-in [fetch --quiet])
  if $f.exit_code != 0 {
    # Offline, most days. Keep the previous counts — they were true when made —
    # and note that this attempt did not get through.
    return (save-state ((upgrade status) | merge { checked: (date now), error: ($f.stderr | str trim | lines | get -o 0 | default "fetch failed") }))
  }
  save-state (measure)
}

# Has the last check gone stale, so the shell should spawn a new one?
export def "upgrade stale" [
  every: duration   # how old a result may be before a start re-checks
]: nothing -> bool {
  let s = (upgrade status)
  $s.checked == null or ((date now) - $s.checked) > $every
}

# HEAD without spawning git: `.git/HEAD` names a ref, and the ref is a file
# under `.git/` until git packs it, when it is a line in `packed-refs`. The
# startup path reads two small files where `git rev-parse` would fork. Null
# when it cannot be told, and null never matches, so an unreadable HEAD errs on
# the side of silence.
def head-now []: nothing -> any {
  let git = ((distro-root) | path join .git)
  let head = ($git | path join HEAD)
  if not ($head | path exists) { return null }
  let h = (open --raw $head | str trim)
  if not ($h | str starts-with "ref: ") { return $h }
  let ref = ($h | str replace "ref: " "")
  let loose = ($git | path join $ref)
  if ($loose | path exists) { return (open --raw $loose | str trim) }
  let packed = ($git | path join packed-refs)
  if not ($packed | path exists) { return null }
  open --raw $packed | lines | parse "{sha} {name}" | where name == $ref | get -o 0.sha
}

# `main` from a `ref: refs/heads/main` in .git/HEAD, or null when HEAD is
# detached — a rollback — or unreadable. No git fork: the notice reads it at
# every start.
def head-ref []: nothing -> any {
  let head = ((distro-root) | path join .git HEAD)
  if not ($head | path exists) { return null }
  let h = (open --raw $head | str trim)
  if ($h | str starts-with "ref: refs/heads/") { $h | str replace "ref: refs/heads/" "" } else { null }
}

# Record HEAD as known to parse — `doctor` calls it when distro.nu checked
# out. Quiet outside a git checkout.
export def "upgrade good" []: nothing -> nothing {
  let h = (head-now)
  if $h != null { save-state ((upgrade status) | merge { last_good: $h }) | ignore }
}

# One line, when — and only when — the last check found the checkout behind
# the HEAD it still has, or HEAD is where a rollback left it. Read from the
# state file; no git, no network.
export def "upgrade notice" []: nothing -> nothing {
  let s = (upgrade status)
  if $s.branch? != null and (head-ref) == null {
    print $"(ansi dark_gray)distro: rolled back to ((head-now) | default '' | str substring 0..7) — (ansi reset)(ansi cyan)nu-config upgrade(ansi reset)(ansi dark_gray) returns to ($s.branch)(ansi reset)"
    return
  }
  if $s.error != null or $s.behind == 0 or $s.head != (head-now) { return }
  let n = (if $s.behind == 1 { "1 commit" } else { $"($s.behind) commits" })
  let latest = ($s.log | get -o 0 | default "")
  let tail = (if ($latest | is-empty) { "" } else { $" · ($latest)" })
  print $"(ansi dark_gray)distro: ($n) behind ($s.upstream)($tail) — (ansi reset)(ansi cyan)nu-config upgrade(ansi reset)"
}

# Pull. Fast-forward only: a checkout with commits of its own is a development
# checkout, and merging on its behalf is not a maintenance command's call.
export def upgrade []: nothing -> nothing {
  # After a rollback HEAD is detached; the branch it left is the way back.
  let s = (upgrade status)
  if $s.branch? != null and (head-ref) == null {
    let co = (git-in [checkout --quiet $s.branch])
    if $co.exit_code != 0 { error make { msg: $"cannot return to ($s.branch): ($co.stderr | str trim)" } }
    save-state ($s | merge { branch: null }) | ignore
    print $"back on ($s.branch)"
  }
  let why = (unable)
  if $why != null { error make { msg: $"cannot update: ($why)" } }
  let before = (git-ok [rev-parse HEAD])
  let f = (git-in [fetch --quiet])
  if $f.exit_code != 0 {
    error make { msg: $"git fetch failed in ((distro-root))", label: { text: ($f.stderr | str trim), span: (metadata $why).span } }
  }
  let target = (git-ok [rev-parse '@{u}'])
  if $before == $target {
    let after = (save-state (measure))
    print $"already up to date with ($after.upstream)"
    return
  }
  let bad = (preflight $target)
  if $bad != null {
    save-state (measure) | ignore
    error make { msg: $"not updated — ($target | str substring 0..7) would break the next shell: ($bad)", label: { text: "the checkout is as it was", span: (metadata $why).span } }
  }
  let r = (git-in [pull --ff-only --quiet])
  if $r.exit_code != 0 {
    error make { msg: $"git pull failed in ((distro-root))", label: { text: ($r.stderr | str trim), span: (metadata $why).span } }
  }
  let after = (save-state ((measure) | merge { previous: $before }))
  print $"updated ((distro-root)) → ($after.upstream)"
  for l in (git-ok [log --format=%s $"($before)..($after.head)"] | default "" | lines) { print $"  ($l)" }
  # The scaffold the new version ships — a README or an example a release
  # added — is written where it is missing, the way `edit user` does it; a file
  # you have is never touched. scaffold.nu runs from the checkout as it is now
  # on disk, so the templates are the new ones.
  let written = (scaffold-init | where action != "kept")
  if ($written | is-not-empty) {
    print $"scaffold in ((user-root)):"
    for r in $written { print $"  ($r.action) ($r.file)  ($r.note)" }
  }
  # The generated init files (vendor/autoload) come from generators in the
  # checkout, so a pull that changed one — carapace's wrapper for the
  # completer inputs of Nushell 0.116 — reaches them here, not at the next
  # `tools setup` someone remembers to run. Idempotent; prints only what
  # changed (0.17 s, 2026-09-27).
  tools setup --quiet
  # Claude Code holds a copy of each plugin at the version it was installed
  # at; the marketplace reads the checkout in place. Quiet without claude or
  # when the marketplace is another checkout's (`harness update --verbose`
  # says which).
  if (which claude | is-not-empty) and (harness status).registered == true {
    print "Claude Code:"
    harness update
  }
  print $"(ansi dark_gray)a new shell loads it; `nu-config doctor` checks it parsed, `nu-config upgrade rollback` goes back(ansi reset)"
}

# Check out an earlier version: the one `doctor` last saw parse, else the one
# the last `upgrade` moved off, else the commit named. HEAD is left detached,
# which silences the update notice; `nu-config upgrade` returns to the branch
# and pulls.
export def "upgrade rollback" [
  commit?: string   # a commit to go to instead; `git -C (nu-config distro-root) log --oneline`
]: nothing -> nothing {
  let why = (unable)
  if $why != null and $why != "the checked-out branch tracks no remote branch" { error make { msg: $"cannot roll back: ($why)" } }
  let s = (upgrade status)
  let target = ($commit | default ($s.last_good? | default $s.previous?))
  if $target == null {
    error make { msg: "nothing recorded to roll back to — no upgrade has run and doctor has not seen this checkout parse; name a commit: nu-config upgrade rollback <commit>" }
  }
  let sha = (git-ok [rev-parse --verify $"($target)^{commit}"])
  if $sha == null { error make { msg: $"($target) is not a commit in ((distro-root))" } }
  let here = (git-ok [rev-parse HEAD])
  if $sha == $here { print $"already at ($sha | str substring 0..7)"; return }
  # the branch to return to: the one HEAD is on, or the one an earlier rollback left
  let branch = ((head-ref) | default $s.branch?)
  let co = (git-in [checkout --quiet --detach $sha])
  if $co.exit_code != 0 { error make { msg: $"git checkout failed in ((distro-root))", label: { text: ($co.stderr | str trim), span: (metadata $why).span } } }
  save-state ($s | merge { branch: $branch }) | ignore
  let subject = (git-ok [log --format=%s -1 $sha] | default "")
  let which = (if $commit != null { "" } else if $s.last_good? == $sha { " — the last that doctor saw parse" } else { " — where the last upgrade started" })
  print $"rolled ((distro-root)) back to ($sha | str substring 0..7) ($subject)($which)"
  print $"(ansi dark_gray)a new shell loads it; `nu-config upgrade` returns to ($branch | default 'the branch') and pulls(ansi reset)"
}
