# modules/worktree against real git in the run's scratch directory: a layout
# from nothing and from an existing repository, add with profiles and a
# profile.nuon, the rules apply keeps (tracked never overwritten, later profile
# wins, override: false defers, type: none excludes), the manifest behind
# which/apply/discard/remove, what add carries over, and the two completers.
use lib.nu *
use std/assert
use worktree *

# git with an identity of the test's own, so a commit never asks for one.
def --wrapped git-in [dir: string, ...args: string]: nothing -> string {
  let r = ^git -C $dir -c user.name=test -c user.email=test@test -c init.defaultBranch=main -c commit.gpgsign=false ...$args | complete
  if $r.exit_code != 0 { error make -u { msg: $"git ($args | str join ' '): ($r.stderr)" } }
  $r.stdout | str trim
}

# What a command prints, run in `dir`: `print` goes to the terminal, not the
# pipeline, so a child shell runs the command and `complete` captures it.
def printed [dir: string, code: string]: nothing -> string {
  let mods = $ROOT | path join modules
  let r = ^$nu.current-exe -n -c $"const NU_LIB_DIRS = [($mods | to nuon)]; use worktree *; cd ($dir | to nuon); ($code)" | complete
  if $r.exit_code != 0 { error make -u { msg: $"($code): ($r.stderr)" } }
  $r.stdout
}

# An empty layout with one committed worktree `main`, holding README.md and a
# .gitignore that ignores .env, .claude and ci.yaml; `.profiles/dflt/.env`
# carries the one default entry. Returns the root.
def layout []: nothing -> string {
  let root = scratch
  cd $root
  worktree init
  worktree add main
  let main = $root | path join main
  "hi\n" | save ($main | path join README.md)
  ".env\n.claude\nci.yaml\nlocal.toml\n" | save ($main | path join .gitignore)
  git-in $main add . | ignore
  git-in $main commit -qm init | ignore
  "secret=1\n" | save ($root | path join .profiles dflt .env)
  $root
}

def "test init in an empty directory makes the bare layout" [] {
  let root = scratch
  cd $root
  worktree init
  assert equal ($root | path join .bare | path type) dir
  assert equal (open ($root | path join .git) | str trim) "gitdir: ./.bare"
  assert equal ($root | path join .profiles dflt | path type) dir
  assert equal (git-in $root rev-parse --is-bare-repository) "true"
}

def "test init refuses a layout that already exists" [] {
  let root = scratch
  cd $root
  worktree init
  let err = try { worktree init; null } catch {|e| $e.msg }
  assert ($err =~ "already a bare-worktree layout") $err
}

def "test add in an unborn repository makes an orphan branch and a linked worktree" [] {
  let root = scratch
  cd $root
  worktree init
  worktree add main
  let main = $root | path join main
  assert equal ($main | path join .git | path type) file "a linked worktree carries a .git file"
  assert equal (git-in $main branch --show-current) main
  assert equal (git-in $root worktree list --porcelain | lines | where $it starts-with "worktree " | length) 2 "the bare dir and main"
}

def "test apply places dflt as relative symlinks and the root .claude" [] {
  let root = layout
  mkdir ($root | path join .claude)
  "# claude\n" | save ($root | path join .claude CLAUDE.md)
  cd $root
  worktree apply --to main
  let main = $root | path join main
  assert equal ($main | path join .env | path type) symlink
  assert equal (^readlink ($main | path join .env) | str trim) "../.profiles/dflt/.env" "relative, so the container can move"
  assert equal (open ($main | path join .env)) "secret=1\n"
  assert equal ($main | path join .claude | path type) symlink
  assert equal (open --raw ($main | path join .claude CLAUDE.md)) "# claude\n"
  let st = open ($root | path join .profiles .state main.nuon)
  assert equal $st.applied [dflt]
  assert equal ($st.entries | select target type profile) [[target type profile]; [.claude symlink "(root)"] [.env symlink dflt]]
  assert equal (git-in $main status --porcelain) "" "everything placed is gitignored"
}

def "test apply never overwrites a git-tracked file" [] {
  let root = layout
  "from a profile\n" | save ($root | path join .profiles dflt README.md)
  cd ($root | path join main)
  worktree apply
  assert equal (open --raw README.md) "hi\n"
  assert equal ("README.md" | path type) file "still the tracked file, not a link"
  let st = open ($root | path join .profiles .state main.nuon)
  assert equal ($st.entries | get target) [.env] "the skipped entry is not recorded either"
}

def "test apply never replaces a directory with tracked files in it" [] {
  let root = layout
  let main = $root | path join main
  mkdir ($main | path join config)
  "a = 1\n" | save ($main | path join config a.toml)
  # the scan places the source dir's files under their own name too; ignored, so
  # status stays the measure of what happened to the tracked directory
  "config-src\n" | save -a ($main | path join .gitignore)
  git-in $main add config .gitignore | ignore
  git-in $main commit -qm config | ignore
  let ci = $root | path join .profiles ci
  mkdir ($ci | path join config-src)
  "b = 2\n" | save ($ci | path join config-src b.toml)
  # one declared as a copy, one as a symlink: neither may `rm -rf` the tracked dir
  { entries: [{ source: config-src, target: config, type: copy }] } | to nuon | save ($ci | path join profile.nuon)
  cd $main
  let text = printed $main "worktree apply -p ci"
  assert ($text =~ "config: git-tracked") $text
  assert equal (open --raw ($main | path join config a.toml)) "a = 1\n"
  assert equal (git-in $main status --porcelain) "" "nothing tracked was touched"
  { entries: [{ source: config-src, target: config }] } | to nuon | save -f ($ci | path join profile.nuon)
  worktree apply -p ci
  assert equal ($main | path join config | path type) dir "still the tracked directory, not a link"
  assert equal (git-in $main status --porcelain) ""
}

def "test discard sweeps only the directories its entries made" [] {
  let root = layout
  let ci = $root | path join .profiles ci
  mkdir ($ci | path join deep nest)
  "x\n" | save ($ci | path join deep nest x.txt)
  "deep\n" | save -a ($root | path join main .gitignore)
  let main = $root | path join main
  cd $main
  worktree apply -p ci
  assert equal ($main | path join deep nest x.txt | path type) symlink
  mkdir ($main | path join mywork empty) ($main | path join .cache)
  worktree discard
  assert equal ($main | path join deep | path exists) false "the entry's parents, emptied, are swept"
  assert equal ($main | path join mywork empty | path type) dir "an empty directory of the user's stays"
  assert equal ($main | path join .cache | path type) dir
}

def "test add with a profile: later wins, copy, none and override false" [] {
  let root = layout
  let ci = $root | path join .profiles ci
  mkdir $ci
  "ci: true\n" | save ($ci | path join ci.yaml)
  "secret=ci\n" | save ($ci | path join .env)
  "mine\n" | save ($ci | path join local.toml)
  # .env from ci replaces dflt's as a copy; ci.yaml is excluded; local.toml
  # defers to whatever is already in the worktree
  { entries: [
    { source: .env, type: copy }
    { source: ci.yaml, type: none }
    { source: local.toml, override: false }
  ] } | to nuon | save ($ci | path join profile.nuon)
  cd ($root | path join main)
  worktree add feat -p ci
  let feat = $root | path join feat
  assert equal (git-in $feat branch --show-current) feat
  assert equal ($feat | path join .env | path type) file "copy, not symlink"
  assert equal (open ($feat | path join .env)) "secret=ci\n" "ci wins over dflt"
  assert equal ($feat | path join ci.yaml | path exists) false "type none excludes"
  assert equal ($feat | path join local.toml | path type) symlink "nothing was in the way, so it is placed"
  assert equal ($feat | path join profile.nuon | path exists) false "machinery never propagates"
  let st = open ($root | path join .profiles .state feat.nuon)
  assert equal $st.applied [dflt ci]
  assert equal ($st.entries | select target type profile | sort-by target) [[target type profile]; [.env copy ci] [local.toml symlink ci]]
}

def "test override false defers to a file already in the worktree" [] {
  let root = layout
  let ci = $root | path join .profiles ci
  mkdir $ci
  "theirs\n" | save ($ci | path join local.toml)
  { entries: [{ source: local.toml, override: false }] } | to nuon | save ($ci | path join profile.nuon)
  "mine\n" | save ($root | path join main local.toml)
  cd ($root | path join main)
  worktree apply -p ci
  assert equal (open --raw ($root | path join main local.toml)) "mine\n"
}

def "test hooks run in the worktree with BW_ variables and a failure stops the command" [] {
  let root = layout
  let dflt = $root | path join .profiles dflt
  mkdir ($dflt | path join scripts)
  '$"($env.BW_PROFILE) ($env.BW_WORKTREE | path basename) ($env.BW_ROOT | path basename) ($env.PWD | path basename)\n" | save -f hooked' | save ($dflt | path join scripts hook.nu)
  { hooks: { after-add: { command: scripts/hook.nu } } } | to nuon | save ($dflt | path join profile.nuon)
  cd $root
  worktree add feat
  let feat = $root | path join feat
  assert equal (open ($feat | path join hooked)) $"dflt feat ($root | path basename) feat\n"
  assert equal ($feat | path join scripts | path exists) false "a hook script is machinery, never placed"

  { hooks: { before-apply: { command: scripts/boom.nu } } } | to nuon | save -f ($dflt | path join profile.nuon)
  "error make -u { msg: 'boom' }" | save ($dflt | path join scripts boom.nu)
  cd $feat
  let err = try { worktree apply; null } catch {|e| $e.msg }
  assert ($err =~ "hook scripts/boom.nu .* failed") $err
}

def "test which reports the manifest and the available profiles" [] {
  let root = layout
  mkdir ($root | path join .profiles ci)
  cd ($root | path join main)
  worktree apply
  let text = printed ($root | path join main) "worktree which"
  assert ($text =~ 'main: \[dflt\] applied') $text
  assert ($text =~ 'available profiles: ci, dflt') $text
  let from_root = printed $root "worktree which --on main"
  assert ($from_root =~ 'main: \[dflt\]') $from_root
}

def "test a bare apply refreshes the recorded set, -p changes it, --reset returns to dflt" [] {
  let root = layout
  let ci = $root | path join .profiles ci
  mkdir $ci
  "ci: true\n" | save ($ci | path join ci.yaml)
  let main = $root | path join main
  cd $main
  worktree apply -p ci
  assert equal ($main | path join ci.yaml | path type) symlink
  # a new entry in the profile arrives on a bare apply
  "more\n" | save ($ci | path join local.toml)
  worktree apply
  assert equal ($main | path join local.toml | path type) symlink
  assert equal (open ($root | path join .profiles .state main.nuon) | get applied) [dflt ci]
  # an entry deleted from the profile is retired, not left dangling
  rm ($ci | path join local.toml)
  worktree apply
  assert equal ($main | path join local.toml | path exists) false
  worktree apply --reset
  assert equal (open ($root | path join .profiles .state main.nuon) | get applied) [dflt]
  assert equal ($main | path join ci.yaml | path exists) false "the dropped profile's entries go too"
  assert equal ($main | path join .env | path type) symlink
}

def "test apply names a missing profile and a missing worktree" [] {
  let root = layout
  cd ($root | path join main)
  let err = try { worktree apply -p nope; null } catch {|e| $e.msg }
  assert ($err =~ "no profile 'nope' — available: dflt") $err
  cd $root
  let err2 = try { worktree apply --to nope; null } catch {|e| $e.msg }
  assert ($err2 =~ "nope is not a worktree under") $err2
  let err3 = try { worktree apply; null } catch {|e| $e.msg }
  assert ($err3 =~ "in the root — name a target with --to") $err3
}

def "test discard removes symlinks and keeps a diverged copy" [] {
  let root = layout
  let ci = $root | path join .profiles ci
  mkdir $ci
  "ci: true\n" | save ($ci | path join ci.yaml)
  { entries: [{ source: ci.yaml, type: copy }] } | to nuon | save ($ci | path join profile.nuon)
  let main = $root | path join main
  cd $main
  worktree apply -p ci
  "ci: edited\n" | save -f ($main | path join ci.yaml)
  let text = printed $main "worktree discard"
  assert equal ($main | path join .env | path exists) false
  assert equal (open --raw ($main | path join ci.yaml)) "ci: edited\n" "the diverged copy is the user's work"
  assert ($text =~ "kept ci.yaml: copy has diverged") $text
  assert equal ($root | path join .profiles .state main.nuon | path exists) false
  let again = try { worktree discard; null } catch {|e| $e.msg }
  assert ($again =~ "no applied profiles recorded") $again
}

def "test remove discards then removes, and refuses untracked files without --force" [] {
  let root = layout
  cd $root
  worktree add feat
  let feat = $root | path join feat
  "scratch\n" | save ($feat | path join notes.txt)
  let err = try { worktree remove feat; null } catch {|e| $e.msg }
  assert ($err =~ "--force") $err
  assert equal ($feat | path exists) true
  worktree remove feat --force
  assert equal ($feat | path exists) false
  assert equal ($root | path join .profiles .state feat.nuon | path exists) false
  assert equal (git-in $root worktree list --porcelain | lines | where $it =~ 'feat' | length) 0
}

def "test add inside a worktree starts at its HEAD and carries its ignored files over" [] {
  let root = layout
  let main = $root | path join main
  cd $main
  worktree apply
  "two\n" | save ($main | path join two.txt)
  git-in $main add two.txt | ignore
  git-in $main commit -qm two | ignore
  mkdir ($main | path join .cache)
  "built\n" | save ($main | path join .cache out)
  ".cache\n" | save --append ($main | path join .gitignore)
  git-in $main commit -qam ignore-cache | ignore
  worktree add feat
  let feat = $root | path join feat
  assert equal (git-in $feat log --oneline | lines | length) 3 "based on main's HEAD, not the bare repo's"
  assert equal (open ($feat | path join .cache out)) "built\n" "an ignored directory came along"
  assert equal ($feat | path join .cache out | path type) file "as a copy"
  assert equal ($feat | path join .env | path type) symlink "a link into the root is re-made by apply, not copied"
}

def "test add branches from the first worktree whatever the default branch of git is" [] {
  # A bare HEAD names init.defaultBranch, `master` on a machine without one
  # configured (CI's), never the `main` the layout's first worktree makes.
  with-env { GIT_CONFIG_COUNT: "1", GIT_CONFIG_KEY_0: "init.defaultBranch", GIT_CONFIG_VALUE_0: "master" } {
    let root = layout
    cd $root
    worktree add feat
    assert equal (git-in ($root | path join feat) log --oneline | lines | length) 1 "from the root: main's commit"
    cd ($root | path join main)
    worktree add fix
    assert equal (git-in ($root | path join fix) log --oneline | lines | length) 1 "from inside main: its HEAD"
  }
}

def "test add tracks a branch that only a remote has" [] {
  # a colleague's branch: on origin after a fetch, in no worktree yet
  let up = scratch
  git-in $up init -q | ignore
  "up\n" | save ($up | path join README.md)
  git-in $up add . | ignore
  git-in $up commit -qm up | ignore
  git-in $up checkout -qb pushed | ignore
  "theirs\n" | save ($up | path join theirs.txt)
  git-in $up add . | ignore
  git-in $up commit -qm theirs | ignore
  git-in $up checkout -q main | ignore
  let root = layout
  git-in $root remote add origin $up | ignore
  git-in $root config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*" | ignore
  git-in $root fetch -q origin | ignore
  cd ($root | path join main)
  let text = printed ($root | path join main) "worktree add pushed"
  assert ($text =~ "pushed is on origin: tracking it") $text
  let wt = $root | path join pushed
  assert equal (git-in $wt log --format=%s -1) theirs "origin/pushed's commit, not main's"
  assert equal (git-in $wt rev-parse --abbrev-ref "@{u}") origin/pushed
}

def "test add from the root repairs a bare HEAD that names no branch" [] {
  # a layout made before the first add pointed the bare HEAD, or a bare clone
  # whose HEAD branch was deleted: HEAD → master, only main exists
  let root = layout
  git-in $root symbolic-ref HEAD refs/heads/master | ignore
  cd $root
  let text = printed $root "worktree add feat"
  assert ($text =~ "bare HEAD named master") $text
  assert equal (git-in ($root | path join feat) log --oneline | lines | length) 1 "from main, not an orphan"
  assert equal (git-in $root symbolic-ref --short HEAD) main
  # an existing branch is checked out before anything is judged unborn
  worktree remove feat
  git-in $root symbolic-ref HEAD refs/heads/master | ignore
  worktree add feat
  assert equal (git-in ($root | path join feat) branch --show-current) feat
}

def "test init transforms a repository: history to .bare, ignored files to dflt" [] {
  let repo = scratch
  git-in $repo init -q | ignore
  "hi\n" | save ($repo | path join README.md)
  mkdir ($repo | path join src)
  "fn main() {}\n" | save ($repo | path join src main.rs)
  ".env\nnode_modules\n" | save ($repo | path join .gitignore)
  git-in $repo add . | ignore
  git-in $repo commit -qm init | ignore
  "secret=1\n" | save ($repo | path join .env)
  mkdir ($repo | path join node_modules)
  "junk\n" | save ($repo | path join node_modules x.js)
  let text = printed $repo "worktree init"
  cd $repo
  assert equal ($repo | path join .bare | path type) dir
  assert equal (git-in $repo rev-parse --is-bare-repository) "true"
  let main = $repo | path join main
  assert equal (open ($main | path join src main.rs)) "fn main() {}\n"
  assert equal ($repo | path join README.md | path exists) false "the original is a duplicate of the checkout"
  assert equal ($repo | path join src | path exists) false "and its emptied directory goes"
  assert equal (open ($repo | path join .profiles dflt .env)) "secret=1\n"
  assert equal ($repo | path join .env | path exists) false
  assert ($text =~ "junk landed in .profiles/dflt: node_modules") $text
  worktree apply --to main
  assert equal (open ($main | path join .env)) "secret=1\n"
}

def "test init refuses a dirty tree and a detached HEAD" [] {
  let repo = scratch
  git-in $repo init -q | ignore
  "hi\n" | save ($repo | path join README.md)
  git-in $repo add . | ignore
  git-in $repo commit -qm init | ignore
  "new\n" | save ($repo | path join untracked.txt)
  cd $repo
  let err = try { worktree init; null } catch {|e| $e.msg }
  assert ($err =~ "working tree not clean") $err
  rm ($repo | path join untracked.txt)
  git-in $repo checkout -q --detach | ignore
  let err2 = try { worktree init; null } catch {|e| $e.msg }
  assert ($err2 =~ "detached HEAD") $err2
  assert equal ($repo | path join .git | path type) dir "nothing was touched"
}

def "test outside a layout every command says so" [] {
  let dir = scratch
  cd $dir
  let err = try { worktree which; null } catch {|e| $e.msg }
  assert ($err =~ "not inside a bare-worktree layout") $err
}

def "test Tab completes worktree names and profile names" [] {
  let root = layout
  mkdir ($root | path join .profiles ci) ($root | path join .profiles dev) ($root | path join notes)
  cd $root
  worktree add feat
  assert equal ("worktree remove " | commandline complete | sort) [feat main] "a plain directory is not a worktree"
  assert equal ("worktree apply --to m" | commandline complete) [main]
  assert equal ("worktree add x -p " | commandline complete | sort) [ci dev] "dflt is always applied, so never offered"
  assert equal ("worktree add x -p ci," | commandline complete | sort) ["ci,ci" "ci,dev"]
  assert equal ("worktree add x --profiles=ci,d" | commandline complete) ["ci,dev"] "the glued form is a flag value too"
  cd (scratch)
  assert equal ("worktree remove " | commandline complete) [] "outside a layout: nothing, not an error"
}
