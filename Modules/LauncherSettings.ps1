# ============================================================
# LAUNCHER SETTINGS MODULE
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherSettings"
    LoadOrder = 120
    RequiresModules = @("LauncherDomain", "LauncherLogging")
    RequiresFunctions = [ordered]@{
        "Write-LauncherDiagnostic" = "LauncherLogging"
    }
    RequiresTypes = [ordered]@{
        "GaloreLauncherSettings" = "LauncherDomain"
    }
    RequiresVariables = @()
    RequiresFolders = @()
    RequiresFiles = @()
    ProvidesTypes = @()
}

# ============================================================
# INITIALIZE LAUNCHER SETTINGS
# ============================================================

function Initialize-LauncherSettings {
    param($ProgramRoot)
    $script:SettingsFolder = Join-Path $ProgramRoot "Settings"
    if(-not (Test-Path -LiteralPath $script:SettingsFolder -PathType Container)) {
        New-Item -ItemType Directory -Path $script:SettingsFolder -Force -ErrorAction Stop | Out-Null
    }
    $script:SettingsFile = Join-Path $script:SettingsFolder "settings.json"
    $legacySettingsFile = Join-Path $ProgramRoot "settings.json"
    if(-not (Test-Path -LiteralPath $script:SettingsFile -PathType Leaf) -and (Test-Path -LiteralPath $legacySettingsFile -PathType Leaf)) {
        Move-Item -LiteralPath $legacySettingsFile -Destination $script:SettingsFile -ErrorAction Stop
    }
    $script:WindowPlacementCorrectionLogged = $false
}

# ============================================================
# GET LAUNCHER SETTINGS FOLDER
# ============================================================

function Get-LauncherSettingsFolder {
    return $script:SettingsFolder
}

# ============================================================
# VALIDATE LAUNCHER SETTINGS
# ============================================================

function ConvertTo-ValidatedLauncherSettings {
    param($Settings)
    if($null -eq $Settings) {
        throw "Launcher settings are empty."
    }
    foreach($propertyName in @(
            "Selected"
            "Width"
            "Height"
            "X"
            "Y"
        )
    ) {
        if($null -eq $Settings.PSObject.Properties[$propertyName]) {
            throw "Launcher settings are missing '$propertyName'."
        }
    }
    $width = 0
    $height = 0
    $x = 0
    $y = 0
    if(-not ([int]::TryParse([string]$Settings.Width, [ref]$width)) -or $width -lt 300 -or $width -gt 32767) {
        throw "Launcher window width is invalid."
    }
    if(-not ([int]::TryParse([string]$Settings.Height, [ref]$height)) -or $height -lt 200 -or $height -gt 32767) {
        throw "Launcher window height is invalid."
    }
    if(-not ([int]::TryParse([string]$Settings.X, [ref]$x))) {
        throw "Launcher window X position is invalid."
    }
    if(-not ([int]::TryParse([string]$Settings.Y, [ref]$y))) {
        throw "Launcher window Y position is invalid."
    }
    $selectedPrograms = @()
    foreach($selectedProgram in @($Settings.Selected)
    ) {
        if($null -eq $selectedProgram) {
            continue
        }
        if($selectedProgram -isnot [string]) {
            throw "Launcher program selection data is invalid."
        }
        if(-not [string]::IsNullOrWhiteSpace($selectedProgram)) {
            $selectedPrograms += $selectedProgram
        }
    }
    $browserId = $null
    if($null -ne $Settings.PSObject.Properties["BrowserId"] -and $null -ne $Settings.BrowserId) {
        if($Settings.BrowserId -isnot [string]) {
            throw "Launcher browser selection is invalid."
        }
        $candidateBrowserId = [string]$Settings.BrowserId
        if(-not [string]::IsNullOrWhiteSpace($candidateBrowserId)) {
            $browserId = $candidateBrowserId
        }
    }
    $programOverrides = [ordered]@{}
    if($null -ne $Settings.PSObject.Properties["ProgramOverrides"] -and $null -ne $Settings.ProgramOverrides) {
        $rawOverrides = $Settings.ProgramOverrides
        if($rawOverrides -is [System.Collections.IDictionary]) {
            $overrideNames = @($rawOverrides.Keys)
        } else {
            $overrideNames = @($rawOverrides.PSObject.Properties | ForEach-Object { $_.Name } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        }
        foreach($overrideName in $overrideNames) {
            if([string]::IsNullOrWhiteSpace([string]$overrideName)) {
                throw "Launcher program override name is invalid."
            }
            $override = if($rawOverrides -is [System.Collections.IDictionary]) {
                $rawOverrides[$overrideName]
            } else {
                $rawOverrides.PSObject.Properties[
                    [string]$overrideName
                ].Value
            }
            if($null -eq $override -or $null -eq $override.PSObject.Properties["Path"] -or $override.Path -isnot [string] -or [string]::IsNullOrWhiteSpace($override.Path)) {
                throw "Launcher program override '$overrideName' has an invalid path."
            }
            $displayName = [string]$overrideName
            if($null -ne $override.PSObject.Properties["DisplayName"] -and $null -ne $override.DisplayName) {
                if($override.DisplayName -isnot [string]) {
                    throw "Launcher program override '$overrideName' has an invalid display name."
                }
                if(-not [string]::IsNullOrWhiteSpace([string]$override.DisplayName)) {
                    $displayName = [string]$override.DisplayName
                }
            }
            $programOverrides[[string]$overrideName] = [pscustomobject]@{
                Path = [string]$override.Path
                DisplayName = $displayName
            }
        }
    }
    $validated = [GaloreLauncherSettings]::new()
    $validated.Selected = [string[]]$selectedPrograms
    $validated.Width = $width
    $validated.Height = $height
    $validated.X = $x
    $validated.Y = $y
    $validated.BrowserId = $browserId
    $validated.ProgramOverrides = $programOverrides
    return $validated
}

# ============================================================
# KEEP WINDOW PLACEMENT ON A VISIBLE SCREEN
# ============================================================

function Test-GaloreWindowPlacementVisible {
    param($Settings, [System.Drawing.Rectangle[]]$WorkingAreas)
    $titleAreaRectangle = [System.Drawing.Rectangle]::new($Settings.X, $Settings.Y, $Settings.Width, ([math]::Min(60, $Settings.Height)))
    foreach($workingArea in @($WorkingAreas)) {
        $visibleRectangle = [System.Drawing.Rectangle]::Intersect($titleAreaRectangle, $workingArea)
        if($visibleRectangle.Width -ge 120 -and $visibleRectangle.Height -ge 30) {
            return $true
        }
    }
    return $false
}

function Resolve-LauncherWindowPlacement {
    param($Settings)
    $screens = @(
        [System.Windows.Forms.Screen]::AllScreens
    )
    if($screens.Count -eq 0) {
        return $Settings
    }
    $workingAreas = @($screens | ForEach-Object { $_.WorkingArea })
    if(Test-GaloreWindowPlacementVisible -Settings $Settings -WorkingAreas $workingAreas) {
        return $Settings
    }
    $primaryScreen = [System.Windows.Forms.Screen]::PrimaryScreen
    if($null -eq $primaryScreen) {
        $primaryScreen = $screens[0]
    }
    $workingArea = $primaryScreen.WorkingArea
    $visibleWidth = [math]::Min($Settings.Width, $workingArea.Width)
    $visibleHeight = [math]::Min($Settings.Height, $workingArea.Height)
    $visibleX = $workingArea.Left + [math]::Floor(($workingArea.Width - $visibleWidth) / 2)
    $visibleY = $workingArea.Top + [math]::Floor(($workingArea.Height - $visibleHeight) / 2)
    if(-not $script:WindowPlacementCorrectionLogged) {
        $placementError = New-Object System.InvalidOperationException("Saved window position ($($Settings.X), $($Settings.Y)) is not visible on any connected screen.")
        Write-LauncherDiagnostic -Exception $placementError -Context "Launcher window placement was reset to the primary screen."
        $script:WindowPlacementCorrectionLogged = $true
    }
    $resolved = [GaloreLauncherSettings]::new()
    $resolved.Selected = [string[]]@($Settings.Selected)
    $resolved.Width = $visibleWidth
    $resolved.Height = $visibleHeight
    $resolved.X = $visibleX
    $resolved.Y = $visibleY
    $resolved.BrowserId = $Settings.BrowserId
    $resolved.ProgramOverrides = $Settings.ProgramOverrides
    return $resolved
}

# ============================================================
# READ LAUNCHER SETTINGS FILE
# ============================================================

function Read-LauncherSettingsFile {
    param([string]$Path)
    $settings = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    return ConvertTo-ValidatedLauncherSettings -Settings $settings
}

# ============================================================
# LOAD WINDOW SETTINGS
# ============================================================

function Load-WindowSettings {
    if(-not (Test-Path -LiteralPath $script:SettingsFile -PathType Leaf)) {
        return $null
    }
    try {
        $settings = Read-LauncherSettingsFile -Path $script:SettingsFile
        return Resolve-LauncherWindowPlacement -Settings $settings
    } catch {
        Write-LauncherDiagnostic -Exception $_ -Context "Failed to read launcher settings from '$script:SettingsFile'."
    }
    return $null
}

# ============================================================
# GET SAVED WINDOW BOUNDS
# ============================================================

function Get-LauncherSaveBounds {
    param($Form)
    if($Form.WindowState -eq [System.Windows.Forms.FormWindowState]::Normal) {
        $windowBounds = $Form.Bounds
    } else {
        $windowBounds = $Form.RestoreBounds
    }
    if($null -eq $windowBounds -or $windowBounds.Width -lt 1 -or $windowBounds.Height -lt 1) {
        $windowBounds = New-Object System.Drawing.Rectangle($script:LauncherLocation.X, $script:LauncherLocation.Y, $script:LauncherSize.Width, $script:LauncherSize.Height)
    }
    return $windowBounds
}

# ============================================================
# SAVE WINDOW SETTINGS
# ============================================================

function Save-WindowSettings {
    param($Checks, $Form)
    $selectedPrograms = @()
    foreach($name in $Checks.Keys) {
        if($Checks[$name].Checked) {
            $selectedPrograms += $name
        }
    }
    $windowBounds = Get-LauncherSaveBounds -Form $Form
    $settings = ConvertTo-ValidatedLauncherSettings -Settings ([pscustomobject]@{
        Selected = $selectedPrograms
        Width = $windowBounds.Width
        Height = $windowBounds.Height
        X = $windowBounds.X
        Y = $windowBounds.Y
        BrowserId = $script:SelectedBrowserId
        ProgramOverrides = Get-LauncherProgramOverrides
    })
    $settings = Resolve-LauncherWindowPlacement -Settings $settings
    $temporarySettingsFile = "$script:SettingsFile.$([guid]::NewGuid().ToString('N')).tmp"
    $discardedSettingsFile = $null
    try {
        $json = $settings | ConvertTo-Json -Depth 4 -ErrorAction Stop
        $json | ConvertFrom-Json -ErrorAction Stop | Out-Null
        $utf8Encoding = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($temporarySettingsFile, $json, $utf8Encoding)
        Read-LauncherSettingsFile -Path $temporarySettingsFile | Out-Null
        if(Test-Path -LiteralPath $script:SettingsFile -PathType Leaf) {
            $discardedSettingsFile = "$script:SettingsFile.$([guid]::NewGuid().ToString('N')).previous"
            [System.IO.File]::Replace($temporarySettingsFile, $script:SettingsFile, $discardedSettingsFile, $true)
        } else {
            [System.IO.File]::Move($temporarySettingsFile, $script:SettingsFile)
        }
    } catch {
        Write-LauncherDiagnostic -Exception $_ -Context "Failed to save launcher settings atomically to '$script:SettingsFile'."
    } finally {
        if(Test-Path -LiteralPath $temporarySettingsFile -PathType Leaf) {
            Remove-Item -LiteralPath $temporarySettingsFile -Force -ErrorAction SilentlyContinue
        }
        if($discardedSettingsFile -and (Test-Path -LiteralPath $discardedSettingsFile -PathType Leaf)) {
            Remove-Item -LiteralPath $discardedSettingsFile -Force -ErrorAction SilentlyContinue
        }
    }
}

# ============================================================
# GET AND SAVE PROGRAM OVERRIDES
# ============================================================

function Get-LauncherProgramOverrides {
    if(-not (Test-Path -LiteralPath $script:SettingsFile -PathType Leaf)) {
        return [ordered]@{}
    }
    try {
        return (Read-LauncherSettingsFile -Path $script:SettingsFile).ProgramOverrides
    } catch {
        Write-LauncherDiagnostic -Exception $_ -Context "Failed to read saved program overrides from '$script:SettingsFile'."
    }
    return [ordered]@{}
}

function Save-LauncherProgramOverrides {
    param([System.Collections.IDictionary]$ProgramOverrides)
    $settings = if(Test-Path -LiteralPath $script:SettingsFile -PathType Leaf) {
        Read-LauncherSettingsFile -Path $script:SettingsFile
    } else {
        [pscustomobject]@{
            Selected = @()
            Width = 1100
            Height = 550
            X = 0
            Y = 0
            BrowserId = $null
            ProgramOverrides = [ordered]@{}
        }
    }
    $settings = ConvertTo-ValidatedLauncherSettings -Settings ([pscustomobject]@{
        Selected = @($settings.Selected)
        Width = $settings.Width
        Height = $settings.Height
        X = $settings.X
        Y = $settings.Y
        BrowserId = $settings.BrowserId
        ProgramOverrides = $ProgramOverrides
    })
    $temporarySettingsFile = "$script:SettingsFile.$([guid]::NewGuid().ToString('N')).tmp"
    $discardedSettingsFile = $null
    try {
        $json = $settings | ConvertTo-Json -Depth 5 -ErrorAction Stop
        [System.IO.File]::WriteAllText($temporarySettingsFile, $json, (New-Object System.Text.UTF8Encoding($false)))
        Read-LauncherSettingsFile -Path $temporarySettingsFile | Out-Null
        if(Test-Path -LiteralPath $script:SettingsFile -PathType Leaf) {
            $discardedSettingsFile = "$script:SettingsFile.$([guid]::NewGuid().ToString('N')).previous"
            [System.IO.File]::Replace($temporarySettingsFile, $script:SettingsFile, $discardedSettingsFile, $true)
        } else {
            [System.IO.File]::Move($temporarySettingsFile, $script:SettingsFile)
        }
    } catch {
        Write-LauncherDiagnostic -Exception $_ -Context "Failed to save program overrides atomically to '$script:SettingsFile'."
        throw
    } finally {
        Remove-Item -LiteralPath $temporarySettingsFile -Force -ErrorAction SilentlyContinue
        if($discardedSettingsFile) {
            Remove-Item -LiteralPath $discardedSettingsFile -Force -ErrorAction SilentlyContinue
        }
    }
}
