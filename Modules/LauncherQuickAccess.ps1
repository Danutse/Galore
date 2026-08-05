# ============================================================
# LAUNCHER QUICK ACCESS MODULE
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherQuickAccess"
    LoadOrder = 240
    RequiresModules = @("LauncherAlphaOverlay", "LauncherLogging", "LauncherSettings")
    RequiresFunctions = [ordered]@{
        "Get-LauncherSettingsFolder" = "LauncherSettings"
        "Write-LauncherDiagnostic" = "LauncherLogging"
    }
    RequiresTypes = [ordered]@{
        "GaloreAlphaOverlay.PerPixelAlphaForm" = "LauncherAlphaOverlay"
    }
    RequiresVariables = @("AppRoot")
    RequiresFolders = @("resources")
    RequiresFiles = @("resources\\folder.png", "resources\\exe.png")
    ProvidesTypes = @()
}
$script:GaloreQuickAccessBar = $null
$script:GaloreQuickAccessDropSurface = $null
$script:GaloreQuickAccessPath = $null
$script:GaloreQuickAccessItems = New-Object System.Collections.ArrayList
$script:GaloreQuickAccessKeyColor = [System.Drawing.Color]::FromArgb(1, 2, 3)

function Get-GaloreQuickAccessItems {
    if(-not (Test-Path -LiteralPath $script:GaloreQuickAccessPath -PathType Leaf)) {
        return @()
    }
    try {
        $document = Get-Content -LiteralPath $script:GaloreQuickAccessPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $items = New-Object System.Collections.ArrayList
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
    if([string]::IsNullOrWhiteSpace($script:GaloreQuickAccessPath)) {
        return
    }
    try {
        [pscustomobject]@{
            Version = 1
            Items = @($script:GaloreQuickAccessItems | ForEach-Object {
                [pscustomobject]@{ Path = $_.Path }
            })
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:GaloreQuickAccessPath -Encoding UTF8
    } catch {
        Write-LauncherDiagnostic -Exception $_ -Context "Failed to save quick-access items."
    }
}

function Remove-GaloreQuickAccessItem {
    param([string]$Path)
    if([string]::IsNullOrWhiteSpace($Path)) {
        return
    }
    $removeItem = @($script:GaloreQuickAccessItems | Where-Object { $_.Path -eq $Path }) | Select-Object -First 1
    if($null -eq $removeItem) {
        return
    }
    [void]$script:GaloreQuickAccessItems.Remove($removeItem)
    Save-GaloreQuickAccessItems
    Update-GaloreQuickAccessBar
}

function Add-GaloreQuickAccessDroppedItems {
    param($Data)
    try {
        $added = $false
        if($null -eq $Data -or -not $Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
            return
        }
        foreach($path in @($Data.GetData([System.Windows.Forms.DataFormats]::FileDrop))) {
            $path = [string]$path
            $extension = [System.IO.Path]::GetExtension($path)
            $isFolder = Test-Path -LiteralPath $path -PathType Container
            $isSupportedFile = $extension -ieq ".exe" -or $extension -ieq ".lnk" -or $extension -ieq ".url"
            if(-not $isFolder -and -not $isSupportedFile) {
                continue
            }
            if(-not @($script:GaloreQuickAccessItems | Where-Object { $_.Path -eq $path })) {
                [void]$script:GaloreQuickAccessItems.Add([pscustomobject]@{ Path = $path })
                $added = $true
            }
        }
        if(-not $added) {
            return
        }
        Save-GaloreQuickAccessItems
        Update-GaloreQuickAccessBar
    } catch {
        Write-LauncherDiagnostic -Exception $_ -Context "Failed to add a dropped quick-access item."
    }
}

function Register-GaloreQuickAccessDropTarget {
    param([System.Windows.Forms.Control]$Target)
    $Target.AllowDrop = $true
    $Target.Add_DragEnter({
        param($sender, $e)
        $e.Effect = if($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
            [System.Windows.Forms.DragDropEffects]::Copy
        }
        else {
            [System.Windows.Forms.DragDropEffects]::None
        }
    })
    $Target.Add_DragOver({
        param($sender, $e)
        $e.Effect = if($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
            [System.Windows.Forms.DragDropEffects]::Copy
        }
        else {
            [System.Windows.Forms.DragDropEffects]::None
        }
    })
    $Target.Add_DragDrop({
        param($sender, $e)
        Add-GaloreQuickAccessDroppedItems -Data $e.Data
    })
}

function Set-GaloreQuickAccessBarLocation {
    param([System.Windows.Forms.Form]$LauncherForm)
    if($null -eq $script:GaloreQuickAccessBar -or $script:GaloreQuickAccessBar.IsDisposed -or $LauncherForm.IsDisposed -or $LauncherForm.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized -or $LauncherForm.ClientSize.Width -le 0 -or $LauncherForm.ClientSize.Height -le 0) {
        return
    }
    $location = $LauncherForm.PointToScreen([System.Drawing.Point]::new(0, ($LauncherForm.ClientSize.Height + 4)))
    $bar = $script:GaloreQuickAccessBar
    $targetSize = [System.Drawing.Size]::new($LauncherForm.ClientSize.Width, 44)
    $sizeChanged = $bar.ClientSize -ne $targetSize
    if($sizeChanged) {
        $bar.ClientSize = $targetSize
    }
    $bar.Location = $location
    if($null -ne $script:GaloreQuickAccessDropSurface -and -not $script:GaloreQuickAccessDropSurface.IsDisposed) {
        if($script:GaloreQuickAccessDropSurface.ClientSize -ne $targetSize) {
            $script:GaloreQuickAccessDropSurface.ClientSize = $targetSize
        }
        $script:GaloreQuickAccessDropSurface.Location = $location
    }
    if($sizeChanged) {
        Render-GaloreQuickAccessBar
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
        }
        finally { $icon.Dispose() }
    } catch {
        return [System.Drawing.Bitmap]::new((Get-GaloreResourcePath "exe.png"))
    }
}

function Update-GaloreQuickAccessBar {
    if($null -eq $script:GaloreQuickAccessBar -or $script:GaloreQuickAccessBar.IsDisposed) {
        return
    }
    $bar = $script:GaloreQuickAccessBar
    foreach($control in @($bar.Controls)) {
        if($control.Image) {
            $image = $control.Image
            $control.Image = $null
            $image.Dispose()
        }
        $control.Dispose()
    }
    $bar.Controls.Clear()
    [int]$left = 6
    foreach($item in @($script:GaloreQuickAccessItems)) {
        $entry = New-Object System.Windows.Forms.PictureBox
        $entry.Size = [System.Drawing.Size]::new(34, 34)
        $entry.Location = [System.Drawing.Point]::new($left, 5)
        $entry.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
        $entry.Cursor = [System.Windows.Forms.Cursors]::Hand
        $entry.BackColor = $script:GaloreQuickAccessKeyColor
        $entry.Image = Get-GaloreQuickAccessImage -Path $item.Path
        $entry.Tag = [pscustomobject]@{
            Path = $item.Path
            StartPoint = $null
            DragStarted = $false
        }
        Register-GaloreQuickAccessDropTarget -Target $entry
        $entry.Add_MouseDown({
            param($sender, $e)
            if($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
                $sender.Tag.StartPoint = $e.Location
                $sender.Tag.DragStarted = $false
            }
        })
        $entry.Add_MouseMove({
            param($sender, $e)
            if($e.Button -ne [System.Windows.Forms.MouseButtons]::Left -or $null -eq $sender.Tag.StartPoint -or $sender.Tag.DragStarted) {
                return
            }
            if([Math]::Abs($e.X - $sender.Tag.StartPoint.X) -lt 4 -and [Math]::Abs($e.Y - $sender.Tag.StartPoint.Y) -lt 4) {
                return
            }
            $sender.Tag.DragStarted = $true
            $data = New-Object System.Windows.Forms.DataObject
            $data.SetData([System.Windows.Forms.DataFormats]::FileDrop, [string[]]@([string]$sender.Tag.Path)
            )
            [void]$sender.DoDragDrop($data, [System.Windows.Forms.DragDropEffects]::Copy)
            $removeItem = @($script:GaloreQuickAccessItems | Where-Object { $_.Path -eq $sender.Tag.Path }) | Select-Object -First 1
            if($removeItem) {
                [void]$script:GaloreQuickAccessItems.Remove($removeItem)
                Save-GaloreQuickAccessItems
                Update-GaloreQuickAccessBar
            }
        }.GetNewClosure())
        $entry.Add_MouseUp({
            param($sender, $e)
            if($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
                $removeItem = @($script:GaloreQuickAccessItems | Where-Object { $_.Path -eq $sender.Tag.Path }) | Select-Object -First 1
                if($removeItem) {
                    [void]$script:GaloreQuickAccessItems.Remove($removeItem)
                    Save-GaloreQuickAccessItems
                    Update-GaloreQuickAccessBar
                }
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
        $toolTip = New-Object System.Windows.Forms.ToolTip
        $toolTip.SetToolTip($entry, "$($item.Path)`nRight-click to remove")
        $entry.Visible = $false
        $bar.Controls.Add($entry)
        $left += 40
    }
    Render-GaloreQuickAccessBar
}

function Render-GaloreQuickAccessBar {
    $bar = $script:GaloreQuickAccessBar
    if($null -eq $bar -or $bar.IsDisposed -or -not $bar.IsHandleCreated) {
        return
    }
    if($bar.ClientSize.Width -le 0 -or $bar.ClientSize.Height -le 0) {
        return
    }
    $bitmap = New-Object System.Drawing.Bitmap($bar.ClientSize.Width, $bar.ClientSize.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        foreach($control in @($bar.Controls)) {
            if($control.Image) {
                $graphics.DrawImage($control.Image, $control.Bounds)
            }
        }
        $bar.SetLayeredBitmap($bitmap)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Initialize-GaloreQuickAccessBar {
    param([System.Windows.Forms.Form]$Form)
    $settingsFolder = Get-LauncherSettingsFolder
    if([string]::IsNullOrWhiteSpace($settingsFolder)) {
        return
    }
    $script:GaloreQuickAccessPath = Join-Path $settingsFolder "quick-access.json"
    $script:GaloreQuickAccessItems = New-Object System.Collections.ArrayList
    foreach($item in @(Get-GaloreQuickAccessItems)) {
        [void]$script:GaloreQuickAccessItems.Add($item)
    }
    $bar = New-Object GaloreAlphaOverlay.PerPixelAlphaForm
    $bar.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $bar.ShowInTaskbar = $false
    $bar.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $bar.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $bar.ClientSize = [System.Drawing.Size]::new($Form.ClientSize.Width, 44)
    $bar.Owner = $Form
    Register-GaloreQuickAccessDropTarget -Target $bar
    $bar.Add_MouseDown({
        param($sender, $e)
        $entry = @($sender.Controls | Where-Object { $_.Bounds.Contains($e.Location) }) | Select-Object -First 1
        if($null -eq $entry) {
            return
        }
        if($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
            Remove-GaloreQuickAccessItem -Path ([string]$entry.Tag.Path)
            return
        }
        if($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) {
            return
        }
        $entry.Tag.StartPoint = $e.Location
        $entry.Tag.DragStarted = $false
    }.GetNewClosure())
    $bar.Add_MouseMove({
        param($sender, $e)
        if($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) {
            return
        }
        $entry = @($sender.Controls | Where-Object {
            $null -ne $_.Tag.StartPoint -and $_.Bounds.Contains($_.Tag.StartPoint)
        }) | Select-Object -First 1
        if($null -eq $entry -or $entry.Tag.DragStarted) {
            return
        }
        if([Math]::Abs($e.X - $entry.Tag.StartPoint.X) -lt 4 -and [Math]::Abs($e.Y - $entry.Tag.StartPoint.Y) -lt 4) {
            return
        }
        $entry.Tag.DragStarted = $true
        $data = New-Object System.Windows.Forms.DataObject
        $data.SetData([System.Windows.Forms.DataFormats]::FileDrop, [string[]]@([string]$entry.Tag.Path)
        )
        [void]$sender.DoDragDrop($data, [System.Windows.Forms.DragDropEffects]::Copy)
        Remove-GaloreQuickAccessItem -Path ([string]$entry.Tag.Path)
    }.GetNewClosure())
    $bar.Add_MouseUp({
        param($sender, $e)
        $entry = @($sender.Controls | Where-Object { $_.Bounds.Contains($e.Location) }) | Select-Object -First 1
        if($null -eq $entry) {
            return
        }
        $entry.Tag.StartPoint = $null
        if($e.Button -eq [System.Windows.Forms.MouseButtons]::Left -and -not $entry.Tag.DragStarted) {
            Start-Process -FilePath ([string]$entry.Tag.Path) -ErrorAction Stop
        }
    }.GetNewClosure())
    $bar.Add_FormClosed({
        param($sender, $e)
        foreach($control in @($sender.Controls)) {
            if($control.Image) {
                $control.Image.Dispose()
                $control.Image = $null
            }
        }
    })
    $script:GaloreQuickAccessBar = $bar
    $script:GaloreQuickAccessDropSurface = $null
    $Form.Add_Move({ Set-GaloreQuickAccessBarLocation -LauncherForm $Form }.GetNewClosure())
    $Form.Add_SizeChanged({ Set-GaloreQuickAccessBarLocation -LauncherForm $Form }.GetNewClosure())
    $Form.Add_FormClosed({
        if($null -ne $script:GaloreQuickAccessBar -and -not $script:GaloreQuickAccessBar.IsDisposed) {
            $script:GaloreQuickAccessBar.Close()
        }
        if($null -ne $script:GaloreQuickAccessDropSurface -and -not $script:GaloreQuickAccessDropSurface.IsDisposed) {
            $script:GaloreQuickAccessDropSurface.Close()
        }
    }.GetNewClosure())
    $Form.Add_Shown({
        $bar.SetLayeredOpacity(0)
        $bar.Show()
        $bar.ClientSize = [System.Drawing.Size]::new($Form.ClientSize.Width, 44)
        Set-GaloreQuickAccessBarLocation -LauncherForm $Form
        Update-GaloreQuickAccessBar
    }.GetNewClosure())
}
foreach($callbackName in @(
    "Get-GaloreQuickAccessItems", "Save-GaloreQuickAccessItems", "Remove-GaloreQuickAccessItem", "Add-GaloreQuickAccessDroppedItems", "Set-GaloreQuickAccessBarLocation", "Update-GaloreQuickAccessBar", "Render-GaloreQuickAccessBar"
)) {
    $callback = Get-Command -Name $callbackName -CommandType Function -ErrorAction Stop
    Set-Item -Path ("Function:global:{0}" -f $callbackName) -Value $callback.ScriptBlock -Force
}
