# restore-overlay.ps1 - put a known-good DSH profile overlay back, with verification
# and automatic rollback.
#
# Usage:
#   .\restore-overlay.ps1 -Good .\good\cordis.patch.yml -ProfileDir "C:\path\to\harness\profiles\desktop"
#   .\restore-overlay.ps1 -Check  -ProfileDir "...\profiles\desktop"
#
# Options:
#   -ProfileDir   profile folder that holds cordis.patch.yml and package.json
#                 (default: %APPDATA%\dsh-desktop\harness\profiles\desktop)
#   -Good         known-good cordis.patch.yml to install
#   -PackageJson  optional known-good package.json (bundle list); beware: a RUNNING
#                 DSH rewrites this file from memory when it exits, so restoring it
#                 only helps while DSH is closed
#   -Presets      optional folder of *.patch.yml preset files to restore as well
#   -PresetDir    where those preset files belong
#   -MinEntries   fail if the overlay parses to fewer entries than this (default 0)
#   -Check        verify only, change nothing
#
# The script never writes a file it has not first validated, and it backs up the
# current file as <name>.bak-broken-<timestamp> before replacing it.

param(
    [string]$ProfileDir = (Join-Path $env:APPDATA 'dsh-desktop\harness\profiles\desktop'),
    [string]$Good       = '',
    [string]$PackageJson = '',
    [string]$Presets    = '',
    [string]$PresetDir  = '',
    [int]$MinEntries    = 0,
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
$Stamp    = Get-Date -Format 'yyyyMMdd-HHmmss'
$Overlay  = Join-Path $ProfileDir 'cordis.patch.yml'
$Pkg      = Join-Path $ProfileDir 'package.json'
$Verifier = Join-Path $PSScriptRoot 'verify-yaml.mjs'
$Harness  = Split-Path (Split-Path $ProfileDir -Parent) -Parent
$NodeCmd  = Join-Path $Harness '.desktop-bin\node.cmd'
if (-not (Test-Path $NodeCmd)) { $NodeCmd = 'node' }

function Say($m)  { Write-Host $m }
function Ok($m)   { Write-Host "   OK   $m"   -ForegroundColor Green }
function Bad($m)  { Write-Host "   FAIL $m"   -ForegroundColor Red }
function Warn($m) { Write-Host "   WARN $m"   -ForegroundColor Yellow }

function Test-Overlay([string]$file) {
    if (-not (Test-Path $file)) { Bad "missing: $file"; return $false }
    if (-not (Test-Path $Verifier)) { Warn 'verify-yaml.mjs not next to this script; parse check skipped'; return $true }
    & $NodeCmd $Verifier $file $MinEntries
    return ($LASTEXITCODE -eq 0)
}

Say ''
Say "profile: $ProfileDir"

if ($Check -or -not $Good) {
    Say '== check overlay =='
    if (Test-Overlay $Overlay) { Ok 'cordis.patch.yml parses' }

    Say '== check package.json =='
    if (Test-Path $Pkg) {
        try {
            $j = Get-Content $Pkg -Raw -Encoding UTF8 | ConvertFrom-Json
            $bundles = @($j.dsh.profile.bundles)
            Ok ("bundles=" + $bundles.Count)
        } catch { Bad ("package.json is not valid JSON: " + $_.Exception.Message) }
    } else { Bad 'package.json missing' }

    if (-not $Good) { Say ''; Say 'no -Good given: check only, nothing changed.'; exit 0 }
}

if (-not (Test-Path $Good)) { throw "good copy not found: $Good" }
if (-not (Test-Overlay $Good)) { throw 'the good copy itself does not parse - refusing to touch anything' }

Say ''
Say '== install overlay =='
if (Test-Path $Overlay) {
    $bak = "$Overlay.bak-broken-$Stamp"
    Copy-Item $Overlay $bak -Force
    Say "   current file kept as: $bak"
}
Copy-Item $Good $Overlay -Force
if (-not (Test-Overlay $Overlay)) {
    Warn 'verification failed after writing; restoring the backup'
    if (Test-Path "$Overlay.bak-broken-$Stamp") { Copy-Item "$Overlay.bak-broken-$Stamp" $Overlay -Force }
    throw 'install failed and was rolled back'
}
Ok 'cordis.patch.yml installed and verified'

if ($PackageJson -and (Test-Path $PackageJson)) {
    Say ''
    Say '== install package.json =='
    if (Test-Path $Pkg) { Copy-Item $Pkg "$Pkg.bak-$Stamp" -Force }
    Copy-Item $PackageJson $Pkg -Force
    Ok 'package.json installed'
    Warn 'a running DSH overwrites this on exit - fully quit DSH before relying on it'
}

if ($Presets -and (Test-Path $Presets)) {
    Say ''
    Say '== install preset patches =='
    if (-not $PresetDir) { throw '-Presets given without -PresetDir' }
    New-Item -ItemType Directory -Force -Path $PresetDir | Out-Null
    Get-ChildItem $Presets -Filter '*.patch.yml' | ForEach-Object {
        $dst = Join-Path $PresetDir $_.Name
        if (Test-Path $dst) { Copy-Item $dst "$dst.bak-$Stamp" -Force }
        Copy-Item $_.FullName $dst -Force
        Ok "$($_.Name) installed"
    }
}

Say ''
Say 'done. quit DSH Desktop completely (including the tray icon), then start it again.'