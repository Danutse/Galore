# ============================================================
# LAUNCHER CONFIGURATION MODULE
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherConfiguration"
    LoadOrder = 190
    RequiresModules = @()
    RequiresFunctions = [ordered]@{}
    RequiresTypes = [ordered]@{}
    RequiresVariables = @()
    RequiresFolders = @("Resources", "Programs", "Programs\scrcpy")
    RequiresFiles = @("Resources\Galore.ico", "Programs\scrcpy\playphone.vbs")
    ProvidesTypes = @()
}

# ============================================================
# FIND INSTALLED PROGRAM
# ============================================================

function Find-ProgramPath {
    param([string[]]$PossiblePaths)
    foreach($possiblePath in $PossiblePaths) {
        if([string]::IsNullOrWhiteSpace($possiblePath)) {
            continue
        }
        if(Test-Path -LiteralPath $possiblePath -PathType Leaf) {
            return $possiblePath
        }
    }
    return $null
}

# ============================================================
# FIND BATTLESTATE LAUNCHER
# ============================================================

function Find-BattleStateLauncherPath {
    param([string]$ProgramRoot)
    $possiblePaths = @(
        (Join-Path $ProgramRoot "Programs\BattleState\BsgLauncher.exe")
        (Join-Path $env:ProgramFiles "Battlestate Games\BsgLauncher\BsgLauncher.exe")
        (Join-Path ${env:ProgramFiles(x86)} "Battlestate Games\BsgLauncher\BsgLauncher.exe")
        (Join-Path $env:LOCALAPPDATA "Battlestate Games\BsgLauncher\BsgLauncher.exe")
    )
    foreach($registryPath in @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )) {
        foreach($application in @(
                Get-ItemProperty -Path $registryPath -ErrorAction SilentlyContinue
            )
        ) {
            if([string]$application.DisplayName -notmatch "(?i)(battlestate|escape from tarkov)") {
                continue
            }
            if(-not [string]::IsNullOrWhiteSpace([string]$application.InstallLocation)) {
                $possiblePaths += Join-Path $application.InstallLocation "BsgLauncher.exe"
            }
            if(-not [string]::IsNullOrWhiteSpace([string]$application.DisplayIcon)) {
                $possiblePaths += ([string]$application.DisplayIcon -replace '"', '' -replace ',\d+$', '')
            }
        }
    }
    return Find-ProgramPath -PossiblePaths $possiblePaths
}

# ============================================================
# INSTALLED BROWSERS
# ============================================================

function Get-InstalledBrowsers {
    $browsers = [ordered]@{}
    foreach($browserDefinition in @(
            [pscustomobject]@{
                Id = "Edge"
                DisplayName = "Microsoft Edge"
                ProcessName = "msedge"
                Paths = @(
                    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
                    "${env:ProgramFiles}\Microsoft\Edge\Application\msedge.exe"
                )
            }
            [pscustomobject]@{
                Id = "Chrome"
                DisplayName = "Google Chrome"
                ProcessName = "chrome"
                Paths = @(
                    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
                    "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe"
                    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
                )
            }
            [pscustomobject]@{
                Id = "Firefox"
                DisplayName = "Mozilla Firefox"
                ProcessName = "firefox"
                Paths = @(
                    "${env:ProgramFiles}\Mozilla Firefox\firefox.exe"
                    "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe"
                )
            }
            [pscustomobject]@{
                Id = "Brave"
                DisplayName = "Brave"
                ProcessName = "brave"
                Paths = @(
                    "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\Application\brave.exe"
                    "${env:ProgramFiles}\BraveSoftware\Brave-Browser\Application\brave.exe"
                    "${env:ProgramFiles(x86)}\BraveSoftware\Brave-Browser\Application\brave.exe"
                )
            }
            [pscustomobject]@{
                Id = "OperaGX"
                DisplayName = "Opera GX"
                ProcessName = "opera"
                Paths = @(
                    "$env:LOCALAPPDATA\Programs\Opera GX\opera.exe"
                )
            }
            [pscustomobject]@{
                Id = "Opera"
                DisplayName = "Opera"
                ProcessName = "opera"
                Paths = @(
                    "$env:LOCALAPPDATA\Programs\Opera\opera.exe"
                    "${env:ProgramFiles}\Opera\opera.exe"
                    "${env:ProgramFiles(x86)}\Opera\opera.exe"
                )
            }
            [pscustomobject]@{
                Id = "Vivaldi"
                DisplayName = "Vivaldi"
                ProcessName = "vivaldi"
                Paths = @(
                    "$env:LOCALAPPDATA\Vivaldi\Application\vivaldi.exe"
                    "${env:ProgramFiles}\Vivaldi\Application\vivaldi.exe"
                )
            }
            [pscustomobject]@{
                Id = "Chromium"
                DisplayName = "Chromium"
                ProcessName = "chromium"
                Paths = @(
                    "$env:LOCALAPPDATA\Chromium\Application\chrome.exe"
                    "${env:ProgramFiles}\Chromium\Application\chrome.exe"
                )
            }
            [pscustomobject]@{
                Id = "Waterfox"
                DisplayName = "Waterfox"
                ProcessName = "waterfox"
                Paths = @(
                    "${env:ProgramFiles}\Waterfox\waterfox.exe"
                    "${env:ProgramFiles(x86)}\Waterfox\waterfox.exe"
                )
            }
            [pscustomobject]@{
                Id = "TorBrowser"
                DisplayName = "Tor Browser"
                ProcessName = "firefox"
                Paths = @(
                    "$env:LOCALAPPDATA\Tor Browser\Browser\firefox.exe"
                    "${env:ProgramFiles}\Tor Browser\Browser\firefox.exe"
                )
            }
            [pscustomobject]@{
                Id = "Safari"
                DisplayName = "Safari"
                ProcessName = "Safari"
                Paths = @(
                    "${env:ProgramFiles}\Safari\Safari.exe"
                    "${env:ProgramFiles(x86)}\Safari\Safari.exe"
                )
            }
        )
    ) {
        $browserPath = Find-ProgramPath -PossiblePaths $browserDefinition.Paths
        if($browserPath) {
            $browsers[$browserDefinition.Id] = [pscustomobject]@{
                Id = $browserDefinition.Id
                DisplayName = $browserDefinition.DisplayName
                Path = $browserPath
                ProcessName = $browserDefinition.ProcessName
            }
        }
    }
    return $browsers
}

# ============================================================
# BUILD ENVIRONMENT PATHS
# ============================================================

function New-LauncherEnvironmentPaths {
    param([string]$ResourceFolder, [string]$ScrcpyFolder, [string]$ProgramRoot)
    return @{
        AppIcon = Join-Path $ResourceFolder "Galore.ico"
        ScrcpyVBS = Join-Path $ScrcpyFolder "playphone.vbs"
        Discord = Find-ProgramPath @(
            "$env:LOCALAPPDATA\Discord\Update.exe"
        )
        Steam = Find-ProgramPath @(
            "${env:ProgramFiles(x86)}\Steam\Steam.exe"
            "${env:ProgramFiles}\Steam\Steam.exe"
        )
        Browsers = Get-InstalledBrowsers
        BSG = Find-BattleStateLauncherPath -ProgramRoot $ProgramRoot
        RivaTuner = Find-ProgramPath @(
            "${env:ProgramFiles(x86)}\RivaTuner Statistics Server\RTSS.exe"
        )
        MSIAfterBurner = Find-ProgramPath @(
            "${env:ProgramFiles(x86)}\MSI Afterburner\MSIAfterburner.exe"
        )
        ShareX = Find-ProgramPath @(
            "${env:ProgramFiles}\ShareX\ShareX.exe"
        )
        Spotify = Find-ProgramPath @(
            "$env:APPDATA\Spotify\Spotify.exe"
            "${env:ProgramFiles}\Spotify\Spotify.exe"
        )
    }
}

# ============================================================
# BUILD PROGRAM CONFIGURATION
# ============================================================

function New-LauncherProgramConfiguration {
    param([hashtable]$EnvPaths)
    $defaultBrowser = @(
        $EnvPaths.Browsers.Values | Select-Object -First 1
    )[0]
    return @{
        "Phone" = @{
            Path = "$env:SystemRoot\System32\wscript.exe"
            Args = "//nologo `"$($EnvPaths.ScrcpyVBS)`""
            StatusProcess = "scrcpy"
            WindowProcess = "scrcpy"
        }
        "Discord" = @{
            Path = $EnvPaths.Discord
            Args = "--processStart Discord.exe"
            StatusProcess = "Discord"
            WindowProcess = "Discord"
        }
        "Steam" = @{
            Path = $EnvPaths.Steam
            Args = "-silent"
            StatusProcess = "steam"
            WindowProcess = "steam"
        }
        "Browser" = @{
            Path = if($defaultBrowser) {
                $defaultBrowser.Path
            } else {
                $null
            }
            Args = ""
            StatusProcess = if($defaultBrowser) {
                $defaultBrowser.ProcessName
            } else {
                "browser"
            }
            WindowProcess = if($defaultBrowser) {
                $defaultBrowser.ProcessName
            } else {
                "browser"
            }
            BrowserId = if($defaultBrowser) {
                $defaultBrowser.Id
            } else {
                $null
            }
            BrowserDisplayName = if($defaultBrowser) {
                $defaultBrowser.DisplayName
            } else {
                "No browser detected"
            }
        }
        "BattleStateLauncher" = @{
            Path = $EnvPaths.BSG
            Args = "-silent"
            StatusProcess = "BsgLauncher"
            WindowProcess = "BsgLauncher"
        }
        "RivaTuner" = @{
            Path = $EnvPaths.RivaTuner
            Args = "-silent"
            StatusProcess = "RTSS"
            WindowProcess = "RTSS"
        }
        "MSI Afterburner" = @{
            Path = $EnvPaths.MSIAfterBurner
            Args = "-silent"
            StatusProcess = "MSIAfterburner"
            WindowProcess = "MSIAfterburner"
        }
        "ShareX" = @{
            Path = $EnvPaths.ShareX
            Args = "-silent"
            StatusProcess = "ShareX"
            WindowProcess = "ShareX"
        }
        "Spotify" = @{
            Path = $EnvPaths.Spotify
            Args = "-silent"
            StatusProcess = "Spotify"
            WindowProcess = "Spotify"
        }
    }
}

# ============================================================
# VALIDATE CONFIGURATION SCHEMA
# ============================================================

function Test-LauncherConfigurationSchema {
    param($Configuration)
    $errors = New-Object System.Collections.ArrayList
    if($null -eq $Configuration) {
        $null = $errors.Add("Configuration object is missing.")
        return [PSCustomObject]@{
            IsValid = $false
            Errors = @($errors)
        }
    }
    foreach($propertyName in @(
            "ProgramRoot"
            "EnvPaths"
            "Programs"
        )
    ) {
        if($null -eq $Configuration.PSObject.Properties[$propertyName]) {
            $null = $errors.Add("Configuration property '$propertyName' is missing.")
        }
    }
    if($null -ne $Configuration.PSObject.Properties["ProgramRoot"]) {
        if(-not ($Configuration.ProgramRoot -is [string]) -or [string]::IsNullOrWhiteSpace($Configuration.ProgramRoot)) {
            $null = $errors.Add("ProgramRoot must be a non-empty string.")
        } elseif(-not (Test-Path -LiteralPath $Configuration.ProgramRoot -PathType Container)) {
            $null = $errors.Add("ProgramRoot does not resolve to an existing folder.")
        }
    }
    $requiredEnvironmentPaths = @(
        "AppIcon"
        "ScrcpyVBS"
        "Discord"
        "Steam"
        "Browsers"
        "BSG"
        "RivaTuner"
        "MSIAfterBurner"
        "ShareX"
        "Spotify"
    )
    if($null -ne $Configuration.PSObject.Properties["EnvPaths"]) {
        if(-not ($Configuration.EnvPaths -is [System.Collections.IDictionary])) {
            $null = $errors.Add("EnvPaths must be a dictionary.")
        } else {
            foreach($pathName in $requiredEnvironmentPaths) {
                if(-not $Configuration.EnvPaths.Contains($pathName)) {
                    $null = $errors.Add("EnvPaths entry '$pathName' is missing.")
                    continue
                }
                $pathValue = $Configuration.EnvPaths[$pathName]
                if($pathName -eq "Browsers") {
                    if(-not ($pathValue -is [System.Collections.IDictionary])) {
                        $null = $errors.Add("EnvPaths entry 'Browsers' must be a dictionary.")
                    }
                    continue
                }
                if($null -ne $pathValue -and -not ($pathValue -is [string])) {
                    $null = $errors.Add("EnvPaths entry '$pathName' must be a string or null.")
                    continue
                }
                if($pathName -in @(
                        "AppIcon"
                        "ScrcpyVBS"
                    ) -and [string]::IsNullOrWhiteSpace([string]$pathValue)
                ) {
                    $null = $errors.Add("Required EnvPaths entry '$pathName' is empty.")
                    continue
                }
                if(-not [string]::IsNullOrWhiteSpace([string]$pathValue) -and -not (Test-Path -LiteralPath $pathValue -PathType Leaf)) {
                    $null = $errors.Add("EnvPaths entry '$pathName' does not resolve to a file.")
                }
            }
        }
    }
    $requiredPrograms = @(
        "Phone"
        "Discord"
        "Steam"
        "Browser"
        "BattleStateLauncher"
        "RivaTuner"
        "MSI Afterburner"
        "ShareX"
        "Spotify"
    )
    $requiredProgramProperties = @(
        "Path"
        "Args"
        "StatusProcess"
        "WindowProcess"
    )
    if($null -ne $Configuration.PSObject.Properties["Programs"]) {
        if(-not ($Configuration.Programs -is [System.Collections.IDictionary])) {
            $null = $errors.Add("Programs must be a dictionary.")
        } else {
            foreach($programName in $requiredPrograms) {
                if(-not $Configuration.Programs.Contains($programName)) {
                    $null = $errors.Add("Required program '$programName' is missing.")
                    continue
                }
                $program = $Configuration.Programs[$programName]
                if(-not ($program -is [System.Collections.IDictionary])) {
                    $null = $errors.Add("Program '$programName' must be a dictionary.")
                    continue
                }
                foreach($programProperty in $requiredProgramProperties) {
                    if(-not $program.Contains($programProperty)) {
                        $null = $errors.Add("Program '$programName' is missing '$programProperty'.")
                    }
                }
                if($program.Contains("Path") -and $null -ne $program.Path -and (-not ($program.Path -is [string]) -or [string]::IsNullOrWhiteSpace($program.Path))) {
                    $null = $errors.Add("Program '$programName' Path must be a non-empty string or null.")
                }
                if($programName -eq "Phone" -and $program.Contains("Path") -and [string]::IsNullOrWhiteSpace([string]$program.Path)) {
                    $null = $errors.Add("Program 'Phone' requires an executable Path.")
                }
                if($program.Contains("Path") -and -not [string]::IsNullOrWhiteSpace([string]$program.Path) -and -not (Test-Path -LiteralPath $program.Path -PathType Leaf)) {
                    $null = $errors.Add("Program '$programName' Path does not resolve to a file.")
                }
                if($program.Contains("Args") -and -not ($program.Args -is [string])) {
                    $null = $errors.Add("Program '$programName' Args must be a string.")
                }
                foreach($processProperty in @(
                        "StatusProcess"
                        "WindowProcess"
                    )
                ) {
                    if($program.Contains($processProperty) -and (-not ($program[$processProperty] -is [string]) -or [string]::IsNullOrWhiteSpace($program[$processProperty]))) {
                        $null = $errors.Add("Program '$programName' $processProperty must be a non-empty string.")
                    }
                }
            }
        }
    }
    return [PSCustomObject]@{
        IsValid = $errors.Count -eq 0
        Errors = @($errors)
    }
}

# ============================================================
# SHOW CONFIGURATION ERROR
# ============================================================

function Show-LauncherConfigurationError {
    param([string]$Message)
    [System.Windows.Forms.MessageBox]::Show($Message, "Launcher Error") | Out-Null
}

# ============================================================
# INITIALIZE LAUNCHER CONFIGURATION
# ============================================================

function Initialize-LauncherConfiguration {
    param([string]$AppRoot)
    if([string]::IsNullOrWhiteSpace($AppRoot)) {
        $ProgramRoot = Split-Path ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) -Parent
    } else {
        $ProgramRoot = $AppRoot
    }
    $ResourceFolder = $script:GaloreResourceRoot
    $ProgramsFolder = Join-Path $ProgramRoot "Programs"
    $ScrcpyFolder = Join-Path $ProgramsFolder "scrcpy"
    $RequiredFolders = @(
        [PSCustomObject]@{
            Name = "Resources"
            Path = $ResourceFolder
        }
        [PSCustomObject]@{
            Name = "Programs"
            Path = $ProgramsFolder
        }
        [PSCustomObject]@{
            Name = "scrcpy"
            Path = $ScrcpyFolder
        }
    )
    foreach($RequiredFolder in $RequiredFolders) {
        if(-not (Test-Path -LiteralPath $RequiredFolder.Path -PathType Container)) {
            Show-LauncherConfigurationError -Message "Missing $($RequiredFolder.Name) folder."
            return $null
        }
    }
    $EnvPaths = New-LauncherEnvironmentPaths -ResourceFolder $ResourceFolder -ScrcpyFolder $ScrcpyFolder -ProgramRoot $ProgramRoot
    $Programs = New-LauncherProgramConfiguration -EnvPaths $EnvPaths
    $Configuration = [PSCustomObject]@{
        ProgramRoot = $ProgramRoot
        EnvPaths = $EnvPaths
        Programs = $Programs
    }
    $schemaValidation = Test-LauncherConfigurationSchema -Configuration $Configuration
    if(-not $schemaValidation.IsValid) {
        $errorMessage = "Launcher configuration failed validation:`r`n`r`n- " + ($schemaValidation.Errors -join "`r`n- ")
        Show-LauncherConfigurationError -Message $errorMessage
        return $null
    }
    return $Configuration
}
