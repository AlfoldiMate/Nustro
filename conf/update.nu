# update.nu — tell an interactive shell when the distro is behind its remote
#
# Two things, both off the network. Read the last check's result and print one
# line when it says there is something to pull. And when that result is older
# than UPDATE_CHECK_EVERY, start a fresh check as a background job — the
# `git fetch` runs while you type, and what it finds is what the NEXT start
# reports. The commands are `nustro upgrade …`, modules/nustro/upstream.nu;
# `nustro upgrade` is the pull.
#
# Interactive only: `nu -c` and a script get no notice and spawn nothing — a
# script whose output starts with "distro: 2 commits behind" is a bug. A job
# also dies with the shell that spawned it, and a script would be gone before
# the fetch returned.
if $nu.is-interactive and $UPDATE_CHECK_EVERY > 0sec {
  nustro bootstrap upgrade notice
  if (nustro bootstrap upgrade stale $UPDATE_CHECK_EVERY) {
    job spawn --description "nustro bootstrap upgrade check" {|| nustro bootstrap upgrade check | ignore } | ignore
  }
}
