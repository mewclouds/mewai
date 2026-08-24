#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Reports which installed files still match the rendered source.

.DESCRIPTION
    This answers the question the repository exists for: what has changed and what
    has not. Four skills were copied into two locations by hand and one of them
    silently drifted. Nothing reported it. This does.

    Exit code is 1 when anything is modified or missing, so it works as a check.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ManifestPath = Join-Path $RepoRoot 'build/manifest.json'
$HomeDir = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }

if (-not (Test-Path $ManifestPath)) {
    Write-Host 'error: build/manifest.json not found. Run scripts/render.ps1 first.'
    exit 1
}

$manifest = Get-Content -Path $ManifestPath -Raw | ConvertFrom-Json

$inSync = [System.Collections.Generic.List[string]]::new()
$modified = [System.Collections.Generic.List[string]]::new()
$missing = [System.Collections.Generic.List[string]]::new()

foreach ($entry in $manifest.entries) {
    $target = if ($entry.install.StartsWith('~/')) {
        Join-Path $HomeDir $entry.install.Substring(2)
    }
    else {
        $entry.install
    }

    if (-not (Test-Path $target)) {
        $missing.Add($entry.install)
        continue
    }

    $actual = (Get-FileHash -Path $target -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -eq $entry.sha256) {
        $inSync.Add($entry.install)
    }
    else {
        $modified.Add($entry.install)
    }
}

# A skill deleted from core/skills stays installed forever unless something looks
# for it. An orphan still loads into context and still gets invoked.
$orphans = [System.Collections.Generic.List[string]]::new()
$managed = @{}
foreach ($entry in $manifest.entries) { $managed[$entry.install] = $true }

foreach ($root in @('~/.claude/skills', '~/.agents/skills', '~/.gemini/skills')) {
    $rootPath = Join-Path $HomeDir $root.Substring(2)
    if (-not (Test-Path $rootPath)) { continue }

    foreach ($dir in Get-ChildItem -Path $rootPath -Directory) {
        if (-not $managed.ContainsKey("$root/$($dir.Name)/SKILL.md")) {
            $orphans.Add("$root/$($dir.Name)")
        }
    }
}

function Write-Section {
    param([string]$Title, [System.Collections.Generic.List[string]]$Items)
    if ($Items.Count -eq 0) { return }
    Write-Host ''
    Write-Host "${Title}:"
    foreach ($item in $Items) { Write-Host "  $item" }
}

Write-Section -Title 'in sync' -Items $inSync
Write-Section -Title 'modified on disk' -Items $modified
Write-Section -Title 'not installed' -Items $missing
Write-Section -Title 'installed but not managed by mewai' -Items $orphans

Write-Host ''
Write-Host ("{0} in sync, {1} modified, {2} not installed, {3} unmanaged" -f
    $inSync.Count, $modified.Count, $missing.Count, $orphans.Count)

if ($modified.Count -gt 0) {
    Write-Host ''
    Write-Host 'A modified file was edited after install, or the source changed and was not reinstalled.'
    Write-Host 'Run scripts/install.ps1 to overwrite, after saving anything worth keeping.'
}

if ($modified.Count -gt 0 -or $missing.Count -gt 0) { exit 1 }
