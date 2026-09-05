#!/usr/bin/env pwsh
# Rendered companion: ./rules.json. Hermes runs this via mewai-hook.cmd.
# Covers read_file, the tool approvals.deny cannot see. Terminal commands are
# already covered by the generated approvals.deny block in config.yaml.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Convert-GlobToRegex {
    param([string]$Glob)

    $escaped = [regex]::Escape($Glob)
    $escaped = $escaped.Replace('\*\*', '<<GLOBSTAR>>')
    $escaped = $escaped.Replace('\*', '.*')
    $escaped = $escaped.Replace('\?', '.')
    $escaped.Replace('<<GLOBSTAR>>', '.*')
}

function Test-ReadPath {
    param([string]$FilePath, [string]$Pattern, [string]$HomeDir)

    if ([string]::IsNullOrWhiteSpace($FilePath)) { return $false }

    $normalized = ($FilePath -replace '\\', '/').TrimEnd('/')
    $glob = ($Pattern -replace '\\', '/').TrimEnd('/')
    if ($glob.StartsWith('~/')) {
        $glob = ($HomeDir.TrimEnd('/', '\') + $glob.Substring(1)) -replace '\\', '/'
    }

    if ($glob -notmatch '[\*\?]') {
        $leaf = Split-Path -Path $normalized -Leaf
        return (
            [string]::Compare($normalized, $glob, $true) -eq 0 -or
            [string]::Compare($leaf, $glob, $true) -eq 0 -or
            $normalized.EndsWith('/' + $glob, [System.StringComparison]::OrdinalIgnoreCase)
        )
    }

    [regex]::IsMatch($normalized, (Convert-GlobToRegex -Glob $glob), 'IgnoreCase')
}

function Write-Allow {
    # Empty object means proceed. Hermes treats no output the same way, but an
    # explicit {} makes a truncated write distinguishable from a silent pass.
    [Console]::Out.WriteLine('{}')
    exit 0
}

function Write-Block {
    param([string]$Message)

    $payload = [ordered]@{ action = 'block'; message = $Message }
    [Console]::Out.WriteLine(($payload | ConvertTo-Json -Compress -Depth 5))
    exit 0
}

$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { Write-Allow }

try {
    $event = ConvertFrom-Json -InputObject $raw
}
catch {
    Write-Block -Message 'mewai: could not parse the hook payload, so the read cannot be checked against the policy.'
}

$rulesPath = Join-Path $PSScriptRoot 'rules.json'
if (-not (Test-Path $rulesPath)) {
    Write-Block -Message 'mewai: rules.json is missing next to the hook, so no read is verifiable. Reinstall mewai.'
}

$rules = Get-Content -Path $rulesPath -Raw | ConvertFrom-Json
$homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }

# Hermes does not document the argument name read_file uses for its path, and it
# differs between call shapes. Checking every string in tool_input costs nothing
# and cannot miss the path by guessing the wrong key.
$candidates = [System.Collections.Generic.List[string]]::new()
if ($event.PSObject.Properties.Name -contains 'tool_input' -and $event.tool_input) {
    foreach ($prop in $event.tool_input.PSObject.Properties) {
        if ($prop.Value -is [string]) { $candidates.Add([string]$prop.Value) }
    }
}

if ($candidates.Count -eq 0) { Write-Allow }

foreach ($rule in @($rules.read)) {
    foreach ($pattern in @($rule.patterns)) {
        foreach ($candidate in $candidates) {
            if (Test-ReadPath -FilePath $candidate -Pattern $pattern -HomeDir $homeDir) {
                Write-Block -Message "mewai policy '$($rule.id)' blocks reading $candidate. $($rule.why) Do not retry, rephrase, or reach the same file through another tool."
            }
        }
    }
}

Write-Allow
