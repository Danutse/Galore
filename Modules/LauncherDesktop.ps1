# ============================================================
# LAUNCHER DESKTOP MODULE
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherDesktop"
    LoadOrder = 80
    RequiresModules = @("LauncherLogging", "LauncherStartup", "LauncherRecycleHelper", "ProgramWindowUI", "UI")
    RequiresFunctions = [ordered]@{
        "Write-LauncherDiagnostic" = "LauncherLogging"
        "Test-ProgramStartup" = "LauncherStartup"
        "Initialize-WindowDragging" = "ProgramWindowUI"
        "Get-ResourceIcon" = "UI"
        "New-TaskbarFolderButton" = "UI"
        "New-WindowButton" = "UI"
    }
    RequiresTypes = [ordered]@{
        "GaloreDropHelper.Exports" = "LauncherRecycleHelper"
    }
    RequiresVariables = @("AppRoot")
    RequiresFolders = @("Resources")
    RequiresFiles = @(
        "Resources\close.png", "Resources\downloads.png", "Resources\games.png", "Resources\images.png", "Resources\maximize.png", "Resources\minimize.png", "Resources\misc.png", "Resources\notes.png", "Resources\programs.png", "Resources\recyclebin.png", "Resources\thispc.png"
    )
    ProvidesTypes = @()
}

# ==========================
# THIS PC BUTTON
# ==========================

function Add-ThisPCButton {
    param($Parent)
    $thisPCButton = New-Object System.Windows.Forms.Button
    $thisPCButton.Width = 40
    $thisPCButton.Height = 40
    $thisPCButton.Location = New-Object System.Drawing.Point(0, 0)
    $thisPCButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $thisPCButton.FlatAppearance.BorderSize = 0
    $thisPCButton.BackColor = [System.Drawing.Color]::Transparent
    $thisPCButton.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(20, 255, 255, 255)
    $thisPCButton.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(100, 255, 255, 255)
    $thisPCImage = Get-ResourceIcon "thispc.png"
    if($thisPCImage) {
        try {
            $thisPCButton.Image = New-Object System.Drawing.Bitmap($thisPCImage, 26, 26)
        } finally {
            $thisPCImage.Dispose()
        }
    }
    $thisPCButton.Add_Disposed({
        $ownedImage = $this.Image
        if($ownedImage) {
            $this.Image = $null
            $ownedImage.Dispose()
        }
    })
    $thisPCButton.Add_Click({
        Start-Process "explorer.exe" "shell:MyComputerFolder"
    })
    $Parent.Controls.Add($thisPCButton)
}

# ==========================
# RECYCLE BIN BUTTON
# ==========================

function Add-RecycleBinButton {
    param($Parent)
    $recycleBinButton = New-Object System.Windows.Forms.Button
    $recycleBinButton.Width = 40
    $recycleBinButton.Height = 40
    $recycleBinButton.Location = New-Object System.Drawing.Point(40, 0)
    $recycleBinButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $recycleBinButton.FlatAppearance.BorderSize = 0
    $recycleBinButton.BackColor = [System.Drawing.Color]::Transparent
    $recycleBinButton.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(20, 255, 255, 255)
    $recycleBinButton.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(100, 255, 255, 255)

    # ==========================
    # LOAD RECYCLE BIN ICON
    # ==========================

    $recycleBinImagePath = Get-GaloreResourcePath "recyclebin.png"
    if(Test-Path $recycleBinImagePath) {
        $recycleSource = [System.Drawing.Bitmap]::FromFile($recycleBinImagePath)
        $recycleBinButton.Image = New-Object System.Drawing.Bitmap($recycleSource, 26, 26)
        $recycleSource.Dispose()
    }
    $recycleBinButton.Add_Disposed({
        $ownedImage = $this.Image
        if($ownedImage) {
            $this.Image = $null
            $ownedImage.Dispose()
        }
    })

    # ==========================
    # OPEN RECYCLE BIN
    # ==========================

    $recycleBinButton.Add_Click({
        Start-Process explorer.exe "shell:RecycleBinFolder"
    })

    # ==========================
    # ENABLE FILE DROP
    # ==========================

    $recycleBinButton.AllowDrop = $true
    $recycleBinButton.Add_DragEnter({
        param($sender, $e)
        if($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
            $e.Effect = [System.Windows.Forms.DragDropEffects]::Copy
        } else {
            $e.Effect = [System.Windows.Forms.DragDropEffects]::None
        }
    })
    $recycleBinButton.Add_DragOver({
        param($sender, $e)
        $e.Effect = [System.Windows.Forms.DragDropEffects]::Copy
    })
    $recycleBinButton.Add_DragDrop({
        param($sender, $e)
        try {
            $files = $e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)
            if($null -eq $files) {
                return
            }
            $shell = New-Object -ComObject Shell.Application
            foreach($file in $files) {
                try {
                    $item = $shell.Namespace((Split-Path $file)).ParseName((Split-Path $file -Leaf))
                    if($item) {
                        $item.InvokeVerb("delete")
                    }
                } catch {
                    Write-LauncherDiagnostic -Exception $_ -Context "Failed to recycle dropped item '$file'."
                }
            }
        } catch {
            Write-LauncherDiagnostic -Exception $_ -Context "Recycle-bin drop handling failed."
        }
    })
    return $recycleBinButton
}

# ============================================================
# PORTABLE TASKBAR FOLDER
# ============================================================

function Resolve-GaloreTaskbarFolder {
    param([string]$FolderName)
    if([string]::IsNullOrWhiteSpace($FolderName)) {
        throw "Taskbar folder name is empty."
    }
    $legacyFolderPath = Join-Path "D:\" $FolderName
    if(Test-Path -LiteralPath $legacyFolderPath -PathType Container) {
        return $legacyFolderPath
    }
    $folderPath = Join-Path $AppRoot $FolderName
    if(-not (Test-Path -LiteralPath $folderPath -PathType Container)) {
        New-Item -ItemType Directory -Path $folderPath -Force -ErrorAction Stop | Out-Null
    }
    return $folderPath
}

# ============================================================
# TASKBAR FOLDER BUTTONS
# ============================================================

function New-TaskbarFolderButtons {
    param($Parent)
    $DownloadsFolder = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)) "Downloads"
    $null = New-TaskbarFolderButton -Parent $Parent -X 85 -Icon "downloads.png" -Folder $DownloadsFolder -Tooltip "Downloads"
    $script:GamesFolder = Resolve-GaloreTaskbarFolder "GameShortcut"
    $null = New-TaskbarFolderButton -Parent $Parent -X 130 -Icon "games.png" -Folder $GamesFolder -Tooltip "Game Shortcut"
    $script:ProgramsFolder = Resolve-GaloreTaskbarFolder "ProgramShortcut"
    $null = New-TaskbarFolderButton -Parent $Parent -X 175 -Icon "programs.png" -Folder $ProgramsFolder -Tooltip "Program Shortcut"
    $ImageFolder = Resolve-GaloreTaskbarFolder "Image"
    $null = New-TaskbarFolderButton -Parent $Parent -X 220 -Icon "images.png" -Folder $ImageFolder -Tooltip "Image"
    $NotesFolder = Resolve-GaloreTaskbarFolder "Notes"
    $null = New-TaskbarFolderButton -Parent $Parent -X 265 -Icon "notes.png" -Folder $NotesFolder -Tooltip "Notes"
    $MiscFolder = Resolve-GaloreTaskbarFolder "Misc"
    $null = New-TaskbarFolderButton -Parent $Parent -X 310 -Icon "misc.png" -Folder $MiscFolder -Tooltip "Misc"
}

# ==========================
# DESKTOP SHORTCUT DIALOG
# ==========================

function Show-DesktopShortcutDialog {
    param([string]$ShortcutPath)
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "Galore Launcher"
    $dialog.StartPosition = "CenterScreen"
    $dialog.ClientSize = New-Object System.Drawing.Size(400, 180)
    $dialog.FormBorderStyle = "FixedDialog"
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $false
    $dialog.ControlBox = $false
    $dialog.BackColor = [System.Drawing.Color]::FromArgb(25, 25, 25)
    $dialog.ForeColor = [System.Drawing.Color]::White
    $promptLabel = New-Object System.Windows.Forms.Label
    $promptLabel.AutoSize = $false
    $promptLabel.Width = 360
    $promptLabel.Height = 24
    $promptLabel.Left = 20
    $promptLabel.Top = 18
    $promptLabel.TextAlign = "MiddleCenter"
    $promptLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $promptLabel.Text = "Where should this shortcut go?"
    $dialog.Controls.Add($promptLabel)
    $nameLabel = New-Object System.Windows.Forms.Label
    $nameLabel.AutoSize = $false
    $nameLabel.AutoEllipsis = $true
    $nameLabel.Width = 360
    $nameLabel.Height = 42
    $nameLabel.Left = 20
    $nameLabel.Top = 48
    $nameLabel.TextAlign = "MiddleCenter"
    $nameLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $nameLabel.Text = [System.IO.Path]::GetFileNameWithoutExtension($ShortcutPath)
    $dialog.Controls.Add($nameLabel)
    $gamesButton = New-Object System.Windows.Forms.Button
    $gamesButton.Text = "Games"
    $gamesButton.Width = 170
    $gamesButton.Height = 35
    $gamesButton.Left = 20
    $gamesButton.Top = 120
    $programsButton = New-Object System.Windows.Forms.Button
    $programsButton.Text = "Programs"
    $programsButton.Width = 170
    $programsButton.Height = 35
    $programsButton.Left = 210
    $programsButton.Top = 120
    $dialog.Tag = $null
    $gamesButton.Add_Click({
        $dialog.Tag = "Games"
        $dialog.Close()
    })
    $programsButton.Add_Click({
        $dialog.Tag = "Programs"
        $dialog.Close()
    })
    $dialog.Controls.Add($gamesButton)
    $dialog.Controls.Add($programsButton)
    $dialog.AcceptButton = $gamesButton
    $dialog.Add_FormClosing({
        if($dialog.Tag -eq $null) {
            $_.Cancel = $true
        }
    })
    try {
        $dialog.ShowDialog() | Out-Null
        return $dialog.Tag
    } finally {
        $dialog.Dispose()
    }
}

# ==========================
# DESKTOP SHORTCUT WATCHER
# ==========================

function Initialize-DesktopShortcutWatcher {
    $script:DesktopPath = Join-Path $env:USERPROFILE "OneDrive\Desktop"
    if (-not (Test-Path $script:DesktopPath)) {
        $script:DesktopPath = [Environment]::GetFolderPath("Desktop")
    }
    $script:DesktopShortcutDialogOpen = $false
    $script:DesktopShortcutTimer = New-Object System.Windows.Forms.Timer
    $script:DesktopShortcutTimer.Interval = 1000
    $script:DesktopShortcutTimer.Add_Tick({
        if ($script:DesktopShortcutDialogOpen) {
            return
        }
        $DesktopFiles = Get-ChildItem -Path $script:DesktopPath -Force -ErrorAction SilentlyContinue
        $Shortcut = $DesktopFiles | Where-Object {
            $_.Extension -eq ".lnk" -or $_.Extension -eq ".url"
        } | Select-Object -First 1
        if ($null -eq $Shortcut) {
            return
        }
        $ShortcutPath = $Shortcut.FullName
        $script:DesktopShortcutDialogOpen = $true
        $script:DesktopShortcutTimer.Stop()
        try {
            $result = Show-DesktopShortcutDialog -ShortcutPath $ShortcutPath
            switch ($result) {
                "Games" {
                    $DestinationFolder = $GamesFolder
                }
                "Programs" {
                    $DestinationFolder = $ProgramsFolder
                }
                default {
                    return
                }
            }
            if (-not (Test-Path $ShortcutPath)) {
                return
            }
            for ($attempt = 1; $attempt -le 5; $attempt++) {
                try {
                    Move-Item -LiteralPath $ShortcutPath -Destination $DestinationFolder -Force -ErrorAction Stop
                    break
                } catch {
                    if ($attempt -eq 5) {
                        throw
                    }
                    Start-Sleep -Milliseconds 250
                }
            }
        } finally {
            $script:DesktopShortcutDialogOpen = $false
            $script:DesktopShortcutTimer.Start()
        }
    })
    $script:DesktopShortcutTimer.Start()
}

# ==========================
# STOP DESKTOP RESOURCES
# ==========================

function Stop-DesktopResources {
    if($script:DesktopShortcutTimer) {
        $script:DesktopShortcutTimer.Stop()
        $script:DesktopShortcutTimer.Dispose()
        $script:DesktopShortcutTimer = $null
    }
    $script:DesktopShortcutDialogOpen = $false
}

# ==========================
# MINIMIZE BUTTON
# ==========================

function New-MinimizeButton {
    $button = New-WindowButton -IconName "minimize.png"
    return $button
}

# ==========================
# MAXIMIZE BUTTON
# ==========================

function New-MaximizeButton {
    $button = New-WindowButton -IconName "maximize.png"
    return $button
}

# ==========================
# CLOSE BUTTON
# ==========================

function New-CloseButton {
    $button = New-WindowButton -IconName "close.png"
    return $button
}

# ============================================================
# START WITH WINDOWS TOGGLE
# ============================================================

function New-StartupToggle {
    $startupToggle = New-Object System.Windows.Forms.CheckBox
    $startupToggle.Text = "Launches with Windows"
    $startupToggle.AutoSize = $true
    $startupToggle.Width = 250
    $startupToggle.Checked = Test-ProgramStartup
    $startupToggle.ForeColor = [System.Drawing.Color]::White
    $startupToggle.BackColor = [System.Drawing.Color]::Transparent
    $startupToggle.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $startupToggle.Location = New-Object System.Drawing.Point(7, 525)
    return $startupToggle
}

# ============================================================
# DESKTOP INITIALIZATION
# ============================================================

function Initialize-DesktopButtons {
    param([System.Windows.Forms.Form]$Form, [System.Windows.Forms.Control]$TitleBar)
    # --------------------------
    # THIS PC
    # --------------------------
    $null = Add-ThisPCButton -Parent $TitleBar
    # --------------------------
    # RECYCLE BIN
    # --------------------------
    $recycleBinButton = Add-RecycleBinButton -Parent $TitleBar
    $TitleBar.Controls.Add($recycleBinButton)
    $null = $recycleBinButton.Handle
    [GaloreDropHelper.Exports]::AttachRecycleDrop($recycleBinButton.Handle)
    # --------------------------
    # TASKBAR FOLDERS
    # --------------------------
    $null = New-TaskbarFolderButtons -Parent $TitleBar
    # --------------------------
    # DESKTOP WATCHER
    # --------------------------
    Initialize-DesktopShortcutWatcher
    # --------------------------
    # WINDOW DRAGGING
    # --------------------------
    Initialize-WindowDragging -Form $Form -TitleBar $TitleBar
}
