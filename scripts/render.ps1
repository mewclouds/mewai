#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Renders core/ into build/ and writes build/manifest.json.

.DESCRIPTION
    This is the only script that contains rendering logic. The installers read the
    manifest and copy files, so adding a second installer language does not
    duplicate any of the work done here.

    Rendering is pure: the same core/ produces byte-identical build/ output. CI
    depends on that, because it re-renders and fails when git reports a diff.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$CoreDir = Join-Path $RepoRoot 'core'
$BuildDir = Join-Path $RepoRoot 'build'

# Every provider renders the same instruction file. Only the filename and the
# install path differ, so a rule cannot drift between providers.
$SharedModules = @('base.md')

# One entry per provider, holding everything that differs. Adding a provider is
# adding a row here. A null SkillsInstallRoot means the provider already reads a
# root another provider installs to, so mewai renders no second copy for it.
$Providers = @(
    @{
        Name               = 'opencode'
        InstructionFile    = 'AGENTS.md'
        InstructionInstall = '~/.config/opencode/AGENTS.md'
        SkillsInstallRoot  = '~/.agents/skills'
    },
    @{
        Name               = 'antigravity'
        InstructionFile    = 'GEMINI.md'
        InstructionInstall = '~/.gemini/GEMINI.md'
        SkillsInstallRoot  = '~/.gemini/skills'
    },
    @{
        Name               = 'codex'
        InstructionFile    = 'AGENTS.md'
        InstructionInstall = '~/.codex/AGENTS.md'
        SkillsInstallRoot  = $null
    }
)

function Get-Sha256 {
    param([string]$Path)
    (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-RenderedFile {
    <#
        Writes UTF-8 without a BOM and with LF endings regardless of host platform.
        Without this, rendering on Windows and rendering in Linux CI produce
        different bytes and the render-is-clean check fails for no real reason.
    #>
    param(
        [string]$Path,
        [string]$Content
    )

    $normalized = $Content -replace "`r`n", "`n"
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $normalized, $utf8NoBom)
}

function Read-Module {
    param([string]$RelativePath)

    $path = Join-Path $CoreDir (Join-Path 'instructions' $RelativePath)
    if (-not (Test-Path $path)) {
        throw "instruction module not found: $RelativePath"
    }

    ((Get-Content -Path $path -Raw) -replace "`r`n", "`n").TrimEnd("`n")
}

function Get-Policy {
    $path = Join-Path $CoreDir 'policy/policy.json'
    if (-not (Test-Path $path)) {
        throw 'core/policy/policy.json not found'
    }

    $policy = Get-Content -Path $path -Raw | ConvertFrom-Json
    foreach ($rule in $policy.rules) {
        if ($rule.decision -notin @('confirm', 'forbid')) {
            throw "rule '$($rule.id)' has unknown decision '$($rule.decision)'"
        }
        if ([string]::IsNullOrWhiteSpace($rule.why)) {
            throw "rule '$($rule.id)' has no 'why'. Every boundary states its reason."
        }
    }
    $policy
}

function ConvertTo-OpenCodeReadPattern {
    <#
        Turns a policy read path into OpenCode permission.read patterns.

        OpenCode matches file paths and expands a leading tilde, so the
        repository-relative "./" prefix means nothing there. A path without one
        also gets a "**/" variant, because the same secret file at a nested path
        is the same secret.
    #>
    param([string]$Path)

    $normalized = $Path -replace '^\./', ''
    if ($normalized.StartsWith('~')) {
        return @($normalized)
    }

    $patterns = @($normalized)
    if (-not $normalized.StartsWith('**/')) {
        $patterns += "**/$normalized"
    }
    $patterns
}

function New-OpenCodeSettings {
    <#
        Emits the complete OpenCode config: the base settings from
        core/providers/opencode/opencode.json with the rendered permission block
        injected.

        OpenCode evaluates permission patterns last-match-wins, so tier order in
        the emitted object is part of the meaning. Ask first, deny last. There
        is one bash matcher. Unmatched commands fall through to OpenCode's default
        of allow.
    #>
    param([object]$Policy)

    $basePath = Join-Path $CoreDir 'providers/opencode/opencode.json'
    if (-not (Test-Path $basePath)) {
        throw 'core/providers/opencode/opencode.json not found'
    }
    $base = Get-Content -Path $basePath -Raw | ConvertFrom-Json

    $buckets = @{ ask = @(); deny = @() }
    $keyFor = @{ confirm = 'ask'; forbid = 'deny' }

    # An ordinal comparer, not [ordered]@{}. PowerShell's default ordered
    # hashtable compares keys case insensitively, which silently collapses a
    # pattern pair that differs only in casing.
    $readPatterns = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)

    foreach ($rule in $Policy.rules) {
        $key = $keyFor[$rule.decision]

        foreach ($command in @($rule.commands)) {
            if ([string]::IsNullOrWhiteSpace($command)) { continue }

            $buckets[$key] += $command
            $buckets[$key] += "$command *"
            $buckets[$key] += "* $command"
            $buckets[$key] += "* $command *"
        }

        if ($rule.PSObject.Properties.Name -contains 'glob_rules') {
            foreach ($raw in $rule.glob_rules) {
                $buckets[$key] += $raw
            }
        }

        if ($rule.PSObject.Properties.Name -contains 'read_paths') {
            foreach ($path in $rule.read_paths) {
                foreach ($pattern in (ConvertTo-OpenCodeReadPattern -Path $path)) {
                    if ($readPatterns.Contains($pattern)) { $readPatterns.Remove($pattern) }
                    $readPatterns[$pattern] = $key
                }
            }
        }
    }

    $bash = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)
    foreach ($tier in @('ask', 'deny')) {
        foreach ($pattern in $buckets[$tier]) {
            if ($bash.Contains($pattern)) { $bash.Remove($pattern) }
            $bash[$pattern] = $tier
        }
    }

    $settings = [ordered]@{}
    foreach ($property in $base.PSObject.Properties) {
        if ($property.Name -eq 'permission') {
            throw 'core/providers/opencode/opencode.json must not set permission. It is generated from core/policy/policy.json.'
        }
        if ($property.Name.StartsWith('_')) { continue }
        $settings[$property.Name] = $property.Value
    }

    $settings['permission'] = [ordered]@{
        bash = $bash
        read = $readPatterns
    }

    ($settings | ConvertTo-Json -Depth 32 -WarningAction Stop) + "`n"
}

function New-CodexRules {
    <#
        Emits Codex execpolicy prefix_rule entries.

        'confirm' emits decision="prompt". Codex execpolicy evaluates
        forbidden > prompt > allow, so prompt rules pause for user
        approval, allow runs unprompted, and forbidden blocks.
    #>
    param([object]$Policy)

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# Rendered by mewai from core/policy/policy.json. Do not edit this file.')
    $lines.Add('# Change the policy and run scripts/render.ps1.')
    $lines.Add('#')
    $lines.Add('# Rules control which commands Codex may run outside the sandbox.')
    $lines.Add('# Behavioral expectations belong in AGENTS.md. Do not blanket-allow shells,')
    $lines.Add('# wrappers, or tools that can hide arbitrary commands.')

    $decisionMap = @{
        'allow'   = 'allow'
        'confirm' = 'prompt'
        'forbid'  = 'forbidden'
    }

    foreach ($rule in $Policy.rules) {
        if (@($rule.commands).Count -eq 0) { continue }

        $decision = $decisionMap[$rule.decision]

        $lines.Add('')
        $lines.Add("# $($rule.id): $($rule.why)")

        foreach ($command in $rule.commands) {
            $words = $command -split '\s+' | Where-Object { $_ }
            $pattern = ($words | ForEach-Object { '"' + $_ + '"' }) -join ', '

            $lines.Add('prefix_rule(')
            $lines.Add("    pattern=[$pattern],")
            $lines.Add("    decision=`"$decision`",")
            if ($decision -ne 'allow') {
                $lines.Add("    justification=`"$($rule.why)`",")
            }
            $lines.Add(')')
        }
    }

    ($lines -join "`n") + "`n"
}

function New-InstructionFile {
    $sections = foreach ($module in $SharedModules) { Read-Module -RelativePath $module }

    $header = @(
        "<!-- Rendered by mewai from core/instructions/. Do not edit this file. -->"
        "<!-- Change the source module and run scripts/render.ps1. -->"
    ) -join "`n"

    ($header + "`n`n" + ($sections -join "`n`n") + "`n")
}

# --- render ------------------------------------------------------------------

if (Test-Path $BuildDir) {
    Remove-Item -Path $BuildDir -Recurse -Force
}

$manifestEntries = [System.Collections.Generic.List[object]]::new()

# Every provider gets byte-identical content. Only the filename and the install
# path differ.
$instructionBody = New-InstructionFile
$instructionSources = @($SharedModules) | ForEach-Object { "core/instructions/$_" }

foreach ($provider in $Providers) {
    $target = Join-Path (Join-Path $BuildDir $provider.Name) $provider.InstructionFile
    Write-RenderedFile -Path $target -Content $instructionBody

    $manifestEntries.Add([ordered]@{
        build   = "build/$($provider.Name)/$($provider.InstructionFile)"
        install = $provider.InstructionInstall
        action  = 'copy'
        sources = $instructionSources
        sha256  = Get-Sha256 -Path $target
    })
}

$policy = Get-Policy

$configTargets = @(
    @{
        Build   = 'build/opencode/opencode.jsonc'
        Install = '~/.config/opencode/opencode.jsonc'
        Content = New-OpenCodeSettings -Policy $policy
        Sources = @('core/providers/opencode/opencode.json', 'core/policy/policy.json')
    },
    @{
        Build   = 'build/codex/rules/default.rules'
        Install = '~/.codex/rules/default.rules'
        Content = New-CodexRules -Policy $policy
        Sources = @('core/policy/policy.json')
    },
    @{
        Build   = 'build/codex/config.toml'
        Install = '~/.codex/config.toml'
        Content = (Get-Content -Path (Join-Path $CoreDir 'providers/codex/config.toml') -Raw)
        Sources = @('core/providers/codex/config.toml')
    }
)

foreach ($target in $configTargets) {
    $path = Join-Path $RepoRoot $target.Build
    Write-RenderedFile -Path $path -Content $target.Content

    $manifestEntries.Add([ordered]@{
        build   = $target.Build
        install = $target.Install
        action  = 'copy'
        sources = $target.Sources
        sha256  = Get-Sha256 -Path $path
    })
}

# Skills are provider-neutral, so every provider that needs its own copy gets a
# byte-identical one. This is the drift that started this repository: the same four
# skills lived in two directories as separate files and one of them was edited alone.
$skillsSource = Join-Path $CoreDir 'skills'
$skillNames = @(Get-ChildItem -Path $skillsSource -Directory | Sort-Object Name)

$skillProviders = @($Providers | Where-Object { $_.SkillsInstallRoot })

foreach ($skill in $skillNames) {
    $content = (Get-Content -Path (Join-Path $skill.FullName 'SKILL.md') -Raw)

    foreach ($provider in $skillProviders) {
        $relative = "build/$($provider.Name)/skills/$($skill.Name)/SKILL.md"
        $path = Join-Path $RepoRoot $relative
        Write-RenderedFile -Path $path -Content $content

        $manifestEntries.Add([ordered]@{
            build   = $relative
            install = "$($provider.SkillsInstallRoot)/$($skill.Name)/SKILL.md"
            action  = 'copy'
            sources = @("core/skills/$($skill.Name)/SKILL.md")
            sha256  = Get-Sha256 -Path $path
        })
    }
}

$manifest = [ordered]@{
    version   = 1
    generator = 'scripts/render.ps1'
    entries   = $manifestEntries
}

Write-RenderedFile -Path (Join-Path $BuildDir 'manifest.json') `
    -Content (($manifest | ConvertTo-Json -Depth 32 -WarningAction Stop) + "`n")

Write-Host "rendered $($manifestEntries.Count) file(s) into build/"
