# ============================================================
# LAUNCHER INTEGRATION ADAPTERS MODULE
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherIntegrationAdapters"
    LoadOrder = 300
    RequiresModules = @("LauncherDomain", "LauncherLogging")
    RequiresFunctions = [ordered]@{
        "Write-LauncherDiagnostic" = "LauncherLogging"
    }
    RequiresTypes = [ordered]@{
        "GaloreProgramDefinition" = "LauncherDomain"
    }
    RequiresVariables = @()
    RequiresFolders = @()
    RequiresFiles = @()
    ProvidesTypes = @()
}

# ============================================================
# PROCESS IDENTITY
# ============================================================

function Test-GaloreProcessRunning {
    param([string]$ProcessName)
    if([string]::IsNullOrWhiteSpace($ProcessName)) { return $false }
    return $null -ne (Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Get-GaloreVisibleProcess {
    param([string]$ProcessName)
    if([string]::IsNullOrWhiteSpace($ProcessName)) { return $null }
    return Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
}

# ============================================================
# SCRIPT HOST ADAPTERS
# ============================================================

function Start-GaloreHiddenWscript {
    param([string]$ScriptPath, [string]$ArgumentList = "")
    if([string]::IsNullOrWhiteSpace($ScriptPath) -or -not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) { return $false }
    $wscriptPath = Join-Path $env:SystemRoot "System32\wscript.exe"
    if(-not (Test-Path -LiteralPath $wscriptPath -PathType Leaf)) { return $false }
    $arguments = "//nologo `"$ScriptPath`""
    if(-not [string]::IsNullOrWhiteSpace($ArgumentList)) { $arguments = "$arguments $ArgumentList" }
    try {
        Start-Process -FilePath $wscriptPath -ArgumentList $arguments -WindowStyle Hidden -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Write-LauncherDiagnostic -Exception $_ -Context "Failed to start hidden script adapter '$ScriptPath'."
        return $false
    }
}

function Start-GaloreProgramAdapter {
    param([GaloreProgramDefinition]$Program)
    if($null -eq $Program -or -not $Program.IsConfigured()) { return $false }
    $path = [string]$Program.Path
    try {
        if([IO.Path]::GetExtension($path).Equals(".vbs", [System.StringComparison]::OrdinalIgnoreCase)) {
            return Start-GaloreHiddenWscript -ScriptPath $path -ArgumentList $Program.Args
        }
        if([string]::IsNullOrWhiteSpace([string]$Program.Args)) {
            Start-Process -FilePath $path -ErrorAction Stop | Out-Null
        } else {
            Start-Process -FilePath $path -ArgumentList $Program.Args -ErrorAction Stop | Out-Null
        }
        return $true
    } catch {
        Write-LauncherDiagnostic -Exception $_ -Context "Failed to start program adapter '$path'."
        return $false
    }
}

function Start-GaloreSpotifyAutoplayAdapter {
    param([string]$AppRoot)
    if([string]::IsNullOrWhiteSpace($AppRoot)) { return $false }
    return Start-GaloreHiddenWscript -ScriptPath (Join-Path $AppRoot "Programs\SpotifyPlay.vbs")
}
