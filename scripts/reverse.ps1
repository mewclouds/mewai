#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pulls locally modified settings into core/ and re-renders.

.DESCRIPTION
    Reverse of install: reads installed provider settings files
    (~/.config/opencode/opencode.jsonc and ~/.codex/config.toml),
    strips any generated policy permissions, and writes the user settings back into
    core/providers/.

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

function Get-NormalizedFileContent {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    (Get-Content -Path $Path -Raw) -replace "`r`n", "`n"
}

function Get-OpenCodeBaseJson {
    param([string]$Path)

    $settings = Get-Content -Path $Path -Raw | ConvertFrom-Json
    $base = [ordered]@{}
    foreach ($property in $settings.PSObject.Properties) {
        if ($property.Name.StartsWith('_') -or $property.Name -eq 'permission') { continue }
        $base[$property.Name] = $property.Value
    }
    $base | ConvertTo-Json -Depth 32 -Compress
}

$openCodeInstalled = Join-Path $HomeDir '.config/opencode/opencode.jsonc'
$openCodeBuild = Join-Path $BuildDir 'opencode/opencode.jsonc'
$openCodeCore = Join-Path $CoreDir 'providers/opencode/opencode.json'
$codexInstalled = Join-Path $HomeDir '.codex/config.toml'
$codexBuild = Join-Path $BuildDir 'codex/config.toml'
$codexCore = Join-Path $CoreDir 'providers/codex/config.toml'

$openCodeNeedsReverse = (Test-Path $openCodeInstalled) -and
    ((Get-FileSha256 -Path $openCodeInstalled) -ne (Get-FileSha256 -Path $openCodeBuild))
$codexNeedsReverse = (Test-Path $codexInstalled) -and
    ((Get-FileSha256 -Path $codexInstalled) -ne (Get-FileSha256 -Path $codexBuild))

$openCodeInstalledSettings = $null
if ($openCodeNeedsReverse) {
    if (-not (Test-Path $openCodeBuild) -or -not (Test-Path $openCodeCore)) {
        throw 'OpenCode reverse needs both the rendered file and its source file.'
    }
    if ((Get-OpenCodeBaseJson -Path $openCodeCore) -cne (Get-OpenCodeBaseJson -Path $openCodeBuild)) {
        throw 'conflict: the OpenCode source and installed file both changed since the last render. Reconcile them before reverse.'
    }
    $openCodeInstalledSettings = Get-Content -Path $openCodeInstalled -Raw | ConvertFrom-Json
}

if ($codexNeedsReverse) {
    if (-not (Test-Path $codexBuild) -or -not (Test-Path $codexCore)) {
        throw 'Codex reverse needs both the rendered file and its source file.'
    }
    if ((Get-NormalizedFileContent -Path $codexCore) -cne (Get-NormalizedFileContent -Path $codexBuild)) {
        throw 'conflict: the Codex source and installed file both changed since the last render. Reconcile them before reverse.'
    }
}

$reversedCount = 0

# --- opencode config ---------------------------------------------------------
if ($openCodeNeedsReverse) {
    $installed = $openCodeInstalledSettings
    $coreExisting = if (Test-Path $openCodeCore) { Get-Content -Path $openCodeCore -Raw | ConvertFrom-Json } else { $null }

    $reversedOpenCode = [ordered]@{}

    $topComment = if ($coreExisting -and ($coreExisting.PSObject.Properties.Name -contains '_comment')) {
        $coreExisting._comment
    } else {
        'Base OpenCode settings owned by mewai. The permission block is generated from core/policy/policy.json by scripts/render.ps1 and must not be set here. Everything else is yours to edit.'
    }
    $reversedOpenCode['_comment'] = $topComment

    foreach ($prop in $installed.PSObject.Properties) {
        if ($prop.Name.StartsWith('_') -or $prop.Name -eq 'permission') { continue }
        $reversedOpenCode[$prop.Name] = $prop.Value
    }

    $openCodeJson = ($reversedOpenCode | ConvertTo-Json -Depth 32 -WarningAction Stop) + "`n"

    if ($DryRun) {
        Write-Host "would reverse ~/.config/opencode/opencode.jsonc -> core/providers/opencode/opencode.json"
    }
    else {
        Write-Utf8NoBom -Path $openCodeCore -Content $openCodeJson
        Write-Host "reversed ~/.config/opencode/opencode.jsonc -> core/providers/opencode/opencode.json"
    }
    $reversedCount++
}

# --- codex config ------------------------------------------------------------
if ($codexNeedsReverse) {
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
