# ============================================================
# LAUNCHER START MENU MODULE
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherStartMenu"
    LoadOrder = 180
    RequiresModules = @("LauncherDomain", "LauncherSearch", "ProgramWindowUI", "UI")
    RequiresFunctions = [ordered]@{
        "Get-SearchResults" = "LauncherSearch"
        "New-SearchBox" = "ProgramWindowUI"
        "New-SearchPanelUI" = "ProgramWindowUI"
        "New-SearchResultsPanel" = "ProgramWindowUI"
        "Restore-GaloreHeaderControlZOrder" = "ProgramWindowUI"
        "Get-ResourceIcon" = "UI"
        "New-WindowsStartButton" = "UI"
    }
    RequiresTypes = [ordered]@{
        "GaloreStartMenuRuntimeState" = "LauncherDomain"
    }
    RequiresVariables = @()
    RequiresFolders = @("Resources")
    RequiresFiles = @(
        "Resources\exe.png", "Resources\folder.png", "Resources\image.png", "Resources\shortcut.png"
    )
    ProvidesTypes = @()
}

# ============================================================
# EMBEDDED SEARCH STATE
# ============================================================

$script:GaloreStartMenuRuntime = [GaloreStartMenuRuntimeState]::new()

# ============================================================
# CLEAR SEARCH RESULT CONTROLS
# ============================================================

function Clear-StartSearchResults {
    $runtime = $script:GaloreStartMenuRuntime
    if($null -eq $runtime.SearchResults -or $runtime.SearchResults.IsDisposed) {
        return
    }
    foreach($resultControl in @($runtime.SearchResults.Controls)
    ) {
        $resultControl.Dispose()
    }
    $runtime.SearchResults.Controls.Clear()
}

# ============================================================
# SEARCH RESULT IMAGE
# ============================================================

function ConvertTo-SearchResultImage {
    param([System.Drawing.Image]$SourceImage)
    if($null -eq $SourceImage) {
        return $null
    }
    $canvas = New-Object System.Drawing.Bitmap(30, 30)
    $graphics = $null
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($canvas)
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $scale = [Math]::Min((28.0 / [double]$SourceImage.Width), (28.0 / [double]$SourceImage.Height))
        $drawWidth = [Math]::Max(1, [int][Math]::Round($SourceImage.Width * $scale))
        $drawHeight = [Math]::Max(1, [int][Math]::Round($SourceImage.Height * $scale))
        $graphics.DrawImage($SourceImage, [int]((30 - $drawWidth) / 2), [int]((30 - $drawHeight) / 2), $drawWidth, $drawHeight)
    } catch {
        $canvas.Dispose()
        return $null
    } finally {
        if($graphics) {
            $graphics.Dispose()
        }
    }
    return $canvas
}

function Get-SearchResultImage {
    param($Item)
    $sourceImage = $null
    try {
        if($Item.Type -eq "Image" -and (Test-Path -LiteralPath $Item.Path -PathType Leaf)) {
            $sourceImage = [System.Drawing.Image]::FromFile($Item.Path)
        } elseif($Item.Type -in @("EXE", "Shortcut") -and (Test-Path -LiteralPath $Item.Path -PathType Leaf)
        ) {
            $associatedIcon = [System.Drawing.Icon]::ExtractAssociatedIcon($Item.Path)
            if($associatedIcon) {
                try {
                    $sourceImage = $associatedIcon.ToBitmap()
                } finally {
                    $associatedIcon.Dispose()
                }
            }
        }
    } catch {
        $sourceImage = $null
    }
    if($null -eq $sourceImage) {
        switch($Item.Type) {
            "Folder" {
                $sourceImage = Get-ResourceIcon "folder.png"
            }
            "Shortcut" {
                $sourceImage = Get-ResourceIcon "shortcut.png"
            }
            "Image" {
                $sourceImage = Get-ResourceIcon "image.png"
            }
            default {
                $sourceImage = Get-ResourceIcon "exe.png"
            }
        }
    }
    if($null -eq $sourceImage) {
        return $null
    }
    try {
        return ConvertTo-SearchResultImage -SourceImage $sourceImage
    } finally {
        $sourceImage.Dispose()
    }
}

# ============================================================
# GET SEARCH PANEL TOP EDGE
# ============================================================

function Get-StartSearchPanelTop {
    $runtime = $script:GaloreStartMenuRuntime
    if($runtime.Form -and -not $runtime.Form.IsDisposed) {
        $programTitleBar = $runtime.Form.Controls["ProgramTitleBar"]
        if($programTitleBar -and -not $programTitleBar.IsDisposed) {
            return [int]$programTitleBar.Bottom
        }
    }
    if($runtime.SearchPanel -and -not $runtime.SearchPanel.IsDisposed -and $runtime.SearchPanel.Top -gt 0) {
        return [int]$runtime.SearchPanel.Top
    }
    return 40
}

# ============================================================
# POSITION WINDOWS SEARCH TOGGLE
# ============================================================

function Set-WindowsSearchToggleBounds {
    param([int]$PanelLeft, [bool]$Compact)
    $runtime = $script:GaloreStartMenuRuntime
    if($null -eq $runtime.WindowsButton -or $runtime.WindowsButton.IsDisposed) {
        return
    }
    if($Compact) {
        if($null -eq $runtime.WindowsButtonNormalBounds) {
            $runtime.WindowsButtonNormalBounds = New-Object System.Drawing.Rectangle($runtime.WindowsButton.Left, $runtime.WindowsButton.Top, $runtime.WindowsButton.Width, $runtime.WindowsButton.Height)
        }
        $panelTop = Get-StartSearchPanelTop
        $toggleSize = [Math]::Max(32, [int][Math]::Round($panelTop * 0.8))
        $toggleMargin = [Math]::Max(4, [int][Math]::Round($panelTop * 0.1))
        $runtime.WindowsButton.Bounds = New-Object System.Drawing.Rectangle([Math]::Max(0, ($PanelLeft - $toggleSize - $toggleMargin)), ($panelTop + $toggleMargin), $toggleSize, $toggleSize)
        $runtime.WindowsButton.BringToFront()
        return
    }
    if($null -ne $runtime.WindowsButtonNormalBounds) {
        $runtime.WindowsButton.Bounds = $runtime.WindowsButtonNormalBounds
        $runtime.WindowsButton.BringToFront()
    }
}

# ============================================================
# STOP SEARCH PANEL ANIMATION
# ============================================================

function Stop-StartSearchPanelAnimation {
    $runtime = $script:GaloreStartMenuRuntime
    if($null -eq $runtime.AnimationTimer) {
        return
    }
    $runtime.AnimationTimer.Stop()
    $runtime.AnimationTimer.Tag = $null
    $runtime.AnimationTimer.Dispose()
    $runtime.AnimationTimer = $null
}

# ============================================================
# SET SEARCH PANEL BOUNDS
# ============================================================

function Set-StartSearchPanelBounds {
    param([bool]$ShowPanel = $script:GaloreStartMenuRuntime.TargetVisible)
    $runtime = $script:GaloreStartMenuRuntime
    if($null -eq $runtime.Form -or $runtime.Form.IsDisposed -or $null -eq $runtime.SearchPanel -or $runtime.SearchPanel.IsDisposed) {
        return
    }
    $panelTop = Get-StartSearchPanelTop
    $panelLeft = if($ShowPanel) {
        [Math]::Max(0, ($runtime.Form.ClientSize.Width - $runtime.SearchPanel.Width))
    } else {
        $runtime.Form.ClientSize.Width
    }
    $runtime.SearchPanel.Location = New-Object System.Drawing.Point($panelLeft, $panelTop)
    $runtime.SearchPanel.Height = [Math]::Max(0, ($runtime.Form.ClientSize.Height - $panelTop))
}

# ============================================================
# SEARCH PANEL SLIDE ANIMATION
# ============================================================

function Start-SearchPanelSlideAnimation {
    param([bool]$ShowPanel, [int]$DurationMilliseconds = 180)
    $runtime = $script:GaloreStartMenuRuntime
    if($null -eq $runtime.Form -or $runtime.Form.IsDisposed -or $null -eq $runtime.SearchPanel -or $runtime.SearchPanel.IsDisposed) {
        return
    }
    Stop-StartSearchPanelAnimation
    $panel = $runtime.SearchPanel
    $form = $runtime.Form
    if($ShowPanel) {
        if(-not $panel.Visible) {
            Set-StartSearchPanelBounds -ShowPanel $false
            $panel.Visible = $true
        }
        $panel.BringToFront()
        Set-WindowsSearchToggleBounds -PanelLeft $panel.Left -Compact $true
        Restore-GaloreHeaderControlZOrder -Form $form
    }
    $targetLeft = if($ShowPanel) {
        [Math]::Max(0, ($form.ClientSize.Width - $panel.Width))
    } else {
        $form.ClientSize.Width
    }
    if($DurationMilliseconds -le 0 -or $panel.Left -eq $targetLeft) {
        Set-StartSearchPanelBounds -ShowPanel $ShowPanel
        $panel.Visible = $ShowPanel
        if($ShowPanel) {
            Set-WindowsSearchToggleBounds -PanelLeft $panel.Left -Compact $true
        } else {
            Set-WindowsSearchToggleBounds -PanelLeft $panel.Left -Compact $false
            $form.ActiveControl = $null
            $form.Focus() | Out-Null
        }
        return
    }
    $animationTimer = New-Object System.Windows.Forms.Timer
    $animationTimer.Interval = 15
    $animationTimer.Tag = [PSCustomObject]@{
        Panel = $panel
        Form = $form
        StartLeft = [int]$panel.Left
        ShowPanel = $ShowPanel
        DurationMilliseconds = $DurationMilliseconds
        Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        Runtime = $runtime
    }
    $animationTimer.Add_Tick({
        $timer = $this
        $state = $timer.Tag
        if($null -eq $state -or $null -eq $state.Panel -or $state.Panel.IsDisposed -or $null -eq $state.Form -or $state.Form.IsDisposed) {
            $runtime = if($null -ne $state) { $state.Runtime } else { $null }
            $timer.Stop()
            $timer.Tag = $null
            $timer.Dispose()
            if($null -ne $runtime -and $runtime.AnimationTimer -eq $timer) {
                $runtime.AnimationTimer = $null
            }
            return
        }
        $targetLeft = if($state.ShowPanel) {
            [Math]::Max(0, ($state.Form.ClientSize.Width - $state.Panel.Width))
        } else {
            $state.Form.ClientSize.Width
        }
        $progress = [Math]::Min(1.0, ($state.Stopwatch.Elapsed.TotalMilliseconds / $state.DurationMilliseconds))
        $easedProgress = $progress * $progress * (3 - (2 * $progress))
        $currentLeft = $state.StartLeft + (($targetLeft - $state.StartLeft) * $easedProgress)
        $panelTop = Get-StartSearchPanelTop
        $state.Panel.Location = New-Object System.Drawing.Point([int][Math]::Round($currentLeft), $panelTop)
        $state.Panel.Height = [Math]::Max(0, ($state.Form.ClientSize.Height - $panelTop))
        Set-WindowsSearchToggleBounds -PanelLeft $state.Panel.Left -Compact $true
        if($progress -lt 1) {
            return
        }
        $state.Panel.Location = New-Object System.Drawing.Point($targetLeft, $panelTop)
        $state.Panel.Visible = $state.ShowPanel
        $timer.Stop()
        $timer.Tag = $null
        if($state.Runtime.AnimationTimer -eq $timer) {
            $state.Runtime.AnimationTimer = $null
        }
        $timer.Dispose()
        if($state.ShowPanel) {
            Set-WindowsSearchToggleBounds -PanelLeft $state.Panel.Left -Compact $true
            if($state.Runtime.Form -and -not $state.Runtime.Form.IsDisposed -and $state.Runtime.SearchBox -and -not $state.Runtime.SearchBox.IsDisposed) {
                $state.Runtime.Form.Activate()
                $state.Runtime.SearchBox.Select()
                $state.Runtime.SearchBox.Focus() | Out-Null
            }
        } else {
            Set-WindowsSearchToggleBounds -PanelLeft $state.Panel.Left -Compact $false
            $state.Form.ActiveControl = $null
            $state.Form.Focus() | Out-Null
        }
    })
    $runtime.AnimationTimer = $animationTimer
    $animationTimer.Start()
}

# ============================================================
# SHOW SEARCH PANEL SMOOTHLY
# ============================================================

function Show-StartSearchWindowAnimated {
    param([System.Windows.Forms.Panel]$Panel = $script:GaloreStartMenuRuntime.SearchPanel, [int]$DurationMilliseconds = 180)
    $runtime = $script:GaloreStartMenuRuntime
    if($null -eq $Panel -or $Panel.IsDisposed) {
        return
    }
    $runtime.TargetVisible = $true
    Start-SearchPanelSlideAnimation -ShowPanel $true -DurationMilliseconds $DurationMilliseconds
    if($runtime.SearchBox -and -not $runtime.SearchBox.IsDisposed) {
        if($runtime.Form -and -not $runtime.Form.IsDisposed) {
            $runtime.Form.Activate()
        }
        $runtime.SearchBox.Select()
        $runtime.SearchBox.Focus() | Out-Null
    }
}

# ============================================================
# HIDE SEARCH PANEL SMOOTHLY
# ============================================================

function Close-StartSearchWindowAnimated {
    param([System.Windows.Forms.Panel]$Panel = $script:GaloreStartMenuRuntime.SearchPanel, [int]$DurationMilliseconds = 160)
    $runtime = $script:GaloreStartMenuRuntime
    $wasTargetVisible = $runtime.TargetVisible
    $runtime.TargetVisible = $false
    if($null -eq $Panel -or $Panel.IsDisposed) {
        return
    }
    if(-not $wasTargetVisible -and -not $Panel.Visible) {
        return
    }
    Start-SearchPanelSlideAnimation -ShowPanel $false -DurationMilliseconds $DurationMilliseconds
}

# ============================================================
# TOGGLE START SEARCH PANEL
# ============================================================

function Show-StartSearchWindow {
    param([System.Windows.Forms.Form]$Form)
    $runtime = $script:GaloreStartMenuRuntime
    if($runtime.SearchPanel -and -not $runtime.SearchPanel.IsDisposed) {
        if($runtime.TargetVisible) {
            Close-StartSearchWindowAnimated
        } else {
            Show-StartSearchWindowAnimated
        }
        return
    }
    $searchPanel = New-SearchPanelUI -Form $Form
    $runtime.SearchPanel = $searchPanel
    $searchBox = New-SearchBox -SearchPanel $searchPanel
    $searchResults = New-SearchResultsPanel -SearchPanel $searchPanel
    $runtime.SearchBox = $searchBox
    $runtime.SearchResults = $searchResults
    $runtime.SearchDelayTimer = New-Object System.Windows.Forms.Timer
    $runtime.SearchDelayTimer.Interval = 250
    $runtime.SearchDelayTimer.Tag = $runtime
    $runtime.PendingSearch = $null
    $runtime.SearchBox.Add_KeyDown({
        param($sender, $e)
        if($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
            $e.SuppressKeyPress = $true
            Close-StartSearchWindowAnimated
        }
    })
    $runtime.SearchBox.Add_TextChanged({
        if($null -eq $runtime -or $null -eq $runtime.SearchDelayTimer) {
            return
        }
        $runtime.PendingSearch = $this.Text
        $runtime.SearchDelayTimer.Stop()
        $runtime.SearchDelayTimer.Start()
    }.GetNewClosure())
    $runtime.SearchDelayTimer.Add_Tick({
        $runtime = $this.Tag
        if($null -eq $runtime) { return }
        $this.Stop()
        Clear-StartSearchResults
        $query = [string]$runtime.PendingSearch
        $query = $query.Trim()
        if([string]::IsNullOrWhiteSpace($query) -or $query.Length -lt 2) {
            return
        }
        $SearchResults = Get-SearchResults $query
        foreach($item in $SearchResults) {
            $resultButton = New-Object System.Windows.Forms.Button
            $resultButton.ImageAlign = [System.Drawing.ContentAlignment]::MiddleLeft
            $resultButton.TextImageRelation = [System.Windows.Forms.TextImageRelation]::ImageBeforeText
            $resultButton.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
            $resultButton.Image = Get-SearchResultImage -Item $item
            $resultButton.Width = 320
            $resultButton.Height = 40
            if($item.Path -match "\.(exe|lnk|url)$") {
                $displayName = [System.IO.Path]::GetFileNameWithoutExtension($item.Name)
                $resultButton.Text = $displayName + ".exe"
            } else {
                $resultButton.Text = $item.Name
            }
            $resultButton.Tag = $item
            $resultButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
            $resultButton.FlatAppearance.BorderSize = 0
            $resultButton.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 40)
            $resultButton.ForeColor = [System.Drawing.Color]::White
            $resultButton.Add_Disposed({
                $ownedImage = $this.Image
                if($ownedImage) {
                    $this.Image = $null
                    $ownedImage.Dispose()
                }
            })
            $resultButton.Add_Click({
                $data = $this.Tag
                if($data.Type -eq "Application") {
                    Start-Process explorer.exe $data.Path
                    return
                }
                $path = $data.Path
                if(Test-Path -LiteralPath $path) {
                    if($path.EndsWith(".exe")) {
                        Start-Process $path
                    } else {
                        Invoke-Item $path
                    }
                } else {
                    $fixedPath = $path.Replace("\Utilisateurs\", "\Users\")
                    if(Test-Path -LiteralPath $fixedPath) {
                        Invoke-Item $fixedPath
                    }
                }
            })
            if($runtime.SearchResults -and -not $runtime.SearchResults.IsDisposed) {
                $runtime.SearchResults.Controls.Add($resultButton)
            } else {
                $resultButton.Dispose()
            }
        }
    })
    Show-StartSearchWindowAnimated
}

# ============================================================
# INITIALIZE START MENU
# ============================================================

function Initialize-StartMenu {
    param([System.Windows.Forms.Form]$Form)
    $runtime = $script:GaloreStartMenuRuntime
    if($runtime.Form -eq $Form -and $runtime.WindowsButton -and -not $runtime.WindowsButton.IsDisposed) {
        return
    }
    if($runtime.Form -and $runtime.Form -ne $Form) {
        Stop-StartMenuResources
    }
    if($runtime.Form -ne $Form) {
        $runtime.Form = $Form
        $runtime.Form.Add_Resize({
            $runtime = $script:GaloreStartMenuRuntime
            if($runtime.SearchPanel -and -not $runtime.SearchPanel.IsDisposed) {
                Stop-StartSearchPanelAnimation
                Set-StartSearchPanelBounds -ShowPanel $runtime.TargetVisible
                $runtime.SearchPanel.Visible = $runtime.TargetVisible
                Set-WindowsSearchToggleBounds -PanelLeft $runtime.SearchPanel.Left -Compact $runtime.TargetVisible
            }
        })
    }
    $WindowsUI = New-WindowsStartButton
    $runtime.WindowsButton = $WindowsUI.Button
    $runtime.WindowsButton.Name = "WindowsSearchToggle"
    $runtime.WindowsButton.AccessibleName = "WindowsSearchToggle"
    $runtime.WindowsTimer = $WindowsUI.Timer
    $Form.Controls.Add($runtime.WindowsButton)
    $runtime.WindowsButton.Add_Click({
        Show-StartSearchWindow -Form $script:GaloreStartMenuRuntime.Form
    })
}

# ============================================================
# STOP START MENU RESOURCES
# ============================================================

function Stop-StartMenuResources {
    $runtime = $script:GaloreStartMenuRuntime
    Stop-StartSearchPanelAnimation
    $runtime.TargetVisible = $false
    if($runtime.SearchDelayTimer) {
        $runtime.SearchDelayTimer.Stop()
        $runtime.SearchDelayTimer.Tag = $null
        $runtime.SearchDelayTimer.Dispose()
        $runtime.SearchDelayTimer = $null
    }
    Clear-StartSearchResults
    if($runtime.SearchPanel -and -not $runtime.SearchPanel.IsDisposed) {
        $runtime.SearchPanel.Dispose()
    }
    if($runtime.WindowsTimer) {
        $runtime.WindowsTimer.Stop()
        $runtime.WindowsTimer.Tag = $null
        $runtime.WindowsTimer.Dispose()
        $runtime.WindowsTimer = $null
    }
    if($runtime.WindowsButton -and -not $runtime.WindowsButton.IsDisposed) {
        $runtime.WindowsButton.Dispose()
    }
    $runtime.SearchBox = $null
    $runtime.SearchResults = $null
    $runtime.PendingSearch = $null
    $runtime.SearchPanel = $null
    $runtime.WindowsButtonNormalBounds = $null
    $runtime.WindowsButton = $null
    $runtime.Form = $null
}
