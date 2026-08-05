[CmdletBinding()]

param(
    [Parameter(Mandatory = $true)]
    [string]$GaloreRoot,
    [string]$ReleasePath
)

$ErrorActionPreference = "Stop"

if([string]::IsNullOrWhiteSpace($ReleasePath))
{
    $ReleasePath = Join-Path $GaloreRoot "Release\GaloreLauncher.exe"
}

if(-not (Test-Path -LiteralPath $ReleasePath -PathType Leaf))
{
    throw "Bundled release executable was not found: '$ReleasePath'."
}

if(Get-Process -Name "GaloreLauncher" -ErrorAction SilentlyContinue)
{
    throw "Close Galore Launcher before running the isolated release smoke test."
}

$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("GaloreReleaseSmoke-" + [guid]::NewGuid().ToString("N"))

try
{
    New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
    Copy-Item -LiteralPath $ReleasePath -Destination (Join-Path $temporaryRoot "GaloreLauncher.exe") -Force
    Copy-Item -LiteralPath (Join-Path $GaloreRoot "Programs") -Destination (Join-Path $temporaryRoot "Programs") -Recurse -Force

    $process = Start-Process -FilePath (Join-Path $temporaryRoot "GaloreLauncher.exe") -PassThru
    Start-Sleep -Seconds 5

    if($process.HasExited)
    {
        throw "Bundled release exited during startup with code $($process.ExitCode)."
    }

    $crashPath = Join-Path $temporaryRoot "Logs\Crash.log"
    if((Test-Path -LiteralPath $crashPath -PathType Leaf) -and (Get-Item -LiteralPath $crashPath).Length -gt 0)
    {
        throw "Bundled release wrote a crash during isolated startup."
    }

    Stop-Process -Id $process.Id -Force
    $process.WaitForExit(10000) | Out-Null
    "Galore isolated bundled-release startup smoke test passed."
}
finally
{
    Get-Process -Name "GaloreLauncher" -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -eq (Join-Path $temporaryRoot "GaloreLauncher.exe") } |
    Stop-Process -Force -ErrorAction SilentlyContinue

    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
}
