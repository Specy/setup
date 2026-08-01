# Stage Claude Code and Codex conversation history for restore into the WSL zones.
# Builds a per-zone tree under $Staging; transfer is done separately.
# ASCII only.

param(
    # The folder names that used to sit between the projects root and each repo,
    # e.g. Desktopprojectswork<repo> has the old group 'work'. Include layouts
    # you have since renamed - transcripts outlive directory structures.
    [string[]]$OldGroups = @('work', 'personal', 'external')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\lib\config.ps1')

$Staging = "$env:TEMP\zone-restore"
if (Test-Path $Staging) { Remove-Item $Staging -Recurse -Force }

# repo -> zone, derived from config.json. The local directory name is what appears
# in the old Windows paths, so that is the key.
$cfg = Get-SetupConfig
$repoZone   = @{}
$zoneDistro = @{}
foreach ($z in $cfg.zones) {
    $zoneDistro[$z.name] = Get-ZoneDistro -Config $cfg -Zone $z.name
    foreach ($r in $z.repos) {
        $dir = if ($r -is [string]) { $r.Split('/')[-1] }
               elseif ($r.dir)      { $r.dir }
               else                 { $r.remote.Split('/')[-1] }
        $repoZone[$dir] = $z.name
    }
}
if ($repoZone.Count -eq 0) { throw "no repositories in config.json - nothing to route" }
$winUser = $cfg.windowsUser

# Old Windows project root -> repo name.
function Resolve-Repo([string]$cwd) {
    if (-not $cwd) { return $null }
    $n = $cwd -replace '/', '\'
    if ($n -match '(?i)\\Desktop\\projects\\($($OldGroups -join '|'))\\([^\\]+)') {
        $repo = $Matches[2]
        if ($repoZone.ContainsKey($repo)) { return $repo }
    }
    return $null
}

# Claude Code derives a project directory name from the cwd by replacing every
# non-alphanumeric character with '-'. C:\Users\<you>\Desktop\projects becomes
# C--Users-<you>-Desktop-projects, so /home/dev/code/<repo> becomes -home-dev-code-<repo>.
function Get-ClaudeDirName([string]$posixPath) {
    return ($posixPath -replace '[^a-zA-Z0-9]', '-')
}

function Rewrite-Paths([string]$text, [string]$repo) {
    $new = "/home/dev/code/$repo"
    foreach ($root in $OldGroups) {
        $win = "C:\Users\<you>\Desktop\projects\$root\$repo"
        # As it appears inside JSON string values: backslashes are escaped.
        $text = $text.Replace($win.Replace('\', '\\'), $new)
        # Literal single-backslash and forward-slash variants, just in case.
        $text = $text.Replace($win, $new)
        $text = $text.Replace($win.Replace('\', '/'), $new)
    }
    return $text
}

$summary = @()

# --------------------------------------------------------------------------
# Claude Code
# --------------------------------------------------------------------------
Write-Host "=== Claude Code ==="
$claudeProjects = "$env:USERPROFILE\.claude\projects"
foreach ($dir in Get-ChildItem $claudeProjects -Directory) {
    # Decode the encoded directory name back to something matchable.
    $decoded = $dir.Name -replace '^C--', 'C:\' -replace '-', '\'
    $repo = $null
    foreach ($k in $repoZone.Keys) {
        if ($dir.Name -match "(?i)Desktop-projects-($($OldGroups -join '|'))-$([regex]::Escape($k))$") { $repo = $k; break }
    }
    if (-not $repo) { Write-Host ("  skip  {0}" -f $dir.Name); continue }

    $zone = $repoZone[$repo]
    $target = Join-Path $Staging "$($zoneDistro[$zone])\.claude\projects\$(Get-ClaudeDirName "/home/dev/code/$repo")"
    New-Item -ItemType Directory -Force -Path $target | Out-Null

    $n = 0
    foreach ($f in Get-ChildItem $dir.FullName -Recurse -File) {
        $rel = $f.FullName.Substring($dir.FullName.Length).TrimStart('\')
        $dest = Join-Path $target $rel
        New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
        if ($f.Extension -in @('.jsonl', '.json', '.md', '.txt')) {
            [IO.File]::WriteAllText($dest, (Rewrite-Paths ([IO.File]::ReadAllText($f.FullName)) $repo))
        } else {
            Copy-Item $f.FullName $dest
        }
        $n++
    }
    Write-Host ("  {0,-10} {1,-18} {2,3} files" -f $zone, $repo, $n)
    $summary += [pscustomobject]@{ Tool='claude'; Zone=$zone; Repo=$repo; Files=$n }
}

# --------------------------------------------------------------------------
# Codex
# --------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Codex ==="
$sessRoot = "$env:USERPROFILE\.codex\sessions"
$migratedIds = @{}
$counts = @{}

foreach ($f in Get-ChildItem $sessRoot -Recurse -File -Filter *.jsonl) {
    $first = Get-Content $f.FullName -TotalCount 1 -ErrorAction SilentlyContinue
    if (-not $first) { continue }
    try { $meta = $first | ConvertFrom-Json } catch { continue }
    $repo = Resolve-Repo $meta.payload.cwd
    if (-not $repo) { continue }

    $zone = $repoZone[$repo]
    $rel = $f.FullName.Substring($sessRoot.Length).TrimStart('\')
    $dest = Join-Path $Staging "$($zoneDistro[$zone])\.codex\sessions\$rel"
    New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
    [IO.File]::WriteAllText($dest, (Rewrite-Paths ([IO.File]::ReadAllText($f.FullName)) $repo))

    if ($meta.payload.session_id) { $migratedIds[$meta.payload.session_id] = $zone }
    $key = "$zone/$repo"
    if (-not $counts.ContainsKey($key)) { $counts[$key] = 0 }
    $counts[$key]++
}
foreach ($k in ($counts.Keys | Sort-Object)) {
    $parts = $k -split '/'
    Write-Host ("  {0,-10} {1,-18} {2,3} rollouts" -f $parts[0], $parts[1], $counts[$k])
    $summary += [pscustomobject]@{ Tool='codex'; Zone=$parts[0]; Repo=$parts[1]; Files=$counts[$k] }
}

# session_index.jsonl carries no cwd, so filter it by the session ids actually moved.
$idxSrc = "$env:USERPROFILE\.codex\session_index.jsonl"
if (Test-Path $idxSrc) {
    $perZone = @{}
    foreach ($line in [IO.File]::ReadAllLines($idxSrc)) {
        if (-not $line.Trim()) { continue }
        try { $o = $line | ConvertFrom-Json } catch { continue }
        if ($o.id -and $migratedIds.ContainsKey($o.id)) {
            $z = $migratedIds[$o.id]
            if (-not $perZone.ContainsKey($z)) { $perZone[$z] = New-Object System.Collections.Generic.List[string] }
            $perZone[$z].Add($line)
        }
    }
    foreach ($z in $perZone.Keys) {
        $dest = Join-Path $Staging "$($zoneDistro[$z])\.codex\session_index.jsonl"
        New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
        [IO.File]::WriteAllLines($dest, $perZone[$z])
        Write-Host ("  index     {0,-18} {1,3} entries" -f $z, $perZone[$z].Count)
    }
}

Write-Host ""
Write-Host "=== staged under $Staging ==="
foreach ($d in Get-ChildItem $Staging -Directory) {
    $sz = (Get-ChildItem $d.FullName -Recurse -File | Measure-Object -Property Length -Sum).Sum
    $n = (Get-ChildItem $d.FullName -Recurse -File | Measure-Object).Count
    "  {0,-14} {1,4} files  {2,8:N1} MB" -f $d.Name, $n, ($sz/1MB)
}
