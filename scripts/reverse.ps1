#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pulls locally modified settings into core/ and re-renders.

.DESCRIPTION
    Reverse of install: reads installed provider settings files (~/.claude/settings.json
    and ~/.codex/config.toml), strips any generated policy permissions, and writes
    the user settings back into core/providers/.

    Only settings files are reversed. Skills, instructions, and policy rules are
    never reversed.
#>
[CmdletBinding()]
param(
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$CoreDir = Join-Path $RepoRoot 'core'
$BuildDir = Join-Path $RepoRoot 'build'
$ManifestPath = Join-Path $BuildDir 'manifest.json'
$HomeDir = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }

if (-not (Test-Path $ManifestPath)) {
    Write-Host 'error: build/manifest.json not found. Run scripts/render.ps1 first.'
    exit 1
}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)
    $normalized = $Content -replace "`r`n", "`n"
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $normalized, $utf8NoBom)
}

function Get-FileSha256 {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$reversedCount = 0

# --- claude settings ---------------------------------------------------------
$claudeInstalled = Join-Path $HomeDir '.claude/settings.json'
$claudeBuild = Join-Path $BuildDir 'claude/settings.json'
$claudeCore = Join-Path $CoreDir 'providers/claude/settings.json'

if (Test-Path $claudeInstalled) {
    $installedSha = Get-FileSha256 -Path $claudeInstalled
    $buildSha = Get-FileSha256 -Path $claudeBuild

    if ($installedSha -ne $buildSha) {
        $installed = Get-Content -Path $claudeInstalled -Raw | ConvertFrom-Json
        $coreExisting = if (Test-Path $claudeCore) { Get-Content -Path $claudeCore -Raw | ConvertFrom-Json } else { $null }

        $reversedClaude = [ordered]@{}

        $topComment = if ($coreExisting -and ($coreExisting.PSObject.Properties.Name -contains '_comment')) {
            $coreExisting._comment
        } else {
            'Base Claude Code settings owned by mewai. The allow, ask, and deny arrays under permissions are generated from core/policy/policy.json by scripts/render.ps1 and must not be set here. Everything else under permissions, including defaultMode, is yours to edit.'
        }
        $reversedClaude['_comment'] = $topComment

        $permissions = [ordered]@{}
        $permComment = if ($coreExisting -and ($coreExisting.PSObject.Properties.Name -contains 'permissions') -and ($coreExisting.permissions.PSObject.Properties.Name -contains '_comment')) {
            $coreExisting.permissions._comment
        } else {
            'auto mode is what makes the three-tier policy work. Ask rules prompt, deny rules block, and allow rules resolve without reaching the classifier. Under bypassPermissions the ask tier is silently inert. Do not set disableAutoMode here: it turns auto mode off.'
        }
        $permissions['_comment'] = $permComment

        if ($installed.PSObject.Properties.Name -contains 'permissions') {
            foreach ($prop in $installed.permissions.PSObject.Properties) {
                if ($prop.Name.StartsWith('_') -or $prop.Name -in @('allow', 'ask', 'deny')) { continue }
                $permissions[$prop.Name] = $prop.Value
            }
        }
        $reversedClaude['permissions'] = $permissions

        foreach ($prop in $installed.PSObject.Properties) {
            if ($prop.Name.StartsWith('_') -or $prop.Name -eq 'permissions') { continue }
            $reversedClaude[$prop.Name] = $prop.Value
        }

        $claudeJson = ($reversedClaude | ConvertTo-Json -Depth 10) + "`n"

        if ($DryRun) {
            Write-Host "would reverse ~/.claude/settings.json -> core/providers/claude/settings.json"
        }
        else {
            Write-Utf8NoBom -Path $claudeCore -Content $claudeJson
            Write-Host "reversed ~/.claude/settings.json -> core/providers/claude/settings.json"
        }
        $reversedCount++
    }
}

# --- codex config ------------------------------------------------------------
$codexInstalled = Join-Path $HomeDir '.codex/config.toml'
$codexBuild = Join-Path $BuildDir 'codex/config.toml'
$codexCore = Join-Path $CoreDir 'providers/codex/config.toml'

if (Test-Path $codexInstalled) {
    $installedSha = Get-FileSha256 -Path $codexInstalled
    $buildSha = Get-FileSha256 -Path $codexBuild

    if ($installedSha -ne $buildSha) {
        $content = Get-Content -Path $codexInstalled -Raw

        if ($DryRun) {
            Write-Host "would reverse ~/.codex/config.toml -> core/providers/codex/config.toml"
        }
        else {
            Write-Utf8NoBom -Path $codexCore -Content $content
            Write-Host "reversed ~/.codex/config.toml -> core/providers/codex/config.toml"
        }
        $reversedCount++
    }
}

# --- finalize ----------------------------------------------------------------
if ($reversedCount -eq 0) {
    Write-Host 'all settings are in sync with core/'
    exit 0
}

if ($DryRun) {
    Write-Host ''
    Write-Host "would reverse $reversedCount setting file(s)"
}
else {
    Write-Host ''
    & (Join-Path $PSScriptRoot 'render.ps1')
    & (Join-Path $PSScriptRoot 'install.ps1')
    Write-Host ''
    Write-Host "reversed $reversedCount setting file(s), re-rendered, and installed"
}
