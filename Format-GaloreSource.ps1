[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"

function Get-GaloreParenthesisDelta {
    param([string]$Line)
    $delta = 0
    $singleQuoted = $false
    $doubleQuoted = $false
    $escaped = $false
    for($index = 0; $index -lt $Line.Length; $index++) {
        $character = $Line[$index]
        if($escaped) { $escaped = $false; continue }
        if($character -eq '`' -and -not $singleQuoted) { $escaped = $true; continue }
        if($character -eq "'" -and -not $doubleQuoted) { $singleQuoted = -not $singleQuoted; continue }
        if($character -eq '"' -and -not $singleQuoted) { $doubleQuoted = -not $doubleQuoted; continue }
        if($character -eq '#' -and -not $singleQuoted -and -not $doubleQuoted) { break }
        if($singleQuoted -or $doubleQuoted) { continue }
        if($character -eq '(') { $delta++ }
        elseif($character -eq ')') { $delta-- }
    }
    return $delta
}

function Get-GaloreBraceDelta {
    param([string]$Line)
    $delta = 0
    $singleQuoted = $false
    $doubleQuoted = $false
    $escaped = $false
    for($index = 0; $index -lt $Line.Length; $index++) {
        $character = $Line[$index]
        if($escaped) { $escaped = $false; continue }
        if($character -eq '`' -and -not $singleQuoted) { $escaped = $true; continue }
        if($character -eq "'" -and -not $doubleQuoted) { $singleQuoted = -not $singleQuoted; continue }
        if($character -eq '"' -and -not $singleQuoted) { $doubleQuoted = -not $doubleQuoted; continue }
        if($character -eq '#' -and -not $singleQuoted -and -not $doubleQuoted) { break }
        if($singleQuoted -or $doubleQuoted) { continue }
        if($character -eq '{') { $delta++ }
        elseif($character -eq '}') { $delta-- }
    }
    return $delta
}

function Join-GaloreSourceText {
    param([string]$Left, [string]$Right)
    $leftText = $Left.TrimEnd()
    $rightText = $Right.TrimStart()
    if($leftText.EndsWith('(') -or $rightText.StartsWith(')') -or $rightText.StartsWith(']') -or $rightText.StartsWith('.')) { return $leftText + $rightText }
    return "$leftText $rightText"
}

function Format-GaloreCodeChunk {
    param([string[]]$Lines)
    $sourceLines = @($Lines | ForEach-Object { $_.TrimEnd() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if($sourceLines.Count -eq 0) { return @() }

    $continuedLines = [System.Collections.Generic.List[string]]::new()
    for($index = 0; $index -lt $sourceLines.Count; $index++) {
        $current = $sourceLines[$index]
        while($current.TrimEnd().EndsWith('`') -and $index + 1 -lt $sourceLines.Count -and -not $current.TrimStart().StartsWith('#')) {
            $current = $current.TrimEnd()
            $current = $current.Substring(0, $current.Length - 1)
            $index++
            $current = Join-GaloreSourceText -Left $current -Right $sourceLines[$index]
        }
        $continuedLines.Add($current)
    }

    $logicalLines = [System.Collections.Generic.List[string]]::new()
    $buffer = $null
    $parenthesisDepth = 0
    $braceDepth = 0
    foreach($line in $continuedLines) {
        $trimmed = $line.Trim()
        if($trimmed.StartsWith('#')) {
            if($null -ne $buffer) { $logicalLines.Add($buffer); $buffer = $null; $parenthesisDepth = 0; $braceDepth = 0 }
            $logicalLines.Add($line)
            continue
        }
        if($null -eq $buffer) { $buffer = $line }
        else { $buffer = Join-GaloreSourceText -Left $buffer -Right $line }
        $parenthesisDepth += Get-GaloreParenthesisDelta -Line $line
        $braceDepth += Get-GaloreBraceDelta -Line $line
        $containsArrayExpression = $buffer -match '@\('
        $continues = ($braceDepth -eq 0 -and -not $containsArrayExpression -and $parenthesisDepth -gt 0) -or $buffer.TrimEnd() -match '(?x)(=|\+=|-=|\*=|/=|\||,|-and|-or|-xor|(?<!\+)\+|::)$'
        if(-not $continues) { $logicalLines.Add($buffer); $buffer = $null; $parenthesisDepth = 0; $braceDepth = 0 }
    }
    if($null -ne $buffer) { $logicalLines.Add($buffer) }

    $braceLines = [System.Collections.Generic.List[string]]::new()
    foreach($line in $logicalLines) {
        $normalizedLine = if($line.TrimStart().StartsWith('#')) { $line } else { $line -replace '\)\{$', ') {' }
        $trimmed = $normalizedLine.Trim()
        if($trimmed -eq '{' -and $braceLines.Count -gt 0 -and -not $braceLines[$braceLines.Count - 1].TrimStart().StartsWith('#')) {
            $braceLines[$braceLines.Count - 1] = $braceLines[$braceLines.Count - 1].TrimEnd() + ' {'
            continue
        }
        if($trimmed -match '^(else|elseif\b.*|catch\b.*|finally)$' -and $braceLines.Count -gt 0 -and $braceLines[$braceLines.Count - 1].Trim() -eq '}') {
            $indent = $braceLines[$braceLines.Count - 1].Substring(0, $braceLines[$braceLines.Count - 1].Length - $braceLines[$braceLines.Count - 1].TrimStart().Length)
            $braceLines[$braceLines.Count - 1] = "$indent} $trimmed"
            continue
        }
        $braceLines.Add($normalizedLine)
    }

    $formatted = [System.Collections.Generic.List[string]]::new()
    for($index = 0; $index -lt $braceLines.Count; $index++) {
        $headerEnd = -1
        if($braceLines[$index].Trim() -match '^# ={10,}$') {
            $probe = $index + 1
            while($probe -lt $braceLines.Count -and $braceLines[$probe].TrimStart().StartsWith('#')) {
                if($braceLines[$probe].Trim() -match '^# ={10,}$') { $headerEnd = $probe; break }
                $probe++
            }
        }
        if($headerEnd -gt $index + 1) {
            if($formatted.Count -gt 0 -and $formatted[$formatted.Count - 1] -ne '') { $formatted.Add('') }
            foreach($headerIndex in $index..$headerEnd) { $formatted.Add($braceLines[$headerIndex].TrimEnd()) }
            $formatted.Add('')
            $index = $headerEnd
            continue
        }
        if($braceLines[$index].TrimStart().StartsWith('function ') -and $formatted.Count -gt 0 -and $formatted[$formatted.Count - 1] -ne '') { $formatted.Add('') }
        $formatted.Add($braceLines[$index])
    }
    while($formatted.Count -gt 0 -and $formatted[$formatted.Count - 1] -eq '') { $formatted.RemoveAt($formatted.Count - 1) }
    return $formatted.ToArray()
}

$resolvedPath = (Resolve-Path -LiteralPath $Path).Path
if([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = $resolvedPath }
$originalSource = [IO.File]::ReadAllText($resolvedPath)
$sourceNewLine = if($originalSource.Contains("`r`n")) { "`r`n" } else { "`n" }
$originalTokens = $null
$originalErrors = $null
[System.Management.Automation.Language.Parser]::ParseInput($originalSource, $resolvedPath, [ref]$originalTokens, [ref]$originalErrors) | Out-Null
if($originalErrors.Count -gt 0) { throw "Cannot format invalid PowerShell source '$resolvedPath': $($originalErrors[0].Message)" }
$inputLines = [IO.File]::ReadAllLines($resolvedPath)
$outputLines = [System.Collections.Generic.List[string]]::new()
$codeChunk = [System.Collections.Generic.List[string]]::new()
$protectedLines = [System.Collections.Generic.HashSet[int]]::new()
$protectedOutputLines = [System.Collections.Generic.HashSet[int]]::new()
$protectedTokenKinds = @('HereStringExpandable', 'HereStringLiteral', 'StringExpandable', 'StringLiteral', 'Comment')
foreach($token in $originalTokens) {
    if($token.Kind.ToString() -in $protectedTokenKinds -and $token.Extent.EndLineNumber -gt $token.Extent.StartLineNumber) {
        foreach($lineNumber in $token.Extent.StartLineNumber..$token.Extent.EndLineNumber) { $protectedLines.Add($lineNumber) | Out-Null }
    }
}

for($lineIndex = 0; $lineIndex -lt $inputLines.Count; $lineIndex++) {
    $line = $inputLines[$lineIndex]
    if($protectedLines.Contains($lineIndex + 1)) {
        foreach($formattedLine in @(Format-GaloreCodeChunk -Lines $codeChunk.ToArray())) { $outputLines.Add($formattedLine) }
        $codeChunk.Clear()
        $protectedOutputLines.Add($outputLines.Count) | Out-Null
        $outputLines.Add($line)
        continue
    }
    $codeChunk.Add($line)
}
foreach($formattedLine in @(Format-GaloreCodeChunk -Lines $codeChunk.ToArray())) { $outputLines.Add($formattedLine) }

$braceDepth = 0
for($outputIndex = 0; $outputIndex -lt $outputLines.Count; $outputIndex++) {
    if($protectedOutputLines.Contains($outputIndex)) { continue }
    $line = $outputLines[$outputIndex]
    if([string]::IsNullOrWhiteSpace($line)) { continue }
    $trimmed = $line.TrimStart()
    $lineDepth = if($trimmed.StartsWith('}')) { [Math]::Max(0, $braceDepth - 1) } else { $braceDepth }
    $minimumIndent = $lineDepth * 4
    $currentIndent = $line.Length - $trimmed.Length
    if($currentIndent -lt $minimumIndent) { $outputLines[$outputIndex] = (' ' * $minimumIndent) + $trimmed }
    $braceDepth += Get-GaloreBraceDelta -Line $line
    if($braceDepth -lt 0) { $braceDepth = 0 }
}

$formattedSource = ($outputLines -join $sourceNewLine).TrimEnd() + $sourceNewLine
$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseInput($formattedSource, $OutputPath, [ref]$tokens, [ref]$parseErrors) | Out-Null
if($parseErrors.Count -gt 0) {
    $failure = $parseErrors[0]
    [IO.File]::WriteAllText("$OutputPath.invalid", $formattedSource, [Text.UTF8Encoding]::new($false))
    throw "Formatting '$resolvedPath' produced invalid PowerShell at line $($failure.Extent.StartLineNumber): $($failure.Message) Source: $($failure.Extent.Text)"
}
$ignoredTokenKinds = @('NewLine', 'LineContinuation', 'EndOfInput')
$originalSignature = @($originalTokens | Where-Object { $_.Kind.ToString() -notin $ignoredTokenKinds } | ForEach-Object { "$($_.Kind)|$($_.Text)" })
$formattedSignature = @($tokens | Where-Object { $_.Kind.ToString() -notin $ignoredTokenKinds } | ForEach-Object { "$($_.Kind)|$($_.Text)" })
if($originalSignature.Count -ne $formattedSignature.Count) { throw "Formatting '$resolvedPath' changed its significant token count." }
for($index = 0; $index -lt $originalSignature.Count; $index++) {
    if($originalSignature[$index] -cne $formattedSignature[$index]) { throw "Formatting '$resolvedPath' changed token $index from '$($originalSignature[$index])' to '$($formattedSignature[$index])'." }
}
[IO.File]::WriteAllText($OutputPath, $formattedSource, [Text.UTF8Encoding]::new($false))
