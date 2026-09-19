#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Pulls locally modified settings into core/ and re-renders.

.DESCRIPTION
    Reverse of install: reads the installed provider settings file
    (~/.config/opencode/opencode.jsonc), strips any generated policy permissions,
    and writes the user settings back into core/providers/.

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

# --- opencode config ---------------------------------------------------------
$openCodeInstalled = Join-Path $HomeDir '.config/opencode/opencode.jsonc'
$openCodeBuild = Join-Path $BuildDir 'opencode/opencode.jsonc'
$openCodeCore = Join-Path $CoreDir 'providers/opencode/opencode.json'

if (Test-Path $openCodeInstalled) {
    $installedSha = Get-FileSha256 -Path $openCodeInstalled
    $buildSha = Get-FileSha256 -Path $openCodeBuild

    if ($installedSha -ne $buildSha) {
        $installed = Get-Content -Path $openCodeInstalled -Raw | ConvertFrom-Json
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
}

# --- hermes config -----------------------------------------------------------
# The generated approvals block is delimited by markers, so stripping it is a text
# operation. That is deliberate: PowerShell has no built-in YAML parser, and a
# hand-rolled one would be a worse dependency than a pair of comment lines.
$hermesInstalled = Join-Path $HomeDir 'AppData/Local/hermes/config.yaml'
$hermesBuild = Join-Path $BuildDir 'hermes/config.yaml'
$hermesCore = Join-Path $CoreDir 'providers/hermes/config.yaml'

if (Test-Path $hermesInstalled) {
    $installedSha = Get-FileSha256 -Path $hermesInstalled
    $buildSha = Get-FileSha256 -Path $hermesBuild

    if ($installedSha -ne $buildSha) {
        $text = (Get-Content -Path $hermesInstalled -Raw) -replace "`r`n", "`n"
        $endMarker = '# --- end generated ---'
        $markerIndex = $text.IndexOf($endMarker)

        if ($markerIndex -lt 0) {
            Write-Host "error: $hermesInstalled has no mewai generated block. Reinstall before reversing, otherwise the generated rules would be written back into source."
            exit 1
        }

        $stripped = $text.Substring($markerIndex + $endMarker.Length).TrimStart("`n")

        if ($DryRun) {
            Write-Host "would reverse ~/AppData/Local/hermes/config.yaml -> core/providers/hermes/config.yaml"
        }
        else {
            Write-Utf8NoBom -Path $hermesCore -Content $stripped
            Write-Host "reversed ~/AppData/Local/hermes/config.yaml -> core/providers/hermes/config.yaml"
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
