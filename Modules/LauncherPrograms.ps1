# ============================================================
# LAUNCHER START PROGRAMS MODULE
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherPrograms"
    LoadOrder = 110
    RequiresModules = @("LauncherBrowser", "LauncherDesktop", "LauncherEvents", "LauncherLogging", "LauncherMaintenance", "LauncherProcess", "LauncherSettings", "LauncherStartup", "UI")
    RequiresFunctions = [ordered]@{
        "New-StartupToggle" = "LauncherDesktop"
        "Register-ProgramNameToggleEvent" = "LauncherEvents"
        "Update-GaloreApplicationMaintenanceState" = "LauncherMaintenance"
        "Bring-ProgramToFront" = "LauncherProcess"
        "Get-ProgramStatus" = "LauncherProcess"
        "Load-WindowSettings" = "LauncherSettings"
        "Get-LauncherProgramOverrides" = "LauncherSettings"
        "Save-LauncherProgramOverrides" = "LauncherSettings"
        "Set-ProgramStartup" = "LauncherStartup"
        "New-ProgramCheckbox" = "UI"
        "New-ProgramStatusLabel" = "UI"
        "Show-GaloreBrowserSelector" = "LauncherBrowser"
        "Write-LauncherDiagnostic" = "LauncherLogging"
        "Write-GaloreLog" = "LauncherLogging"
    }
    RequiresTypes = [ordered]@{}
    RequiresVariables = @("AppRoot")
    RequiresFolders = @()
    RequiresFiles = @()
    ProvidesTypes = @()
}

# ============================================================
# PROGRAM CUSTOMIZATION
# ============================================================

function Apply-GaloreProgramOverrides {
    param([System.Collections.IDictionary]$Programs)
    $overrides = Get-LauncherProgramOverrides
    foreach($programName in @($overrides.Keys)) {
        if(-not $Programs.Contains($programName)) {
            continue
        }
        $override = $overrides[$programName]
        if(-not (Test-Path -LiteralPath $override.Path -PathType Leaf) -or [System.IO.Path]::GetExtension([string]$override.Path) -ne ".exe") {
            Write-GaloreLog -Level "WARNING" -Component "Programs" -Message "Saved override for '$programName' was ignored because its executable is unavailable."
            continue
        }
        $processName = [System.IO.Path]::GetFileNameWithoutExtension([string]$override.Path)
        $Programs[$programName]["Path"] = [string]$override.Path
        $Programs[$programName]["Args"] = ""
        $Programs[$programName]["StatusProcess"] = $processName
        $Programs[$programName]["WindowProcess"] = $processName
        $Programs[$programName]["DisplayName"] = [string]$override.DisplayName
    }
}

function Show-GaloreProgramNameDialog {
    param([string]$Prompt, [string]$DefaultName, [System.Windows.Forms.IWin32Window]$Owner)
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $dialog.ShowInTaskbar = $false
    $dialog.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $dialog.TopMost = $true
    $dialog.BackColor = [System.Drawing.Color]::Black
    $path = Get-GaloreResourcePath "programname.png"
    if(Test-Path -LiteralPath $path) { $source=[System.Drawing.Image]::FromFile($path); $dialog.BackgroundImage=New-Object System.Drawing.Bitmap($source); $source.Dispose(); $dialog.BackgroundImageLayout=[System.Windows.Forms.ImageLayout]::None; $dialog.ClientSize=$dialog.BackgroundImage.Size }
    else { $dialog.ClientSize=[System.Drawing.Size]::new(360,160) }
    $label=New-Object System.Windows.Forms.Label; $label.Text=$Prompt; $label.Bounds=[System.Drawing.Rectangle]::new(20,20,$dialog.ClientSize.Width-40,28); $label.ForeColor=[System.Drawing.Color]::White; $label.BackColor=[System.Drawing.Color]::Transparent
    $box=New-Object System.Windows.Forms.TextBox; $box.Text=$DefaultName; $box.Bounds=[System.Drawing.Rectangle]::new(20,57,$dialog.ClientSize.Width-40,25)
    $save=New-Object System.Windows.Forms.Button; $save.Text='Save'; $save.Bounds=[System.Drawing.Rectangle]::new($dialog.ClientSize.Width-100,$dialog.ClientSize.Height-45,80,25); $save.DialogResult=[System.Windows.Forms.DialogResult]::OK
    $dialog.Controls.AddRange(@($label,$box,$save)); $dialog.AcceptButton=$save
    try { $result=if($Owner){$dialog.ShowDialog($Owner)}else{$dialog.ShowDialog()}; if($result -eq [System.Windows.Forms.DialogResult]::OK -and -not [string]::IsNullOrWhiteSpace($box.Text)) { return $box.Text.Trim() }; return $DefaultName } finally { if($dialog.BackgroundImage){$dialog.BackgroundImage.Dispose()};$dialog.Dispose() }
}

function Show-GaloreProgramCustomization {
    param([System.Collections.IDictionary]$Programs, [string]$ProgramName, $ProgramLabel)
    if(-not $Programs.Contains($ProgramName)) {
        return
    }
    $fileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $fileDialog.Title = "Choose the executable for $ProgramName"
    $fileDialog.Filter = "Applications (*.exe)|*.exe"
    $fileDialog.CheckFileExists = $true
    $currentPath = [string]$Programs[$ProgramName]["Path"]
    if(-not [string]::IsNullOrWhiteSpace($currentPath) -and (Test-Path -LiteralPath $currentPath -PathType Leaf)) {
        $fileDialog.InitialDirectory = [System.IO.Path]::GetDirectoryName($currentPath)
    }
    try {
        if($fileDialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
            return
        }
        $defaultDisplayName = [System.IO.Path]::GetFileNameWithoutExtension($fileDialog.FileName)
        $displayName = Show-GaloreProgramNameDialog -Prompt "Choose the name shown in Galore for this item." -DefaultName $defaultDisplayName
        $overrides = Get-LauncherProgramOverrides
        $overrides[$ProgramName] = [pscustomobject]@{
            Path = $fileDialog.FileName
            DisplayName = $displayName
        }
        Save-LauncherProgramOverrides -ProgramOverrides $overrides
        $processName = [System.IO.Path]::GetFileNameWithoutExtension($fileDialog.FileName)
        $Programs[$ProgramName]["Path"] = $fileDialog.FileName
        $Programs[$ProgramName]["Args"] = ""
        $Programs[$ProgramName]["StatusProcess"] = $processName
        $Programs[$ProgramName]["WindowProcess"] = $processName
        $Programs[$ProgramName]["DisplayName"] = $displayName
        $ProgramLabel.Text = $displayName
        $toolTip = New-Object System.Windows.Forms.ToolTip
        $toolTip.SetToolTip($ProgramLabel, $fileDialog.FileName)
    } catch {
        Write-LauncherDiagnostic -Exception $_ -Context "Failed to customize launcher program '$ProgramName'."
        [System.Windows.Forms.MessageBox]::Show("Galore could not save the selected program. See Diagnostics.log for details.", "Galore Launcher") | Out-Null
    } finally {
        $fileDialog.Dispose()
    }
}

# ============================================================
# PROGRAM STORAGE
# ============================================================

function Initialize-ProgramStorage {
    param($Programs)
    $checks = @{}
    $statuses = @{}
    $columnWidth = 330
    $rowHeight = 75
    $totalColumns = 3
    $totalRows = [math]::Ceiling($Programs.Count / $totalColumns)
    return @{
        Checks = $checks
        Statuses = $statuses
        ColumnWidth = $columnWidth
        RowHeight = $rowHeight
        TotalColumns = $totalColumns
        TotalRows = $totalRows
    }
}

# ============================================================
# BUILD PROGRAM GRID
# ============================================================

function Build-ProgramGrid {
    param($Form, $Programs, $checks, $statuses, $columnWidth, $rowHeight, $totalColumns, $totalRows)

    # ============================================================
    # DYNAMIC WINDOW SIZE
    # ============================================================

    $windowWidth = 1100
    $topPadding = 150
    $bottomPadding = 80
    $windowHeight = $topPadding + ($totalRows * $rowHeight) + $bottomPadding
    $minHeight = 550
    if($windowHeight -lt $minHeight) {
        $windowHeight = $minHeight
    }
    $maxHeight = 900
    if($windowHeight -gt $maxHeight) {
        $windowHeight = $maxHeight
    }
    $form.Size = New-Object System.Drawing.Size($windowWidth, $windowHeight)
    $gridWidth = (($totalColumns - 1) * $columnWidth) + 250
    $startY = 90
    $index = 0
    foreach($name in $Programs.Keys) {
        $column = $index % $totalColumns
        $row = [math]::Floor($index / $totalColumns)
        $startX = ($form.ClientSize.Width - $gridWidth) / 2
        $x = [int]($startX + ($column * $columnWidth))
        $y = [int]($startY + ($row * $rowHeight))

        # ==========================
        # CHECKBOX
        # ==========================

        $box = New-ProgramCheckbox -Name $name -X $x -Y $y
        $box.UseVisualStyleBackColor = $false
        $box.FlatStyle = [System.Windows.Forms.FlatStyle]::Standard
        $box.BackColor = [System.Drawing.Color]::Transparent
        $box.ForeColor = [System.Drawing.Color]::White
        $box.Text = ""

        # ==========================
        # PROGRAM NAME LABEL
        # ==========================

        $nameLabel = New-Object System.Windows.Forms.Label
        $nameLabel.Text = if($name -eq "Browser" -and $Programs[$name].Contains("BrowserDisplayName")) {
            "Browser: $($Programs[$name]["BrowserDisplayName"])"
        } elseif($Programs[$name].Contains("DisplayName") -and -not [string]::IsNullOrWhiteSpace([string]$Programs[$name]["DisplayName"])) {
            [string]$Programs[$name]["DisplayName"]
        } else {
            $name
        }
        $nameLabel.Name = $name
        $nameLabel.Location = New-Object System.Drawing.Point(($x + 22), $y)
        $nameLabel.Width = 250
        $nameLabel.Height = 25
        $nameLabel.Font = $box.Font
        $nameLabel.ForeColor = [System.Drawing.Color]::White
        $nameLabel.BackColor = [System.Drawing.Color]::Transparent
        $nameLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $nameLabel.AutoEllipsis = $true
        $nameLabel.Parent = $form
        $nameLabel.UseMnemonic = $false

        # ==========================
        # CLICK NAME TO TOGGLE CHECKBOX
        # ==========================

        $nameLabel.Tag = $box
        Register-ProgramNameToggleEvent $nameLabel

        # ==========================
        # HOVER EFFECT
        # ==========================

        $nameLabel.Add_MouseEnter({
            $this.ForeColor = [System.Drawing.Color]::Blue
        })
        $nameLabel.Add_MouseLeave({
            $this.ForeColor = [System.Drawing.Color]::White
        })

        # ==========================
        # SELECTED EFFECT
        # ==========================

        $box.Tag = $nameLabel
        $box.Add_CheckedChanged({
            if($null -ne $this.Tag -and $this.Tag -is [System.Windows.Forms.Label]) {
                $this.Tag.ForeColor = [System.Drawing.Color]::White
            }
        })

        # ==========================
        # RIGHT CLICK - CHANGE PROGRAM EXECUTABLE
        # ==========================

        $box.Add_MouseUp({
            param($sender, $e)
            if($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
                $programName = $this.Tag.Name
                if($programName -eq "Browser") {
                    Show-GaloreBrowserSelector -Programs $Programs -BrowserLabel $this.Tag -AppRoot $AppRoot
                } else {
                    Show-GaloreProgramCustomization -Programs $Programs -ProgramName $programName -ProgramLabel $this.Tag
                }
            }
        })
        $nameLabel.Add_MouseUp({
            param($sender, $e)
            if($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
                $programName = $this.Name
                if($programName -eq "Browser") {
                    Show-GaloreBrowserSelector -Programs $Programs -BrowserLabel $this -AppRoot $AppRoot
                } else {
                    Show-GaloreProgramCustomization -Programs $Programs -ProgramName $programName -ProgramLabel $this
                }
            }
        })

        # ==========================
        # STATUS LABEL
        # ==========================

        $status = New-ProgramStatusLabel -Text "Closed" -X $x -Y ($y + 25)

        # ==========================
        # ADD CONTROLS
        # ==========================

        $form.Controls.Add($box)
        $form.Controls.Add($nameLabel)
        $nameLabel.BringToFront()
        $form.Controls.Add($status)
        $checks[$name] = $box
        $statuses[$name] = $status
        $index++
    }
}

# ============================================================
# RESTORE PROGRAM SELECTIONS
# ============================================================

function Restore-ProgramSelections {
    param($Checks)
    $windowSettings = Load-WindowSettings
    if($windowSettings -and $windowSettings.Selected) {
        foreach($name in $windowSettings.Selected) {
            if($Checks.ContainsKey($name)) {
                $Checks[$name].Checked = $true
            }
        }
    }
}

# ============================================================
# STARTUP TOGGLE
# ============================================================

function Initialize-StartupToggle {
    param($Form)
    $startupToggle = New-StartupToggle
    $startupToggle.Add_CheckedChanged({
        Set-ProgramStartup($this.Checked)
    })
    $Form.Controls.Add($startupToggle)
    return $startupToggle
}

# ============================================================
# UPDATE PROGRAM STATUS INDICATORS
# ============================================================

function Update-ProgramStatus {
    param($Programs, $Statuses, [string[]]$ProgramsToUpdate)
    foreach($name in $ProgramsToUpdate) {
        if(-not $Statuses.ContainsKey($name)) {
            continue
        }
        $process = $Programs[$name]["StatusProcess"]
        $isRunning = [bool](Get-ProgramStatus $process)
        Update-GaloreApplicationMaintenanceState -ApplicationName $name -IsRunning $isRunning
        if($isRunning) {
            $Statuses[$name].Text = "● Running"
            $Statuses[$name].ForeColor = [System.Drawing.Color]::Green
            $Statuses[$name].Text = "$([char]0x25CF) Running"
        } else {
            $Statuses[$name].Text = "○ Closed"
            $Statuses[$name].ForeColor = [System.Drawing.Color]::Red
            $Statuses[$name].Text = "$([char]0x25CB) Closed"
        }
    }
}

# ============================================================
# DELAYED STATUS REFRESH
# ============================================================

function Refresh-StatusDelayed {
    param($Programs, $Statuses, [string[]]$ProgramsToUpdate)
    $refreshTimer = New-Object System.Windows.Forms.Timer
    if($null -eq $script:StatusRefreshTimers) {
        $script:StatusRefreshTimers = New-Object System.Collections.ArrayList
    }
    $script:StatusRefreshTimers.Add($refreshTimer) | Out-Null
    $refreshTimer.Interval = 1200
    $refreshTimer.Tag = @{
        Programs = $Programs
        Statuses = $Statuses
        ProgramsToUpdate = @(
            $ProgramsToUpdate
        )
    }
    $refreshTimer.Add_Tick({
        $timer = $this
        $timer.Stop()
        $state = $timer.Tag
        try {
            Update-ProgramStatus -Programs $state.Programs -Statuses $state.Statuses -ProgramsToUpdate $state.ProgramsToUpdate
        } finally {
            if($script:StatusRefreshTimers) {
                $script:StatusRefreshTimers.Remove($timer) | Out-Null
            }
            $timer.Tag = $null
            $timer.Dispose()
        }
    })
    $refreshTimer.Start()
}

# ============================================================
# INITIAL PROGRAM STATUS
# ============================================================

function Initialize-ProgramStatus {
    param($Programs, $Statuses)
    Update-ProgramStatus -Programs $Programs -Statuses $Statuses -ProgramsToUpdate @(
        $Programs.Keys
    )
}

# ============================================================
# STATUS TIMER
# ============================================================

function Initialize-StatusTimer {
    param($Programs, $Statuses)
    $statusTimer = New-Object System.Windows.Forms.Timer
    $statusTimer.Interval = 30000
    $statusTimer.Tag = @{
        Programs = $Programs
        Statuses = $Statuses
    }
    $statusTimer.Add_Tick({
        $state = $this.Tag
        Update-ProgramStatus -Programs $state.Programs -Statuses $state.Statuses -ProgramsToUpdate @(
            $state.Programs.Keys
        )
    })
    $statusTimer.Start()
    $script:ProgramStatusTimer = $statusTimer
    return $statusTimer
}

# ============================================================
# STOP PROGRAM STATUS RESOURCES
# ============================================================

function Stop-ProgramStatusResources {
    if($script:ProgramStatusTimer) {
        $script:ProgramStatusTimer.Stop()
        $script:ProgramStatusTimer.Tag = $null
        $script:ProgramStatusTimer.Dispose()
        $script:ProgramStatusTimer = $null
    }
    if($script:StatusRefreshTimers) {
        foreach($refreshTimer in @($script:StatusRefreshTimers)
        ) {
            if($refreshTimer) {
                $refreshTimer.Stop()
                $refreshTimer.Tag = $null
                $refreshTimer.Dispose()
            }
        }
        $script:StatusRefreshTimers.Clear()
        $script:StatusRefreshTimers = $null
    }
}

# ============================================================
# PROGRAM CONTROLS
# ============================================================

function Initialize-ProgramControls {
    param($Form, $Programs)

    # ============================================================
    # CONTROL STORAGE
    # ============================================================

    $Storage = Initialize-ProgramStorage -Programs $Programs
    $checks = $Storage.Checks
    $statuses = $Storage.Statuses
    $columnWidth = $Storage.ColumnWidth
    $rowHeight = $Storage.RowHeight
    $totalColumns = $Storage.TotalColumns
    $totalRows = $Storage.TotalRows

    # ============================================================
    # BUILD PROGRAM GRID
    # ============================================================

    Build-ProgramGrid -Form $Form -Programs $Programs -Checks $checks -Statuses $statuses -ColumnWidth $columnWidth -RowHeight $rowHeight -TotalColumns $totalColumns -TotalRows $totalRows

    # ============================================================
    # RESTORE PROGRAM SELECTIONS
    # ============================================================

    Restore-ProgramSelections -Checks $checks

    # ============================================================
    # STARTUP TOGGLE
    # ============================================================

    $startupToggle = Initialize-StartupToggle -Form $Form

    # ============================================================
    # INITIAL PROGRAM STATUS
    # ============================================================

    Initialize-ProgramStatus -Programs $Programs -Statuses $statuses

    # ============================================================
    # STATUS TIMER
    # ============================================================

    $statusTimer = Initialize-StatusTimer -Programs $Programs -Statuses $statuses

    # ============================================================
    # RETURN CONTROLS
    # ============================================================

    return @{
        Checks      = $checks
        Statuses    = $statuses
        StatusTimer = $statusTimer
    }
}
