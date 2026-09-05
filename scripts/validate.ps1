#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Fails when the sources drift from the rules this repository claims to follow.

.DESCRIPTION
    Every check here exists because the failure it catches is invisible to a human
    rereading the file. Style slips, a rule quietly restated in two layers, a file
    that grew past the point anyone reads it to the end.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$InstructionsDir = Join-Path $RepoRoot 'core/instructions'

# Exceeding a budget is a signal to cut, not to raise the number. Raising one is a
# decision worth arguing for in a commit message.
$LineBudgets = @{
    'base.md' = 80
}
$RenderedLineBudget = 400

$script:Failures = [System.Collections.Generic.List[string]]::new()

# A check that needs a binary this machine does not have reports as skipped. An
# unverifiable check must never look like a passing one.
$script:Skipped = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([string]$Message)
    $script:Failures.Add($Message)
}

function Get-InstructionModules {
    Get-ChildItem -Path $InstructionsDir -Recurse -Filter '*.md' | ForEach-Object {
        $relative = $_.FullName.Substring($InstructionsDir.Length + 1) -replace '\\', '/'
        [pscustomobject]@{
            Relative = $relative
            Path     = $_.FullName
            Text     = (Get-Content -Path $_.FullName -Raw) -replace "`r`n", "`n"
        }
    }
}

function Get-NormalizedBullets {
    <#
        Collapses a markdown bullet and its continuation lines into one normalized
        string so that the same rule wrapped differently in two files still compares
        equal. Borrowed from the duplicate-rule check in titus-ai.
    #>
    param([string]$Text)

    $bullets = [System.Collections.Generic.List[string]]::new()
    $current = $null

    foreach ($line in $Text -split "`n") {
        if ($line -match '^\s*[-*]\s+') {
            if ($null -ne $current) { $bullets.Add($current) }
            $current = $line.Trim()
        }
        elseif ($null -ne $current -and $line -match '^\s+\S') {
            $current += ' ' + $line.Trim()
        }
        elseif ($null -ne $current) {
            $bullets.Add($current)
            $current = $null
        }
    }
    if ($null -ne $current) { $bullets.Add($current) }

    $bullets | ForEach-Object {
        ($_ -replace '^\s*[-*]\s+', '' -replace '\s+', ' ').Trim().TrimEnd('.').ToLowerInvariant()
    } | Where-Object { $_.Length -gt 0 }
}

function Get-SkillFiles {
    $skillsDir = Join-Path $RepoRoot 'core/skills'
    if (-not (Test-Path $skillsDir)) { return @() }

    Get-ChildItem -Path $skillsDir -Directory | ForEach-Object {
        [pscustomobject]@{
            Name     = $_.Name
            Relative = "core/skills/$($_.Name)/SKILL.md"
            Path     = Join-Path $_.FullName 'SKILL.md'
            Exists   = Test-Path (Join-Path $_.FullName 'SKILL.md')
        }
    }
}

$modules = @(Get-InstructionModules)
$skills = @(Get-SkillFiles)

if ($modules.Count -eq 0) {
    Add-Failure 'no instruction modules found under core/instructions'
}
if ($skills.Count -eq 0) {
    Add-Failure 'no skills found under core/skills'
}

# The same style rules apply to skills, because a skill is loaded into context the
# same way an instruction file is.
$styleTargets = @($modules) + @(
    $skills | Where-Object { $_.Exists } | ForEach-Object {
        [pscustomobject]@{
            Relative = $_.Relative
            Path     = $_.Path
            Text     = (Get-Content -Path $_.Path -Raw) -replace "`r`n", "`n"
        }
    }
)

# --- style -------------------------------------------------------------------
# En dashes, smart quotes, and stray pictographs are paste artifacts rather than
# authorial choices, so catching them is not a style opinion. Punctuation the
# author picked on purpose is left alone.

foreach ($module in $styleTargets) {
    $lineNumber = 0
    foreach ($line in $module.Text -split "`n") {
        $lineNumber++

        if ($line -match '–') {
            Add-Failure "$($module.Relative):${lineNumber}: en dash"
        }
        if ($line -match '[‘’“”]') {
            Add-Failure "$($module.Relative):${lineNumber}: smart quote"
        }
        # \p{So} covers pictographs and dingbats, \p{Cs} covers the surrogate pairs
        # that astral-plane emoji are encoded as in .NET strings.
        if ($line -match '[\p{So}\p{Cs}]') {
            Add-Failure "$($module.Relative):${lineNumber}: emoji or pictograph"
        }
        if ($line -match 'TODO|FIXME|\[TODO:|XXX') {
            Add-Failure "$($module.Relative):${lineNumber}: placeholder text"
        }
    }
}

# --- important-if tags -------------------------------------------------------
# Unbalanced tags would drop a rule from the rendered file with no other signal.

foreach ($module in $modules) {
    $opens = [regex]::Matches($module.Text, '<important if="[^"]*">').Count
    $closes = [regex]::Matches($module.Text, '</important>').Count
    if ($opens -ne $closes) {
        Add-Failure ("{0}: {1} opening important-if tag(s) and {2} closing tag(s)" -f $module.Relative, $opens, $closes)
    }
}

# --- line budgets ------------------------------------------------------------

foreach ($module in $modules) {
    $budget = $LineBudgets[$module.Relative]
    if ($null -eq $budget) {
        Add-Failure "$($module.Relative): no line budget defined in validate.ps1"
        continue
    }

    $lines = ($module.Text.TrimEnd("`n") -split "`n").Count
    if ($lines -gt $budget) {
        Add-Failure "$($module.Relative): $lines lines exceeds budget of $budget"
    }
}

# --- duplicate rules across layers -------------------------------------------
# A rule restated in two modules means one copy will eventually be edited alone.

$bulletsByModule = @{}
foreach ($module in $modules) {
    $bulletsByModule[$module.Relative] = @(Get-NormalizedBullets -Text $module.Text)
}

$names = @($bulletsByModule.Keys | Sort-Object)
for ($i = 0; $i -lt $names.Count; $i++) {
    for ($j = $i + 1; $j -lt $names.Count; $j++) {
        $shared = $bulletsByModule[$names[$i]] |
            Where-Object { $bulletsByModule[$names[$j]] -contains $_ }

        foreach ($duplicate in $shared) {
            Add-Failure "duplicate rule in $($names[$i]) and $($names[$j]): $duplicate"
        }
    }
}

# --- skills ------------------------------------------------------------------

foreach ($skill in $skills) {
    if (-not $skill.Exists) {
        Add-Failure "$($skill.Name): missing SKILL.md"
        continue
    }

    $text = (Get-Content -Path $skill.Path -Raw) -replace "`r`n", "`n"
    $lines = $text -split "`n"

    if ($lines[0] -ne '---') {
        Add-Failure "$($skill.Relative): no YAML front matter"
        continue
    }

    $closing = [array]::IndexOf($lines, '---', 1)
    if ($closing -lt 0) {
        Add-Failure "$($skill.Relative): front matter is not closed"
        continue
    }

    $frontMatter = $lines[1..($closing - 1)]
    $name = ($frontMatter | Where-Object { $_ -match '^name:\s*(.+)$' } |
        ForEach-Object { $Matches[1].Trim() } | Select-Object -First 1)
    $description = ($frontMatter | Where-Object { $_ -match '^description:\s*(.+)$' } |
        ForEach-Object { $Matches[1].Trim() } | Select-Object -First 1)

    if (-not $name) {
        Add-Failure "$($skill.Relative): front matter has no name"
    }
    elseif ($name -ne $skill.Name) {
        Add-Failure "$($skill.Relative): name '$name' does not match its directory"
    }

    if (-not $description) {
        Add-Failure "$($skill.Relative): front matter has no description"
    }
    elseif ($description -notmatch 'Use (only )?when') {
        # Without a stated trigger, a provider that auto-selects skills has to guess
        # from the topic alone, and guesses wrong on adjacent tasks.
        Add-Failure "$($skill.Relative): description does not state when to use the skill"
    }
}

# --- policy ------------------------------------------------------------------

$policy = $null
$policyPath = Join-Path $RepoRoot 'core/policy/policy.json'
if (-not (Test-Path $policyPath)) {
    Add-Failure 'core/policy/policy.json is missing'
}
else {
    try {
        $policy = Get-Content -Path $policyPath -Raw | ConvertFrom-Json
    }
    catch {
        Add-Failure "core/policy/policy.json is not valid JSON: $_"
        $policy = $null
    }

    if ($policy) {
        $seenIds = @{}
        foreach ($rule in $policy.rules) {
            if ($seenIds.ContainsKey($rule.id)) {
                Add-Failure "policy: duplicate rule id '$($rule.id)'"
            }
            $seenIds[$rule.id] = $true

            if ($rule.decision -notin @('allow', 'confirm', 'forbid')) {
                Add-Failure "policy rule '$($rule.id)': unknown decision '$($rule.decision)'"
            }
            if ([string]::IsNullOrWhiteSpace($rule.why)) {
                Add-Failure "policy rule '$($rule.id)': no 'why'"
            }
            if ($rule.PSObject.Properties.Name -contains 'autonomy_omit') {
                if ($rule.autonomy_omit -isnot [bool]) {
                    Add-Failure "policy rule '$($rule.id)': autonomy_omit must be true or false"
                }
                elseif ($rule.autonomy_omit -and $rule.decision -ne 'confirm') {
                    Add-Failure "policy rule '$($rule.id)': autonomy_omit is only valid on confirm"
                }
            }
        }

        # A command that is both allowed and restricted is a contradiction the
        # providers resolve differently, so catch it here instead.
        $byDecision = @{ allow = @(); confirm = @(); forbid = @() }
        foreach ($rule in $policy.rules) {
            $byDecision[$rule.decision] += $rule.commands
        }
        foreach ($allowed in $byDecision.allow) {
            if ($byDecision.confirm -contains $allowed -or $byDecision.forbid -contains $allowed) {
                Add-Failure "policy: '$allowed' is both allowed and restricted"
            }
        }
    }
}

# --- rendered output ---------------------------------------------------------

$buildDir = Join-Path $RepoRoot 'build'
if (-not (Test-Path (Join-Path $buildDir 'manifest.json'))) {
    Add-Failure 'build/manifest.json is missing. Run scripts/render.ps1.'
}
else {
    $manifest = Get-Content -Path (Join-Path $buildDir 'manifest.json') -Raw | ConvertFrom-Json

    foreach ($entry in $manifest.entries) {
        $path = Join-Path $RepoRoot $entry.build
        if (-not (Test-Path $path)) {
            Add-Failure "manifest lists a file that was not rendered: $($entry.build)"
            continue
        }

        $actual = (Get-FileHash -Path $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $entry.sha256) {
            Add-Failure "$($entry.build) does not match its manifest hash. Re-render."
        }

        $lines = ((Get-Content -Path $path -Raw).TrimEnd("`n") -split "`n").Count
        if ($lines -gt $RenderedLineBudget) {
            Add-Failure "$($entry.build): $lines lines exceeds budget of $RenderedLineBudget"
        }

        foreach ($source in $entry.sources) {
            if (-not (Test-Path (Join-Path $RepoRoot $source))) {
                Add-Failure "manifest references a missing source: $source"
            }
        }
    }
}

# --- claude settings ---------------------------------------------------------
# A mode and a switch that disables that mode is a contradiction the settings file
# accepts silently, and the symptom is a permission tier that never fires.

$claudeSettingsPath = Join-Path $RepoRoot 'build/claude/settings.json'
if (Test-Path $claudeSettingsPath) {
    $claudeSettings = Get-Content -Path $claudeSettingsPath -Raw | ConvertFrom-Json
    $claudePermissions = $claudeSettings.permissions
    $permissionKeys = $claudePermissions.PSObject.Properties.Name

    $mode = if ($permissionKeys -contains 'defaultMode') { $claudePermissions.defaultMode } else { $null }

    if ($mode -eq 'auto' -and $permissionKeys -contains 'disableAutoMode') {
        Add-Failure 'settings: defaultMode is auto but disableAutoMode is set, which turns auto mode off'
    }
    if ($mode -eq 'bypassPermissions' -and $permissionKeys -contains 'disableBypassPermissionsMode') {
        Add-Failure 'settings: defaultMode is bypassPermissions but disableBypassPermissionsMode is set'
    }

    # Ask rules are silently inert under bypassPermissions, verified on this machine
    # against Claude Code's own behavior. Shipping ask rules with that mode gives a
    # confirm tier that looks configured and never fires.
    if ($mode -eq 'bypassPermissions' -and $claudePermissions.ask.Count -gt 0) {
        Add-Failure ("settings: defaultMode is bypassPermissions, where the {0} ask rule(s) never prompt. Use auto, or move those commands to forbid." -f $claudePermissions.ask.Count)
    }
}

# --- cursor hooks ------------------------------------------------------------
# These run the rendered matcher the same way Cursor will: JSON on stdin, JSON
# on stdout. They do not need the Cursor binary. A matcher that cannot decide
# is a failed check, not a skipped one.

$cursorScript = Join-Path $RepoRoot 'build/cursor/hooks/mewai-policy.ps1'
$cursorRulesPath = Join-Path $RepoRoot 'build/cursor/hooks/rules.json'
$cursorHooksPath = Join-Path $RepoRoot 'build/cursor/hooks.json'

if (-not (Test-Path $cursorScript) -or -not (Test-Path $cursorRulesPath) -or -not (Test-Path $cursorHooksPath)) {
    Add-Failure 'build/cursor hook files are missing. Run scripts/render.ps1.'
}
else {
    $hooksRaw = (Get-Content -Path $cursorHooksPath -Raw) -replace "`r`n", "`n"
    $failClosedCount = ([regex]::Matches($hooksRaw, '"failClosed"\s*:\s*true')).Count
    if ($failClosedCount -lt 2) {
        Add-Failure 'cursor: hooks.json must set failClosed true on both policy hooks so a broken matcher blocks'
    }

    if ($policy) {
        $cursorRules = Get-Content -Path $cursorRulesPath -Raw | ConvertFrom-Json
        $shellIds = @($cursorRules.shell | ForEach-Object { $_.id })

        foreach ($rule in @($policy.rules | Where-Object { $_.decision -in @('forbid', 'confirm') })) {
            $autonomyOmit = ($rule.PSObject.Properties.Name -contains 'autonomy_omit' -and $rule.autonomy_omit)
            if (@($rule.commands).Count -eq 0) { continue }
            if ($autonomyOmit) {
                if ($shellIds -contains $rule.id) {
                    Add-Failure "cursor: autonomy_omit rule '$($rule.id)' still rendered a shell matcher"
                }
                continue
            }
            if ($shellIds -notcontains $rule.id) {
                Add-Failure "cursor: rule '$($rule.id)' rendered no shell matcher"
            }
        }

        foreach ($rule in $policy.rules) {
            if ($rule.PSObject.Properties.Name -notcontains 'glob_rules') { continue }
            if ($rule.PSObject.Properties.Name -contains 'autonomy_omit' -and $rule.autonomy_omit) {
                continue
            }
            $row = @($cursorRules.shell | Where-Object { $_.id -eq $rule.id }) | Select-Object -First 1
            if (-not $row) {
                Add-Failure "cursor: glob_rules from '$($rule.id)' rendered no shell row"
                continue
            }
            $emitted = @($row.globs)
            foreach ($rawPattern in $rule.glob_rules) {
                if ($emitted -cnotcontains $rawPattern) {
                    Add-Failure "cursor: glob '$rawPattern' from rule '$($rule.id)' is missing from rules.json"
                }
            }
        }
    }

    $sshPath = Join-Path $(if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }) '.ssh/config'
    $cases = @(
        @{ Name = 'read-only inspection is allowed'; Payload = '{"command":"git status"}'; Expect = 'allow' }
        @{ Name = 'omitted confirm-tier pr create is allowed'; Payload = '{"command":"gh pr create --title test"}'; Expect = 'allow' }
        @{
            Name          = 'local-commit is denied with a handoff'
            Payload       = '{"command":"git commit -m test"}'
            Expect        = 'deny'
            AgentContains = 'Give the user this exact command'
        }
        @{ Name = 'recursive delete is allowed'; Payload = '{"command":"rm -rf /tmp/scratch"}'; Expect = 'allow' }
        @{
            Name             = 'forbid-tier force push is denied without a handoff'
            Payload          = '{"command":"git push --force"}'
            Expect           = 'deny'
            AgentNotContains = 'Give the user this exact command'
        }
        @{ Name = 'a wrapper cannot launder a forbidden command'; Payload = '{"command":"rtk git push --force"}'; Expect = 'deny' }
        @{ Name = 'force flag in fifth position is denied'; Payload = '{"command":"git push origin main --force"}'; Expect = 'deny' }
        @{
            Name    = 'secret file read is denied'
            Payload = (@{ file_path = $sshPath } | ConvertTo-Json -Compress)
            Expect  = 'deny'
        }
        @{
            Name    = 'beforeReadFile payload larger than one pipe chunk is allowed'
            Payload = (@{
                    file_path = (Join-Path $RepoRoot 'README.md')
                    content   = ('x' * 80000)
                } | ConvertTo-Json -Compress)
            Expect  = 'allow'
        }
        @{
            Name    = 'secret file read with a large content payload is still denied'
            Payload = (@{
                    file_path = $sshPath
                    content   = ('x' * 80000)
                } | ConvertTo-Json -Compress)
            Expect  = 'deny'
        }
    )

    foreach ($case in $cases) {
        $result = $case.Payload | & pwsh -NoProfile -File $cursorScript
        if ($LASTEXITCODE -ne 0) {
            Add-Failure "cursor hook could not evaluate '$($case.Name)': $result"
            continue
        }

        try {
            $decision = ($result | Out-String).Trim() | ConvertFrom-Json
        }
        catch {
            Add-Failure "cursor hook '$($case.Name)' did not return JSON: $result"
            continue
        }

        if ($decision.permission -ne $case.Expect) {
            Add-Failure "$($case.Name): expected '$($case.Expect)', got '$($decision.permission)'"
        }
        if ($case.ContainsKey('AgentContains') -and $decision.agent_message -notlike "*$($case.AgentContains)*") {
            Add-Failure "$($case.Name): agent_message missing '$($case.AgentContains)'"
        }
        if ($case.ContainsKey('AgentNotContains') -and $decision.agent_message -like "*$($case.AgentNotContains)*") {
            Add-Failure "$($case.Name): agent_message must not contain '$($case.AgentNotContains)'"
        }
    }
}

# --- hermes approvals --------------------------------------------------------
# approvals.deny is the only Hermes boundary that survives yolo, so a forbid rule
# that renders nothing there is a boundary that silently does not exist.

$hermesBasePath = Join-Path $RepoRoot 'core/providers/hermes/config.yaml'
$hermesBuildPath = Join-Path $RepoRoot 'build/hermes/config.yaml'

if (-not (Test-Path $hermesBasePath)) {
    Add-Failure 'core/providers/hermes/config.yaml is missing'
}
elseif ((Get-Content -Path $hermesBasePath) -match '^approvals:') {
    Add-Failure 'core/providers/hermes/config.yaml declares approvals. That block is generated, and a second one would be a duplicate YAML key.'
}

if (-not (Test-Path $hermesBuildPath)) {
    Add-Failure 'build/hermes/config.yaml was not rendered'
}
elseif ($policy) {
    $hermesText = (Get-Content -Path $hermesBuildPath -Raw) -replace "`r`n", "`n"

    $markerStart = '# --- generated by mewai from core/policy/policy.json. Do not edit. ---'
    $markerEnd = '# --- end generated ---'
    if (-not $hermesText.StartsWith($markerStart)) {
        Add-Failure 'build/hermes/config.yaml does not open with the generated marker. reverse strips the block by marker, so losing it would laundered generated rules back into source.'
    }
    if ($hermesText -notmatch [regex]::Escape($markerEnd)) {
        Add-Failure 'build/hermes/config.yaml has no end marker for the generated block'
    }

    $denyLines = @()
    foreach ($line in $hermesText -split "`n") {
        if ($line -match '^\s+- "(.+)"$') { $denyLines += $Matches[1] }
        if ($line -eq $markerEnd) { break }
    }

    foreach ($rule in $policy.rules) {
        $omitted = ($rule.PSObject.Properties.Name -contains 'autonomy_omit' -and $rule.autonomy_omit)

        foreach ($command in @($rule.commands)) {
            if ([string]::IsNullOrWhiteSpace($command)) { continue }
            $expected = "*$command*"
            $present = $denyLines -contains $expected

            if ($rule.decision -eq 'forbid' -and -not $present) {
                Add-Failure "hermes: forbid command '$command' from '$($rule.id)' rendered no deny pattern"
            }
            if ($rule.decision -eq 'confirm' -and -not $omitted -and -not $present) {
                Add-Failure "hermes: confirm command '$command' from '$($rule.id)' rendered no deny pattern"
            }
            if ($omitted -and $present) {
                Add-Failure "hermes: autonomy_omit rule '$($rule.id)' still rendered a deny pattern for '$command'"
            }
        }
    }

    foreach ($pattern in $denyLines) {
        if (-not $pattern.StartsWith('*') -or -not $pattern.EndsWith('*')) {
            Add-Failure "hermes: deny pattern '$pattern' is not wrapped in wildcards, so it only matches a command that is the whole string"
        }
    }
}

# --- report ------------------------------------------------------------------

foreach ($skip in $script:Skipped) {
    Write-Host "skipped: $skip"
}

if ($script:Failures.Count -gt 0) {
    foreach ($failure in $script:Failures) {
        Write-Host "error: $failure"
    }
    Write-Host ''
    Write-Host "validation failed with $($script:Failures.Count) error(s)"
    exit 1
}

Write-Host ("validation passed: {0} instruction module(s), {1} skill(s), {2} rendered file(s)" -f
    $modules.Count, $skills.Count, $manifest.entries.Count)
