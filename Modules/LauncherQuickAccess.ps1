# ============================================================
# LAUNCHER QUICK ACCESS MODULE
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherQuickAccess"
    LoadOrder = 240
    RequiresModules = @("LauncherAlphaOverlay", "LauncherDomain", "LauncherLogging", "LauncherSettings")
    RequiresFunctions = [ordered]@{
        "Get-LauncherSettingsFolder" = "LauncherSettings"
        "Write-LauncherDiagnostic" = "LauncherLogging"
        "Register-GaloreOverlayForm" = "LauncherAlphaOverlay"
        "Unregister-GaloreOverlayForm" = "LauncherAlphaOverlay"
    }
    RequiresTypes = [ordered]@{
        "GaloreAlphaOverlay.PerPixelAlphaForm" = "LauncherAlphaOverlay"
        "GaloreQuickAccessRuntimeState" = "LauncherDomain"
    }
    RequiresVariables = @("AppRoot")
    RequiresFolders = @("resources")
    RequiresFiles = @("resources\\folder.png", "resources\\exe.png")
    ProvidesTypes = @()
}

$script:GaloreQuickAccessRuntime = [GaloreQuickAccessRuntimeState]::new()

# ============================================================
# RUNTIME HELPERS
# ============================================================

function Get-GaloreQuickAccessKeyColor {
    param($Runtime = $script:GaloreQuickAccessRuntime)
    if($null -eq $Runtime.KeyColor) {
        $Runtime.KeyColor = [System.Drawing.Color]::FromArgb(1, 2, 3)
    }
    return $Runtime.KeyColor
}

function Clear-GaloreQuickAccessBarControls {
    param($Runtime = $script:GaloreQuickAccessRuntime)
    if($null -eq $Runtime -or $null -eq $Runtime.Bar -or $Runtime.Bar.IsDisposed) {
        return
    }
    foreach($control in @($Runtime.Bar.Controls)) {
        if($control.Image) {
            $image = $control.Image
            $control.Image = $null
            $image.Dispose()
        }
        $control.Dispose()
    }
    $Runtime.Bar.Controls.Clear()
}

# ============================================================
# PERSISTENCE
# ============================================================

function Get-GaloreQuickAccessItems {
    param($Runtime = $script:GaloreQuickAccessRuntime)
    if($null -eq $Runtime -or [string]::IsNullOrWhiteSpace($Runtime.StatePath) -or -not (Test-Path -LiteralPath $Runtime.StatePath -PathType Leaf)) {
        return @()
    }
    try {
        $document = Get-Content -LiteralPath $Runtime.StatePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $items = [System.Collections.ArrayList]::new()
        foreach($item in @($document.Items)) {
            if($null -ne $item -and -not [string]::IsNullOrWhiteSpace([string]$item.Path) -and (Test-Path -LiteralPath ([string]$item.Path))) {
                [void]$items.Add([pscustomobject]@{ Path = [string]$item.Path })
            }
        }
        return $items.ToArray()
    } catch {
        Write-LauncherDiagnostic -Exception $_ -Context "Failed to load quick-access items."
        return @()
    }
}

function Save-GaloreQuickAccessItems {
    param($Runtime = $script:GaloreQuickAccessRuntime)
    if($null -eq $Runtime -or [string]::IsNullOrWhiteSpace($Runtime.StatePath)) {
        return
    }
    try {
        [pscustomobject]@{
            Version = 1
            Items = @($Runtime.Items | ForEach-Object { [pscustomobject]@{ Path = $_.Path } })
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Runtime.StatePath -Encoding UTF8
    } catch {
        Write-LauncherDiagnostic -Exception $_ -Context "Failed to save quick-access items."
    }
}

function Remove-GaloreQuickAccessItem {
    param([string]$Path, $Runtime = $script:GaloreQuickAccessRuntime)
    if($null -eq $Runtime -or [string]::IsNullOrWhiteSpace($Path)) {
        return
    }
    $removeItem = @($Runtime.Items | Where-Object { $_.Path -eq $Path }) | Select-Object -First 1
    if($null -eq $removeItem) {
        return
    }
    [void]$Runtime.Items.Remove($removeItem)
    Save-GaloreQuickAccessItems -Runtime $Runtime
    Update-GaloreQuickAccessBar -Runtime $Runtime
}

function Add-GaloreQuickAccessDroppedItems {
    param($Data, $Runtime = $script:GaloreQuickAccessRuntime)
    try {
        if($null -eq $Runtime -or $Runtime.IsStopping -or $null -eq $Data -or -not $Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
            return
        }
        $added = $false
        foreach($path in @($Data.GetData([System.Windows.Forms.DataFormats]::FileDrop))) {
            $path = [string]$path
            $extension = [System.IO.Path]::GetExtension($path)
            $isFolder = Test-Path -LiteralPath $path -PathType Container
            $isSupportedFile = $extension -ieq ".exe" -or $extension -ieq ".lnk" -or $extension -ieq ".url"
            if(-not $isFolder -and -not $isSupportedFile) {
                continue
            }
            if(-not @($Runtime.Items | Where-Object { $_.Path -eq $path })) {
                [void]$Runtime.Items.Add([pscustomobject]@{ Path = $path })
                $added = $true
            }
        }
        if($added) {
            Save-GaloreQuickAccessItems -Runtime $Runtime
            Update-GaloreQuickAccessBar -Runtime $Runtime
        }
    } catch {
        Write-LauncherDiagnostic -Exception $_ -Context "Failed to add a dropped quick-access item."
    }
}

# ============================================================
# DROP TARGETS
# ============================================================

function Register-GaloreQuickAccessDropTarget {
    param([System.Windows.Forms.Control]$Target, $Runtime = $script:GaloreQuickAccessRuntime)
    if($null -eq $Target -or $Target.IsDisposed -or $null -eq $Runtime) {
        return
    }
    $Target.AllowDrop = $true
    $Target.Add_DragEnter({
        param($sender, $e)
        $e.Effect = if($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) { [System.Windows.Forms.DragDropEffects]::Copy } else { [System.Windows.Forms.DragDropEffects]::None }
    })
    $Target.Add_DragOver({
        param($sender, $e)
        $e.Effect = if($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) { [System.Windows.Forms.DragDropEffects]::Copy } else { [System.Windows.Forms.DragDropEffects]::None }
    })
    $Target.Add_DragDrop({
        param($sender, $e)
        Add-GaloreQuickAccessDroppedItems -Data $e.Data -Runtime $Runtime
    }.GetNewClosure())
}

# ============================================================
# BAR LOCATION AND IMAGES
# ============================================================

function Set-GaloreQuickAccessBarLocation {
    param([System.Windows.Forms.Form]$LauncherForm, $Runtime = $script:GaloreQuickAccessRuntime)
    if($null -eq $Runtime -or $Runtime.IsStopping -or $null -eq $Runtime.Bar -or $Runtime.Bar.IsDisposed -or $null -eq $LauncherForm -or $LauncherForm.IsDisposed -or -not [object]::ReferenceEquals($Runtime.OwnerForm, $LauncherForm) -or $LauncherForm.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized -or $LauncherForm.ClientSize.Width -le 0 -or $LauncherForm.ClientSize.Height -le 0) {
        return
    }
    $location = $LauncherForm.PointToScreen([System.Drawing.Point]::new(0, ($LauncherForm.ClientSize.Height + 4)))
    $targetSize = [System.Drawing.Size]::new($LauncherForm.ClientSize.Width, 44)
    $sizeChanged = $Runtime.Bar.ClientSize -ne $targetSize
    if($sizeChanged) {
        $Runtime.Bar.ClientSize = $targetSize
    }
    $Runtime.Bar.Location = $location
    if($null -ne $Runtime.DropSurface -and -not $Runtime.DropSurface.IsDisposed) {
        if($Runtime.DropSurface.ClientSize -ne $targetSize) {
            $Runtime.DropSurface.ClientSize = $targetSize
        }
        $Runtime.DropSurface.Location = $location
    }
    if($sizeChanged) {
        Render-GaloreQuickAccessBar -Runtime $Runtime
    }
}

function Get-GaloreQuickAccessImage {
    param([string]$Path)
    try {
        if(Test-Path -LiteralPath $Path -PathType Container) {
            return [System.Drawing.Bitmap]::new((Get-GaloreResourcePath "folder.png"))
        }
        $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($Path)
        if($null -eq $icon) {
            throw "No associated icon was found for $Path"
        }
        try {
            return [GaloreAlphaOverlay.PerPixelAlphaForm]::IconToAlphaBitmap($icon, 32, 32)
        } finally {
            $icon.Dispose()
        }
    } catch {
        return [System.Drawing.Bitmap]::new((Get-GaloreResourcePath "exe.png"))
    }
}

# ============================================================
# BAR RENDERING
# ============================================================

function Update-GaloreQuickAccessBar {
    param($Runtime = $script:GaloreQuickAccessRuntime)
    if($null -eq $Runtime -or $Runtime.IsStopping -or $null -eq $Runtime.Bar -or $Runtime.Bar.IsDisposed) {
        return
    }
    if($null -eq $Runtime.ToolTip) {
        $Runtime.ToolTip = New-Object System.Windows.Forms.ToolTip
    }
    $Runtime.ToolTip.RemoveAll()
    Clear-GaloreQuickAccessBarControls -Runtime $Runtime
    [int]$left = 6
    foreach($item in @($Runtime.Items)) {
        $entry = New-Object System.Windows.Forms.PictureBox
        $entry.Size = [System.Drawing.Size]::new(34, 34)
        $entry.Location = [System.Drawing.Point]::new($left, 5)
        $entry.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
        $entry.Cursor = [System.Windows.Forms.Cursors]::Hand
        $entry.BackColor = Get-GaloreQuickAccessKeyColor -Runtime $Runtime
        $entry.Image = Get-GaloreQuickAccessImage -Path $item.Path
        $entry.Tag = [pscustomobject]@{ Path = $item.Path; StartPoint = $null; DragStarted = $false }
        Register-GaloreQuickAccessDropTarget -Target $entry -Runtime $Runtime
        $entry.Add_MouseDown({
            param($sender, $e)
            if($e.Button -eq [System.Windows.Forms.MouseButtons]::Left -and -not $Runtime.IsStopping) {
                $Runtime.IsDragging = $true
                $sender.Tag.StartPoint = $e.Location
                $sender.Tag.DragStarted = $false
            }
        }.GetNewClosure())
        $entry.Add_MouseMove({
            param($sender, $e)
            if($Runtime.IsStopping -or $e.Button -ne [System.Windows.Forms.MouseButtons]::Left -or $null -eq $sender.Tag.StartPoint -or $sender.Tag.DragStarted) {
                return
            }
            if([Math]::Abs($e.X - $sender.Tag.StartPoint.X) -lt 4 -and [Math]::Abs($e.Y - $sender.Tag.StartPoint.Y) -lt 4) {
                return
            }
            $sender.Tag.DragStarted = $true
            $data = New-Object System.Windows.Forms.DataObject
            $data.SetData([System.Windows.Forms.DataFormats]::FileDrop, [string[]]@([string]$sender.Tag.Path))
            [void]$sender.DoDragDrop($data, [System.Windows.Forms.DragDropEffects]::Copy)
            $Runtime.IsDragging = $false
            if(-not $Runtime.IsStopping) {
                Remove-GaloreQuickAccessItem -Path ([string]$sender.Tag.Path) -Runtime $Runtime
            }
        }.GetNewClosure())
        $entry.Add_MouseUp({
            param($sender, $e)
            $Runtime.IsDragging = $false
            if($Runtime.IsStopping) {
                return
            }
            if($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
                Remove-GaloreQuickAccessItem -Path ([string]$sender.Tag.Path) -Runtime $Runtime
                return
            }
            if($e.Button -eq [System.Windows.Forms.MouseButtons]::Left -and -not $sender.Tag.DragStarted) {
                try {
                    Start-Process -FilePath ([string]$sender.Tag.Path) -ErrorAction Stop
                } catch {
                    Write-LauncherDiagnostic -Exception $_ -Context "Failed to open quick-access item."
                }
            }
        }.GetNewClosure())
        $Runtime.ToolTip.SetToolTip($entry, "$($item.Path)`nRight-click to remove")
        $entry.Visible = $false
        $Runtime.Bar.Controls.Add($entry)
        $left += 40
    }
    Render-GaloreQuickAccessBar -Runtime $Runtime
}

function Render-GaloreQuickAccessBar {
    param($Runtime = $script:GaloreQuickAccessRuntime)
    if($null -eq $Runtime -or $null -eq $Runtime.Bar -or $Runtime.Bar.IsDisposed -or -not $Runtime.Bar.IsHandleCreated -or $Runtime.Bar.ClientSize.Width -le 0 -or $Runtime.Bar.ClientSize.Height -le 0) {
        return
    }
    $bitmap = New-Object System.Drawing.Bitmap($Runtime.Bar.ClientSize.Width, $Runtime.Bar.ClientSize.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        foreach($control in @($Runtime.Bar.Controls)) {
            if($control.Image) {
                $graphics.DrawImage($control.Image, $control.Bounds)
            }
        }
        $Runtime.Bar.SetLayeredBitmap($bitmap)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

# ============================================================
# LIFECYCLE
# ============================================================

function Initialize-GaloreQuickAccessBar {
    param([System.Windows.Forms.Form]$Form, $Runtime = $script:GaloreQuickAccessRuntime)
    if($null -eq $Runtime -or $null -eq $Form -or $Form.IsDisposed) {
        return
    }
    if([object]::ReferenceEquals($Runtime.OwnerForm, $Form) -and $Runtime.IsInitialized -and $Runtime.Bar -and -not $Runtime.Bar.IsDisposed) {
        return
    }
    Stop-GaloreQuickAccessResources -Runtime $Runtime
    $settingsFolder = Get-LauncherSettingsFolder
    if([string]::IsNullOrWhiteSpace($settingsFolder)) {
        return
    }
    $Runtime.OwnerForm = $Form
    $Runtime.StatePath = Join-Path $settingsFolder "quick-access.json"
    $Runtime.Items = [System.Collections.ArrayList]::new()
    foreach($item in @(Get-GaloreQuickAccessItems -Runtime $Runtime)) {
        [void]$Runtime.Items.Add($item)
    }
    $bar = New-Object GaloreAlphaOverlay.PerPixelAlphaForm
    $bar.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $bar.ShowInTaskbar = $false
    $bar.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $bar.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $bar.ClientSize = [System.Drawing.Size]::new($Form.ClientSize.Width, 44)
    $bar.Owner = $Form
    $Runtime.Bar = $bar
    Register-GaloreOverlayForm -Form $bar
    Register-GaloreQuickAccessDropTarget -Target $bar -Runtime $Runtime
    $bar.Add_MouseDown({
        param($sender, $e)
        if($Runtime.IsStopping) {
            return
        }
        $entry = @($sender.Controls | Where-Object { $_.Bounds.Contains($e.Location) }) | Select-Object -First 1
        if($null -eq $entry) {
            return
        }
        if($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
            Remove-GaloreQuickAccessItem -Path ([string]$entry.Tag.Path) -Runtime $Runtime
            return
        }
        if($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            $Runtime.IsDragging = $true
            $entry.Tag.StartPoint = $e.Location
            $entry.Tag.DragStarted = $false
        }
    }.GetNewClosure())
    $bar.Add_MouseMove({
        param($sender, $e)
        if($Runtime.IsStopping -or $e.Button -ne [System.Windows.Forms.MouseButtons]::Left) {
            return
        }
        $entry = @($sender.Controls | Where-Object { $null -ne $_.Tag.StartPoint -and $_.Bounds.Contains($_.Tag.StartPoint) }) | Select-Object -First 1
        if($null -eq $entry -or $entry.Tag.DragStarted) {
            return
        }
        if([Math]::Abs($e.X - $entry.Tag.StartPoint.X) -lt 4 -and [Math]::Abs($e.Y - $entry.Tag.StartPoint.Y) -lt 4) {
            return
        }
        $entry.Tag.DragStarted = $true
        $data = New-Object System.Windows.Forms.DataObject
        $data.SetData([System.Windows.Forms.DataFormats]::FileDrop, [string[]]@([string]$entry.Tag.Path))
        [void]$sender.DoDragDrop($data, [System.Windows.Forms.DragDropEffects]::Copy)
        $Runtime.IsDragging = $false
        if(-not $Runtime.IsStopping) {
            Remove-GaloreQuickAccessItem -Path ([string]$entry.Tag.Path) -Runtime $Runtime
        }
    }.GetNewClosure())
    $bar.Add_MouseUp({
        param($sender, $e)
        $Runtime.IsDragging = $false
        if($Runtime.IsStopping) {
            return
        }
        $entry = @($sender.Controls | Where-Object { $_.Bounds.Contains($e.Location) }) | Select-Object -First 1
        if($null -eq $entry) {
            return
        }
        $entry.Tag.StartPoint = $null
        if($e.Button -eq [System.Windows.Forms.MouseButtons]::Left -and -not $entry.Tag.DragStarted) {
            try {
                Start-Process -FilePath ([string]$entry.Tag.Path) -ErrorAction Stop
            } catch {
                Write-LauncherDiagnostic -Exception $_ -Context "Failed to open quick-access item."
            }
        }
    }.GetNewClosure())
    $bar.Add_FormClosed({
        param($sender, $e)
        if($sender -and [object]::ReferenceEquals($Runtime.Bar, $sender)) {
            Clear-GaloreQuickAccessBarControls -Runtime $Runtime
        }
    }.GetNewClosure())
    $Runtime.MoveHandler = { param($sender, $e) Set-GaloreQuickAccessBarLocation -LauncherForm $sender -Runtime $Runtime }.GetNewClosure()
    $Runtime.SizeChangedHandler = { param($sender, $e) Set-GaloreQuickAccessBarLocation -LauncherForm $sender -Runtime $Runtime }.GetNewClosure()
    $Runtime.ShownHandler = {
        param($sender, $e)
        if($Runtime.IsStopping -or -not [object]::ReferenceEquals($Runtime.OwnerForm, $sender) -or $null -eq $Runtime.Bar -or $Runtime.Bar.IsDisposed) {
            return
        }
        $Runtime.Bar.SetLayeredOpacity(0)
        $Runtime.Bar.Show()
        $Runtime.Bar.ClientSize = [System.Drawing.Size]::new($sender.ClientSize.Width, 44)
        Set-GaloreQuickAccessBarLocation -LauncherForm $sender -Runtime $Runtime
        Update-GaloreQuickAccessBar -Runtime $Runtime
    }.GetNewClosure()
    $Runtime.FormClosedHandler = {
        param($sender, $e)
        if([object]::ReferenceEquals($Runtime.OwnerForm, $sender)) {
            Stop-GaloreQuickAccessResources -Runtime $Runtime
        }
    }.GetNewClosure()
    $Form.Add_Move($Runtime.MoveHandler)
    $Form.Add_SizeChanged($Runtime.SizeChangedHandler)
    $Form.Add_Shown($Runtime.ShownHandler)
    $Form.Add_FormClosed($Runtime.FormClosedHandler)
    $Runtime.IsInitialized = $true
}

function Stop-GaloreQuickAccessResources {
    param($Runtime = $script:GaloreQuickAccessRuntime)
    if($null -eq $Runtime -or $Runtime.IsStopping) {
        return
    }
    $Runtime.IsStopping = $true
    $ownerForm = $Runtime.OwnerForm
    if($ownerForm -and -not $ownerForm.IsDisposed) {
        if($Runtime.MoveHandler) { try { $ownerForm.Remove_Move($Runtime.MoveHandler) } catch {} }
        if($Runtime.SizeChangedHandler) { try { $ownerForm.Remove_SizeChanged($Runtime.SizeChangedHandler) } catch {} }
        if($Runtime.ShownHandler) { try { $ownerForm.Remove_Shown($Runtime.ShownHandler) } catch {} }
        if($Runtime.FormClosedHandler) { try { $ownerForm.Remove_FormClosed($Runtime.FormClosedHandler) } catch {} }
    }
    if($Runtime.ToolTip) {
        try {
            $Runtime.ToolTip.Dispose()
        } catch {
        }
    }
    if($Runtime.Bar -and -not $Runtime.Bar.IsDisposed) {
        Unregister-GaloreOverlayForm -Form $Runtime.Bar
        Clear-GaloreQuickAccessBarControls -Runtime $Runtime
        try {
            $Runtime.Bar.Close()
        } catch {
        }
    }
    if($Runtime.DropSurface -and -not $Runtime.DropSurface.IsDisposed) {
        try {
            $Runtime.DropSurface.Close()
        } catch {
        }
    }
    $Runtime.OwnerForm = $null
    $Runtime.Bar = $null
    $Runtime.DropSurface = $null
    $Runtime.StatePath = ""
    $Runtime.Items = [System.Collections.ArrayList]::new()
    $Runtime.KeyColor = $null
    $Runtime.ToolTip = $null
    $Runtime.MoveHandler = $null
    $Runtime.SizeChangedHandler = $null
    $Runtime.ShownHandler = $null
    $Runtime.FormClosedHandler = $null
    $Runtime.IsInitialized = $false
    $Runtime.IsDragging = $false
    $Runtime.IsStopping = $false
}

foreach($callbackName in @(
        "Get-GaloreQuickAccessItems", "Save-GaloreQuickAccessItems", "Remove-GaloreQuickAccessItem", "Add-GaloreQuickAccessDroppedItems", "Set-GaloreQuickAccessBarLocation", "Update-GaloreQuickAccessBar", "Render-GaloreQuickAccessBar", "Initialize-GaloreQuickAccessBar", "Stop-GaloreQuickAccessResources"
    )) {
    $callback = Get-Command -Name $callbackName -CommandType Function -ErrorAction Stop
    Set-Item -Path ("Function:global:{0}" -f $callbackName) -Value $callback.ScriptBlock -Force
}
