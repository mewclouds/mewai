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
    'base.md' = 120
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

        if ($line -match 'â€“') {
            Add-Failure "$($module.Relative):${lineNumber}: en dash"
        }
        if ($line -match '[â€˜â€™â€œâ€]') {
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

            if ($rule.decision -notin @('confirm', 'forbid')) {
                Add-Failure "policy rule '$($rule.id)': unknown decision '$($rule.decision)'"
            }
            if ([string]::IsNullOrWhiteSpace($rule.why)) {
                Add-Failure "policy rule '$($rule.id)': no 'why'"
            }
        }

        $byDecision = @{ confirm = @(); forbid = @() }
        foreach ($rule in $policy.rules) {
            $byDecision[$rule.decision] += $rule.commands
        }
        foreach ($command in $byDecision.confirm) {
            if ($byDecision.forbid -contains $command) {
                Add-Failure "policy: '$command' is both confirm and forbid"
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

# --- opencode permissions ----------------------------------------------------
# OpenCode resolves a command by taking the last pattern that matches it, so
# tier order in the emitted object is the decision.

$bashRules = @()
$openCodePath = Join-Path $RepoRoot 'build/opencode/opencode.jsonc'
if (-not (Test-Path $openCodePath)) {
    Add-Failure 'build/opencode/opencode.jsonc is missing. Run scripts/render.ps1.'
}
else {
    $openCodeRaw = (Get-Content -Path $openCodePath -Raw) -replace "`r`n", "`n"

    try {
        $null = $openCodeRaw | ConvertFrom-Json -AsHashtable
        $openCode = $true
    }
    catch {
        Add-Failure "build/opencode/opencode.jsonc is not valid JSON: $_"
        $openCode = $false
    }

    if ($openCode) {
        $bashBlock = [regex]::Match($openCodeRaw, '(?s)"bash":\s*\{(.*?)\n    \}')
        $bashRules = [regex]::Matches($bashBlock.Groups[1].Value, '"((?:[^"\\]|\\.)*)":\s*"(ask|deny)"') |
            ForEach-Object { [pscustomobject]@{ Pattern = $_.Groups[1].Value; Action = $_.Groups[2].Value } }

        if ($bashRules.Count -eq 0) {
            Add-Failure 'opencode: permission.bash has no patterns'
        }

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

        $rank = @{ ask = 0; deny = 1 }
        $highest = -1
        foreach ($entry in $bashRules) {
            if ($rank[$entry.Action] -lt $highest) {
                Add-Failure ("opencode: permission.bash pattern '{0}' is '{1}' but sits below a stricter tier. Last match wins, so the stricter rule never fires. Emit ask, then deny." -f $entry.Pattern, $entry.Action)
                break
            }
            $highest = $rank[$entry.Action]
        }

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

            $emitted = @($bashRules | ForEach-Object { $_.Pattern })
            foreach ($rule in $policy.rules) {
                if ($rule.PSObject.Properties.Name -notcontains 'glob_rules') { continue }
                foreach ($raw in $rule.glob_rules) {
                    if ($emitted -cnotcontains $raw) {
                        Add-Failure "opencode: glob '$raw' from rule '$($rule.id)' is missing from permission.bash"
                    }
                }
            }
        }
    }
}

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
                foreach ($tier in @('ask', 'deny')) {
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

# --- codex execpolicy --------------------------------------------------------
# These assertions prove the rendered rules actually decide the way the policy says.
# They need a working codex binary. When there is not one, say so: a check that could
# not run must never read as a check that passed.

$HomeDir = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }
$codexRulesPath = Join-Path $RepoRoot 'build/codex/rules/default.rules'
$codexConfigPath = Join-Path $RepoRoot 'build/codex/config.toml'
$codexSourceConfig = Join-Path $RepoRoot 'core/providers/codex/config.toml'

if (-not (Test-Path $codexSourceConfig)) {
    Add-Failure 'core/providers/codex/config.toml is missing'
}
if (-not (Test-Path $codexRulesPath)) {
    Add-Failure 'build/codex/rules/default.rules is missing'
}
if (-not (Test-Path $codexConfigPath)) {
    Add-Failure 'build/codex/config.toml is missing'
}

if (Test-Path $codexRulesPath) {
    $rulesRaw = (Get-Content -Path $codexRulesPath -Raw) -replace "`r`n", "`n"

    if ($policy) {
        foreach ($rule in $policy.rules) {
            if (@($rule.commands).Count -eq 0) { continue }

            foreach ($command in $rule.commands) {
                $words = $command -split '\s+' | Where-Object { $_ }
                $pattern = ($words | ForEach-Object { '"' + $_ + '"' }) -join ', '
                if ($rulesRaw -notmatch [regex]::Escape("pattern=[$pattern]")) {
                    Add-Failure "codex: command '$command' from rule '$($rule.id)' rendered no prefix_rule"
                }
            }
        }
    }

    $codexCommand = Get-Command codex -ErrorAction SilentlyContinue
    $codexExe = if ($codexCommand) {
        $codexCommand.Source
    }
    else {
        $localApp = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $HomeDir 'AppData/Local' }
        $candidate = Get-ChildItem -Path (Join-Path $localApp 'OpenAI/Codex/bin/*/codex.exe') -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($candidate) { $candidate.FullName } else { $null }
    }

    $codexWorks = $false
    if ($codexExe) {
        try {
            & $codexExe --version *>$null
            $codexWorks = ($LASTEXITCODE -eq 0)
        }
        catch {
            $codexWorks = $false
        }
    }

    if (-not $codexWorks) {
        $reason = if ($codexExe) {
            "codex is at $codexExe but does not run"
        }
        else {
            'codex is not on PATH or local AppData'
        }
        $script:Skipped.Add("codex execpolicy assertions: $reason")
    }
    else {
        $cases = @(
            @{ Name = 'read-only inspection is allowed'; Args = @('rg', '--files'); Expect = 'allow' }
            @{ Name = 'git commit requires confirmation'; Args = @('git', 'commit', '-m', 'test'); Expect = 'prompt' }
            @{ Name = 'history rewrite is forbidden'; Args = @('git', 'clean'); Expect = 'forbidden' }
        )

        foreach ($case in $cases) {
            $result = & $codexExe execpolicy check --rules $codexRulesPath @($case.Args) 2>&1
            if ($LASTEXITCODE -ne 0) {
                Add-Failure "codex execpolicy could not evaluate '$($case.Name)': $result"
                continue
            }

            $parsed = $result | ConvertFrom-Json
            $decision = if ($parsed.PSObject.Properties.Name -contains 'decision') {
                $parsed.decision
            }
            elseif (
                ($parsed.PSObject.Properties.Name -contains 'matchedRules') -and
                (@($parsed.matchedRules).Count -eq 0)
            ) {
                # Codex 0.153 emits { matchedRules: [] } for unmatched commands, not decision=allow.
                'allow'
            }
            else {
                $null
            }

            if ($decision -ne $case.Expect) {
                Add-Failure "$($case.Name): expected '$($case.Expect)', got '$decision'"
            }
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
