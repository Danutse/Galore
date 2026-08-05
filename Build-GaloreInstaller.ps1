[CmdletBinding()]

param(
    [string]$GaloreRoot,

    [string]$OutputPath,

    [switch]$SkipApplicationCompile
)



$ErrorActionPreference =
"Stop"



Add-Type `
-AssemblyName System.IO.Compression



Add-Type `
-AssemblyName System.IO.Compression.FileSystem



if([string]::IsNullOrWhiteSpace($GaloreRoot))
{

    $GaloreRoot =
    $PSScriptRoot

}



$GaloreRoot =
(Resolve-Path `
-LiteralPath $GaloreRoot).Path

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




if([string]::IsNullOrWhiteSpace($OutputPath))
{

    $OutputPath =
    Join-Path `
    $GaloreRoot `
    "Installers\GaloreLauncherSetup.exe"

}



$moduleRoot =
Join-Path `
$GaloreRoot `
"Modules"



$resourceRoot =
Join-Path `
$GaloreRoot `
"resources"



$programRoot =
Join-Path `
$GaloreRoot `
"Programs"



$mainScript =
Join-Path `
$moduleRoot `
"GaloreLauncher.ps1"



$applicationPath =
Join-Path `
$GaloreRoot `
"GaloreLauncher.exe"




$releaseBuilder =
Join-Path `
$GaloreRoot `
"Build-GaloreRelease.ps1"



$releaseApplicationPath =
Join-Path `
$GaloreRoot `
"Release\GaloreLauncher.exe"



$releaseSmokeScript =
Join-Path `
$GaloreRoot `
"Test-GaloreReleaseRuntime.ps1"



$installerSmokeScript =
Join-Path `
$GaloreRoot `
"Test-GaloreInstallerSmoke.ps1"



$installerScript =
Join-Path `
$GaloreRoot `
"Installer\Install-Galore.ps1"




$uninstallerScript =
Join-Path `
$GaloreRoot `
"Installer\Uninstall-Galore.ps1"



foreach($requiredPath in @(
    $moduleRoot,
    $resourceRoot,
    $programRoot,
    $mainScript,
    $installerScript,
    $uninstallerScript,
    $releaseBuilder,
    $releaseSmokeScript,
    $installerSmokeScript
))
{

    if(-not (Test-Path -LiteralPath $requiredPath))
    {

        throw "Installer input is missing: $requiredPath"

    }

}



if(
    Get-Process `
    -Name "GaloreLauncher" `
    -ErrorAction SilentlyContinue
)
{

    throw "Close Galore Launcher before building its installer."

}



& (Join-Path $GaloreRoot "Test-GaloreBuild.ps1") `
-Compile



if($LASTEXITCODE -ne 0)
{

    throw "Galore build validation failed; the installer was not created."

}



if(-not $SkipApplicationCompile)
{

    if(
        -not (
            Get-Command `
            -Name ps2exe `
            -ErrorAction SilentlyContinue
        )
    )
    {

        Import-Module `
        ps2exe `
        -ErrorAction Stop

    }



    $temporaryApplicationPath =
    Join-Path `
    ([System.IO.Path]::GetTempPath()) `
    ("GaloreLauncher-{0}.exe" -f [guid]::NewGuid().ToString("N"))



    try
    {

        ps2exe `
        -inputFile $mainScript `
        -outputFile $temporaryApplicationPath `
        -noConsole `
        -iconFile (Join-Path $resourceRoot "Galore.ico") `
        -title "Galore Launcher" `
        -description "Interface Manager" `
        -company "Galore Inc." `
        -product "Galore Launcher" `
        -trademark "Galore" `
        -version "1.0.0.0" `
        -copyright "Copyright (c) 2026 Galore Inc."



        Sign-GaloreBinary `
        -Path $temporaryApplicationPath `
        -Root $GaloreRoot

        Move-Item `
        -LiteralPath $temporaryApplicationPath `
        -Destination $applicationPath `
        -Force

    }
    finally
    {

        Remove-Item `
        -LiteralPath $temporaryApplicationPath `
        -Force `
        -ErrorAction SilentlyContinue

    }

}



if(-not (Test-Path -LiteralPath $applicationPath -PathType Leaf))
{

    throw "The current Galore executable is missing."

}



& $releaseBuilder `
-GaloreRoot $GaloreRoot `
-OutputPath $releaseApplicationPath



if($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $releaseApplicationPath -PathType Leaf))
{

    throw "The bundled Galore release could not be created."

}



& $releaseSmokeScript `
-GaloreRoot $GaloreRoot `
-ReleasePath $releaseApplicationPath



if($LASTEXITCODE -ne 0)
{

    throw "The bundled Galore release failed its isolated startup smoke test."

}



$outputFolder =
[System.IO.Path]::GetDirectoryName(
    $OutputPath
)



New-Item `
-ItemType Directory `
-Path $outputFolder `
-Force |
Out-Null



$stagingPath =
Join-Path `
([System.IO.Path]::GetTempPath()) `
("GaloreInstaller-{0}" -f [guid]::NewGuid().ToString("N"))



New-Item `
-ItemType Directory `
-Path $stagingPath `
-Force |
Out-Null




if(
    -not (
        Get-Command `
        -Name ps2exe `
        -ErrorAction SilentlyContinue
    )
)
{

    Import-Module `
    ps2exe `
    -ErrorAction Stop

}



try
{

    $payloadPath =
    Join-Path `
    $stagingPath `
    "GalorePayload.zip"




    $payloadApplicationPath =
    Join-Path `
    $stagingPath `
    "GaloreLauncher.exe"



    Copy-Item `
    -LiteralPath $releaseApplicationPath `
    -Destination $payloadApplicationPath `
    -Force




    $temporaryUninstallerPath =
    Join-Path `
    $stagingPath `
    "Uninstall-Galore.exe"



    ps2exe `
    -inputFile $uninstallerScript `
    -outputFile $temporaryUninstallerPath `
    -noConsole `
    -STA `
    -iconFile (Join-Path $resourceRoot "Galore.ico") `
    -title "Uninstall Galore Launcher" `
    -description "Galore Launcher uninstaller" `
    -company "Galore Inc." `
    -product "Galore Launcher Uninstaller" `
    -trademark "Galore" `
    -version "1.0.0.0" `
    -copyright "Copyright (c) 2026 Galore Inc."



    if(-not (Test-Path -LiteralPath $temporaryUninstallerPath -PathType Leaf))
    {

        throw "PS2EXE did not create the Galore uninstaller."

    }

    Sign-GaloreBinary `
    -Path $temporaryUninstallerPath `
    -Root $GaloreRoot



    Compress-Archive `
    -LiteralPath @(
        $payloadApplicationPath,
        $temporaryUninstallerPath,
        $programRoot
    ) `
    -DestinationPath $payloadPath `
    -CompressionLevel Optimal



    $generatedInstallerScript =
    Join-Path `
    $stagingPath `
    "GaloreLauncherSetup.ps1"



    $payloadBase64 =
    [System.Convert]::ToBase64String(
        [System.IO.File]::ReadAllBytes($payloadPath)
    )



    $installerTemplate =
    Get-Content `
    -LiteralPath $installerScript `
    -Raw `
    -ErrorAction Stop



    if($installerTemplate -notmatch "__GALORE_PAYLOAD_BASE64__")
    {

        throw "The Galore installer template does not contain its payload marker."

    }



    [System.IO.File]::WriteAllText(
        $generatedInstallerScript,
        $installerTemplate.Replace(
            "__GALORE_PAYLOAD_BASE64__",
            $payloadBase64
        ),
        (New-Object System.Text.UTF8Encoding($false))
    )



    if(
        -not (
            Get-Command `
            -Name ps2exe `
            -ErrorAction SilentlyContinue
        )
    )
    {

        Import-Module `
        ps2exe `
        -ErrorAction Stop

    }



    $temporarySetupPath =
    Join-Path `
    $stagingPath `
    "GaloreLauncherSetup.exe"



    ps2exe `
    -inputFile $generatedInstallerScript `
    -outputFile $temporarySetupPath `
    -noConsole `
    -STA `
    -iconFile (Join-Path $resourceRoot "Galore.ico") `
    -title "Galore Launcher Setup" `
    -description "Galore Launcher installer" `
    -company "Galore Inc." `
    -product "Galore Launcher Setup" `
    -trademark "Galore" `
    -version "1.0.0.0" `
    -copyright "Copyright (c) 2026 Galore Inc."



    if(-not (Test-Path -LiteralPath $temporarySetupPath -PathType Leaf))
    {

        throw "PS2EXE did not create the Galore installer."

    }

    Sign-GaloreBinary `
    -Path $temporarySetupPath `
    -Root $GaloreRoot



    $smokePath =
    Join-Path `
    $stagingPath `
    "SmokeTest"



    [System.IO.Compression.ZipFile]::ExtractToDirectory(
        $payloadPath,
        $smokePath
    )



    foreach($expectedPath in @(
        "GaloreLauncher.exe",
        "Uninstall-Galore.exe",
        "Programs\scrcpy\playphone.vbs",
        "Programs\NvidiaSensor\NvidiaSensorReader.exe"
    ))
    {

        if(
            -not (
                Test-Path `
                -LiteralPath (Join-Path $smokePath $expectedPath)
            )
        )
        {

            throw "Installer payload smoke test failed: missing $expectedPath"

        }

    }



    if(Test-Path -LiteralPath (Join-Path $smokePath "Modules"))
    {

        throw "Installer payload smoke test contains the development Modules folder."

    }

    if(Test-Path -LiteralPath (Join-Path $smokePath "resources"))
    {

        throw "Installer payload smoke test contains the release resources folder."

    }



    if(@(Get-ChildItem -LiteralPath $smokePath -Recurse -Filter *.ps1 -File).Count -gt 0)
    {

        throw "Installer payload smoke test contains editable PowerShell source files."

    }



    if(Test-Path -LiteralPath $OutputPath -PathType Leaf)
    {

        Remove-Item `
        -LiteralPath $OutputPath `
        -Force

    }



    Move-Item `
    -LiteralPath $temporarySetupPath `
    -Destination $OutputPath `
    -Force



    & $installerSmokeScript `
    -GaloreRoot $GaloreRoot `
    -SetupPath $OutputPath



    if($LASTEXITCODE -ne 0)
    {

        throw "The installer failed its isolated installation smoke test."

    }



    Write-Host "Installer created and payload smoke-tested: $OutputPath" -ForegroundColor Green

}
finally
{

    Remove-Item `
    -LiteralPath $stagingPath `
    -Recurse `
    -Force `
    -ErrorAction SilentlyContinue

}
