# The costs docs/concepts/completion.md claims, as upper bounds a regression
# would cross: each bound is ten to twenty times what was measured on an
# M-series Mac on 2026-09-19 (in the comments), because CI runners are slower
# and a test that fails on noise is worse than none. The minimum of a few
# runs is taken, the way the documented numbers were.
use lib.nu *
use std/assert
use nu-complete *

def fastest [runs: int, code: closure]: nothing -> duration {
  1..$runs | each {|_| timeit $code } | math min
}

def "test external binds the completer inputs within its budget" [] {
  # 0.2 ms (2026-09-27): reading the closure's header, building its inputs.
  $env.config.completions.external.completer = {|place: record, buffer: string| [] }
  let spans = [git commit -m '"a b"' --author=x] ++ (1..20 | each {|i| $"word($i)" })
  let took = fastest 5 { nu-complete external $spans }
  assert ($took < 5ms) $"external took ($took)"
}

def "test quote scans two thousand plain values within its budget" [] {
  # 0.5 ms: one regex over the joined values, no closure per item.
  let plain = 1..2000 | each {|i| { value: $"formula-($i)" } }
  let took = fastest 5 { $plain | nu-complete quote }
  assert ($took < 10ms) $"quote took ($took)"
}

def "test quote rewrites two thousand values with spaces within its budget" [] {
  # 38 ms: a closure per item once one needs quoting.
  let spaced = 1..2000 | each {|i| { value: $"formula ($i)" } }
  let took = fastest 3 { $spaced | nu-complete quote }
  assert ($took < 400ms) $"quote took ($took)"
}

def "test filter narrows two thousand values within its budget" [] {
  # prefix 4.4 ms, fuzzy 15 ms with descriptions (ranked in tiers, column-wise).
  let items = 1..2000 | each {|i| { value: $"formula-($i)", description: $"the ($i)th formula" } }
  $env.config.completions.algorithm = "prefix"
  let prefix = fastest 3 { $items | nu-complete filter "formula-19" }
  assert ($prefix < 100ms) $"prefix filter took ($prefix)"
  $env.config.completions.algorithm = "fuzzy"
  let fuzzy = fastest 3 { $items | nu-complete filter "f19" }
  assert ($fuzzy < 100ms) $"fuzzy filter took ($fuzzy)"
}

def "test the smart menu answers within its budget" [] {
  # `ps ` 3.7 ms, `ls | where ` 3.4 ms from the memoised probe (2026-10-01;
  # the first call of a line pays the probe's subprocess, 40 ms).
  let ps_in = ("ps " | commandline complete --input)
  let cols_in = ("ls | where " | commandline complete --input)
  nu-complete smart $ps_in.buffer $ps_in.place | ignore
  nu-complete smart $cols_in.buffer $cols_in.place | ignore
  let ps = fastest 5 { nu-complete smart $ps_in.buffer $ps_in.place }
  assert ($ps < 30ms) $"ps took ($ps)"
  let cols = fastest 5 { nu-complete smart $cols_in.buffer $cols_in.place }
  assert ($cols < 50ms) $"ls | where took ($cols)"
}

def "test a line that may not run is refused once, not per keystroke" [] {
  # The safety check is one `scope commands` (4 ms); it is inside the
  # memoised probe, so the second Tab on `^ls | where ` is the bare 1 ms.
  let i = ("^ls | where " | commandline complete --input)
  nu-complete smart $i.buffer $i.place | ignore
  let took = fastest 5 { nu-complete smart $i.buffer $i.place }
  assert ($took < 30ms) $"a refused line took ($took)"
}
