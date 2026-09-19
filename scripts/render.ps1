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
param(
    [switch]$Check
)

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
        SkillsInstallRoot  = $null
    },
    @{
        Name               = 'antigravity'
        InstructionFile    = 'GEMINI.md'
        InstructionInstall = '~/.gemini/GEMINI.md'
        SkillsInstallRoot  = '~/.gemini/skills'
    },
    @{
        Name               = 'hermes'
        InstructionFile    = 'SOUL.md'
        InstructionInstall = '~/AppData/Local/hermes/SOUL.md'
        SkillsInstallRoot  = '~/.agents/skills'
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
        if ($rule.PSObject.Properties.Name -contains 'autonomy_omit') {
            if ($rule.autonomy_omit -isnot [bool]) {
                throw "rule '$($rule.id)': autonomy_omit must be true or false."
            }
            if ($rule.autonomy_omit -and $rule.decision -ne 'confirm') {
                throw "rule '$($rule.id)': autonomy_omit is only valid on confirm. A forbid rule cannot be dropped from a provider that runs autonomously."
            }
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

        confirm renders as ask. autonomy_omit is for Hermes, not here.
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

function ConvertTo-HermesGlob {
    <#
        Wraps a pattern so it matches anywhere in the command string, without
        doubling a wildcard the pattern already carries.
    #>
    param([string]$Pattern)

    $glob = $Pattern
    if (-not $glob.StartsWith('*')) { $glob = "*$glob" }
    if (-not $glob.EndsWith('*')) { $glob = "$glob*" }
    $glob
}

function ConvertTo-HermesReadPattern {
    <#
        Turns a policy read path into Hermes deny globs.

        Hermes matches fnmatch against the whole command string, so a bare
        *.env* would also block --env and environment. Anchoring on a path
        separator or on the whitespace that starts an argument keeps the
        pattern to the file it is about.
    #>
    param([string]$Path)

    $core = $Path -replace '^\./', '' -replace '^~/', '' -replace '^\*\*/', ''
    $core = $core -replace '/\*\*$', '/'
    $core = $core -replace '\*\*/', ''

    @("*/$core*", "* $core*")
}

function New-HermesHookRules {
    <#
        Emits the read patterns the pre_tool_call hook matches against.

        approvals.deny only sees terminal commands. read_file is a native Hermes
        tool, so a secret-file rule needs the hook to have any effect there.
    #>
    param([object]$Policy)

    $read = [System.Collections.Generic.List[object]]::new()

    foreach ($rule in $Policy.rules) {
        if ($rule.decision -ne 'forbid') { continue }
        if ($rule.PSObject.Properties.Name -notcontains 'read_paths') { continue }

        $read.Add([ordered]@{
            id       = $rule.id
            why      = $rule.why
            patterns = @(@($rule.read_paths) | ForEach-Object { $_ -replace '^\./', '' })
        })
    }

    (([ordered]@{ read = @($read) } | ConvertTo-Json -Depth 32 -WarningAction Stop) + "`n")
}

function New-HermesConfig {
    <#
        Emits the generated approvals block followed by the base config verbatim.

        approvals.deny is the only Hermes boundary that survives --yolo, /yolo,
        and approvals.mode off, so both forbid and confirm land there. Hermes has
        no prompt-level decision that still works in an autonomous session, so a
        confirm rule with autonomy_omit is left out and runs.

        Every pattern is wrapped in * because Hermes matches against the whole
        command string. That also catches wrappers such as `rtk git push --force`
        without a separate rule.
    #>
    param([object]$Policy, [string]$BaseConfig)

    $deny = [System.Collections.Generic.List[string]]::new()

    foreach ($tier in @('forbid', 'confirm')) {
        foreach ($rule in $Policy.rules) {
            if ($rule.decision -ne $tier) { continue }
            if ($rule.PSObject.Properties.Name -contains 'autonomy_omit' -and $rule.autonomy_omit) {
                continue
            }

            foreach ($command in @($rule.commands)) {
                if ([string]::IsNullOrWhiteSpace($command)) { continue }
                $deny.Add((ConvertTo-HermesGlob -Pattern $command))
            }

            if ($rule.PSObject.Properties.Name -contains 'glob_rules') {
                foreach ($glob in @($rule.glob_rules)) {
                    $deny.Add((ConvertTo-HermesGlob -Pattern $glob))
                }
            }

            if ($rule.PSObject.Properties.Name -contains 'read_paths') {
                foreach ($path in @($rule.read_paths)) {
                    foreach ($pattern in (ConvertTo-HermesReadPattern -Path $path)) {
                        $deny.Add($pattern)
                    }
                }
            }
        }
    }

    $unique = [System.Collections.Generic.List[string]]::new()
    foreach ($pattern in $deny) {
        if (-not $unique.Contains($pattern)) { $unique.Add($pattern) }
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# --- generated by mewai from core/policy/policy.json. Do not edit. ---')
    $lines.Add('# These block unconditionally, before --yolo, /yolo, and approvals.mode off.')
    $lines.Add('# Change core/policy/policy.json and run scripts/render.ps1.')
    $lines.Add('approvals:')
    $lines.Add('  deny:')
    foreach ($pattern in $unique) {
        $lines.Add('    - "' + $pattern + '"')
    }
    $lines.Add('hooks:')
    $lines.Add('  pre_tool_call:')
    $lines.Add('    - matcher: "read_file"')
    $lines.Add('      command: "~/AppData/Local/hermes/hooks/mewai-hook.cmd"')
    $lines.Add('      timeout: 15')
    $lines.Add('      fail_closed: true')
    # Without this the hook is skipped whenever its script hash is not on the
    # allowlist, and a skipped hook is a boundary that silently stopped existing.
    # A re-render changes the hash, so the prompt would fire again every install.
    $lines.Add('hooks_auto_accept: true')
    $lines.Add('# --- end generated ---')
    $lines.Add('')

    ($lines -join "`n") + $BaseConfig
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
        Build   = 'build/hermes/hooks/mewai-hook.ps1'
        Install = '~/AppData/Local/hermes/hooks/mewai-hook.ps1'
        Content = (Get-Content -Path (Join-Path $CoreDir 'providers/hermes/mewai-hook.ps1') -Raw)
        Sources = @('core/providers/hermes/mewai-hook.ps1')
    },
    @{
        Build   = 'build/hermes/hooks/mewai-hook.cmd'
        Install = '~/AppData/Local/hermes/hooks/mewai-hook.cmd'
        Content = (Get-Content -Path (Join-Path $CoreDir 'providers/hermes/mewai-hook.cmd') -Raw)
        Sources = @('core/providers/hermes/mewai-hook.cmd')
    },
    @{
        Build   = 'build/hermes/hooks/rules.json'
        Install = '~/AppData/Local/hermes/hooks/rules.json'
        Content = New-HermesHookRules -Policy $policy
        Sources = @('core/policy/policy.json')
    },
    @{
        Build   = 'build/hermes/config.yaml'
        Install = '~/AppData/Local/hermes/config.yaml'
        Content = New-HermesConfig -Policy $policy -BaseConfig (Get-Content -Path (Join-Path $CoreDir 'providers/hermes/config.yaml') -Raw)
        Sources = @('core/providers/hermes/config.yaml', 'core/policy/policy.json')
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
