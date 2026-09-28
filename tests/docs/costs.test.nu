# The numbers the documentation quotes for a module are the ones its
# meta.nuon measured. "Every number was measured" is a rule the docs state
# about themselves (docs/README.md); nothing else keeps a module's cost in the
# README's table and in its reference page from drifting when meta.nuon is
# re-measured — first-shell.md said 18 ms for terminal a week after its
# meta.nuon said 31 (2026-09-28).
use lib.nu *
use std/assert

def modules []: nothing -> table<name: string, cost: string> {
  ls ($ROOT | path join modules) | where type == dir | get name | each {|d|
    let meta = ($d | path join meta.nuon)
    if not ($meta | path exists) { return null }
    let c = (open $meta | get -o cost | default 0ns)
    { name: ($d | path basename), cost: $"(($c | into int) / 1_000_000 | math round) ms" }
  } | compact
}

def "test the README table quotes each module cost as meta.nuon has it" [] {
  let readme = (open --raw ($ROOT | path join README.md))
  for m in (modules) {
    let row = ($readme | lines | where $it =~ $"^\\| `($m.name)` \\|" | get -o 0)
    assert ($row != null) $"README.md has no row for ($m.name)"
    assert ($row | str contains $m.cost) $"README.md's row for ($m.name) says (($row | parse --regex '(?<c>\\d+ ms)' | get -o 0.c | default 'no cost')), meta.nuon ($m.cost)"
  }
}

def "test each module reference page quotes the cost meta.nuon has" [] {
  for m in (modules) {
    let docs = ($ROOT | path join (open ($ROOT | path join modules $m.name meta.nuon) | get docs))
    assert ($docs | path exists) $"($m.name): ($docs) is missing"
    assert (open --raw $docs | str contains $m.cost) $"($docs) never says ($m.cost), which meta.nuon measured"
  }
}
