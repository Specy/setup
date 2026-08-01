# Harden the general-purpose distro: keep /mnt/c, lose interop.
# Idempotent - safe to re-run.
#
#     .\harden-daily.ps1
#
# ASCII only. Windows PowerShell 5.1 reads .ps1 as ANSI without a BOM.
#
# This distro is the weakest link if left alone. With interop enabled it can run
#   wsl.exe -d dev-work cat /home/dev/.config/gh/hosts.yml
# which executes as that distro's default user with no password - so the distro
# holding no credentials could read the one holding all of them.
#
# See decisions/0002-wsl-conf-hardening.md.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\lib\config.ps1')

$cfg = Get-SetupConfig
if (-not $cfg.daily -or -not $cfg.daily.distro) {
    Write-Host "config.json has no 'daily' distro - nothing to do."
    return
}

$distro = $cfg.daily.distro
$user   = $cfg.daily.user
if (-not $user -or $user -like 'REPLACE_*') {
    throw "config.json: daily.user must be the existing user inside $distro. Find it with: wsl -d $distro -- whoami"
}

$existing = (wsl.exe --list --quiet) -replace "`0", '' -split "`r?`n" | ForEach-Object { $_.Trim() }
if ($existing -notcontains $distro) { throw "distro '$distro' not found" }

# Confirm the configured user really exists, because a wrong name here silently
# demotes you to root on the next start.
$check = (wsl.exe -d $distro -u root -- getent passwd $user) -replace "`0", ''
if (-not $check) { throw "user '$user' does not exist in $distro - check config.json daily.user" }

Write-Host "=== $distro ==="
Write-Host "backing up existing /etc/wsl.conf to /etc/wsl.conf.bak"
wsl.exe -d $distro -u root -- bash -c 'test -f /etc/wsl.conf && cp -p /etc/wsl.conf /etc/wsl.conf.bak || true'

$tpl  = Get-Content (Join-Path $PSScriptRoot 'wsl.conf.daily.template') -Raw
$conf = $tpl.Replace('{{HOSTNAME}}', 'daily').Replace('{{USER}}', $user)
$b64  = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($conf))
wsl.exe -d $distro -u root -- bash -c "echo '$b64' | base64 -d > /etc/wsl.conf && chmod 644 /etc/wsl.conf"
if ($LASTEXITCODE -ne 0) { throw "failed to write /etc/wsl.conf" }

wsl.exe --terminate $distro | Out-Null
Start-Sleep -Seconds 2

Write-Host "--- verification ---"
$check = @'
printf "user:      %s (uid %s)\n" "$(id -un)" "$(id -u)"
printf "hostname:  %s\n" "$(hostname)"
if grep -qE "^[^ ]+ /mnt/[a-z] " /proc/mounts; then
    printf "automount: mounted - correct for this distro\n"
else
    printf "automount: NOT mounted - expected /mnt/c here\n"
fi
if ls /proc/sys/fs/binfmt_misc/ 2>/dev/null | grep -qi wsl; then
    printf "interop:   ENABLED - WRONG, this is the pivot path\n"
else
    printf "interop:   disabled - correct\n"
fi
'@
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($check))
wsl.exe -d $distro -- bash -c "echo '$b64' | base64 -d | bash"

Write-Host ""
Write-Host "Expect cmd.exe and explorer.exe to stop working from this distro. That is the point."
