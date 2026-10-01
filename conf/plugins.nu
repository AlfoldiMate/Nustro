# plugins.nu — tell an interactive shell when its plugins stopped loading
#
# The plugin registry names each plugin's file, and a package manager's path
# to it carries the Nushell version: after an upgrade every entry points at a
# file that is gone and the plugin's commands fail with "Unable to spawn
# plugin". `nustro bootstrap plugins notice` says so in one line, with the command
# that registers them again; modules/nustro/mod.nu has the cost.
#
# Interactive only, like conf/update.nu: a script's output is its own.
if $nu.is-interactive { nustro bootstrap plugins notice }
