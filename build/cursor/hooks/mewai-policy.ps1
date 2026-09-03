#!/usr/bin/env pwsh
# Rendered companion: ./rules.json. Cursor runs this from ~/.cursor/.
# Exit 0 always when a decision is produced so agent_message is delivered.
# No CmdletBinding: it can steal stdin and leave Cursor with an empty hook result.
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

function Get-CommandTokens {
    param([string]$Command)
    @($Command -split '\s+' | Where-Object { $_ })
}

function Test-TokenSequence {
    param([string[]]$Haystack, [string[]]$Needle)

    if ($Needle.Count -eq 0 -or $Haystack.Count -lt $Needle.Count) {
        return $false
    }

    $limit = $Haystack.Count - $Needle.Count
    for ($i = 0; $i -le $limit; $i++) {
        $matched = $true
        for ($j = 0; $j -lt $Needle.Count; $j++) {
            if ([string]::Compare($Haystack[$i + $j], $Needle[$j], $true) -ne 0) {
                $matched = $false
                break
            }
        }
        if ($matched) {
            return $true
        }
    }

    $false
}

function Test-GlobAgainst {
    param([string]$Text, [string]$Glob)

    if ([string]::IsNullOrWhiteSpace($Glob)) {
        return $false
    }

    [regex]::IsMatch($Text, (Convert-GlobToRegex -Glob $Glob), 'IgnoreCase')
}

function Test-ReadPath {
    param([string]$FilePath, [string]$Pattern, [string]$HomeDir)

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

    Test-GlobAgainst -Text $normalized -Glob $glob
}

function Write-Decision {
    param(
        [string]$Permission,
        [string]$UserMessage = '',
        [string]$AgentMessage = ''
    )

    $payload = [ordered]@{ permission = $Permission }
    if ($UserMessage) { $payload.user_message = $UserMessage }
    if ($AgentMessage) { $payload.agent_message = $AgentMessage }
    [Console]::Out.WriteLine(($payload | ConvertTo-Json -Compress -Depth 5))
}

function Test-CompleteJson {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    try {
        $null = ConvertFrom-Json -InputObject $Text
        $true
    }
    catch {
        $false
    }
}

function Get-HookStdin {
    <#
        Cursor keeps stdin open, so ReadToEnd hangs.
        A single Read is also wrong: Windows anonymous pipes often
        return 4KB even when more JSON is already buffered, and
        beforeReadFile includes the whole file in "content".
        Keep reading until the bytes so far are valid JSON.
        After the first byte, an idle timeout stops us from blocking
        forever on a pipe that never sends EOF.
    #>
    $maxBytes = 16MB
    $idleTimeoutMs = 1000
    $chunkBytes = 65536

    try {
        $stdin = [Console]::OpenStandardInput()
        $ms = [System.IO.MemoryStream]::new()
        $buffer = [byte[]]::new($chunkBytes)
        $gotAny = $false

        while ($ms.Length -lt $maxBytes) {
            if (-not $gotAny) {
                $read = $stdin.Read($buffer, 0, $buffer.Length)
            }
            else {
                $async = $stdin.BeginRead($buffer, 0, $buffer.Length, $null, $null)
                if (-not $async.AsyncWaitHandle.WaitOne($idleTimeoutMs)) {
                    break
                }
                $read = $stdin.EndRead($async)
            }

            if ($read -le 0) {
                break
            }

            $gotAny = $true
            $ms.Write($buffer, 0, $read)
            $text = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()).Trim().Trim([char]0xFEFF)
            if (Test-CompleteJson -Text $text) {
                return $text
            }
        }

        if ($ms.Length -le 0) {
            return ''
        }

        return [System.Text.Encoding]::UTF8.GetString($ms.ToArray()).Trim().Trim([char]0xFEFF)
    }
    catch {
        return ''
    }
}

try {
$rulesPath = Join-Path $PSScriptRoot 'rules.json'
if (-not (Test-Path $rulesPath)) {
    throw "mewai cursor policy rules not found: $rulesPath"
}

$rules = Get-Content -Path $rulesPath -Raw | ConvertFrom-Json
$raw = Get-HookStdin
if ([string]::IsNullOrWhiteSpace($raw)) {
    Write-Decision -Permission 'allow'
    exit 0
}

try {
    $inputObject = ConvertFrom-Json -InputObject $raw
}
catch {
    throw "hook stdin JSON parse failed ($($raw.Length) chars): $($_.Exception.Message)"
}
$homeDir = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }

$command = $null
$commandProp = $inputObject.PSObject.Properties['command']
if ($null -ne $commandProp -and $null -ne $commandProp.Value) {
    $command = [string]$commandProp.Value
}

$filePath = $null
$fileProp = $inputObject.PSObject.Properties['file_path']
if ($null -eq $fileProp) {
    $fileProp = $inputObject.PSObject.Properties['filePath']
}
if ($null -ne $fileProp -and $null -ne $fileProp.Value) {
    $filePath = [string]$fileProp.Value
}

if ($command) {
    $tokens = @(Get-CommandTokens -Command $command)
    foreach ($rule in @($rules.shell)) {
        $hit = $false
        foreach ($phrase in @($rule.tokens)) {
            $needle = @(Get-CommandTokens -Command ([string]$phrase))
            if (Test-TokenSequence -Haystack $tokens -Needle $needle) {
                $hit = $true
                break
            }
        }
        if (-not $hit) {
            foreach ($glob in @($rule.globs)) {
                if (Test-GlobAgainst -Text $command -Glob ([string]$glob)) {
                    $hit = $true
                    break
                }
            }
        }
        if (-not $hit) {
            continue
        }

        if ($rule.tier -eq 'confirm') {
            Write-Decision -Permission 'deny' `
                -UserMessage "Blocked ($($rule.id)). Run this yourself in a terminal." `
                -AgentMessage ("Blocked by mewai rule '{0}'. {1} Do not retry or wrap it. Give the user this exact command to run themselves: {2}" -f $rule.id, $rule.why, $command)
            exit 0
        }

        Write-Decision -Permission 'deny' `
            -UserMessage "Blocked ($($rule.id))." `
            -AgentMessage ("Blocked by mewai rule '{0}'. {1} Do not retry, wrap, or ask the user to run it on your behalf." -f $rule.id, $rule.why)
        exit 0
    }

    Write-Decision -Permission 'allow'
    exit 0
}

if ($filePath) {
    foreach ($rule in @($rules.read)) {
        foreach ($pattern in @($rule.patterns)) {
            if (Test-ReadPath -FilePath $filePath -Pattern ([string]$pattern) -HomeDir $homeDir) {
                Write-Decision -Permission 'deny' `
                    -UserMessage "Blocked ($($rule.id)): secret file read." `
                    -AgentMessage ("Blocked by mewai rule '{0}'. {1} Do not retry or read an equivalent secret path." -f $rule.id, $rule.why)
                exit 0
            }
        }
    }

    Write-Decision -Permission 'allow'
    exit 0
}

Write-Decision -Permission 'allow'
exit 0
}
catch {
    Write-Decision -Permission 'deny' `
        -UserMessage ("mewai hook failed closed: {0}" -f $_.Exception.Message) `
        -AgentMessage ("mewai cursor hook error: {0} Do not retry around the hook." -f $_.Exception.Message)
    exit 0
}
