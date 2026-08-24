#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Copies rendered files from build/ to their installed locations.

.DESCRIPTION
    This script holds no rendering logic. It reads build/manifest.json and copies.
    Keeping it dumb is what lets a PowerShell installer and a shell installer
    coexist without drifting apart, because there is nothing in either of them
    complex enough to disagree about.

    Run scripts/render.ps1 first. Existing targets are backed up before replacement.
#>
[CmdletBinding()]
param(
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ManifestPath = Join-Path $RepoRoot 'build/manifest.json'
$HomeDir = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }
$BackupRoot = Join-Path $HomeDir ".mewai/backups/$(Get-Date -Format 'yyyyMMdd-HHmmss')"

if (-not (Test-Path $ManifestPath)) {
    Write-Host 'error: build/manifest.json not found. Run scripts/render.ps1 first.'
    exit 1
}

$manifest = Get-Content -Path $ManifestPath -Raw | ConvertFrom-Json

function Resolve-InstallPath {
    param([string]$Path)
    if ($Path.StartsWith('~/')) {
        Join-Path $HomeDir $Path.Substring(2)
    }
    else {
        $Path
    }
}

$installed = 0
$unchanged = 0
$backedUp = 0

function Backup-Target {
    param([string]$Target, [string]$InstallPath)

    $backupPath = Join-Path $BackupRoot ($InstallPath -replace '^~[/\\]', '' -replace '[/\\]', '_')
    if ($DryRun) {
        Write-Host "would back up $Target to $backupPath"
    }
    else {
        New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
        Copy-Item -Path $Target -Destination $backupPath -Force
    }
}

foreach ($entry in $manifest.entries) {
    if ($entry.action -ne 'copy') {
        Write-Host "error: unsupported manifest action '$($entry.action)' for $($entry.build)"
        exit 1
    }

    $source = Join-Path $RepoRoot $entry.build
    $target = Resolve-InstallPath -Path $entry.install

    if (-not (Test-Path $source)) {
        Write-Host "error: rendered file missing: $($entry.build)"
        exit 1
    }

    if (Test-Path $target) {
        $existing = (Get-FileHash -Path $target -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($existing -eq $entry.sha256) {
            $unchanged++
            continue
        }

        # Back up only what is about to be replaced, so a second install of
        # unchanged content leaves no empty backup directory behind.
        Backup-Target -Target $target -InstallPath $entry.install
        $backedUp++
    }

    if ($DryRun) {
        Write-Host "would install $($entry.build) to $target"
    }
    else {
        $targetDir = Split-Path -Parent $target
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
        Copy-Item -Path $source -Destination $target -Force
        Write-Host "installed $target"
    }
    $installed++
}

$verb = if ($DryRun) { 'would install' } else { 'installed' }
Write-Host ''
Write-Host "$verb $installed file(s), $unchanged already current, $backedUp backed up"
if ($backedUp -gt 0 -and -not $DryRun) {
    Write-Host "backups in $BackupRoot"
}
