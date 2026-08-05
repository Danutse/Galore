# ============================================================
# LAUNCHER ACTION MODULE
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherAction"
    LoadOrder = 130
    RequiresModules = @("LauncherLogging", "LauncherPrograms", "UI")
    RequiresFunctions = [ordered]@{
        "Write-LauncherDiagnostic" = "LauncherLogging"
        "Refresh-StatusDelayed" = "LauncherPrograms"
        "Get-ResourceIcon" = "UI"
        "Style-Button" = "UI"
    }
    RequiresTypes = [ordered]@{}
    RequiresVariables = @("AppRoot")
    RequiresFolders = @("Programs")
    RequiresFiles = @("Programs\SpotifyPlay.vbs")
    ProvidesTypes = @()
}

# ============================================================
# ACTION BUTTON IMAGE
# ============================================================

function Set-ActionButtonImage {
    param($Button)
    $actionButtonImage = Get-ResourceIcon "actionbutton.png"
    if(-not $actionButtonImage) {
        return
    }
    try {
        $Button.BackgroundImage = New-Object System.Drawing.Bitmap($actionButtonImage)
    } finally {
        $actionButtonImage.Dispose()
    }
    $Button.BackgroundImageLayout = [System.Windows.Forms.ImageLayout]::Stretch
    $Button.Add_Disposed({
        $ownedImage = $this.BackgroundImage
        if($ownedImage) {
            $this.BackgroundImage = $null
            $ownedImage.Dispose()
        }
    })
}

# ============================================================
# ACTION BUTTON
# ============================================================

function New-ActionButton {
    param($Text, $X, $Y)
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    Style-Button $button
    Set-ActionButtonImage $button
    $button.Location = New-Object System.Drawing.Point($X, $Y)
    return $button
}

# ============================================================
# LAUNCH ALL BUTTON
# ============================================================

function New-LaunchAllButton {
    return (New-ActionButton "Launch All" 50 400)
}

# ============================================================
# TERMINATE ALL BUTTON
# ============================================================

function New-TerminateAllButton {
    return (New-ActionButton "Terminate All" 240 400)
}

# ============================================================
# LAUNCH SELECTED BUTTON
# ============================================================

function New-LaunchSelectedButton {
    return (New-ActionButton "Launch Selected" 50 450)
}

# ============================================================
# TERMINATE SELECTED BUTTON
# ============================================================

function New-TerminateSelectedButton {
    return (New-ActionButton "Terminate Selected" 240 450)
}

# ============================================================
# SPOTIFY AUTOPLAY
# ============================================================

function Start-SpotifyAutoplay {
    param($AppRoot)
    $spotifyScript = Join-Path $AppRoot "Programs\SpotifyPlay.vbs"
    if(Test-Path $spotifyScript) {
        Start-Process -FilePath "$env:WINDIR\System32\wscript.exe" -ArgumentList "`"$spotifyScript`"" -WindowStyle Hidden
    }
}

# ============================================================
# LAUNCH PROGRAMS
# ============================================================

function Invoke-ProgramLaunch {
    param($Programs, $Statuses, [string[]]$ProgramNames, $AppRoot, [switch]$ShowStartingStatus)
    $updated = @()
    $launchedPrograms = @{}
    foreach($name in $ProgramNames) {
        if(-not $Programs.ContainsKey($name)) {
            continue
        }
        $program = $Programs[$name]
        if($null -eq $program) {
            continue
        }
        if([string]::IsNullOrWhiteSpace($program.Path)) {
            continue
        }
        $launchIdentity = (([string]$program.Path).Trim().ToLowerInvariant() + "|" + ([string]$program.Args).Trim())
        if($launchedPrograms.ContainsKey($launchIdentity)) {
            continue
        }
        $launchedPrograms[$launchIdentity] = $true
        try {
            if([string]::IsNullOrWhiteSpace($program.Args)) {
                Start-Process -FilePath $program.Path -ErrorAction Stop
            } else {
                Start-Process -FilePath $program.Path -ArgumentList $program.Args -ErrorAction Stop
            }
        } catch {
            Write-LauncherDiagnostic -Exception $_ -Context "Failed to launch '$name' from '$($program.Path)'."
            continue
        }
        if($ShowStartingStatus -and $Statuses.ContainsKey($name)) {
            $Statuses[$name].Text = "| Starting"
            $Statuses[$name].ForeColor = [System.Drawing.Color]::Orange
            $Statuses[$name].Refresh()
        }
        $updated += $name
    }
    Refresh-StatusDelayed -Programs $Programs -Statuses $Statuses -ProgramsToUpdate $updated
    Start-SpotifyAutoplay -AppRoot $AppRoot
}

# ============================================================
# TERMINATE PROGRAMS
# ============================================================

function Invoke-ProgramTermination {
    param($Programs, $Statuses, [string[]]$ProgramNames)
    $updated = @()
    $processList = @()
    foreach($name in $ProgramNames) {
        if(-not $Programs.ContainsKey($name)) {
            continue
        }
        $process = $Programs[$name]["StatusProcess"]
        if([string]::IsNullOrWhiteSpace($process)) {
            continue
        }
        $processList += $process
        $updated += $name
    }
    if($processList.Count -gt 0) {
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(($processList -join ",")))
        Start-Process powershell.exe -WindowStyle Hidden -Verb RunAs -ArgumentList "-WindowStyle Hidden -Command `$p=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$encoded')); `$p.Split(',') | ForEach-Object { Stop-Process -Name `$_.Replace('.exe','') -Force -ErrorAction SilentlyContinue }"
    }
    Refresh-StatusDelayed -Programs $Programs -Statuses $Statuses -ProgramsToUpdate $updated
}

# ============================================================
# KEEP BUTTONS LOCKED TO BOTTOM LEFT WHEN RESIZING
# ============================================================

function Add-LauncherButtonResizeHandler {
    param($Form, $LaunchAll, $TerminateAll, $LaunchSelected, $TerminateSelected)
    $Form.Add_SizeChanged({
        $bottomOffset = 50
        $leftMargin = 50
        $buttonSpacing = 20
        if($LaunchAll) {
            $LaunchAll.Left = $leftMargin
            $LaunchAll.Top = $Form.ClientSize.Height -
            $bottomOffset -
            ($LaunchAll.Height * 2) -
            $buttonSpacing
        }
        if($TerminateAll) {
            $TerminateAll.Left = $leftMargin + $LaunchAll.Width + $buttonSpacing
            $TerminateAll.Top = $LaunchAll.Top
        }
        if($LaunchSelected) {
            $LaunchSelected.Left = $leftMargin
            $LaunchSelected.Top = $Form.ClientSize.Height -
            $bottomOffset -
            $LaunchSelected.Height
        }
        if($TerminateSelected) {
            $TerminateSelected.Left = $leftMargin + $LaunchSelected.Width + $buttonSpacing
            $TerminateSelected.Top = $LaunchSelected.Top
        }
    })
}

# ============================================================
# INITIAL BUTTON POSITION
# ============================================================

function Set-LauncherButtonInitialPosition {
    param($Form, $LaunchAll, $TerminateAll, $LaunchSelected, $TerminateSelected)
    $bottomOffset = 50
    $leftMargin = 50
    $buttonSpacing = 20
    $LaunchAll.Left = $leftMargin
    $LaunchAll.Top = $Form.ClientSize.Height -
    $bottomOffset -
    ($LaunchAll.Height * 2) -
    $buttonSpacing
    $TerminateAll.Left = $leftMargin + $LaunchAll.Width + $buttonSpacing
    $TerminateAll.Top = $LaunchAll.Top
    $LaunchSelected.Left = $leftMargin
    $LaunchSelected.Top = $Form.ClientSize.Height -
    $bottomOffset -
    $LaunchSelected.Height
    $TerminateSelected.Left = $leftMargin + $LaunchSelected.Width + $buttonSpacing
    $TerminateSelected.Top = $LaunchSelected.Top
}

# ============================================================
# LAUNCHER ACTION BUTTONS
# ============================================================

function Initialize-LauncherButtons {
    param([System.Windows.Forms.Form]$Form, $Programs, $Checks, $Statuses)

    # ============================================================
    # LAUNCH ALL BUTTON
    # ============================================================

    $launchAll = New-LaunchAllButton
    $launchAllState = [PSCustomObject]@{
        Programs = $Programs
        Statuses = $Statuses
        AppRoot = $AppRoot
        TerminateButton = $null
    }
    $launchAll.Tag = $launchAllState
    $launchAll.Add_Click({
        param($sender, $e)
        $state = $sender.Tag
        if(-not $state) {
            return
        }
        $terminateButton = $state.TerminateButton
        $sender.Enabled = $false
        if($terminateButton -and -not $terminateButton.IsDisposed) {
            $terminateButton.Enabled = $false
        }
        try {
            $programNames = @(
            foreach($name in $state.Programs.Keys) {
                if($name -ne "Loader") {
                    $name
                }
            }
            )
            Invoke-ProgramLaunch -Programs $state.Programs -Statuses $state.Statuses -ProgramNames $programNames -AppRoot $state.AppRoot -ShowStartingStatus
        } finally {
            if(-not $sender.IsDisposed) {
                $sender.Enabled = $true
            }
            if($terminateButton -and -not $terminateButton.IsDisposed) {
                $terminateButton.Enabled = $true
            }
        }
    })
    $Form.Controls.Add($launchAll)

    # ============================================================
    # TERMINATE ALL BUTTON
    # ============================================================

    $terminateAll = New-TerminateAllButton
    $launchAllState.TerminateButton = $terminateAll
    $terminateAll.Add_Click({
        Invoke-ProgramTermination -Programs $Programs -Statuses $Statuses -ProgramNames @(
        $Programs.Keys
        )
    })
    $Form.Controls.Add($terminateAll)

    # ============================================================
    # LAUNCH SELECTED BUTTON
    # ============================================================

    $launchSelected = New-LaunchSelectedButton
    $launchSelected.Add_Click({
        $selectedPrograms = @(
        foreach($name in $Checks.Keys) {
            if($Checks[$name].Checked) {
                $name
            }
        }
        )
        Invoke-ProgramLaunch -Programs $Programs -Statuses $Statuses -ProgramNames $selectedPrograms -AppRoot $AppRoot
    })
    $Form.Controls.Add($launchSelected)

    # ============================================================
    # TERMINATE SELECTED BUTTON
    # ============================================================

    $action = New-TerminateSelectedButton
    $action.Add_Click({
        $selectedPrograms = @(
        foreach($name in $Checks.Keys) {
            if($Checks[$name].Checked) {
                $name
            }
        }
        )
        Invoke-ProgramTermination -Programs $Programs -Statuses $Statuses -ProgramNames $selectedPrograms
    })
    $Form.Controls.Add($action)

    # ============================================================
    # KEEP BUTTONS LOCKED TO BOTTOM LEFT WHEN RESIZING
    # ============================================================

    Add-LauncherButtonResizeHandler -Form $Form -LaunchAll $launchAll -TerminateAll $terminateAll -LaunchSelected $launchSelected -TerminateSelected $action
    Set-LauncherButtonInitialPosition -Form $Form -LaunchAll $launchAll -TerminateAll $terminateAll -LaunchSelected $launchSelected -TerminateSelected $action
}
