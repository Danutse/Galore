# ============================================================
# LAUNCHER STARTUP MODULE
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherStartup"
    LoadOrder = 30
    RequiresModules = @()
    RequiresFunctions = [ordered]@{}
    RequiresTypes = [ordered]@{}
    RequiresVariables = @()
    RequiresFolders = @()
    RequiresFiles = @()
    ProvidesTypes = @()
}

# ============================================================
# WINDOWS STARTUP CONTROL
# ============================================================

$script:StartupKeyName = "Program Manager"

function Enable-ProgramStartup {

    $exePath =
    [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName

    $startupValue =
    '"' + $exePath + '"'

    Set-ItemProperty `
    -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" `
    -Name $script:StartupKeyName `
    -Value $startupValue

}

function Disable-ProgramStartup {

    Remove-ItemProperty `
    -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" `
    -Name $script:StartupKeyName `
    -ErrorAction SilentlyContinue

}

function Test-ProgramStartup {

    $startup =
    Get-ItemProperty `
    -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" `
    -Name $script:StartupKeyName `
    -ErrorAction SilentlyContinue

    return $null -ne $startup

}

# ============================================================
# STARTUP TOGGLE HELPER
# ============================================================

function Set-ProgramStartup {

    param(
        [bool]$Enabled
    )

    if(
        $Enabled
    )
    {

        Enable-ProgramStartup

    }
    else
    {

        Disable-ProgramStartup

    }

}
