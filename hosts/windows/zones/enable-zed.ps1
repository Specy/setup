# Let Zed open projects in a zone, without re-enabling automount.
# Idempotent - safe to re-run.
#
#     .\enable-zed.ps1              # all dev zones
#     .\enable-zed.ps1 -Zone work
#
# ASCII only. Windows PowerShell 5.1 reads .ps1 as ANSI without a BOM.
#
# THE PROBLEM
#
# Zed's WSL remoting runs, on the Windows side:
#     wsl.exe --distribution dev-personal --exec wslpath -u "C:/Users/.../Zed/remote_servers/..."
# and wslpath can only translate a Windows path when that drive is mounted through
# drvfs. decisions/0002 sets automount = false, so there is no /mnt/c and wslpath
# returns its input unchanged. Zed reports:
#     failed ensuring server binary: ... failed: wslpath: C:/Users/...
#
# THE FIX
#
# Mount ONLY Zed's remote_servers directory, read-only, at the exact path wslpath
# will produce. wslpath is satisfied, Zed finds its server binary, and the rest of
# C: stays invisible - `ls /mnt/c/Users/<you>/Desktop` still fails.
#
# Read-only on purpose: every zone mounts the same Windows directory, so a writable
# mount would let the least trusted zone replace a server binary that another zone
# later executes. See decisions/0021-zed-remote-servers-mount.md.

param(
    [string]$Zone,

    # Flip to read-write if Zed turns out to need to write here. Understand the
    # cross-zone consequence in 0021 before using it.
    [switch]$Writable
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\lib\config.ps1')

$cfg   = Get-SetupConfig
$zones = if ($Zone) { @($Zone) } else { @($cfg.zones | ForEach-Object { $_.name }) }
$opts  = if ($Writable) { 'rw,noatime' } else { 'ro,noatime' }

$user     = $cfg.windowsUser
$winDir   = "C:\Users\$user\AppData\Local\Zed\remote_servers"
$posixDir = "/mnt/c/Users/$user/AppData/Local/Zed/remote_servers"

if (-not (Test-Path $winDir)) {
    Write-Warning "$winDir does not exist yet. Launch Zed once, then re-run."
}

# fstab needs the source escaped for the shell, and the mount point to already exist.
$fstabLine = "$winDir $posixDir drvfs $opts 0 0"

foreach ($z in $zones) {
    $distro = Get-ZoneDistro -Config $cfg -Zone $z
    Write-Host "=== $distro ==="

    $script = @"
set -e
mkdir -p '$posixDir'
# Replace any previous managed entry rather than appending duplicates.
sed -i '\#$posixDir#d' /etc/fstab 2>/dev/null || true
printf '%s\n' '$fstabLine' >> /etc/fstab
mountpoint -q '$posixDir' && umount '$posixDir' || true
mount '$posixDir'
printf '  mounted %s\n' "`$(grep -c '$posixDir' /proc/mounts)"
"@
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script))
    wsl.exe -d $distro -u root -- bash -c "echo '$b64' | base64 -d | bash"
    if ($LASTEXITCODE -ne 0) { Write-Warning "failed for $distro"; continue }

    # Prove wslpath is satisfied and that the rest of C: is still not reachable.
    wsl.exe -d $distro -- bash -c "printf '  wslpath -> %s\n' `"`$(wslpath -u 'C:/Users/$user/AppData/Local/Zed/remote_servers')`"; ls /mnt/c/Users/$user/Desktop >/dev/null 2>&1 && printf '  WARNING: Desktop is reachable\n' || printf '  rest of C: still hidden\n'"
}

Write-Host ""
Write-Host "Mounts are in /etc/fstab, so they survive a restart."
Write-Host "In Zed, open a WSL project as usual. If it reports it cannot write the"
Write-Host "server binary, re-run this with -Writable and read 0021 first."
