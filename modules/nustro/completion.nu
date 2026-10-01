# completion — Tab, as a person asks about it
#
#   nustro completion explain "<line>"   which rule answered a line, what it offered, what it cost
#   nustro completion status             what is cached, and where
#   nustro completion clear              forget the session's memoised answers
#   nustro completion fetch <tool>       vendor a completion module from nu_scripts into YOUR completions/
#
# The engine is modules/nu-complete, and its `nu-complete …` commands are what
# a spec in completions/ calls; these are the four a person types.

use nu-complete *

const NU_SCRIPTS = "https://raw.githubusercontent.com/nushell/nu_scripts/main"

# Which rule answered a line, what it offered and what each stage cost — the
# same code path as Tab, for a slot that offers the wrong thing or is slow.
export def "completion explain" [
  line: string   # the line up to the cursor, as typed
]: nothing -> record {
  nu-complete explain $line
}

# What the engine has cached, and where.
export def "completion status" []: nothing -> table<what: string, where: string, size: string, age: string> {
  nu-complete status
}

# Forget the session's memoised answers: the next Tab asks the tool again.
export def "completion clear" []: nothing -> nothing {
  nu-complete cache clear
}

# Vendor a completion module from nu_scripts into YOUR completions/. Anything
# fetched belongs to you, not to the distro, so it lands in your directory —
# which is also first on NU_LIB_DIRS, so it shadows a shipped file of the
# same name.
#   nustro completion fetch docker
export def "completion fetch" [tool: string]: nothing -> nothing {
  let url = $"($NU_SCRIPTS)/custom-completions/($tool)/($tool)-completions.nu"
  let dir = ($nu.config-path | path dirname | path expand | path join completions)
  mkdir $dir
  let dest = ($dir | path join $"($tool)-completions.nu")
  let body = (try { http get $url } catch { error make { msg: $"nothing at ($url)" } })
  $body | save -f $dest
  print $"saved ($dest)"
  print $"add to your settings.nu:   use ($tool)-completions.nu *"
}
