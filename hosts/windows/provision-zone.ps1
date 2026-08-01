# Push this repo into a zone and run its provisioning. Idempotent.
#
#     .\provision-zone.ps1 -Zone work
#     .\provision-zone.ps1 -Zone work -SkipPackages   # user-level config only
#
# ASCII only. Windows PowerShell 5.1 reads .ps1 as ANSI without a BOM.
#
# WHY PUSH INSTEAD OF CLONE
#
# The zones cannot see C:\ (decisions/0002) and cannot all read this repo from
# GitHub: it sits in the personal token's repository selection, so dev-work gets a
# 404 and dev-external holds no credentials at all by design (decisions/0006).
#
# Widening the work token to include an infrastructure repo would weaken the
# separation for a non-project reason. Pushing from the host is better anyway -
# external never gets a full checkout of anything it does not need.
#
# dev-personal CAN clone this repo normally, and may prefer to.

param(
    [string]$Zone,
    [switch]$All,

    [switch]$SkipPackages,
    [switch]$SkipVerify,

    # Agent CLIs are a separate step because claude alone pulls a ~275 MB native
    # binary. verify.sh asserts them, so a freshly provisioned zone will not be
    # green until this has been run once.
    [switch]$WithAgents,

    # Clone the zone's repositories from config.json into ~/code.
    [switch]$WithRepos
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\config.ps1')

$cfg = Get-SetupConfig
if (-not $Zone -and -not $All) { throw "specify -Zone <name> or -All" }
$zoneList = if ($All) { @($cfg.zones | ForEach-Object { $_.name }) } else { @($Zone) }

foreach ($Zone in $zoneList) {

$z        = Get-ZoneConfig -Config $cfg -Zone $Zone
$distro   = Get-ZoneDistro -Config $cfg -Zone $Zone
$user     = if ($z.user) { $z.user } else { 'dev' }
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$remote   = "/home/$user/setup"

if (-not (Test-Path (Join-Path $repoRoot 'env/bootstrap.sh'))) {
    throw "repo root looks wrong: $repoRoot"
}

Write-Host "=== $distro ==="
Write-Host "source: $repoRoot"

# --- transfer --------------------------------------------------------------
# Staged through a tar file and fed in with cmd's redirection rather than a
# PowerShell pipeline: PowerShell re-encodes bytes crossing a native-command
# pipe, which corrupts a tar stream.
$tmp = Join-Path $env:TEMP "setup-$Zone-$PID.tar"
try {
    tar -cf $tmp -C $repoRoot --exclude='.git' .
    if ($LASTEXITCODE -ne 0) { throw "tar failed with exit $LASTEXITCODE" }

    $unpack = "rm -rf $remote && mkdir -p $remote && tar -xf - -C $remote && chmod +x $remote/env/*.sh $remote/verify/*.sh"
    cmd /c "wsl.exe -d $distro -- bash -c `"$unpack`" < `"$tmp`""
    if ($LASTEXITCODE -ne 0) { throw "transfer failed with exit $LASTEXITCODE" }
    Write-Host "transferred to $remote"
}
finally {
    Remove-Item $tmp -ErrorAction SilentlyContinue
}

# config.json and overrides/ may sit beside the template or one level above it, but
# inside the zone the layout is always flat. Normalising here keeps every in-zone
# script free of layout guessing.
$instanceRoot = Get-InstanceRoot
if ($instanceRoot -ne $repoRoot) {
    $extra = Join-Path $env:TEMP "setup-instance-$Zone-$PID.tar"
    try {
        $paths = @('config.json')
        if (Test-Path (Join-Path $instanceRoot 'overrides')) { $paths += 'overrides' }
        tar -cf $extra -C $instanceRoot --exclude='.git' $paths
        if ($LASTEXITCODE -ne 0) { throw "tar of instance files failed with exit $LASTEXITCODE" }

        $unpack2 = "tar -xf - -C $remote && chmod -R +x $remote/overrides 2>/dev/null; true"
        cmd /c "wsl.exe -d $distro -- bash -c `"$unpack2`" < `"$extra`""
        if ($LASTEXITCODE -ne 0) { throw "transfer of instance files failed with exit $LASTEXITCODE" }
        Write-Host "overlaid config.json and overrides/ from $instanceRoot"
    }
    finally {
        Remove-Item $extra -ErrorAction SilentlyContinue
    }
}

# --- system packages (root) ------------------------------------------------
if (-not $SkipPackages) {
    Write-Host ""
    wsl.exe -d $distro -u root -- "$remote/env/packages.sh" --zone $Zone
    if ($LASTEXITCODE -ne 0) { throw "packages.sh failed with exit $LASTEXITCODE" }
}

# --- user environment ------------------------------------------------------
Write-Host ""
wsl.exe -d $distro -- "$remote/env/bootstrap.sh" --zone $Zone
if ($LASTEXITCODE -ne 0) { throw "bootstrap.sh failed with exit $LASTEXITCODE" }

# --- agent CLIs ------------------------------------------------------------
if ($WithAgents) {
    Write-Host ""
    wsl.exe -d $distro -- bash -lc "$remote/env/agents.sh"
    if ($LASTEXITCODE -ne 0) { throw "agents.sh failed with exit $LASTEXITCODE" }
}

# --- repositories ----------------------------------------------------------
if ($WithRepos) {
    Write-Host ""
    wsl.exe -d $distro -- bash -lc "$remote/env/clone-repos.sh --zone $Zone"
    if ($LASTEXITCODE -ne 0) { throw "clone-repos.sh failed with exit $LASTEXITCODE" }
}

# --- verify ----------------------------------------------------------------
if (-not $SkipVerify) {
    Write-Host ""
    # Login shell: the toolchain is on PATH via ~/.profile, and a bare
    # `wsl -d X -- cmd` reads no shell configuration at all. See env/README.md.
    wsl.exe -d $distro -- bash -lc "$remote/verify/verify.sh --zone $Zone"
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Warning "verify reported failures for $distro"
        exit 1
    }
}

# --- overrides -------------------------------------------------------------
# Optional per-user extension point on the host side. See overrides/README.md.
$overrideHook = Join-Path $repoRoot 'overrides\hosts\windows\post-provision.ps1'
if (Test-Path $overrideHook) {
    Write-Host ""
    Write-Host "--- overrides ---"
    & $overrideHook -Zone $Zone
    if ($LASTEXITCODE -ne 0) { throw "override post-provision failed with exit $LASTEXITCODE" }
}

Write-Host ""
}  # foreach zone
