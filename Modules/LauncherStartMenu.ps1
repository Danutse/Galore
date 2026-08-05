# ============================================================
# LAUNCHER START MENU MODULE
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherStartMenu"
    LoadOrder = 180
    RequiresModules = @("LauncherSearch", "ProgramWindowUI", "UI")
    RequiresFunctions = [ordered]@{
        "Get-SearchResults" = "LauncherSearch"
        "New-SearchBox" = "ProgramWindowUI"
        "New-SearchPanelUI" = "ProgramWindowUI"
        "New-SearchResultsPanel" = "ProgramWindowUI"
        "Restore-GaloreHeaderControlZOrder" = "ProgramWindowUI"
        "Get-ResourceIcon" = "UI"
        "New-WindowsStartButton" = "UI"
    }
    RequiresTypes = [ordered]@{}
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

$script:StartSearchPanel = $null
$script:StartMenuForm = $null
$script:SearchPanelAnimationTimer = $null
$script:SearchPanelTargetVisible = $false
$script:SearchDelayTimer = $null
$script:PendingSearch = $null
$script:StartSearchBox = $null
$script:StartSearchResults = $null
$script:WindowsButtonNormalBounds = $null

# ============================================================
# CLEAR SEARCH RESULT CONTROLS
# ============================================================

function Clear-StartSearchResults {
    if($null -eq $script:StartSearchResults -or $script:StartSearchResults.IsDisposed) {
        return
    }
    foreach($resultControl in @($script:StartSearchResults.Controls)
    ) {
        $resultControl.Dispose()
    }
    $script:StartSearchResults.Controls.Clear()
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
    if($script:StartMenuForm -and -not $script:StartMenuForm.IsDisposed) {
        $programTitleBar = $script:StartMenuForm.Controls["ProgramTitleBar"]
        if($programTitleBar -and -not $programTitleBar.IsDisposed) {
            return [int]$programTitleBar.Bottom
        }
    }
    if($script:StartSearchPanel -and -not $script:StartSearchPanel.IsDisposed -and $script:StartSearchPanel.Top -gt 0) {
        return [int]$script:StartSearchPanel.Top
    }
    return 40
}

# ============================================================
# POSITION WINDOWS SEARCH TOGGLE
# ============================================================

function Set-WindowsSearchToggleBounds {
    param([int]$PanelLeft, [bool]$Compact)
    if($null -eq $script:WindowsButton -or $script:WindowsButton.IsDisposed) {
        return
    }
    if($Compact) {
        if($null -eq $script:WindowsButtonNormalBounds) {
            $script:WindowsButtonNormalBounds = New-Object System.Drawing.Rectangle($script:WindowsButton.Left, $script:WindowsButton.Top, $script:WindowsButton.Width, $script:WindowsButton.Height)
        }
        $panelTop = Get-StartSearchPanelTop
        $toggleSize = [Math]::Max(32, [int][Math]::Round($panelTop * 0.8))
        $toggleMargin = [Math]::Max(4, [int][Math]::Round($panelTop * 0.1))
        $script:WindowsButton.Bounds = New-Object System.Drawing.Rectangle([Math]::Max(0, ($PanelLeft - $toggleSize - $toggleMargin)), ($panelTop + $toggleMargin), $toggleSize, $toggleSize)
        $script:WindowsButton.BringToFront()
        return
    }
    if($null -ne $script:WindowsButtonNormalBounds) {
        $script:WindowsButton.Bounds = $script:WindowsButtonNormalBounds
        $script:WindowsButton.BringToFront()
    }
}

# ============================================================
# STOP SEARCH PANEL ANIMATION
# ============================================================

function Stop-StartSearchPanelAnimation {
    if($null -eq $script:SearchPanelAnimationTimer) {
        return
    }
    $script:SearchPanelAnimationTimer.Stop()
    $script:SearchPanelAnimationTimer.Tag = $null
    $script:SearchPanelAnimationTimer.Dispose()
    $script:SearchPanelAnimationTimer = $null
}

# ============================================================
# SET SEARCH PANEL BOUNDS
# ============================================================

function Set-StartSearchPanelBounds {
    param([bool]$ShowPanel = $script:SearchPanelTargetVisible)
    if($null -eq $script:StartMenuForm -or $script:StartMenuForm.IsDisposed -or $null -eq $script:StartSearchPanel -or $script:StartSearchPanel.IsDisposed) {
        return
    }
    $panelTop = Get-StartSearchPanelTop
    $panelLeft = if($ShowPanel) {
        [Math]::Max(0, ($script:StartMenuForm.ClientSize.Width - $script:StartSearchPanel.Width))
    } else {
        $script:StartMenuForm.ClientSize.Width
    }
    $script:StartSearchPanel.Location = New-Object System.Drawing.Point($panelLeft, $panelTop)
    $script:StartSearchPanel.Height = [Math]::Max(0, ($script:StartMenuForm.ClientSize.Height - $panelTop))
}

# ============================================================
# SEARCH PANEL SLIDE ANIMATION
# ============================================================

function Start-SearchPanelSlideAnimation {
    param([bool]$ShowPanel, [int]$DurationMilliseconds = 180)
    if($null -eq $script:StartMenuForm -or $script:StartMenuForm.IsDisposed -or $null -eq $script:StartSearchPanel -or $script:StartSearchPanel.IsDisposed) {
        return
    }
    Stop-StartSearchPanelAnimation
    $panel = $script:StartSearchPanel
    $form = $script:StartMenuForm
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
    }
    $animationTimer.Add_Tick({
        $timer = $this
        $state = $timer.Tag
        if($null -eq $state -or $null -eq $state.Panel -or $state.Panel.IsDisposed -or $null -eq $state.Form -or $state.Form.IsDisposed) {
            $timer.Stop()
            $timer.Tag = $null
            $timer.Dispose()
            if($script:SearchPanelAnimationTimer -eq $timer) {
                $script:SearchPanelAnimationTimer = $null
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
        if($script:SearchPanelAnimationTimer -eq $timer) {
            $script:SearchPanelAnimationTimer = $null
        }
        $timer.Dispose()
        if($state.ShowPanel) {
            Set-WindowsSearchToggleBounds -PanelLeft $state.Panel.Left -Compact $true
            if($script:StartMenuForm -and -not $script:StartMenuForm.IsDisposed -and $script:StartSearchBox -and -not $script:StartSearchBox.IsDisposed) {
                $script:StartMenuForm.Activate()
                $script:StartSearchBox.Select()
                $script:StartSearchBox.Focus() | Out-Null
            }
        } else {
            Set-WindowsSearchToggleBounds -PanelLeft $state.Panel.Left -Compact $false
            $state.Form.ActiveControl = $null
            $state.Form.Focus() | Out-Null
        }
    })
    $script:SearchPanelAnimationTimer = $animationTimer
    $animationTimer.Start()
}

# ============================================================
# SHOW SEARCH PANEL SMOOTHLY
# ============================================================

function Show-StartSearchWindowAnimated {
    param([System.Windows.Forms.Panel]$Panel = $script:StartSearchPanel, [int]$DurationMilliseconds = 180)
    if($null -eq $Panel -or $Panel.IsDisposed) {
        return
    }
    $script:SearchPanelTargetVisible = $true
    Start-SearchPanelSlideAnimation -ShowPanel $true -DurationMilliseconds $DurationMilliseconds
    if($script:StartSearchBox -and -not $script:StartSearchBox.IsDisposed) {
        if($script:StartMenuForm -and -not $script:StartMenuForm.IsDisposed) {
            $script:StartMenuForm.Activate()
        }
        $script:StartSearchBox.Select()
        $script:StartSearchBox.Focus() | Out-Null
    }
}

# ============================================================
# HIDE SEARCH PANEL SMOOTHLY
# ============================================================

function Close-StartSearchWindowAnimated {
    param([System.Windows.Forms.Panel]$Panel = $script:StartSearchPanel, [int]$DurationMilliseconds = 160)
    $wasTargetVisible = $script:SearchPanelTargetVisible
    $script:SearchPanelTargetVisible = $false
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
    if($script:StartSearchPanel -and -not $script:StartSearchPanel.IsDisposed) {
        if($script:SearchPanelTargetVisible) {
            Close-StartSearchWindowAnimated
        } else {
            Show-StartSearchWindowAnimated
        }
        return
    }
    $searchPanel = New-SearchPanelUI -Form $Form
    $script:StartSearchPanel = $searchPanel
    $searchBox = New-SearchBox -SearchPanel $searchPanel
    $searchResults = New-SearchResultsPanel -SearchPanel $searchPanel
    $script:StartSearchBox = $searchBox
    $script:StartSearchResults = $searchResults
    $script:SearchDelayTimer = New-Object System.Windows.Forms.Timer
    $script:SearchDelayTimer.Interval = 250
    $script:PendingSearch = $null
    $script:StartSearchBox.Add_KeyDown({
        param($sender, $e)
        if($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
            $e.SuppressKeyPress = $true
            Close-StartSearchWindowAnimated
        }
    })
    $script:StartSearchBox.Add_TextChanged({
        if($null -eq $script:SearchDelayTimer) {
            return
        }
        $script:PendingSearch = $script:StartSearchBox.Text
        $script:SearchDelayTimer.Stop()
        $script:SearchDelayTimer.Start()
    })
    $script:SearchDelayTimer.Add_Tick({
        $script:SearchDelayTimer.Stop()
        Clear-StartSearchResults
        $query = [string]$script:PendingSearch
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
            $script:StartSearchResults.Controls.Add($resultButton)
        }
    })
    Show-StartSearchWindowAnimated
}

# ============================================================
# INITIALIZE START MENU
# ============================================================

function Initialize-StartMenu {
    param([System.Windows.Forms.Form]$Form)
    if($script:StartMenuForm -ne $Form) {
        $script:StartMenuForm = $Form
        $script:StartMenuForm.Add_Resize({
            if($script:StartSearchPanel -and -not $script:StartSearchPanel.IsDisposed) {
                Stop-StartSearchPanelAnimation
                Set-StartSearchPanelBounds -ShowPanel $script:SearchPanelTargetVisible
                $script:StartSearchPanel.Visible = $script:SearchPanelTargetVisible
                Set-WindowsSearchToggleBounds -PanelLeft $script:StartSearchPanel.Left -Compact $script:SearchPanelTargetVisible
            }
        })
    }
    $WindowsUI = New-WindowsStartButton
    $script:WindowsButton = $WindowsUI.Button
    $script:WindowsButton.Name = "WindowsSearchToggle"
    $script:WindowsButton.AccessibleName = "WindowsSearchToggle"
    $script:WindowsTimer = $WindowsUI.Timer
    $Form.Controls.Add($script:WindowsButton)
    $script:WindowsButton.Add_Click({
        Show-StartSearchWindow -Form $script:StartMenuForm
    })
}

# ============================================================
# STOP START MENU RESOURCES
# ============================================================

function Stop-StartMenuResources {
    Stop-StartSearchPanelAnimation
    $script:SearchPanelTargetVisible = $false
    if($script:SearchDelayTimer) {
        $script:SearchDelayTimer.Stop()
        $script:SearchDelayTimer.Dispose()
        $script:SearchDelayTimer = $null
    }
    Clear-StartSearchResults
    if($script:StartSearchPanel -and -not $script:StartSearchPanel.IsDisposed) {
        $script:StartSearchPanel.Dispose()
    }
    if($script:WindowsTimer) {
        $script:WindowsTimer.Stop()
        $script:WindowsTimer.Dispose()
        $script:WindowsTimer = $null
    }
    $script:StartSearchBox = $null
    $script:StartSearchResults = $null
    $script:PendingSearch = $null
    $script:StartSearchPanel = $null
    $script:WindowsButtonNormalBounds = $null
    $script:WindowsButton = $null
    $script:StartMenuForm = $null
}
