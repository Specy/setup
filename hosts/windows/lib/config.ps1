# Shared config loader for the Windows-side scripts. Dot-source it:
#
#     . (Join-Path $PSScriptRoot '..\lib\config.ps1')
#     $cfg = Get-SetupConfig
#
# ASCII only. Windows PowerShell 5.1 reads .ps1 as ANSI without a BOM.

# The template root: <repo>/hosts/windows/lib/config.ps1 is three levels down.
function Get-TemplateRoot {
    return (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
}

# Where config.json and overrides/ live. Two supported layouts:
#
#   setup/config.json              cloned on its own
#   my-setup/config.json           this repo used as a submodule under your own
#   my-setup/setup/...
#
# so the same template works whether you use it directly or nest it in a private
# repo alongside your own config.
function Get-InstanceRoot {
    $template = Get-TemplateRoot
    if (Test-Path (Join-Path $template 'config.json')) { return $template }
    $parent = Split-Path -Parent $template
    if ($parent -and (Test-Path (Join-Path $parent 'config.json'))) { return $parent }
    return $template
}

function Get-SetupConfig {
    param([string]$Path)

    if (-not $Path) { $Path = Join-Path (Get-InstanceRoot) 'config.json' }

    if (-not (Test-Path $Path)) {
        throw "config.json not found at $Path. Copy config.example.json to config.json and edit it."
    }

    $raw = Get-Content $Path -Raw
    if ($raw -match '(?m)^\s*//') {
        throw "config.json contains // comments, which PowerShell 5.1 cannot parse. Remove them."
    }
    $cfg = $raw | ConvertFrom-Json

    if (-not $cfg.windowsUser -or $cfg.windowsUser -like 'REPLACE_*') {
        throw "config.json: windowsUser is not set."
    }
    if (-not $cfg.zones -or @($cfg.zones).Count -eq 0) {
        throw "config.json: no zones defined."
    }

    # uid collisions are the failure mode from decisions/0016, and they present as an
    # unrelated systemd error hours later. Catch them here instead.
    $uids = @($cfg.zones | ForEach-Object { $_.uid })
    if ($cfg.daily -and $cfg.daily.uid) { $uids += $cfg.daily.uid }
    $dupes = $uids | Group-Object | Where-Object { $_.Count -gt 1 }
    if ($dupes) {
        throw "config.json: uid $($dupes[0].Name) is used by more than one zone. Every distro needs a distinct uid - see decisions/0016."
    }

    return $cfg
}

function Get-ZoneConfig {
    param([Parameter(Mandatory)]$Config, [Parameter(Mandatory)][string]$Zone)
    $z = $Config.zones | Where-Object { $_.name -eq $Zone }
    if (-not $z) {
        throw "zone '$Zone' is not in config.json (have: $(($Config.zones | ForEach-Object { $_.name }) -join ', '))"
    }
    return $z
}

function Get-ZoneDistro {
    param([Parameter(Mandatory)]$Config, [Parameter(Mandatory)][string]$Zone)
    return "dev-$Zone"
}
