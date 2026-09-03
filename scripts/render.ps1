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

# Each provider renders one instruction file from the shared modules plus its own.
# Order matters: shared behavior first, provider notes last.
$SharedModules = @('base.md', 'autonomy.md', 'explainability.md')

# One entry per provider, holding everything that differs. Adding a provider is
# adding a row here. A null SkillsInstallRoot means the provider already reads a
# root another provider installs to, so mewai renders no second copy for it.
$Providers = @(
    @{
        Name               = 'claude'
        InstructionFile    = 'CLAUDE.md'
        InstructionInstall = '~/.claude/CLAUDE.md'
        ProviderModule     = 'providers/claude.md'
        SkillsInstallRoot  = '~/.claude/skills'
    },
    @{
        Name               = 'codex'
        InstructionFile    = 'AGENTS.md'
        InstructionInstall = '~/.codex/AGENTS.md'
        ProviderModule     = 'providers/codex.md'
        SkillsInstallRoot  = '~/.agents/skills'
    },
    @{
        Name               = 'antigravity'
        InstructionFile    = 'GEMINI.md'
        InstructionInstall = '~/.gemini/GEMINI.md'
        ProviderModule     = 'providers/antigravity.md'
        SkillsInstallRoot  = '~/.gemini/skills'
    },
    @{
        Name               = 'opencode'
        InstructionFile    = 'AGENTS.md'
        InstructionInstall = '~/.config/opencode/AGENTS.md'
        ProviderModule     = 'providers/opencode.md'
        SkillsInstallRoot  = $null
    },
    @{
        Name                    = 'cursor'
        InstructionFile         = 'mewai.mdc'
        InstructionInstall      = '~/.cursor/rules/mewai.mdc'
        ProviderModule          = 'providers/cursor.md'
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

function ConvertTo-OpenCodeReadPattern {
    <#
        Turns a policy read path into the OpenCode permission.read patterns that
        cover it. OpenCode matches file paths and expands a leading tilde, so the
        repository-relative "./" prefix Claude Code uses means nothing there. A path
        without one is also given a "**/" variant, because the same secret file at a
        nested path is the same secret.
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

        OpenCode evaluates permission patterns last-match-wins, so tier order in the
        emitted object is part of the meaning, not formatting. Allow patterns are
        written first and deny patterns last, which is what makes a deny outrank an
        overlapping allow. Reordering this by hand downgrades a boundary silently.

        Unlike Claude Code there is one bash matcher rather than separate Bash() and
        PowerShell() ones, so each command produces one pattern set instead of two.
    #>
    param([object]$Policy)

    $basePath = Join-Path $CoreDir 'providers/opencode/opencode.json'
    if (-not (Test-Path $basePath)) {
        throw 'core/providers/opencode/opencode.json not found'
    }
    $base = Get-Content -Path $basePath -Raw | ConvertFrom-Json

    $buckets = @{ allow = @(); ask = @(); deny = @() }
    $keyFor = @{ allow = 'allow'; confirm = 'ask'; forbid = 'deny' }

    # An ordinal comparer, not [ordered]@{}. PowerShell's default ordered hashtable
    # compares keys case insensitively, which silently collapses a pattern pair that
    # differs only in casing, such as -Recurse and -recurse, down to whichever came
    # last. Shell command patterns are case sensitive strings.
    $readPatterns = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)

    foreach ($rule in $Policy.rules) {
        $key = $keyFor[$rule.decision]

        foreach ($command in $rule.commands) {
            # The bare form and the trailing-wildcard form together cover both
            # "git clean" and "git clean -fd". A trailing "*" alone would not match
            # the bare invocation, because it needs the separating space.
            $buckets[$key] += $command
            $buckets[$key] += "$command *"

            # Wrappers such as rtk, npx, and docker exec run their arguments without
            # appearing to. A leading wildcard catches the laundered form. Only for
            # rules that restrict: broadening an allow this way would approve
            # anything that merely ends with the right words.
            if ($rule.decision -ne 'allow') {
                $buckets[$key] += "* $command"
                $buckets[$key] += "* $command *"
            }
        }

        if ($rule.PSObject.Properties.Name -contains 'opencode_rules') {
            foreach ($raw in $rule.opencode_rules) {
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
    foreach ($tier in @('allow', 'ask', 'deny')) {
        foreach ($pattern in $buckets[$tier]) {
            # Re-adding moves the key to the end, so a pattern claimed by two tiers
            # ends up in the later and stricter one. Position is the decision here.
            if ($bash.Contains($pattern)) { $bash.Remove($pattern) }
            $bash[$pattern] = $tier
        }
    }

    $settings = [ordered]@{}
    foreach ($property in $base.PSObject.Properties) {
        if ($property.Name -eq 'permission') {
            throw 'core/providers/opencode/opencode.json must not set permission. It is generated from core/policy/policy.json.'
        }
        # Keys starting with an underscore are notes for whoever edits the source
        # file. OpenCode should never see them.
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

        'confirm' emits no rule on purpose. Codex execpolicy expresses allow and
        forbidden, so a command with no matching rule falls through to Codex's own
        approval flow, which is the behavior 'confirm' asks for.
    #>
    param([object]$Policy)

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# Rendered by mewai from core/policy/policy.json. Do not edit this file.')
    $lines.Add('# Change the policy and run scripts/render.ps1.')
    $lines.Add('#')
    $lines.Add('# Rules control which commands Codex may run outside the sandbox.')
    $lines.Add('# Behavioral expectations belong in AGENTS.md. Do not blanket-allow shells,')
    $lines.Add('# wrappers, or tools that can hide arbitrary commands.')

    foreach ($rule in $Policy.rules) {
        if ($rule.decision -eq 'confirm') { continue }
        if ($rule.commands.Count -eq 0) { continue }

        $decision = if ($rule.decision -eq 'allow') { 'allow' } else { 'forbidden' }

        $lines.Add('')
        $lines.Add("# $($rule.id): $($rule.why)")

        foreach ($command in $rule.commands) {
            $words = $command -split '\s+' | Where-Object { $_ }
            $pattern = ($words | ForEach-Object { '"' + $_ + '"' }) -join ', '

            $lines.Add('prefix_rule(')
            $lines.Add("    pattern=[$pattern],")
            $lines.Add("    decision=`"$decision`",")
            if ($decision -eq 'forbidden') {
                $lines.Add("    justification=`"$($rule.why)`",")
            }
            $lines.Add(')')
        }
    }

    ($lines -join "`n") + "`n"
}

function New-CursorRules {
    <#
        Emits the rule table the Cursor hook script matches against.

        Cursor hook `ask` is a no-op in Run Everything, so confirm is written as
        deny and the script tells the agent to hand the user the exact command.
        A confirm rule with cursor omit is left out of the hook and runs.
        Forbid is deny without that handoff. Allow is omitted: unlisted commands
        fall through to Run Everything.

        Token phrases come from policy commands. Globs reuse opencode_rules,
        which are already unwrapped command strings that close the flag-position
        gap prefix matching cannot.
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
            if ($rule.PSObject.Properties.Name -contains 'opencode_rules') {
                foreach ($glob in @($rule.opencode_rules)) {
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
    param([hashtable]$Provider)

    $modules = @($SharedModules) + @($Provider.ProviderModule)
    $sections = foreach ($module in $modules) { Read-Module -RelativePath $module }

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

foreach ($provider in $Providers) {
    $target = Join-Path (Join-Path $BuildDir $provider.Name) $provider.InstructionFile
    $instruction = New-InstructionFile -Provider $provider
    if ($provider.ContainsKey('InstructionFrontMatter')) {
        $instruction = $provider.InstructionFrontMatter.TrimEnd() + "`n`n" + $instruction
    }
    Write-RenderedFile -Path $target -Content $instruction

    $sources = @($SharedModules) + @($provider.ProviderModule) |
        ForEach-Object { "core/instructions/$_" }

    $manifestEntries.Add([ordered]@{
        build   = "build/$($provider.Name)/$($provider.InstructionFile)"
        install = $provider.InstructionInstall
        action  = 'copy'
        sources = $sources
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
    },
    @{
        Build   = 'build/claude/statusline-command.sh'
        Install = '~/.claude/statusline-command.sh'
        Content = (Get-Content -Path (Join-Path $CoreDir 'providers/claude/statusline-command.sh') -Raw)
        Sources = @('core/providers/claude/statusline-command.sh')
    },
    @{
        Build   = 'build/opencode/opencode.jsonc'
        Install = '~/.config/opencode/opencode.jsonc'
        Content = New-OpenCodeSettings -Policy $policy
        Sources = @('core/providers/opencode/opencode.json', 'core/policy/policy.json')
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
