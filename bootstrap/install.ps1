# install.ps1 — get Nushell, get this distro, hand over to install.nu
#
#   irm https://raw.githubusercontent.com/AlfoldiMate/Nustro/main/bootstrap/install.ps1 | iex
#   .\install.ps1 -Yes                      take every default, ask nothing
#   .\install.ps1 -Dir C:\src\nu-distro     clone somewhere else
#   .\install.ps1 -Pass '--minimal','--skip-deps'   anything install.nu takes is handed on to it
#
# The Windows half of bootstrap/install.sh, and it has the same two jobs: make
# sure `nu` exists, and put the distro on disk. Everything after that is
# Nushell — install.nu is the installer, written in the shell it installs.
# A `nu` older than the distro requires is upgraded first: install.nu would
# refuse it.
#
# Piped into `iex` there are no parameters, so every one of them also reads an
# environment variable: NUSTRO_REPO, NUSTRO_DIR,
# NUSTRO_REF, NUSHELL_VERSION, NUSHELL_BIN_DIR.

[CmdletBinding()]
param(
  [string] $Repo    = $env:NUSTRO_REPO,
  [string] $Dir     = $env:NUSTRO_DIR,
  [string] $Ref     = $env:NUSTRO_REF,
  [string] $Version = $env:NUSHELL_VERSION,
  [string] $BinDir  = $env:NUSHELL_BIN_DIR,
  [string[]] $Pass  = @(),
  [switch] $Yes,
  [switch] $NoInstall
)

$ErrorActionPreference = 'Stop'

# The oldest Nushell the distro runs on — nustro.nuon's `requires_nu`, which
# cannot be read before the clone. Raised together with it and the CI pin.
$MinNu = [version]'0.116'

if (-not $Repo)   { $Repo   = 'https://github.com/AlfoldiMate/Nustro.git' }
if (-not $Dir)    { $Dir    = Join-Path $env:LOCALAPPDATA 'nustro' }
if (-not $BinDir) { $BinDir = Join-Path $env:LOCALAPPDATA 'Programs\nu' }

function Step($m) { Write-Host $m -ForegroundColor Cyan }
function Info($m) { Write-Host "  $m" }
function Note($m) { Write-Host "  $m" -ForegroundColor DarkGray }
function Die($m)  { Write-Error $m; exit 1 }
function Have($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }

function Ask($question, $defaultYes = $true) {
  if ($Yes) { return $true }
  $hint = if ($defaultYes) { '[Y/n]' } else { '[y/N]' }
  $reply = Read-Host "  $question $hint"
  if (-not $reply) { return $defaultYes }
  return $reply -match '^(y|yes)$'
}

# ── Nushell ───────────────────────────────────────────────────────────────────

function Latest-Nu {
  if ($Version) { return $Version }
  # A rate-limited or offline machine falls back to the version this distro
  # is verified against rather than failing.
  try {
    (Invoke-RestMethod 'https://api.github.com/repos/nushell/nushell/releases/latest').tag_name
  } catch { "$MinNu.0" }
}

# Major and minor, as numbers: 0.99 is older than 0.116.
function New-Enough($nu) {
  $text = (& $nu --version 2>$null | Select-Object -First 1)
  $v = $null
  if (-not [version]::TryParse(($text -replace '[^0-9.].*$', ''), [ref]$v)) { return $false }
  return ($v.Major -gt $MinNu.Major) -or ($v.Major -eq $MinNu.Major -and $v.Minor -ge $MinNu.Minor)
}

function Install-NuZip {
  $v = Latest-Nu
  $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'aarch64' } else { 'x86_64' }
  $url = "https://github.com/nushell/nushell/releases/download/$v/nu-$v-$arch-pc-windows-msvc.zip"
  Info "downloading $url"
  $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid())
  New-Item -ItemType Directory -Path $tmp | Out-Null
  try {
    Invoke-WebRequest $url -OutFile "$tmp\nu.zip"
    Expand-Archive "$tmp\nu.zip" -DestinationPath $tmp -Force
    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
    # nu and the plugins that ship with it have to land in ONE directory:
    # `nu-config plugins add` registers whatever sits next to the nu binary.
    Get-ChildItem $tmp -Recurse -Filter 'nu*.exe' | Copy-Item -Destination $BinDir -Force
    Info "installed nu $v into $BinDir"
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($userPath -notlike "*$BinDir*") {
      [Environment]::SetEnvironmentVariable('Path', "$userPath;$BinDir", 'User')
      Note "added $BinDir to your PATH — new terminals will see it"
    }
    $env:Path = "$env:Path;$BinDir"
  } finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
  return (Join-Path $BinDir 'nu.exe')
}

function Ensure-Nu {
  Step 'Nushell'
  if (Have 'nu') {
    $nu = (Get-Command nu).Source
    Info "$(& $nu --version) at $nu"
    if (New-Enough $nu) { return $nu }
    Info "the distro needs $MinNu or later"
    if ((Have 'winget') -and (Ask 'upgrade it with winget?')) {
      winget upgrade --id Nushell.Nushell --source winget --accept-package-agreements --accept-source-agreements
      if (New-Enough $nu) { return $nu }
      Note 'winget finished but that nu is still the old one — falling back to the release build'
    }
    if (Ask "download the official release build into $BinDir?") {
      $nu = Install-NuZip
      if (-not (New-Enough $nu)) { Die "$nu is still older than $MinNu — set NUSHELL_VERSION to a release that is not" }
      if ((Get-Command nu).Source -ne $nu) { Note "$((Get-Command nu).Source) is still first on PATH — put $BinDir ahead of it, or remove the old one" }
      return $nu
    }
    Die "Nushell $MinNu or later is required — https://www.nushell.sh/book/installation.html"
  }
  Info 'not installed'
  # winget first: it is what will also upgrade nu later. The release zip is
  # the fallback that always works, and it is what -Yes takes.
  if ((Have 'winget') -and (Ask 'install it with winget?')) {
    winget install --id Nushell.Nushell --source winget --accept-package-agreements --accept-source-agreements
    # winget puts it on the machine PATH, which this process does not have yet.
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
    if (Have 'nu') { return (Get-Command nu).Source }
    Note 'winget finished but nu is not on PATH yet — falling back to the release build'
  }
  if (Ask "download the official release build into $BinDir?") { return Install-NuZip }
  Die 'Nushell is required — https://www.nushell.sh/book/installation.html'
}

# ── The distro ────────────────────────────────────────────────────────────────

function Get-Distro {
  Step 'Distro'
  if (-not (Have 'git')) { Die "git is needed to clone $Repo" }
  if (Test-Path (Join-Path $Dir '.git')) {
    Info "already at $Dir — updating"
    git -C $Dir pull --ff-only
    if ($LASTEXITCODE -ne 0) { Note 'could not fast-forward; your checkout has local changes' }
  } elseif (Test-Path $Dir) {
    Die "$Dir exists and is not a git checkout — move it, or pass -Dir"
  } else {
    Info "cloning $Repo into $Dir"
    New-Item -ItemType Directory -Path (Split-Path $Dir -Parent) -Force | Out-Null
    git clone --quiet $Repo $Dir
    if ($LASTEXITCODE -ne 0) { Die "clone failed" }
  }
  if ($Ref) {
    git -C $Dir checkout --quiet $Ref
    if ($LASTEXITCODE -ne 0) { Die "$Ref is not a branch, tag or commit of $Repo" }
    Info "checked out $Ref"
  }
  if (-not (Test-Path (Join-Path $Dir 'install.nu'))) {
    Die "$Dir has no install.nu — is $Repo the right repository?"
  }
}

# ── Hand over ─────────────────────────────────────────────────────────────────

Write-Host "Nustro  $Repo" -ForegroundColor Cyan
Write-Host ''
$nu = Ensure-Nu
Write-Host ''
Get-Distro
Write-Host ''

$installer = Join-Path $Dir 'install.nu'
if ($NoInstall) {
  Step 'Next'
  Info "$nu $installer"
} elseif ($Yes) {
  & $nu $installer --defaults @Pass
} else {
  & $nu $installer @Pass
}
# The installer's verdict is this script's: a caller (CI, a provisioning
# script) must not read a failed install as a success.
if (-not $NoInstall -and $LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
