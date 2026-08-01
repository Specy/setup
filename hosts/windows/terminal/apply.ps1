# Merge the zone colour schemes and profile settings into Windows Terminal.
# Idempotent - safe to re-run.
#
#     .\apply.ps1
#
# ASCII only. Windows PowerShell 5.1 reads .ps1 as ANSI without a BOM.
#
# Windows Terminal generates the WSL profiles itself, deriving a guid from the
# distro name. This script MATCHES those generated profiles by name and edits
# them in place - it does not create profiles and does not hardcode guids, which
# would only ever be correct on the machine they were copied from.
#
# Everything not listed here is left untouched, and settings.json is backed up
# before every write.

param(
    [string]$SettingsPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\lib\config.ps1')

$cfg = Get-SetupConfig

if (-not $SettingsPath) {
    $candidates = @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
    )
    $SettingsPath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $SettingsPath -or -not (Test-Path $SettingsPath)) {
    throw "Windows Terminal settings.json not found. Launch Terminal once, then re-run."
}
Write-Host "settings: $SettingsPath"

$raw = Get-Content $SettingsPath -Raw
# ConvertFrom-Json in PS 5.1 rejects JSONC. Terminal writes plain JSON by default,
# but a hand-edited file may carry comments - fail clearly rather than corrupt it.
if ($raw -match '(?m)^\s*//') {
    throw "settings.json contains // comments, which PowerShell 5.1 cannot parse. Merge by hand, or strip them first."
}
$settings   = $raw | ConvertFrom-Json
$newSchemes = Get-Content (Join-Path $PSScriptRoot 'schemes.json') -Raw | ConvertFrom-Json

Copy-Item $SettingsPath "$SettingsPath.bak" -Force
Write-Host "backup:   $SettingsPath.bak"

# --- schemes: match by name ------------------------------------------------
$schemeList = @()
if ($settings.schemes) { $schemeList = @($settings.schemes) }
foreach ($s in $newSchemes) {
    if ($schemeList | Where-Object { $_.name -eq $s.name }) {
        $schemeList = @($schemeList | Where-Object { $_.name -ne $s.name })
    }
    $schemeList += $s
}
$settings.schemes = $schemeList
Write-Host "  $($newSchemes.Count) scheme(s) merged"

# --- profiles: match generated WSL profiles by distro name -----------------
# A zone with no colour of its own falls back to the neutral scheme rather than
# being skipped, so every zone still gets a readable window.
$wanted = @{}
foreach ($z in $cfg.zones) {
    $distro = Get-ZoneDistro -Config $cfg -Zone $z.name
    $scheme = "zone-$($z.name)"
    if (-not ($newSchemes | Where-Object { $_.name -eq $scheme })) { $scheme = 'zone-daily' }
    $user = if ($z.user) { $z.user } else { 'dev' }
    $wanted[$distro] = @{ name = $z.name; scheme = $scheme; dir = "//wsl$/$distro/home/$user/code" }
}
if ($cfg.daily -and $cfg.daily.distro) {
    $wanted[$cfg.daily.distro] = @{
        name = 'daily'; scheme = 'zone-daily'; dir = "//wsl$/$($cfg.daily.distro)/home/$($cfg.daily.user)"
    }
}

$profileList = @()
if ($settings.profiles.list) { $profileList = @($settings.profiles.list) }

foreach ($distro in $wanted.Keys) {
    $w = $wanted[$distro]
    # Terminal names the generated profile after the distro; once this script has
    # run it carries our name instead, so match on either.
    $p = $profileList | Where-Object { $_.name -eq $distro -or $_.name -eq $w.name } | Select-Object -First 1
    if (-not $p) {
        Write-Warning "no Terminal profile found for $distro - launch Terminal once after creating the distro"
        continue
    }
    foreach ($kv in @(
        @{ k = 'name';                     v = $w.name },
        @{ k = 'tabTitle';                 v = $w.name },
        @{ k = 'colorScheme';              v = $w.scheme },
        @{ k = 'suppressApplicationTitle'; v = $true },
        @{ k = 'startingDirectory';        v = $w.dir })) {
        if ($p.PSObject.Properties.Name -contains $kv.k) { $p.($kv.k) = $kv.v }
        else { $p | Add-Member -NotePropertyName $kv.k -NotePropertyValue $kv.v }
    }
    Write-Host "  profile updated: $distro -> $($w.name) ($($w.scheme))"
}
$settings.profiles.list = $profileList

# Depth must be generous: the default of 2 silently flattens nested objects.
$settings | ConvertTo-Json -Depth 32 | Set-Content $SettingsPath -Encoding UTF8

Write-Host ""
Write-Host "Restart Windows Terminal to see the changes."
Write-Host "To undo: copy $SettingsPath.bak back over $SettingsPath"
