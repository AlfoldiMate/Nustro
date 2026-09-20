# modules/terminal/wezterm.nu against the fake wezterm: where the config is,
# our file and the line that applies it, `set`/`reset`/`live`/`shell`, the
# validation through `ls-fonts`, and `theme use` / `font use` through the
# registry with WezTerm as the target.
use lib.nu *
use std/assert
use terminal *

const INCLUDE = 'pcall(function() dofile(require("wezterm").config_dir .. "/nustro.lua").apply(config) end)'

def "test config-path is the XDG wezterm.lua when nothing exists yet" [] {
  let fake = fake-wezterm
  assert equal (wezterm config-path) ($fake.config | path join wezterm.lua)
}

def "test config-path prefers XDG over the home file, and the file WezTerm says it loaded over both" [] {
  let fake = fake-wezterm
  let home = $nu.home-dir | path join .wezterm.lua
  "return {}\n" | save $home
  assert equal (wezterm config-path) $home "~/.wezterm.lua is read when the XDG one is missing"
  "return {}\n" | save ($fake.config | path join wezterm.lua)
  assert equal (wezterm config-path) ($fake.config | path join wezterm.lua)
  let other = scratch | path join elsewhere.lua
  "return {}\n" | save $other
  $env.WEZTERM_CONFIG_FILE = $other
  assert equal (wezterm config-path) $other "inside a WezTerm window the loaded file is known"
}

def "test set creates the config with the line when there is none" [] {
  let fake = fake-wezterm
  wezterm set { color_scheme: "nustro-x" }
  let cfg = open --raw ($fake.config | path join wezterm.lua) | lines
  assert ($INCLUDE in $cfg) ($cfg | to nuon)
  assert equal ($cfg | last) "return config"
  assert ("local config = wezterm.config_builder()" in $cfg)
  assert equal (wezterm settings) { color_scheme: "nustro-x" }
  assert equal (wezterm status | select included config_exists) { included: true, config_exists: true }
}

def "test set puts the line before the final return of an existing config, once, after a backup" [] {
  let fake = fake-wezterm
  let cfg = $fake.config | path join wezterm.lua
  "local wezterm = require 'wezterm'\nlocal cfg = wezterm.config_builder()\ncfg.font_size = 11\n\nreturn cfg\n" | save $cfg
  wezterm set { color_scheme: "nustro-x" }
  wezterm set { font_size: 14 }
  let lines = open --raw $cfg | lines
  assert equal ($lines | last 3) ["-- Added by Nustro; `wezterm reset` removes it again." ($INCLUDE | str replace "apply(config)" "apply(cfg)") "return cfg"] ($lines | to nuon)
  assert equal ($lines | where {|l| $l =~ '(?i)nustro' } | length) 2 "the line is added once"
  assert equal ($lines | first 3) ["local wezterm = require 'wezterm'" "local cfg = wezterm.config_builder()" "cfg.font_size = 11"] "their lines are untouched"
  assert equal (glob ($cfg + ".backup-*") | length) 1
}

def "test set refuses a config that does not end with a named return, and says what to add" [] {
  let fake = fake-wezterm
  let cfg = $fake.config | path join wezterm.lua
  "return {\n  font_size = 11,\n}\n" | save $cfg
  let err = try { wezterm set { color_scheme: "nustro-x" }; null } catch {|e| $e }
  assert ($err.msg | str contains "does not end with") $err.msg
  assert ($err.details.help | str contains $INCLUDE) $err.details.help
  assert equal (open --raw $cfg | lines | length) 3 "their file is left alone"
}

def "test set rewrites our file whole, sorted, in Lua, and a null drops a key" [] {
  let fake = fake-wezterm
  wezterm set { font_size: 14, color_scheme: "nustro-x", default_prog: ["/usr/local/bin/nu" "-l"], font_family: "Hack Nerd Font" }
  let ours = open --raw ($fake.config | path join nustro.lua) | lines
  assert equal ($ours | where {|l| $l starts-with "  " and ($l | str ends-with ",") }) [
    '  color_scheme = "nustro-x",'
    '  default_prog = { "/usr/local/bin/nu", "-l" },'
    '  font = wezterm.font("Hack Nerd Font"),'
    '  font_size = 14,'
  ]
  assert equal ($ours | last) "return M"
  assert equal (wezterm settings) { color_scheme: "nustro-x", default_prog: ["/usr/local/bin/nu" "-l"], font_family: "Hack Nerd Font", font_size: 14 }
  wezterm set { font_size: null, font_family: "FiraCode Nerd Font" }
  assert equal (wezterm settings) { color_scheme: "nustro-x", default_prog: ["/usr/local/bin/nu" "-l"], font_family: "FiraCode Nerd Font" }
}

def "test set escapes a Windows path in a Lua string" [] {
  let fake = fake-wezterm
  wezterm set { default_prog: ['C:\Program Files\nu\nu.exe' "-l"] }
  let ours = open --raw ($fake.config | path join nustro.lua)
  assert ($ours | str contains '{ "C:\\Program Files\\nu\\nu.exe", "-l" }') $ours
  assert equal (wezterm settings | get default_prog) ['C:\Program Files\nu\nu.exe' "-l"]
}

def "test set puts our file back when WezTerm reports an error, and removes a first one" [] {
  let fake = fake-wezterm
  "Your configuration specifies color_scheme=\"nope\" but that scheme was not found" | save ($fake.root | path join error)
  let err = try { wezterm set { color_scheme: "nope" }; null } catch {|e| $e.msg }
  assert ($err | str contains "WezTerm rejected") $err
  assert not (($fake.config | path join nustro.lua) | path exists) "a rejected first write leaves no file"
  rm ($fake.root | path join error)
  wezterm set { color_scheme: "good" }
  "bad key" | save ($fake.root | path join error)
  let err = try { wezterm set { color_scheme: "worse" }; null } catch {|e| $e.details.labels.0.text }
  assert ($err | str contains "bad key") $err
  assert equal (wezterm settings) { color_scheme: "good" } "the previous file is back"
  # Validation loads the config WezTerm reads, with our file applied.
  let call = wezterm-calls $fake | where {|c| "ls-fonts" in $c } | last
  assert equal ($call | first 2) ["--config-file" ($fake.config | path join wezterm.lua)]
}

def "test reset removes our file and the two lines, keeps the backup" [] {
  let fake = fake-wezterm
  let cfg = $fake.config | path join wezterm.lua
  "local wezterm = require 'wezterm'\nlocal config = wezterm.config_builder()\nreturn config\n" | save $cfg
  wezterm set { color_scheme: "nustro-x" }
  wezterm reset
  assert not (($fake.config | path join nustro.lua) | path exists)
  assert equal (open --raw $cfg) "local wezterm = require 'wezterm'\nlocal config = wezterm.config_builder()\nreturn config\n"
  assert equal (glob ($cfg + ".backup-*") | length) 1
  assert equal (wezterm status | select included) { included: false }
}

def "test live font_family is what ls-fonts resolves for the loaded config" [] {
  let fake = fake-wezterm
  "Hack Nerd Font" | save ($fake.root | path join faces)
  assert equal (wezterm live font_family) "JetBrains Mono" "nothing configured: the built-in"
  wezterm set { font_family: "Hack Nerd Font" }
  assert equal (wezterm live font_family) "Hack Nerd Font"
  assert equal (wezterm live color_scheme) null "the other keys are ours or nothing"
}

def "test face asks with the family alone and reads the resolved primary font" [] {
  let fake = fake-wezterm
  "Hack Nerd Font" | save ($fake.root | path join faces)
  assert equal (wezterm face "Hack Nerd Font") "Hack Nerd Font"
  assert equal (wezterm face "Nope Nerd Font") "JetBrains Mono"
  let call = wezterm-calls $fake | where {|c| "ls-fonts" in $c } | first
  assert equal $call ["--config" 'font=wezterm.font("Hack Nerd Font")' "ls-fonts"]
}

def "test shell writes default_prog with -l and --reset drops it" [] {
  let fake = fake-wezterm
  terminal shell
  assert equal (wezterm settings | get default_prog) [(terminal nu-path) "-l"]
  terminal shell --reset
  assert equal (wezterm settings | get -o default_prog) null
}

def "test reload is true: WezTerm reloads by itself" [] {
  let fake = fake-wezterm
  assert equal (wezterm reload) true
  assert equal (terminal reload) true
}

# ── through the registry ──────────────────────────────────────────────────────

def "test theme use writes a scheme file and points WezTerm at it" [] {
  let fake = fake-wezterm
  theme use onedark
  let dir = theme state-dir | path join wezterm
  let file = $dir | path join nustro-onedark.toml
  assert ($file | path exists) $file
  let toml = open --raw $file | from toml
  assert equal $toml.metadata.name "nustro-onedark"
  assert equal ($toml.colors.ansi | length) 8
  assert equal ($toml.colors.brights | length) 8
  assert equal $toml.colors.background "#1e222a"
  assert equal (wezterm settings) { color_scheme: "nustro-onedark", color_scheme_dirs: [$dir] }
  assert equal (theme status | select name terminal terminal_theme icon) { name: onedark, terminal: wezterm, terminal_theme: "nustro-onedark", icon: null }
  assert equal (theme current | select name tier) { name: onedark, tier: palette }
}

def "test theme use of a palette that only extends a Ghostty theme is an error before anything is written" [] {
  let fake = fake-wezterm
  # A palette with no sixteen of its own, extending a theme no Ghostty has:
  # nothing anywhere WezTerm could be given.
  let dir = $nu.config-path | path dirname | path join themes palettes
  mkdir $dir
  { name: "Nowhere", ghostty: "No Such Theme", colours: {}, roles: {} } | to nuon | save ($dir | path join nowhere.nuon)
  let err = try { theme use Nowhere; null } catch {|e| $e.msg }
  assert ($err | str contains "no colours WezTerm could be given") $err
  assert equal (wezterm settings) {}
}

def "test theme icon is Ghostty only" [] {
  let fake = fake-wezterm
  let err = try { theme icon; null } catch {|e| $e.msg }
  assert ($err | str contains "Ghostty's") $err
}

def "test font use writes the family WezTerm reports, with a size, and font size alone changes it" [] {
  let fake = fake-wezterm
  "Hack Nerd Font" | save ($fake.root | path join faces)
  assert equal (font list | where installed | get font) [Hack]
  font use Hack --size 15
  assert equal (wezterm settings | select font_family font_size) { font_family: "Hack Nerd Font", font_size: 15 }
  assert equal (font list | where current | get font) [Hack]
  font size 14.5
  assert equal (wezterm settings | get font_size) 14.5
  font use Hack
  assert equal (wezterm settings | get font_size) 14.5 "a use without a size keeps the size"
  font size --reset
  assert equal (wezterm settings | get -o font_size) null
  assert equal (wezterm settings | get font_family) "Hack Nerd Font" "the family is untouched"
}

def "test font preview opens a window through --config font" [] {
  let fake = fake-wezterm
  "Hack Nerd Font" | save ($fake.root | path join faces)
  font preview Hack
  let call = wezterm-calls $fake | where {|c| "start" in $c } | first
  assert equal ($call | first 4) ["--config" 'font=wezterm.font("Hack Nerd Font")' "--config" "font_size=14"]
  assert ("--always-new-process" in $call)
  assert equal ($call | skip until {|a| $a == "--" } | get 1) $nu.current-exe
}
