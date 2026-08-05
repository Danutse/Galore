[CmdletBinding()]

param(
    [string]$GaloreRoot,
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"

if([string]::IsNullOrWhiteSpace($GaloreRoot))
{
    $GaloreRoot = $PSScriptRoot
}

$GaloreRoot = (Resolve-Path -LiteralPath $GaloreRoot).Path
$moduleRoot = Join-Path $GaloreRoot "Modules"
$resourceRoot = Join-Path $GaloreRoot "resources"
$mainScript = Join-Path $moduleRoot "GaloreLauncher.ps1"

if([string]::IsNullOrWhiteSpace($OutputPath))
{
    $OutputPath = Join-Path $GaloreRoot "Release\GaloreLauncher.exe"
}

foreach($requiredPath in @($moduleRoot, $resourceRoot, $mainScript))
{
    if(-not (Test-Path -LiteralPath $requiredPath))
    {
        throw "Release input is missing: $requiredPath"
    }
}

if(-not (Get-Command -Name ps2exe -ErrorAction SilentlyContinue))
{
    Import-Module ps2exe -ErrorAction Stop
}

function Get-GaloreCodeSigningCertificate {
    param([string]$Root)
    $certificatePath = Join-Path $Root "GaloreCodeSign.cer"
    if(-not (Test-Path -LiteralPath $certificatePath -PathType Leaf)) { throw "Galore code-signing certificate is missing: $certificatePath" }
    $publicCertificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($certificatePath)
    $certificate = @(Get-ChildItem Cert:\CurrentUser\My,Cert:\LocalMachine\My -ErrorAction SilentlyContinue | Where-Object { $_.Thumbprint -eq $publicCertificate.Thumbprint -and $_.HasPrivateKey } | Select-Object -First 1)[0]
    if($null -eq $certificate) { throw "The private key for the Galore code-signing certificate is not installed for this Windows account." }
    return $certificate
}

function Sign-GaloreBinary {
    param([string]$Path, [string]$Root)
    $certificate = Get-GaloreCodeSigningCertificate -Root $Root
    try { Set-AuthenticodeSignature -FilePath $Path -Certificate $certificate -HashAlgorithm SHA256 -TimestampServer "http://timestamp.digicert.com" | Out-Null }
    catch { Set-AuthenticodeSignature -FilePath $Path -Certificate $certificate -HashAlgorithm SHA256 | Out-Null; Write-Warning "Galore binary was signed without a timestamp: $Path" }
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if($null -eq $signature.SignerCertificate -or $signature.SignerCertificate.Thumbprint -ne $certificate.Thumbprint) { throw "Galore binary signing verification failed: $Path" }
}

$moduleFiles = @(Get-ChildItem -LiteralPath $moduleRoot -Filter *.ps1 -File | Where-Object { $_.Name -ne "GaloreLauncher.ps1" } | Sort-Object Name)
$resourceFiles = @(Get-ChildItem -LiteralPath $resourceRoot -Recurse -File | Sort-Object FullName)

if($moduleFiles.Count -eq 0)
{
    throw "No Galore modules were found to bundle."
}

if($resourceFiles.Count -eq 0)
{
    throw "No Galore resources were found to bundle."
}

$builder = New-Object System.Text.StringBuilder
[void]$builder.AppendLine('$script:GaloreEmbeddedResourceFiles = [ordered]@{')
$resourceSignature = New-Object System.Text.StringBuilder

foreach($resourceFile in $resourceFiles)
{
    $relativeName = $resourceFile.FullName.Substring($resourceRoot.Length).TrimStart([char]'\', [char]'/')
    $resourceBytes = [System.IO.File]::ReadAllBytes($resourceFile.FullName)
    $encoded = [System.Convert]::ToBase64String($resourceBytes)
    $resourceHash = (Get-FileHash -LiteralPath $resourceFile.FullName -Algorithm SHA256).Hash
    [void]$resourceSignature.AppendLine("$relativeName|$resourceHash")
    [void]$builder.AppendLine(("    '{0}' = '{1}'" -f $relativeName.Replace("'", "''"), $encoded))
}

[void]$builder.AppendLine('}')
$resourceVersionBytes = [System.Text.Encoding]::UTF8.GetBytes($resourceSignature.ToString())
$resourceVersion = ([System.Security.Cryptography.SHA256]::Create().ComputeHash($resourceVersionBytes) | ForEach-Object { $_.ToString('x2') }) -join ''
[void]$builder.AppendLine(("`$script:GaloreEmbeddedResourceVersion = '{0}'" -f $resourceVersion))
[void]$builder.AppendLine()
[void]$builder.AppendLine('$script:GaloreEmbeddedModuleSources = [ordered]@{')

foreach($moduleFile in $moduleFiles)
{
    $source = [System.IO.File]::ReadAllText($moduleFile.FullName)
    $encoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($source))
    [void]$builder.AppendLine(("    '{0}' = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('{1}'))" -f $moduleFile.Name, $encoded))
}

[void]$builder.AppendLine('}')
[void]$builder.AppendLine()
[void]$builder.Append([System.IO.File]::ReadAllText($mainScript))

$flattenedSource = $builder.ToString()
$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseInput($flattenedSource, "GaloreRelease.ps1", [ref]$tokens, [ref]$parseErrors) | Out-Null

if($parseErrors.Count -gt 0)
{
    throw "The generated release script does not parse: $($parseErrors[0].Message)"
}

$outputFolder = [System.IO.Path]::GetDirectoryName($OutputPath)
New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null

$stagingPath = Join-Path ([System.IO.Path]::GetTempPath()) ("GaloreRelease-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $stagingPath -Force | Out-Null

try
{
    $generatedScript = Join-Path $stagingPath "GaloreRelease.ps1"
    $temporaryOutput = Join-Path $stagingPath "GaloreLauncher.exe"
    [System.IO.File]::WriteAllText($generatedScript, $flattenedSource, [System.Text.UTF8Encoding]::new($false))

    ps2exe `
    -inputFile $generatedScript `
    -outputFile $temporaryOutput `
    -noConsole `
    -iconFile (Join-Path $resourceRoot "Galore.ico") `
    -title "Galore Launcher" `
    -description "Interface Manager" `
    -company "Galore Inc." `
    -product "Galore Launcher" `
    -trademark "Galore" `
    -version "1.0.0.0" `
    -copyright "Copyright (c) 2026 Galore Inc."

    if(-not (Test-Path -LiteralPath $temporaryOutput -PathType Leaf))
    {
        throw "PS2EXE did not create the bundled Galore release."
    }

    Sign-GaloreBinary -Path $temporaryOutput -Root $GaloreRoot
    Move-Item -LiteralPath $temporaryOutput -Destination $OutputPath -Force
    "Bundled Galore release created: $OutputPath"
}
finally
{
    Remove-Item -LiteralPath $stagingPath -Recurse -Force -ErrorAction SilentlyContinue
}
