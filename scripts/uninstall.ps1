#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Removes the files mewai installs, after backing them up.

.DESCRIPTION
    Use this to clear provider config back to a blank state before a first install,
    or to back mewai out entirely.

    Two deliberate safety properties:

    - It reports what it would do and changes nothing unless you pass -Confirm.
    - It only removes paths listed in build/manifest.json, plus skill directories
      under the two skill roots. It never touches credentials, sessions, history,
      caches, or runtime databases.

    Everything removed is copied to ~/.mewai/backups/<timestamp>/ first.
#>
[CmdletBinding()]
param(
    [switch]$Confirm,
    [switch]$IncludeUnmanagedSkills
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ManifestPath = Join-Path $RepoRoot 'build/manifest.json'
$HomeDir = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }
$BackupRoot = Join-Path $HomeDir ".mewai/backups/uninstall-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

if (-not (Test-Path $ManifestPath)) {
    Write-Host 'error: build/manifest.json not found. Run scripts/render.ps1 first.'
    exit 1
}

$manifest = Get-Content -Path $ManifestPath -Raw | ConvertFrom-Json

$targets = [System.Collections.Generic.List[string]]::new()
foreach ($entry in $manifest.entries) {
    $targets.Add($entry.install)
}

if ($IncludeUnmanagedSkills) {
    $managed = @{}
    foreach ($entry in $manifest.entries) { $managed[$entry.install] = $true }

    foreach ($root in @('~/.claude/skills', '~/.agents/skills', '~/.gemini/skills')) {
        $rootPath = Join-Path $HomeDir $root.Substring(2)
        if (-not (Test-Path $rootPath)) { continue }

        foreach ($dir in Get-ChildItem -Path $rootPath -Directory) {
            if (-not $managed.ContainsKey("$root/$($dir.Name)/SKILL.md")) {
                $targets.Add("$root/$($dir.Name)")
            }
        }
    }
}

$removed = 0
$absent = 0

foreach ($target in $targets) {
    $path = Join-Path $HomeDir $target.Substring(2)

    if (-not (Test-Path $path)) {
        $absent++
        continue
    }

    if (-not $Confirm) {
        Write-Host "would remove $target"
        $removed++
        continue
    }

    $backupPath = Join-Path $BackupRoot ($target -replace '^~[/\\]', '' -replace '[/\\]', '_')
    New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
    Copy-Item -Path $path -Destination $backupPath -Recurse -Force

    Remove-Item -Path $path -Recurse -Force
    Write-Host "removed $target"
    $removed++
}

# Removing a skill's SKILL.md leaves its directory behind. Prune only directories
# that are now empty, and only directly under the skill roots. Never walk further up:
# deleting a non-empty parent is where an uninstall script turns into a mistake.
if ($Confirm) {
    foreach ($root in @('~/.claude/skills', '~/.agents/skills', '~/.gemini/skills')) {
        $rootPath = Join-Path $HomeDir $root.Substring(2)
        if (-not (Test-Path $rootPath)) { continue }

        foreach ($dir in Get-ChildItem -Path $rootPath -Directory) {
            if (-not (Get-ChildItem -Path $dir.FullName -Force)) {
                Remove-Item -Path $dir.FullName -Force
            }
        }
    }
}

Write-Host ''
if ($Confirm) {
    Write-Host "removed $removed path(s), $absent already absent"
    if ($removed -gt 0) { Write-Host "backups in $BackupRoot" }
}
else {
    Write-Host "would remove $removed path(s), $absent already absent"
    Write-Host 'Nothing was changed. Pass -Confirm to actually remove them.'
    if (-not $IncludeUnmanagedSkills) {
        Write-Host 'Pass -IncludeUnmanagedSkills to also remove skills mewai does not manage.'
    }
}
