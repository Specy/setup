# Create and harden one dev zone. Idempotent - safe to re-run.
#
#     .\create-zone.ps1 -Zone work
#     .\create-zone.ps1 -All
#
# Everything comes from config.json. ASCII only: Windows PowerShell 5.1 reads
# .ps1 as ANSI without a BOM, so a non-ASCII character is a parser error.
#
# Does everything except set the account password, which needs an interactive
# terminal. The script reports the command to run.
#
# See decisions/0002-wsl-conf-hardening.md.

param(
    [string]$Zone,
    [switch]$All
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\lib\config.ps1')

$cfg = Get-SetupConfig
if (-not $Zone -and -not $All) { throw "specify -Zone <name> or -All" }
$targets = if ($All) { @($cfg.zones | ForEach-Object { $_.name }) } else { @($Zone) }

foreach ($zoneName in $targets) {
    $z        = Get-ZoneConfig -Config $cfg -Zone $zoneName
    $distro   = Get-ZoneDistro -Config $cfg -Zone $zoneName
    $location = Join-Path $cfg.installRoot $distro
    $confPath = Join-Path $PSScriptRoot "wsl.conf.template"
    $user     = if ($z.user) { $z.user } else { 'dev' }
    $uid      = $z.uid

    if (-not (Test-Path $confPath)) { throw "missing $confPath" }

    Write-Host "=== $distro (uid $uid) ==="

    # --- install ----------------------------------------------------------
    $existing = (wsl.exe --list --quiet) -replace "`0", '' -split "`r?`n" | ForEach-Object { $_.Trim() }
    if ($existing -contains $distro) {
        Write-Host "distro already exists, skipping install"
    }
    else {
        Write-Host "installing $($cfg.image) as $distro at $location"
        wsl.exe --install $cfg.image --name $distro --location $location --no-launch
        if ($LASTEXITCODE -ne 0) { throw "wsl --install failed with exit $LASTEXITCODE" }
    }

    # --- user -------------------------------------------------------------
    # Must exist before wsl.conf is applied: [user] default refers to it.
    #
    # The uid is per-zone and NOT cosmetic. All WSL2 distros share one kernel and
    # systemd's user@<uid>.service collides across them: only the first distro to
    # claim a uid gets a working user manager, every later one fails with
    #   Failed to spawn executor: Device or resource busy
    # and stays degraded for that whole boot. See decisions/0016.
    $hasUser = wsl.exe -d $distro -u root -- getent passwd $user
    if ($LASTEXITCODE -eq 0 -and $hasUser) {
        $currentUid = (wsl.exe -d $distro -u root -- id -u $user) -replace "`0", '' -replace "\s", ''
        if ($currentUid -eq "$uid") {
            Write-Host "user '$user' already exists with uid $uid"
        }
        else {
            Write-Host "user '$user' has uid $currentUid, reassigning to $uid"
            wsl.exe --terminate $distro | Out-Null
            wsl.exe -d $distro -u root -- bash -c "groupmod -g $uid $user && usermod -u $uid -g $uid $user && chown -R ${uid}:${uid} /home/$user"
            if ($LASTEXITCODE -ne 0) { throw "uid reassignment failed with exit $LASTEXITCODE" }
        }
    }
    else {
        Write-Host "creating user '$user' with uid $uid"
        wsl.exe -d $distro -u root -- bash -c "groupadd -g $uid $user && useradd -u $uid -g $uid -m -s /bin/bash -G sudo $user"
        if ($LASTEXITCODE -ne 0) { throw "useradd failed with exit $LASTEXITCODE" }
    }

    # --- wsl.conf ---------------------------------------------------------
    # Rendered from the template, then transferred as base64 so the bytes arrive
    # exactly as written. Piping text through PowerShell to a native command
    # re-encodes it and can introduce CRLF or a BOM, either of which WSL's ini
    # parser handles badly.
    Write-Host "deploying /etc/wsl.conf"
    $conf = (Get-Content $confPath -Raw).Replace('{{HOSTNAME}}', $distro).Replace('{{USER}}', $user)
    $b64  = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($conf))
    wsl.exe -d $distro -u root -- bash -c "echo '$b64' | base64 -d > /etc/wsl.conf && chmod 644 /etc/wsl.conf"
    if ($LASTEXITCODE -ne 0) { throw "failed to write /etc/wsl.conf (exit $LASTEXITCODE)" }

    # The distro is launched once above to create the user, while automount is
    # still at its default, which leaves an empty /mnt/c behind. Harmless, but it
    # makes a directory-existence check look like automount is still on.
    wsl.exe -d $distro -u root -- bash -c 'rmdir /mnt/c 2>/dev/null; true' | Out-Null

    Write-Host "terminating to apply configuration"
    wsl.exe --terminate $distro | Out-Null
    Start-Sleep -Seconds 2

    # --- report -----------------------------------------------------------
    Write-Host ""
    Write-Host "--- verification ---"
    $check = @'
printf "user:      %s (uid %s)\n" "$(id -un)" "$(id -u)"
printf "hostname:  %s\n" "$(hostname)"
printf "user mgr:  user@%s = %s\n" "$(id -u)" "$(systemctl is-active user@$(id -u).service)"
if grep -qE "^[^ ]+ /mnt/[a-z] " /proc/mounts; then
    printf "automount: MOUNTED - WRONG\n"
else
    printf "automount: no windows drive - correct\n"
fi
if ls /proc/sys/fs/binfmt_misc/ 2>/dev/null | grep -qi wsl; then
    printf "interop:   ENABLED - WRONG\n"
else
    printf "interop:   disabled - correct\n"
fi
case "$PATH" in
    */mnt/c*) printf "PATH:      contains windows paths - WRONG\n" ;;
    *)        printf "PATH:      clean\n" ;;
esac
'@
    $checkB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($check))
    wsl.exe -d $distro -- bash -c "echo '$checkB64' | base64 -d | bash"

    # passwd needs a terminal, so the script reports rather than sets it.
    $pwStatus = (wsl.exe -d $distro -u root -- bash -c "passwd -S $user | cut -d' ' -f2") -replace "`0", '' -replace "\s", ''
    Write-Host ""
    if ($pwStatus -eq 'P') {
        Write-Host "password:  set"
    }
    else {
        Write-Host "password:  NOT SET (status '$pwStatus') - the account is locked and sudo"
        Write-Host "           will not work. Run this in an interactive terminal:"
        Write-Host ""
        Write-Host "    wsl -d $distro -u root passwd $user"
    }
    Write-Host ""
}
