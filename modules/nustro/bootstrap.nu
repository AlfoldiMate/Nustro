# bootstrap — what the installer, the startup hooks and `nustro repair` run
#
#   nustro bootstrap scaffold init | status | render                         your directory's READMEs, examples and settings.nu
#   nustro bootstrap tools setup | status | remove | dir                     init files for zoxide, atuin, carapace
#   nustro bootstrap upgrade check | stale | notice | good | head | branch   the update check conf/update.nu wires
#   nustro bootstrap plugins notice                                          the startup line conf/plugins.nu prints
#   nustro bootstrap layout | root | user-root | config-dir | in-place?      where things are
#   nustro bootstrap manifest | nu-older-than                                nustro.nuon against the running nu
#   nustro bootstrap missing-tool | missing-tools                            the error a module gives without its tool
#
# None of it is for every day: `nustro repair` runs the steps in order,
# `nustro status` and `nustro doctor` read the answers. They are commands all
# the same, because the installer runs each in a shell of its own and a test
# asks them one at a time.

export use roots.nu *
export use user.nu ["scaffold init" "scaffold status" "scaffold render"]
export use tools.nu *
export use upstream.nu ["upgrade check" "upgrade stale" "upgrade notice" "upgrade good" "upgrade head" "upgrade branch" manifest "nu-older-than"]
export use plugins.nu ["plugins notice"]
export use missing.nu *
