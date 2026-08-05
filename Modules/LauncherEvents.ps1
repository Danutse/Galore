# ============================================================
# LAUNCHER EVENTS MODULE
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherEvents"
    LoadOrder = 50
    RequiresModules = @("LauncherLogging", "LauncherDesktop", "LauncherHardware", "LauncherHotkeys", "LauncherMaintenance", "LauncherPrograms", "LauncherSettings", "LauncherStartMenu", "ProgramWindowUI", "SplashSupport", "UI", "LauncherRecycleHelper", "LauncherPostIts")
    RequiresFunctions = [ordered]@{
        "Write-GaloreLog" = "LauncherLogging"
        "Write-LauncherDiagnostic" = "LauncherLogging"
        "Clear-RAM" = "LauncherHardware"
        "Save-WindowSettings" = "LauncherSettings"
        "Close-StartSearchWindowAnimated" = "LauncherStartMenu"
        "Get-AppIcon" = "UI"
        "Hide-LauncherWindowAnimated" = "UI"
        "Show-LauncherWindowAnimated" = "UI"
        "Stop-DesktopResources" = "LauncherDesktop"
        "Stop-GlobalHotkey" = "LauncherHotkeys"
        "Stop-GaloreMaintenance" = "LauncherMaintenance"
        "Stop-HardwareMonitor" = "LauncherHardware"
        "Stop-ProgramStatusResources" = "LauncherPrograms"
        "Stop-ProgramWindowResources" = "ProgramWindowUI"
        "Stop-SplashResources" = "SplashSupport"
        "Stop-GalorePostItResources" = "LauncherPostIts"
        "Stop-StartMenuResources" = "LauncherStartMenu"
        "Stop-UIResources" = "UI"
    }
    RequiresTypes = [ordered]@{
        "GaloreDropHelper.Exports" = "LauncherRecycleHelper"
    }
    RequiresVariables = @()
    RequiresFolders = @()
    RequiresFiles = @()
    ProvidesTypes = @()
}
$script:LauncherRuntimeStopped = $false

# ============================================================
# TRAY AUTOMATION SETTINGS
# ============================================================

function Initialize-GaloreTrayAutomation {
    $script:GaloreTrayAutomationFile = Join-Path (Get-LauncherSettingsFolder) "tray-automation.json"
    $script:GaloreTrayAutomation = [pscustomobject]@{ KeepRunningOnClose = $true }
    if(Test-Path -LiteralPath $script:GaloreTrayAutomationFile -PathType Leaf) {
        try {
            $saved = Get-Content -LiteralPath $script:GaloreTrayAutomationFile -Raw | ConvertFrom-Json
            if($null -ne $saved.KeepRunningOnClose) { $script:GaloreTrayAutomation.KeepRunningOnClose = [bool]$saved.KeepRunningOnClose }
        } catch { Write-LauncherDiagnostic -Exception $_ -Context "Failed to load tray automation settings; defaults were restored." }
    }
    Save-GaloreTrayAutomation
}

function Get-GaloreTrayAutomation {
    if($null -eq $script:GaloreTrayAutomation) { Initialize-GaloreTrayAutomation }
    return $script:GaloreTrayAutomation
}

function Save-GaloreTrayAutomation {
    if($null -eq $script:GaloreTrayAutomation -or [string]::IsNullOrWhiteSpace([string]$script:GaloreTrayAutomationFile)) { return }
    $temporaryFile = "$script:GaloreTrayAutomationFile.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporaryFile, ($script:GaloreTrayAutomation | ConvertTo-Json -Depth 2), (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temporaryFile -Destination $script:GaloreTrayAutomationFile -Force
    } catch { Write-LauncherDiagnostic -Exception $_ -Context "Failed to save tray automation settings." }
    finally { Remove-Item -LiteralPath $temporaryFile -Force -ErrorAction SilentlyContinue }
}

# ============================================================
# CLICK HARDWARE MONITOR TO CLEAN RAM
# ============================================================

function Register-HardwareMonitorEvents {
    param($SystemPanel)
    if($null -eq $SystemPanel) {
        return
    }
    $cleanRAMHandler = {
        Clear-RAM
    }
    $SystemPanel.Add_Click($cleanRAMHandler)
    foreach($control in $SystemPanel.Controls) {
        $control.Add_Click($cleanRAMHandler)
    }
}

# ==========================
# CLICK NAME TO TOGGLE CHECKBOX
# ==========================

function Register-ProgramNameToggleEvent {
    param($Label)
    $Label.Add_MouseClick({
        param($sender, $e)
        if($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) {
            return
        }
        $targetBox = $this.Tag
        if($targetBox) {
            $targetBox.Checked = -not $targetBox.Checked
        }
    })
}

# ============================================================
# RESTORE LAUNCHER WINDOW
# ============================================================

function Restore-LauncherWindow {
    $launcherForm = $script:LauncherForm
    if($null -eq $launcherForm -or $launcherForm.IsDisposed) {
        return
    }
    $launcherForm.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    $launcherForm.Size = $script:LauncherSize
    $launcherForm.Location = $script:LauncherLocation
    Show-LauncherWindowAnimated -Form $launcherForm -DurationMilliseconds 220
}

# ============================================================
# SYSTEM TRAY ICON
# ============================================================

function Initialize-SystemTray {
    Initialize-GaloreTrayAutomation
    $script:trayIcon = New-Object System.Windows.Forms.NotifyIcon
    $script:TrayOwnedIcon = Get-AppIcon
    $script:trayIcon.Icon = $script:TrayOwnedIcon
    if(!$script:trayIcon.Icon) {
        $script:trayIcon.Icon = [System.Drawing.SystemIcons]::Application
    }
    $script:trayIcon.Text = "Program Manager"
    $script:trayIcon.Visible = $true

    # ============================================================
    # DOUBLE CLICK TRAY ICON = RESTORE WINDOW
    # ============================================================

    $script:trayIcon.Add_DoubleClick({
        Restore-LauncherWindow
    })

    # ============================================================
    # RIGHT CLICK MENU
    # ============================================================

    $script:TrayMenu = New-Object System.Windows.Forms.ContextMenuStrip
    $showItem = $script:TrayMenu.Items.Add("Open Launcher")
    $automationMenu = New-Object System.Windows.Forms.ToolStripMenuItem("Tray Automation")
    $keepRunningItem = New-Object System.Windows.Forms.ToolStripMenuItem("Keep running in tray when closed")
    $keepRunningItem.CheckOnClick = $true
    $keepRunningItem.Checked = (Get-GaloreTrayAutomation).KeepRunningOnClose
    $backupItem = New-Object System.Windows.Forms.ToolStripMenuItem("Create settings backup...")
    $automationMenu.DropDownItems.Add($keepRunningItem) | Out-Null
    $script:TrayMenu.Items.Add($automationMenu) | Out-Null
    $script:TrayMenu.Items.Add($backupItem) | Out-Null
    $script:TrayMenu.Items.Add("-") | Out-Null
    $exitItem = $script:TrayMenu.Items.Add("Exit")
    $showItem.Add_Click({
        Restore-LauncherWindow
    })
    $keepRunningItem.Add_Click({
        $settings = Get-GaloreTrayAutomation
        $settings.KeepRunningOnClose = [bool]$this.Checked
        Save-GaloreTrayAutomation
    })
    $backupItem.Add_Click({
        Export-GaloreSettingsBackup -Owner $script:LauncherForm | Out-Null
    })
    $exitItem.Add_Click({
        $launcherForm = $script:LauncherForm
        if($null -eq $launcherForm -or $launcherForm.IsDisposed) {
            return
        }
        $launcherForm.Tag = "Exit"
        if($script:trayIcon -and -not $script:trayIcon.IsDisposed) {
            $script:trayIcon.Visible = $false
        }
        $launcherForm.Close()
    })
    $script:trayIcon.ContextMenuStrip = $script:TrayMenu
}

# ============================================================
# STOP LAUNCHER RUNTIME RESOURCES
# ============================================================

function Stop-LauncherRuntimeResources {
    param($Form)
    if($script:LauncherRuntimeStopped) {
        return
    }
    $script:LauncherRuntimeStopped = $true
    Write-GaloreLog -Level "INFO" -Component "Shutdown" -Message "Launcher runtime cleanup started."
    if($null -eq $Form) {
        $Form = $script:LauncherForm
    }
    foreach($stopFunction in @(
            "Stop-GlobalHotkey"
            "Stop-ProgramStatusResources"
            "Stop-StartMenuResources"
            "Stop-DesktopResources"
            "Stop-HardwareMonitor"
            "Stop-GaloreMaintenance"
            "Stop-SplashResources"
            "Stop-GalorePostItResources"
        )
    ) {
        if(Get-Command -Name $stopFunction -CommandType Function -ErrorAction SilentlyContinue) {
            try {
                & $stopFunction
            } catch {
            }
        }
    }
    if("GaloreDropHelper.Exports" -as [type]) {
        try {
            [GaloreDropHelper.Exports]::DetachRecycleDrop()
        } catch {
        }
    }
    foreach($formStopFunction in @(
            "Stop-UIResources"
            "Stop-ProgramWindowResources"
        )
    ) {
        if(Get-Command -Name $formStopFunction -CommandType Function -ErrorAction SilentlyContinue) {
            try {
                & $formStopFunction -Form $Form
            } catch {
            }
        }
    }
    if($script:trayIcon) {
        try {
            $script:trayIcon.Visible = $false
            $script:trayIcon.ContextMenuStrip = $null
            $script:trayIcon.Icon = $null
            $script:trayIcon.Dispose()
        } catch {
        }
        $script:trayIcon = $null
    }
    if($script:TrayMenu) {
        try {
            $script:TrayMenu.Dispose()
        } catch {
        }
        $script:TrayMenu = $null
    }
    if($script:TrayOwnedIcon) {
        try {
            $script:TrayOwnedIcon.Dispose()
        } catch {
        }
        $script:TrayOwnedIcon = $null
    }
    $script:LauncherForm = $null
    Write-GaloreLog -Level "INFO" -Component "Shutdown" -Message "Launcher runtime cleanup completed."
}

# ============================================================
# SAVE SETTINGS WHEN CLOSING
# ============================================================

function Register-LauncherClosingEvent {
    param($Form, $Checks)
    $checksToSave = $Checks
    $Form.Add_FormClosing({
        param($sender, $e)
        if($null -eq $sender -or $sender.IsDisposed) {
            return
        }
        if($sender.Tag -ne "Exit" -and (Get-GaloreTrayAutomation).KeepRunningOnClose) {
            $e.Cancel = $true
            Close-StartSearchWindowAnimated
            Hide-LauncherWindowAnimated -Form $sender -DurationMilliseconds 170
            $sender.ShowInTaskbar = $false
            return
        }
        Save-WindowSettings -Checks $checksToSave -Form $sender
        Stop-LauncherRuntimeResources -Form $sender
    }.GetNewClosure())
}
