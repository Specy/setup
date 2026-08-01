# Host applications. Idempotent - safe to re-run.
#
# ASCII only in this file. Windows PowerShell 5.1 reads .ps1 as ANSI unless the file
# has a UTF-8 BOM, so non-ASCII characters become mojibake and break parsing.
#
# The Windows host deliberately carries NO language toolchains: no Node, no Python,
# no package managers. Those live inside the WSL zones.
# See decisions/0001-zone-isolation-model.md.
#
# Adding an app to this machine means adding it here, not installing it by hand.

$ErrorActionPreference = 'Stop'

# Required = the machine is not correctly provisioned without it.
# Optional = nice to have; a failure is reported but is not an error.
$packages = @(
    # Needed to bootstrap this repo on a fresh machine.
    @{ Id = 'Git.Git';                    Required = $true },
    @{ Id = 'GitHub.cli';                 Required = $true },

    # Editor. Connects into the zones via Remote-WSL; extensions that touch project
    # code must be installed in the WSL remote, not on the host.
    # See decisions/0008-agent-execution-boundary.md.
    @{ Id = 'Microsoft.VisualStudioCode'; Required = $true },

    # Terminal and a modern shell. Terminal is usually preinstalled on Win11.
    @{ Id = 'Microsoft.WindowsTerminal';  Required = $true },
    @{ Id = 'Microsoft.PowerShell';       Required = $true },

    # Archive handling. Optional: Windows ships tar.exe, which is the format
    # wsl --export produces, so nothing here depends on 7-Zip.
    @{ Id = '7zip.7zip';                  Required = $false }
)

$installed = @()
$skipped   = @()
$failures  = @()

foreach ($pkg in $packages) {
    $id = $pkg.Id

    $listing = winget list --id $id --exact --accept-source-agreements 2>$null | Out-String
    if ($listing -match [regex]::Escape($id)) {
        Write-Host "already installed: $id"
        $skipped += $id
        continue
    }

    Write-Host "installing: $id"
    winget install --id $id --exact --silent `
        --accept-source-agreements --accept-package-agreements
    $code = $LASTEXITCODE

    if ($code -eq 0) {
        $installed += $id
    }
    else {
        # 1602 is the MSI code for "user cancelled" - almost always a dismissed
        # UAC prompt rather than a broken package.
        $hint = if ($code -eq 1602) { ' (UAC prompt cancelled)' } else { '' }
        Write-Warning "failed: $id - winget exit $code$hint"
        $failures += [pscustomobject]@{ Id = $id; Code = $code; Required = $pkg.Required }
    }
}

Write-Host ""
Write-Host "installed: $($installed.Count)   already present: $($skipped.Count)   failed: $($failures.Count)"
Write-Host ""
Write-Host "Deliberately NOT installed here:"
Write-Host "  - Docker Desktop    (decisions/0004 - docker runs inside each zone)"
Write-Host "  - Node / Python     (decisions/0001 - toolchains live in WSL)"

if ($failures.Count -eq 0) {
    exit 0
}

Write-Host ""
Write-Host "Failures:"
foreach ($f in $failures) {
    $label = if ($f.Required) { 'REQUIRED' } else { 'optional' }
    Write-Host ("  [{0}] {1} (exit {2})" -f $label, $f.Id, $f.Code)
}
Write-Host ""
Write-Host "Re-running this script retries only what is missing."

# Only a required package failing means the host is not correctly provisioned.
$requiredFailures = @($failures | Where-Object { $_.Required })
if ($requiredFailures.Count -gt 0) {
    exit 1
}
exit 0
