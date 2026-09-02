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
    'base.md'                   = 120
    'autonomy.md'                = 60
    'explainability.md'          = 60
    'providers/claude.md'        = 60
    'providers/codex.md'         = 60
    'providers/antigravity.md'   = 60
    'providers/opencode.md'      = 60
    'providers/cursor.md'        = 60
}
$RenderedLineBudget = 400

$script:Failures = [System.Collections.Generic.List[string]]::new()

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
# The repository tells agents not to use these. A file that breaks its own rule
# teaches the agent that the rules are decorative.

foreach ($module in $styleTargets) {
    $lineNumber = 0
    foreach ($line in $module.Text -split "`n") {
        $lineNumber++

        if ($line -match '—') {
            Add-Failure "$($module.Relative):${lineNumber}: em dash"
        }
        if ($line -match '–') {
            Add-Failure "$($module.Relative):${lineNumber}: en dash"
        }
        if ($line -match '[‘’“”]') {
            Add-Failure "$($module.Relative):${lineNumber}: smart quote"
        }
        # Semicolons inside code spans are legitimate shell and code syntax.
        $withoutCode = $line -replace '`[^`]*`', ''
        # A clause-joining semicolon is followed by a space or ends the line. The
        # end-of-line case is the common one in a bulleted list.
        if ($withoutCode -match ';(\s|$)') {
            Add-Failure "$($module.Relative):${lineNumber}: semicolon joining clauses"
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

# --- codex execpolicy --------------------------------------------------------
# These assertions prove the rendered rules actually decide the way the policy says.
# They need a working codex binary. When there is not one, say so: a check that could
# not run must never read as a check that passed.

$script:Skipped = [System.Collections.Generic.List[string]]::new()
$rulesPath = Join-Path $RepoRoot 'build/codex/rules/default.rules'

$codexCommand = Get-Command codex -ErrorAction SilentlyContinue
$codexWorks = $false
if ($codexCommand) {
    try {
        & codex --version *>$null
        $codexWorks = ($LASTEXITCODE -eq 0)
    }
    catch {
        $codexWorks = $false
    }
}

if (-not (Test-Path $rulesPath)) {
    Add-Failure 'build/codex/rules/default.rules is missing'
}
elseif (-not $codexWorks) {
    $reason = if ($codexCommand) {
        "codex is on PATH at $($codexCommand.Source) but does not run"
    }
    else {
        'codex is not on PATH'
    }
    $script:Skipped.Add("codex execpolicy assertions: $reason")
}
else {
    $cases = @(
        @{ Name = 'read-only inspection is allowed'; Args = @('rg', '--files'); Expect = 'allow' }
        @{ Name = 'repository deletion is forbidden'; Args = @('gh', 'repo', 'delete', 'owner/repo'); Expect = 'forbidden' }
        # The important one. If a wrapper can launder a forbidden command, the rules
        # are decoration.
        @{ Name = 'a wrapper cannot launder a forbidden command'; Args = @('rtk', 'git', 'push', '--force'); Reject = 'allow' }
    )

    foreach ($case in $cases) {
        $result = & codex execpolicy check --rules $rulesPath @($case.Args) 2>&1
        if ($LASTEXITCODE -ne 0) {
            Add-Failure "codex execpolicy could not evaluate '$($case.Name)': $result"
            continue
        }

        $decision = ($result | ConvertFrom-Json).decision

        if ($case.ContainsKey('Expect') -and $decision -ne $case.Expect) {
            Add-Failure "$($case.Name): expected '$($case.Expect)', got '$decision'"
        }
        if ($case.ContainsKey('Reject') -and $decision -eq $case.Reject) {
            Add-Failure "$($case.Name): decision must not be '$($case.Reject)'"
        }
    }
}

# --- opencode permissions ----------------------------------------------------
# OpenCode resolves a command by taking the last pattern that matches it, so tier
# order in the emitted object is the decision. A stricter rule written above a
# looser one is inert, and nothing about reading a 200 key object reveals that.

$bashRules = @()
$openCodePath = Join-Path $RepoRoot 'build/opencode/opencode.jsonc'
if (-not (Test-Path $openCodePath)) {
    Add-Failure 'build/opencode/opencode.jsonc is missing. Run scripts/render.ps1.'
}
else {
    $openCodeRaw = (Get-Content -Path $openCodePath -Raw) -replace "`r`n", "`n"

    # -AsHashtable because command patterns are case sensitive strings and JSON
    # permits keys that differ only in casing. The default parser rejects the whole
    # file in that case, with a message about its own switch rather than the rule.
    try {
        $null = $openCodeRaw | ConvertFrom-Json -AsHashtable
        $openCode = $true
    }
    catch {
        Add-Failure "build/opencode/opencode.jsonc is not valid JSON: $_"
        $openCode = $false
    }

    if ($openCode) {
        # Read the patterns from the text rather than a parsed object, because both
        # their order and their exact casing are load bearing and a hashtable
        # preserves neither reliably.
        $bashBlock = [regex]::Match($openCodeRaw, '(?s)"bash":\s*\{(.*?)\n    \}')
        $bashRules = [regex]::Matches($bashBlock.Groups[1].Value, '"((?:[^"\\]|\\.)*)":\s*"(allow|ask|deny)"') |
            ForEach-Object { [pscustomobject]@{ Pattern = $_.Groups[1].Value; Action = $_.Groups[2].Value } }

        if ($bashRules.Count -eq 0) {
            Add-Failure 'opencode: permission.bash has no patterns'
        }

        # Everything that is not generated must survive rendering byte for byte.
        # A serializer that quietly flattens a nested array into a string produces a
        # file that still parses, still installs, and routes to the wrong place.
        $openCodeSource = Join-Path $RepoRoot 'core/providers/opencode/opencode.json'
        if (Test-Path $openCodeSource) {
            $sourceJson = Get-Content -Path $openCodeSource -Raw | ConvertFrom-Json -AsHashtable
            $renderedJson = $openCodeRaw | ConvertFrom-Json -AsHashtable

            foreach ($key in @($sourceJson.Keys | Where-Object { -not $_.StartsWith('_') })) {
                $expected = $sourceJson[$key] | ConvertTo-Json -Depth 32 -Compress
                $actual = if ($renderedJson.ContainsKey($key)) {
                    $renderedJson[$key] | ConvertTo-Json -Depth 32 -Compress
                } else { '<missing>' }

                if ($expected -ne $actual) {
                    Add-Failure "opencode: base setting '$key' did not survive rendering. source $expected, rendered $actual"
                }
            }
        }

        $rank = @{ allow = 0; ask = 1; deny = 2 }
        $highest = -1

        foreach ($entry in $bashRules) {
            if ($rank[$entry.Action] -lt $highest) {
                Add-Failure ("opencode: permission.bash pattern '{0}' is '{1}' but sits below a stricter tier. Last match wins, so the stricter rule never fires. Emit allow, then ask, then deny." -f $entry.Pattern, $entry.Action)
                break
            }
            $highest = $rank[$entry.Action]
        }

        # Codex drops a rule with no commands on purpose. OpenCode should never drop
        # one, so a forbid that renders to nothing is a regression rather than a
        # documented gap.
        if ($policy) {
            $denied = @($bashRules | Where-Object { $_.Action -eq 'deny' } |
                ForEach-Object { $_.Pattern })

            foreach ($rule in @($policy.rules | Where-Object { $_.decision -eq 'forbid' })) {
                foreach ($command in $rule.commands) {
                    if ($denied -notcontains $command) {
                        Add-Failure "opencode: forbid command '$command' from rule '$($rule.id)' rendered no deny pattern"
                    }
                }
            }

            # Every raw pattern must survive rendering with its exact spelling. Two
            # patterns differing only in casing collapse into one under a case
            # insensitive key comparer, which halves coverage without failing
            # anything. -Recurse and -recurse did exactly that.
            $emitted = @($bashRules | ForEach-Object { $_.Pattern })
            foreach ($rule in $policy.rules) {
                if ($rule.PSObject.Properties.Name -notcontains 'opencode_rules') { continue }
                foreach ($raw in $rule.opencode_rules) {
                    if ($emitted -cnotcontains $raw) {
                        Add-Failure "opencode: pattern '$raw' from rule '$($rule.id)' is missing from permission.bash"
                    }
                }
            }
        }
    }
}

# The checks above read the rendered text. These prove OpenCode itself accepts it,
# by pointing OPENCODE_CONFIG at the build file so the config resolver runs against
# it before it is installed anywhere. This is the OpenCode analogue of the codex
# execpolicy assertions, and it needs a working opencode binary the same way.

$openCodeCommand = Get-Command opencode -ErrorAction SilentlyContinue
$openCodeWorks = $false
if ($openCodeCommand) {
    try {
        & opencode --version *>$null
        $openCodeWorks = ($LASTEXITCODE -eq 0)
    }
    catch {
        $openCodeWorks = $false
    }
}

if (-not (Test-Path $openCodePath)) {
    # Already reported as missing above.
}
elseif (-not $openCodeWorks) {
    $reason = if ($openCodeCommand) {
        "opencode is on PATH at $($openCodeCommand.Source) but does not run"
    }
    else {
        'opencode is not on PATH'
    }
    $script:Skipped.Add("opencode config assertions: $reason")
}
else {
    $previousConfig = $env:OPENCODE_CONFIG
    $env:OPENCODE_CONFIG = $openCodePath
    try {
        $resolvedRaw = & opencode debug config 2>&1 | Out-String

        if ($LASTEXITCODE -ne 0) {
            Add-Failure "opencode rejected the rendered config: $resolvedRaw"
        }
        else {
            $resolved = $resolvedRaw | ConvertFrom-Json -AsHashtable

            if (-not $resolved.permission) {
                Add-Failure 'opencode resolved the rendered config but found no permission block. The file loaded and the rules did not.'
            }
            else {
                # Counting per tier catches a pattern that OpenCode's parser dropped
                # or collapsed, which is the failure that leaves a boundary looking
                # configured while never firing.
                foreach ($tier in @('allow', 'ask', 'deny')) {
                    $rendered = @($bashRules | Where-Object { $_.Action -eq $tier }).Count
                    $loaded = @($resolved.permission.bash.GetEnumerator() |
                        Where-Object { $_.Value -eq $tier }).Count

                    if ($rendered -ne $loaded) {
                        Add-Failure "opencode loaded $loaded '$tier' bash pattern(s) from a file that renders $rendered"
                    }
                }
            }
        }
    }
    finally {
        $env:OPENCODE_CONFIG = $previousConfig
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
            if (@($rule.commands).Count -eq 0) { continue }
            if ($shellIds -notcontains $rule.id) {
                Add-Failure "cursor: rule '$($rule.id)' rendered no shell matcher"
            }
        }

        foreach ($rule in $policy.rules) {
            if ($rule.PSObject.Properties.Name -notcontains 'opencode_rules') { continue }
            $row = @($cursorRules.shell | Where-Object { $_.id -eq $rule.id }) | Select-Object -First 1
            if (-not $row) {
                Add-Failure "cursor: opencode_rules from '$($rule.id)' rendered no shell row"
                continue
            }
            $emitted = @($row.globs)
            foreach ($rawPattern in $rule.opencode_rules) {
                if ($emitted -cnotcontains $rawPattern) {
                    Add-Failure "cursor: glob '$rawPattern' from rule '$($rule.id)' is missing from rules.json"
                }
            }
        }
    }

    $sshPath = Join-Path $(if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }) '.ssh/config'
    $cases = @(
        @{ Name = 'read-only inspection is allowed'; Payload = '{"command":"git status"}'; Expect = 'allow' }
        @{
            Name          = 'confirm-tier pr create is denied with a handoff'
            Payload       = '{"command":"gh pr create --title test"}'
            Expect        = 'deny'
            AgentContains = 'Give the user this exact command'
        }
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
