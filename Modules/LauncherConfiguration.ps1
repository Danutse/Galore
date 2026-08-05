# ============================================================
# LAUNCHER CONFIGURATION MODULE
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherConfiguration"
    LoadOrder = 190
    RequiresModules = @("LauncherDomain")
    RequiresFunctions = [ordered]@{}
    RequiresTypes = [ordered]@{
        "GaloreProgramDefinition" = "LauncherDomain"
    }
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
    $browserProcess = if($defaultBrowser) { $defaultBrowser.ProcessName } else { "browser" }
    $browserProgram = [GaloreProgramDefinition]::new(
        $(if($defaultBrowser) { $defaultBrowser.Path } else { "" }),
        "",
        $browserProcess,
        $browserProcess
    )
    $browserProgram.BrowserId = if($defaultBrowser) { $defaultBrowser.Id } else { "" }
    $browserProgram.BrowserDisplayName = if($defaultBrowser) { $defaultBrowser.DisplayName } else { "No browser detected" }
    return @{
        "Phone" = [GaloreProgramDefinition]::new($EnvPaths.ScrcpyVBS, "", "scrcpy", "scrcpy")
        "Discord" = [GaloreProgramDefinition]::new($EnvPaths.Discord, "--processStart Discord.exe", "Discord", "Discord")
        "Steam" = [GaloreProgramDefinition]::new($EnvPaths.Steam, "-silent", "steam", "steam")
        "Browser" = $browserProgram
        "BattleStateLauncher" = [GaloreProgramDefinition]::new($EnvPaths.BSG, "-silent", "BsgLauncher", "BsgLauncher")
        "RivaTuner" = [GaloreProgramDefinition]::new($EnvPaths.RivaTuner, "-silent", "RTSS", "RTSS")
        "MSI Afterburner" = [GaloreProgramDefinition]::new($EnvPaths.MSIAfterBurner, "-silent", "MSIAfterburner", "MSIAfterburner")
        "ShareX" = [GaloreProgramDefinition]::new($EnvPaths.ShareX, "-silent", "ShareX", "ShareX")
        "Spotify" = [GaloreProgramDefinition]::new($EnvPaths.Spotify, "-silent", "Spotify", "Spotify")
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
                if(-not ($program -is [GaloreProgramDefinition])) {
                    $null = $errors.Add("Program '$programName' must be a GaloreProgramDefinition.")
                    continue
                }
                if($program.Path.Length -gt 0 -and [string]::IsNullOrWhiteSpace($program.Path)) {
                    $null = $errors.Add("Program '$programName' Path cannot contain only whitespace.")
                }
                if($programName -eq "Phone" -and [string]::IsNullOrWhiteSpace($program.Path)) {
                    $null = $errors.Add("Program 'Phone' requires an executable Path.")
                }
                if(-not [string]::IsNullOrWhiteSpace($program.Path) -and -not (Test-Path -LiteralPath $program.Path -PathType Leaf)) {
                    $null = $errors.Add("Program '$programName' Path does not resolve to a file.")
                }
                foreach($processProperty in @(
                        "StatusProcess"
                        "WindowProcess"
                    )
                ) {
                    if([string]::IsNullOrWhiteSpace($program.$processProperty)) {
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
