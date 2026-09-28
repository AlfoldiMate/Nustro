# config.nu — yours. Nushell loads this file, and this file loads the distro.
#
# Everything next to it is yours too:
#   settings.nu      your overrides          (nu-config edit user)
#   autoload/*.nu    drop-ins, loaded last   — machine-local, anything goes
#   completions/     what you fetched or wrote
#   themes/          your themes
#   plugins/         plugins you built or downloaded
#
# The distro below is a git checkout you do not edit; `git pull` in it picks up
# new defaults without touching anything here.
#
# If a new terminal opened with a parse error above this line, Nushell has
# started with nothing of the distro loaded — no `nu-config`, no Tab engine —
# and the error names the file. settings.nu next to this file is the usual
# one: `nu-check --debug settings.nu` says where. The checkout is the other
# — `nu-config upgrade` checks an update parses before pulling it, and
#   nu -n -c 'const NU_LIB_DIRS = [(@DISTRO@ | path join modules)]; use nu-config; nu-config upgrade rollback'
# puts the checkout back on the last version that did.

const DISTRO = @DISTRO@
source ($DISTRO | path join distro.nu)
