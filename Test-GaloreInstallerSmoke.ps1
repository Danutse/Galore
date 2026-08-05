[CmdletBinding()]

param(
    [Parameter(Mandatory = $true)]
    [string]$GaloreRoot,
    [string]$SetupPath
)

$ErrorActionPreference = "Stop"

if([string]::IsNullOrWhiteSpace($SetupPath))
{
    $SetupPath = Join-Path $GaloreRoot "Installers\GaloreLauncherSetup.exe"
}

if(-not (Test-Path -LiteralPath $SetupPath -PathType Leaf))
{
    throw "Installer was not found: '$SetupPath'."
}

if(Get-Process -Name "GaloreLauncher" -ErrorAction SilentlyContinue)
{
    throw "Close Galore Launcher before running the isolated installer smoke test."
}

$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("GaloreInstallerSmoke-" + [guid]::NewGuid().ToString("N"))
$installPath = Join-Path $temporaryRoot "Galore"

try
{
    $process = Start-Process -FilePath $SetupPath -ArgumentList @("-InstallPath", $installPath, "-NoLaunch") -Wait -PassThru

    if($process.ExitCode -ne 0)
    {
        throw "Installer smoke test exited with code $($process.ExitCode)."
    }

    foreach($relativePath in @(
        "GaloreLauncher.exe",
        "Uninstall-Galore.exe",
        "Programs\scrcpy\playphone.vbs",
        "Programs\NvidiaSensor\NvidiaSensorReader.exe"
    ))
    {
        if(-not (Test-Path -LiteralPath (Join-Path $installPath $relativePath) -PathType Leaf))
        {
            throw "Installer smoke test is missing '$relativePath'."
        }
    }

    foreach($unexpectedPath in @("resources", "Settings", "Logs", "Tests", "Backups"))
    {
        if(Test-Path -LiteralPath (Join-Path $installPath $unexpectedPath))
        {
            throw "Installer smoke test copied development or user data: '$unexpectedPath'."
        }
    }

    if(Test-Path -LiteralPath (Join-Path $installPath "Modules"))
    {
        throw "Installer smoke test copied the development Modules folder."
    }

    if(@(Get-ChildItem -LiteralPath $installPath -Recurse -Filter *.ps1 -File).Count -gt 0)
    {
        throw "Installer smoke test copied editable PowerShell source files."
    }

    $launcherPath = Join-Path $installPath "GaloreLauncher.exe"
    $launcherProcess = Start-Process -FilePath $launcherPath -PassThru
    Start-Sleep -Seconds 5

    if($launcherProcess.HasExited)
    {
        throw "Installed launcher exited during startup with code $($launcherProcess.ExitCode)."
    }

    $crashPath = Join-Path $installPath "Logs\Crash.log"
    if((Test-Path -LiteralPath $crashPath -PathType Leaf) -and (Get-Item -LiteralPath $crashPath).Length -gt 0)
    {
        throw "Installed launcher wrote a crash during startup."
    }

    Stop-Process -Id $launcherProcess.Id -Force
    $launcherProcess.WaitForExit(10000) | Out-Null

    $settingsPath = Join-Path $installPath "Settings"
    $logsPath = Join-Path $installPath "Logs"
    $unrelatedPath = Join-Path $installPath "KeepMe.txt"
    New-Item -ItemType Directory -Path $settingsPath -Force | Out-Null
    New-Item -ItemType Directory -Path $logsPath -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $settingsPath "Settings.json"), "{}")
    [System.IO.File]::WriteAllText((Join-Path $logsPath "KeepMe.log"), "Keep")
    [System.IO.File]::WriteAllText($unrelatedPath, "Keep")

    $uninstallerPath = Join-Path $installPath "Uninstall-Galore.exe"
    $uninstallProcess = Start-Process -FilePath $uninstallerPath -ArgumentList @("-NonInteractive") -Wait -PassThru
    if($uninstallProcess.ExitCode -ne 0)
    {
        throw "Bundled uninstaller exited with code $($uninstallProcess.ExitCode)."
    }

    $uninstallDeadline = [DateTime]::UtcNow.AddSeconds(15)
    while((Test-Path -LiteralPath $uninstallerPath) -and [DateTime]::UtcNow -lt $uninstallDeadline)
    {
        Start-Sleep -Milliseconds 250
    }

    foreach($removedPath in @(
        "GaloreLauncher.exe",
        "Uninstall-Galore.exe",
        "Programs",
        "Galore.install.json"
    ))
    {
        if(Test-Path -LiteralPath (Join-Path $installPath $removedPath))
        {
            throw "Bundled uninstaller did not remove '$removedPath'."
        }
    }

    foreach($preservedPath in @(
        "Settings\Settings.json",
        "Logs\KeepMe.log",
        "KeepMe.txt"
    ))
    {
        if(-not (Test-Path -LiteralPath (Join-Path $installPath $preservedPath) -PathType Leaf))
        {
            throw "Bundled uninstaller removed preserved data '$preservedPath'."
        }
    }

    "Galore isolated installer smoke test passed: $installPath"
}
finally
{
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
}
