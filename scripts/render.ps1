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

# Every provider renders the same instruction file. Only the filename, the install
# path, and any front matter the format requires differ, so a rule cannot drift
# between providers.
$SharedModules = @('base.md')

# One entry per provider, holding everything that differs. Adding a provider is
# adding a row here. A null SkillsInstallRoot means the provider already reads a
# root another provider installs to, so mewai renders no second copy for it.
$Providers = @(
    @{
        Name               = 'claude'
        InstructionFile    = 'CLAUDE.md'
        InstructionInstall = '~/.claude/CLAUDE.md'
        SkillsInstallRoot  = '~/.claude/skills'
    },
    @{
        Name               = 'antigravity'
        InstructionFile    = 'GEMINI.md'
        InstructionInstall = '~/.gemini/GEMINI.md'
        SkillsInstallRoot  = '~/.gemini/skills'
    },
    @{
        Name                    = 'cursor'
        InstructionFile         = 'mewai.mdc'
        InstructionInstall      = '~/.cursor/rules/mewai.mdc'
        SkillsInstallRoot       = $null
        InstructionFrontMatter  = "---`nalwaysApply: true`n---"
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
        if ($rule.decision -notin @('allow', 'confirm', 'forbid')) {
            throw "rule '$($rule.id)' has unknown decision '$($rule.decision)'"
        }
        if ([string]::IsNullOrWhiteSpace($rule.why)) {
            throw "rule '$($rule.id)' has no 'why'. Every boundary states its reason."
        }
        if ($rule.PSObject.Properties.Name -contains 'cursor') {
            $cursorMode = [string]$rule.cursor
            if ($cursorMode -ne 'omit') {
                throw "rule '$($rule.id)' has unknown cursor value '$cursorMode'. Use omit, or omit the field."
            }
            if ($rule.decision -ne 'confirm') {
                throw "rule '$($rule.id)': cursor omit is only valid on confirm. Forbid cannot be dropped from the Cursor hook."
            }
        }
    }
    $policy
}

function New-ClaudeSettings {
    <#
        Emits the complete settings file: the base settings from
        core/providers/claude/settings.json with the rendered permissions injected.

        mewai owns this file outright, so installing is a plain copy and drift is a
        hash comparison. Anything you change through /config shows up in `status`,
        which is the point.

        Both Bash() and PowerShell() variants are emitted for every command, because
        on Windows the agent reaches the same git or gh binary through either shell
        and a rule that covers only one of them is a gap.
    #>
    param([object]$Policy)

    $basePath = Join-Path $CoreDir 'providers/claude/settings.json'
    if (-not (Test-Path $basePath)) {
        throw 'core/providers/claude/settings.json not found'
    }
    $base = Get-Content -Path $basePath -Raw | ConvertFrom-Json

    $buckets = @{ allow = @(); ask = @(); deny = @() }
    $keyFor = @{ allow = 'allow'; confirm = 'ask'; forbid = 'deny' }

    foreach ($rule in $Policy.rules) {
        $key = $keyFor[$rule.decision]

        foreach ($command in $rule.commands) {
            # Trailing " *" enforces a word boundary, so "ls *" matches "ls -la" but
            # not "lsof". This is the form the permission dialog itself writes.
            $buckets[$key] += "Bash($command *)"
            $buckets[$key] += "PowerShell($command *)"

            # Claude Code strips only a fixed wrapper list (timeout, nice, nohup and
            # friends). Runners like rtk, npx, and docker exec are not stripped, so a
            # bare prefix rule misses "rtk git push --force". A leading wildcard
            # closes that. Only for rules that restrict: broadening an allow rule
            # this way would hand approval to anything that merely ends the right way.
            if ($rule.decision -ne 'allow') {
                $buckets[$key] += "Bash(* $command *)"
                $buckets[$key] += "PowerShell(* $command *)"
            }
        }

        if ($rule.PSObject.Properties.Name -contains 'claude_rules') {
            foreach ($raw in $rule.claude_rules) {
                $buckets[$key] += $raw
            }
        }

        # read_paths is a file-read boundary rather than a command one. Claude Code
        # matches it with the Read() tool matcher.
        if ($rule.PSObject.Properties.Name -contains 'read_paths') {
            foreach ($path in $rule.read_paths) {
                $buckets[$key] += "Read($path)"
            }
        }
    }

    # Keys starting with an underscore are notes for whoever edits the source file.
    # Claude Code should never see them.
    $settings = [ordered]@{}
    foreach ($property in $base.PSObject.Properties) {
        if ($property.Name.StartsWith('_') -or $property.Name -eq 'permissions') { continue }
        $settings[$property.Name] = $property.Value
    }

    # Mode-level permission settings such as defaultMode come from the settings
    # source. Only the three rule arrays are generated, so changing the mode does not
    # mean editing the renderer.
    $permissions = [ordered]@{}
    if ($base.PSObject.Properties.Name -contains 'permissions') {
        foreach ($property in $base.permissions.PSObject.Properties) {
            if ($property.Name.StartsWith('_')) { continue }
            if ($property.Name -in @('allow', 'ask', 'deny')) {
                throw "core/providers/claude/settings.json must not set permissions.$($property.Name). It is generated from core/policy/policy.json."
            }
            $permissions[$property.Name] = $property.Value
        }
    }

    $permissions['allow'] = @($buckets.allow)
    $permissions['ask'] = @($buckets.ask)
    $permissions['deny'] = @($buckets.deny)

    $settings['permissions'] = $permissions

    ($settings | ConvertTo-Json -Depth 32 -WarningAction Stop) + "`n"
}

function New-CursorRules {
    <#
        Emits the rule table the Cursor hook script matches against.

        Cursor hook `ask` is a no-op in Run Everything, so confirm is written as
        deny and the script tells the agent to hand the user the exact command.
        A confirm rule with cursor omit is left out of the hook and runs.
        Forbid is deny without that handoff. Allow is omitted: unlisted commands
        fall through to Run Everything.

        Token phrases come from policy commands. Globs come from glob_rules,
        unwrapped command strings that close the flag-position gap prefix
        matching cannot.
    #>
    param([object]$Policy)

    $shell = [System.Collections.Generic.List[object]]::new()
    $read = [System.Collections.Generic.List[object]]::new()

    foreach ($tier in @('forbid', 'confirm')) {
        foreach ($rule in $Policy.rules) {
            if ($rule.decision -ne $tier) { continue }
            if ($rule.PSObject.Properties.Name -contains 'cursor' -and [string]$rule.cursor -eq 'omit') {
                continue
            }

            $tokens = [System.Collections.Generic.List[string]]::new()
            foreach ($command in @($rule.commands)) {
                if (-not [string]::IsNullOrWhiteSpace($command)) {
                    $tokens.Add($command)
                }
            }

            $globs = [System.Collections.Generic.List[string]]::new()
            if ($rule.PSObject.Properties.Name -contains 'glob_rules') {
                foreach ($glob in @($rule.glob_rules)) {
                    $globs.Add([string]$glob)
                }
            }

            if ($tokens.Count -gt 0 -or $globs.Count -gt 0) {
                $shell.Add([ordered]@{
                    id     = $rule.id
                    tier   = $tier
                    why    = $rule.why
                    tokens = @($tokens)
                    globs  = @($globs)
                })
            }

            if ($rule.PSObject.Properties.Name -contains 'read_paths') {
                $patterns = [System.Collections.Generic.List[string]]::new()
                foreach ($path in @($rule.read_paths)) {
                    $patterns.Add(($path -replace '^\./', ''))
                }
                $read.Add([ordered]@{
                    id       = $rule.id
                    tier     = $tier
                    why      = $rule.why
                    patterns = @($patterns)
                })
            }
        }
    }

    $payload = [ordered]@{
        shell = @($shell)
        read  = @($read)
    }
    ($payload | ConvertTo-Json -Depth 32 -WarningAction Stop) + "`n"
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

# Every provider gets byte-identical content. Only the filename, the install path,
# and Cursor's required front matter differ.
$instructionBody = New-InstructionFile
$instructionSources = @($SharedModules) | ForEach-Object { "core/instructions/$_" }

foreach ($provider in $Providers) {
    $target = Join-Path (Join-Path $BuildDir $provider.Name) $provider.InstructionFile
    $instruction = $instructionBody
    if ($provider.ContainsKey('InstructionFrontMatter')) {
        $instruction = $provider.InstructionFrontMatter.TrimEnd() + "`n`n" + $instruction
    }
    Write-RenderedFile -Path $target -Content $instruction

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
        Build   = 'build/claude/settings.json'
        Install = '~/.claude/settings.json'
        Content = New-ClaudeSettings -Policy $policy
        Sources = @('core/providers/claude/settings.json', 'core/policy/policy.json')
    },
    @{
        Build   = 'build/claude/statusline-command.sh'
        Install = '~/.claude/statusline-command.sh'
        Content = (Get-Content -Path (Join-Path $CoreDir 'providers/claude/statusline-command.sh') -Raw)
        Sources = @('core/providers/claude/statusline-command.sh')
    },
    @{
        Build   = 'build/cursor/hooks.json'
        Install = '~/.cursor/hooks.json'
        Content = (Get-Content -Path (Join-Path $CoreDir 'providers/cursor/hooks.json') -Raw)
        Sources = @('core/providers/cursor/hooks.json')
    },
    @{
        Build   = 'build/cursor/hooks/mewai-policy.ps1'
        Install = '~/.cursor/hooks/mewai-policy.ps1'
        Content = (Get-Content -Path (Join-Path $CoreDir 'providers/cursor/mewai-policy.ps1') -Raw)
        Sources = @('core/providers/cursor/mewai-policy.ps1')
    },
    @{
        Build   = 'build/cursor/hooks/rules.json'
        Install = '~/.cursor/hooks/rules.json'
        Content = New-CursorRules -Policy $policy
        Sources = @('core/policy/policy.json')
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
