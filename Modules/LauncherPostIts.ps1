# ============================================================
# LAUNCHER POST-ITS MODULE
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherPostIts"
    LoadOrder = 220
    RequiresModules = @("LauncherLogging", "LauncherSettings", "UI")
    RequiresFunctions = [ordered]@{
        "Get-LauncherSettingsFolder" = "LauncherSettings"
        "New-PostItButton" = "UI"
        "Write-LauncherDiagnostic" = "LauncherLogging"
    }
    RequiresTypes = [ordered]@{}
    RequiresVariables = @("AppRoot")
    RequiresFolders = @("resources")
    RequiresFiles = @(
        "resources\\postit.png"
        "resources\\PostitBackground.png"
        "resources\\close.png"
    )
    ProvidesTypes = @()
}
$script:GalorePostIts = New-Object System.Collections.ArrayList
$script:GalorePostItStorePath = $null
$script:GalorePostItShuttingDown = $false
$script:GalorePostItsRestored = $false
if(-not ("GalorePostItDpi.Native" -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;

namespace GalorePostItDpi
{
    public static class Native
    {
        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr SetThreadDpiAwarenessContext(
            IntPtr dpiContext
        );
    }
}
"@
}

function Enter-GalorePostItDpiContext {
    try {
        return [GalorePostItDpi.Native]::SetThreadDpiAwarenessContext([IntPtr](-4))
    } catch {
        return [IntPtr]::Zero
    }
}

function Exit-GalorePostItDpiContext {
    param([IntPtr]$PreviousContext)
    if($PreviousContext -eq [IntPtr]::Zero) {
        return
    }
    try {
        [GalorePostItDpi.Native]::SetThreadDpiAwarenessContext($PreviousContext) | Out-Null
    } catch {
    }
}

function Get-GalorePostItImage {
    param([string]$Name, [int]$Width = 0, [int]$Height = 0)
    $path = Get-GaloreResourcePath $Name
    $sourceImage = $null
    try {
        $sourceImage = [System.Drawing.Image]::FromFile($path)
        if($Width -gt 0 -and $Height -gt 0) {
            return New-Object System.Drawing.Bitmap($sourceImage, $Width, $Height)
        }
        return New-Object System.Drawing.Bitmap($sourceImage)
    } finally {
        if($null -ne $sourceImage) {
            $sourceImage.Dispose()
        }
    }
}

function Resolve-GalorePostItLocation {
    param([int]$X, [int]$Y, [int]$Width = 260, [int]$Height = 250)
    $noteRectangle = [System.Drawing.Rectangle]::new($X, $Y, $Width, $Height)
    $bestScreen = $null
    [int64]$largestVisibleArea = 0
    foreach($screen in [System.Windows.Forms.Screen]::AllScreens) {
        $visibleArea = [System.Drawing.Rectangle]::Intersect($noteRectangle, $screen.WorkingArea)
        [int64]$visibleAreaSize = [int64]$visibleArea.Width *
        [int64]$visibleArea.Height
        if($visibleAreaSize -gt $largestVisibleArea) {
            $largestVisibleArea = $visibleAreaSize
            $bestScreen = $screen
        }
    }
    if($null -ne $bestScreen) {
        $workingArea = $bestScreen.WorkingArea
        [int]$maximumX = [Math]::Max($workingArea.Left, ($workingArea.Right - $Width))
        [int]$maximumY = [Math]::Max($workingArea.Top, ($workingArea.Bottom - $Height))
        return [System.Drawing.Point]::new([Math]::Min([Math]::Max($X, $workingArea.Left), $maximumX), [Math]::Min([Math]::Max($Y, $workingArea.Top), $maximumY))
    }
    $workingArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $offset = ($script:GalorePostIts.Count % 6) * 26
    return [System.Drawing.Point]::new([int]($workingArea.Left + 60 + $offset), [int]($workingArea.Top + 60 + $offset))
}

function Set-GalorePostItFixedLayout {
    param([System.Windows.Forms.Form]$Form, [int]$X, [int]$Y)
    if($null -eq $Form -or $Form.IsDisposed) {
        return
    }
    $fixedSize = [System.Drawing.Size]::new(260, 250)
    $Form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $Form.AutoSize = $false
    $Form.ClientSize = $fixedSize
    $Form.MinimumSize = $fixedSize
    $Form.MaximumSize = $fixedSize
    $Form.Location = Resolve-GalorePostItLocation -X $X -Y $Y -Width $Form.Width -Height $Form.Height
}

function Get-GalorePostItStates {
    $states = @()
    foreach($note in @($script:GalorePostIts)
    ) {
        $noteContext = $null
        if($null -eq $note -or $note.IsDisposed) {
            continue
        }
        $noteContext = $note.Tag
        if($null -eq $noteContext -or -not $noteContext.KeepInPersistence -or $null -eq $noteContext.TextBox -or $noteContext.TextBox.IsDisposed) {
            continue
        }
        $states += [pscustomobject]@{
            Id = $noteContext.Id
            Text = [string]$noteContext.TextBox.Text
            X = [int]$note.Location.X
            Y = [int]$note.Location.Y
            Checked = [bool]$noteContext.Checked
        }
    }
    return @($states)
}

function Save-GalorePostIts {
    if([string]::IsNullOrWhiteSpace($script:GalorePostItStorePath)) {
        return
    }
    $stateFolder = Split-Path -Parent $script:GalorePostItStorePath
    $stateFileName = Split-Path -Leaf $script:GalorePostItStorePath
    $temporaryPath = Join-Path $stateFolder ".${stateFileName}.$([guid]::NewGuid().ToString('N')).tmp"
    $backupPath = $null
    try {
        $noteStates = New-Object System.Collections.ArrayList
        foreach($savedState in @(Get-GalorePostItStates)
        ) {
            [void]$noteStates.Add($savedState)
        }
        $state = [pscustomobject]@{
            Version = 1
            Notes = $noteStates.ToArray()
        }
        $json = $state | ConvertTo-Json -Depth 4 -ErrorAction Stop
        $json | ConvertFrom-Json -ErrorAction Stop | Out-Null
        [System.IO.File]::WriteAllText($temporaryPath, $json, (New-Object System.Text.UTF8Encoding($false)))
        if(Test-Path -LiteralPath $script:GalorePostItStorePath -PathType Leaf) {
            $backupPath = Join-Path $stateFolder ".${stateFileName}.$([guid]::NewGuid().ToString('N')).previous"
            [System.IO.File]::Replace($temporaryPath, $script:GalorePostItStorePath, $backupPath)
        } else {
            [System.IO.File]::Move($temporaryPath, $script:GalorePostItStorePath)
        }
    } catch {
        Write-LauncherDiagnostic -Exception $_ -Context "Failed to save Post-it state."
    } finally {
        if(Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
        if($backupPath -and (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Read-GalorePostItStates {
    if(-not (Test-Path -LiteralPath $script:GalorePostItStorePath -PathType Leaf)) {
        return @()
    }
    try {
        $document = Get-Content -LiteralPath $script:GalorePostItStorePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if($null -eq $document.PSObject.Properties["Notes"]) {
            throw "Post-it data is missing its Notes collection."
        }
        $states = @()
        foreach($savedNote in @($document.Notes)
        ) {
            $x = 0
            $y = 0
            if($null -eq $savedNote -or $null -eq $savedNote.PSObject.Properties["Text"] -or -not [int]::TryParse([string]$savedNote.X, [ref]$x) -or -not [int]::TryParse([string]$savedNote.Y, [ref]$y)) {
                continue
            }
            $id = [guid]::NewGuid().ToString("N")
            if($null -ne $savedNote.PSObject.Properties["Id"] -and -not [string]::IsNullOrWhiteSpace([string]$savedNote.Id)) {
                $id = [string]$savedNote.Id
            }
            $checked = $false
            if($null -ne $savedNote.PSObject.Properties["Checked"]) {
                $checked = [bool]$savedNote.Checked
            }
            $states += [pscustomobject]@{
                Id = $id
                Text = [string]$savedNote.Text
                X = $x
                Y = $y
                Checked = $checked
            }
        }
        return @($states)
    } catch {
        Write-LauncherDiagnostic -Exception $_ -Context "Failed to load Post-it state."
        return @()
    }
}

function Start-GalorePostItDrag {
    param($Sender, $Event)
    if($Event.Button -ne [System.Windows.Forms.MouseButtons]::Left) {
        return
    }
    $note = $Sender.FindForm()
    if($null -eq $note -or $note.IsDisposed -or $null -eq $note.Tag) {
        return
    }
    $note.Tag.DragOffset = $note.PointToClient([System.Windows.Forms.Cursor]::Position)
    $note.Tag.IsDragging = $true
}

function Move-GalorePostItDrag {
    param($Sender, $Event)
    $note = $Sender.FindForm()
    if($null -eq $note -or $note.IsDisposed -or $null -eq $note.Tag -or -not $note.Tag.IsDragging) {
        return
    }
    $cursor = [System.Windows.Forms.Cursor]::Position
    $note.Location = [System.Drawing.Point]::new([int]([int]($cursor.X - $note.Tag.DragOffset.X)), [int]([int]($cursor.Y - $note.Tag.DragOffset.Y)))
}

function Stop-GalorePostItDrag {
    param($Sender)
    $note = $Sender.FindForm()
    if($null -eq $note -or $note.IsDisposed -or $null -eq $note.Tag -or -not $note.Tag.IsDragging) {
        return
    }
    $note.Tag.IsDragging = $false
    Save-GalorePostIts
}

function Set-GalorePostItCompletionStyle {
    param([System.Windows.Forms.TextBox]$Editor, [bool]$Checked)
    if($Checked) {
        $Editor.Font = New-Object System.Drawing.Font($Editor.Font, ([System.Drawing.FontStyle]::Strikeout -bor [System.Drawing.FontStyle]::Regular))
        $Editor.ForeColor = [System.Drawing.Color]::FromArgb(120, 120, 120)
    } else {
        $Editor.Font = New-Object System.Drawing.Font($Editor.Font, [System.Drawing.FontStyle]::Regular)
        $Editor.ForeColor = [System.Drawing.Color]::White
    }
}

function New-GalorePostItIconBitmap {
    param([System.Drawing.Bitmap]$Background, [System.Drawing.Rectangle]$Bounds, [scriptblock]$DrawOverlay)
    [int]$iconWidth = $Bounds.Width
    [int]$iconHeight = $Bounds.Height
    $icon = [System.Drawing.Bitmap]::new($iconWidth, $iconHeight)
    $graphics = [System.Drawing.Graphics]::FromImage($icon)
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
        $graphics.DrawImage($Background, [System.Drawing.Rectangle]::new(0, 0, $iconWidth, $iconHeight), $Bounds, [System.Drawing.GraphicsUnit]::Pixel)
        if($null -ne $DrawOverlay) {
            & $DrawOverlay $graphics $iconWidth $iconHeight
        }
    } finally {
        $graphics.Dispose()
    }
    return $icon
}

function Set-GalorePostItRegion {
    param([System.Windows.Forms.Form]$Form, [System.Drawing.Bitmap]$Bitmap, [int]$AlphaThreshold = 20)
    [int]$width = $Bitmap.Width
    [int]$height = $Bitmap.Height
    $bounds = [System.Drawing.Rectangle]::new(0, 0, $width, $height)
    $bitmapData = $Bitmap.LockBits($bounds, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $stride = [int]$bitmapData.Stride
    $byteCount = $stride * $height
    $pixelBytes = New-Object byte[] $byteCount
    [System.Runtime.InteropServices.Marshal]::Copy($bitmapData.Scan0, $pixelBytes, 0, $byteCount)
    $Bitmap.UnlockBits($bitmapData)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    for([int]$y = 0; $y -lt $height; $y++) {
        [int]$runStart = -1
        [int]$rowOffset = $y * $stride
        for([int]$x = 0; $x -lt $width; $x++) {
            [int]$alpha = $pixelBytes[$rowOffset + ($x * 4) + 3]
            if($alpha -ge $AlphaThreshold) {
                if($runStart -eq -1) {
                    $runStart = $x
                }
            } elseif($runStart -ne -1) {
                [int]$runLength = ([int]$x - [int]$runStart)
                $path.AddRectangle([System.Drawing.Rectangle]::new($runStart, $y, $runLength, 1))
                $runStart = -1
            }
        }
        if($runStart -ne -1) {
            [int]$runLength = ([int]$width - [int]$runStart)
            $path.AddRectangle([System.Drawing.Rectangle]::new($runStart, $y, $runLength, 1))
        }
    }
    if($null -ne $Form.Region) {
        $Form.Region.Dispose()
    }
    $Form.Region = New-Object System.Drawing.Region($path)
}

function New-GalorePostIt {
    param($State)
    $previousDpiContext = Enter-GalorePostItDpiContext
    try {
        return New-GalorePostItWindow -State $State
    } finally {
        Exit-GalorePostItDpiContext -PreviousContext $previousDpiContext
    }
}

function New-GalorePostItWindow {
    param($State)
    $note = New-Object System.Windows.Forms.Form
    $note.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $note.ShowInTaskbar = $false
    $note.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $note.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $note.AutoSize = $false
    $note.ClientSize = [System.Drawing.Size]::new(260, 250)
    $note.MinimumSize = [System.Drawing.Size]::new(260, 250)
    $note.MaximumSize = [System.Drawing.Size]::new(260, 250)
    $note.BackgroundImage = Get-GalorePostItImage -Name "PostitBackground.png"
    $note.BackgroundImageLayout = [System.Windows.Forms.ImageLayout]::None
    Set-GalorePostItRegion -Form $note -Bitmap $note.BackgroundImage
    Set-GalorePostItFixedLayout -Form $note -X $State.X -Y $State.Y
    $editor = New-Object System.Windows.Forms.TextBox
    $editor.Multiline = $true
    $editor.AcceptsReturn = $true
    $editor.AcceptsTab = $true
    $editor.ScrollBars = [System.Windows.Forms.ScrollBars]::None
    $editor.WordWrap = $true
    $editor.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $editor.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 20)
    $editor.ForeColor = [System.Drawing.Color]::White
    $editor.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $editor.Text = [string]$State.Text
    $editor.Bounds = New-Object System.Drawing.Rectangle(20, 31, 220, 195)
    $editor.Add_TextChanged({
        param($sender, $e)
        $measuredSize = [System.Windows.Forms.TextRenderer]::MeasureText($sender.Text, $sender.Font, (New-Object System.Drawing.Size($sender.ClientSize.Width, 0)), ([System.Windows.Forms.TextFormatFlags]::WordBreak -bor [System.Windows.Forms.TextFormatFlags]::TextBoxControl))
        if($measuredSize.Height -gt $sender.ClientSize.Height -and $sender.CanUndo) {
            $sender.Undo()
            $sender.ClearUndo()
        }
    })
    $closeBounds = New-Object System.Drawing.Rectangle(241, 7, 12, 12)
    $closeIcon = New-GalorePostItIconBitmap -Background $note.BackgroundImage -Bounds $closeBounds -DrawOverlay {
        param($graphics, [int]$width, [int]$height)
        $glyph = Get-GalorePostItImage -Name "close.png" -Width $width -Height $height
        $graphics.DrawImage($glyph, 0, 0, $width, $height)
        $glyph.Dispose()
    }
    $closeButton = New-Object System.Windows.Forms.PictureBox
    $closeButton.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Normal
    $closeButton.Cursor = [System.Windows.Forms.Cursors]::Hand
    $closeButton.Size = New-Object System.Drawing.Size(12, 12)
    $closeButton.Location = New-Object System.Drawing.Point(241, 7)
    $closeButton.Image = $closeIcon
    $uncheckedBounds = New-Object System.Drawing.Rectangle(14, 7, 18, 18)
    $uncheckedIcon = New-GalorePostItIconBitmap -Background $note.BackgroundImage -Bounds $uncheckedBounds -DrawOverlay {
        param($graphics, [int]$width, [int]$height)
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(150, 150, 150), 1.5)
        $graphics.DrawRectangle($pen, 2, 2, ([int]$width - 5), ([int]$height - 5))
        $pen.Dispose()
    }
    $checkedIcon = New-GalorePostItIconBitmap -Background $note.BackgroundImage -Bounds $uncheckedBounds -DrawOverlay {
        param($graphics, [int]$width, [int]$height)
        $boxPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(110, 210, 140), 1.5)
        $graphics.DrawRectangle($boxPen, 2, 2, ([int]$width - 5), ([int]$height - 5))
        $boxPen.Dispose()
        $checkPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(110, 210, 140), 2)
        $graphics.DrawLines($checkPen, @(
                (New-Object System.Drawing.Point(4, [int]($height / 2))), (New-Object System.Drawing.Point([int]([int]($width / 2) - 1), ([int]$height - 5))), (New-Object System.Drawing.Point(([int]$width - 4), 4))
            )
        )
        $checkPen.Dispose()
    }
    $completeBox = New-Object System.Windows.Forms.PictureBox
    $completeBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Normal
    $completeBox.Cursor = [System.Windows.Forms.Cursors]::Hand
    $completeBox.Size = New-Object System.Drawing.Size(18, 18)
    $completeBox.Location = New-Object System.Drawing.Point(14, 7)
    $completeBox.Image = if([bool]$State.Checked) { $checkedIcon } else { $uncheckedIcon }
    $dragHandle = New-Object System.Windows.Forms.Panel
    $dragHandle.BackColor = [System.Drawing.Color]::Transparent
    $dragHandle.Bounds = New-Object System.Drawing.Rectangle(34, 6, 205, 18)
    $note.Tag = [pscustomobject]@{
        Id = [string]$State.Id
        TextBox = $editor
        KeepInPersistence = $true
        Checked = [bool]$State.Checked
        IsDragging = $false
        DragOffset = [System.Drawing.Point]::Empty
    }
    $dragHandle.Add_MouseDown({
        param($sender, $e)
        Start-GalorePostItDrag -Sender $sender -Event $e
    })
    $dragHandle.Add_MouseMove({
        param($sender, $e)
        Move-GalorePostItDrag -Sender $sender -Event $e
    })
    $dragHandle.Add_MouseUp({
        param($sender, $e)
        Stop-GalorePostItDrag -Sender $sender
    })
    Set-GalorePostItCompletionStyle -Editor $editor -Checked ([bool]$State.Checked)
    $completeBox.Add_Click({
        param($sender, $e)
        if($null -eq $note -or $note.IsDisposed -or $null -eq $note.Tag) {
            return
        }
        $note.Tag.Checked = -not $note.Tag.Checked
        $sender.Image = if($note.Tag.Checked) { $checkedIcon } else { $uncheckedIcon }
        Set-GalorePostItCompletionStyle -Editor $editor -Checked ([bool]$note.Tag.Checked)
        Save-GalorePostIts
    }.GetNewClosure())
    $editor.Add_Leave({
        Save-GalorePostIts
    })
    $note.Add_Deactivate({
        Save-GalorePostIts
    })
    $closeButton.Add_Click({
        param($sender, $e)
        if($null -eq $note -or $note.IsDisposed -or $null -eq $note.Tag) {
            return
        }
        $note.Tag.KeepInPersistence = $false
        if($null -ne $script:GalorePostIts) {
            [void]$script:GalorePostIts.Remove($note)
        }
        Save-GalorePostIts
        $note.Close()
    }.GetNewClosure())
    $note.Add_FormClosed({
        param($sender, $e)
        if($null -ne $script:GalorePostIts -and $null -ne $sender) {
            [void]$script:GalorePostIts.Remove($sender)
        }
        if($null -ne $sender -and $sender.BackgroundImage) {
            $sender.BackgroundImage.Dispose()
            $sender.BackgroundImage = $null
        }
        if($null -ne $closeButton -and $closeButton.Image) {
            $closeButton.Image.Dispose()
            $closeButton.Image = $null
        }
        if($null -ne $completeBox) {
            $completeBox.Image = $null
        }
        if($null -ne $uncheckedIcon) {
            $uncheckedIcon.Dispose()
        }
        if($null -ne $checkedIcon) {
            $checkedIcon.Dispose()
        }
    }.GetNewClosure())
    $note.Controls.Add($editor)
    $note.Controls.Add($completeBox)
    $note.Controls.Add($dragHandle)
    $note.Controls.Add($closeButton)
    $note.Add_Shown({
        param($sender, $e)
        Set-GalorePostItFixedLayout -Form $sender -X $State.X -Y $State.Y
        $sender.BringToFront()
    }.GetNewClosure())
    [void]$script:GalorePostIts.Add($note)
    $note.Show()
    $note.BringToFront()
    return $note
}

function Restore-GalorePostIts {
    if($script:GalorePostItsRestored) {
        return
    }
    $script:GalorePostItsRestored = $true
    foreach($state in @(Read-GalorePostItStates)
    ) {
        try {
            New-GalorePostIt -State $state | Out-Null
        } catch {
            Write-LauncherDiagnostic -Exception $_ -Context "Failed to restore a Post-it."
        }
    }
}

function Initialize-GalorePostIts {
    param([System.Windows.Forms.Form]$Form)
    $settingsFolder = Get-LauncherSettingsFolder
    if([string]::IsNullOrWhiteSpace($settingsFolder)) {
        return
    }
    $script:GalorePostItStorePath = Join-Path $settingsFolder "postits.json"
    $legacyPostItStorePath = Join-Path $AppRoot "postits.json"
    if(-not (Test-Path -LiteralPath $script:GalorePostItStorePath -PathType Leaf) -and (Test-Path -LiteralPath $legacyPostItStorePath -PathType Leaf)) {
        try {
            Move-Item -LiteralPath $legacyPostItStorePath -Destination $script:GalorePostItStorePath -ErrorAction Stop
        } catch {
            Write-LauncherDiagnostic -Exception $_ -Context "Failed to move legacy Post-it state into Settings."
        }
    }
    $toolTip = New-Object System.Windows.Forms.ToolTip
    $postItButton = New-PostItButton
    $postItButton.Add_Click({
        $state = [pscustomobject]@{
            Id = [guid]::NewGuid().ToString("N")
            Text = ""
            X = -50000
            Y = -50000
            Checked = $false
        }
        New-GalorePostIt -State $state | Out-Null
        Save-GalorePostIts
    })
    $toolTip.SetToolTip($postItButton, "New Post-it")
    $Form.Controls.Add($postItButton)
    $Form.Add_Shown({
        param($sender, $e)
        if($null -eq $sender -or $sender.IsDisposed) {
            return
        }
        $restoreCallback = [System.Windows.Forms.MethodInvoker]{
            Restore-GalorePostIts
        }
        [void]$sender.BeginInvoke($restoreCallback)
    }.GetNewClosure())
}

function Stop-GalorePostItResources {
    if($script:GalorePostItShuttingDown) {
        return
    }
    $script:GalorePostItShuttingDown = $true
    foreach($note in @($script:GalorePostIts)) {
        if($null -ne $note -and -not $note.IsDisposed -and $null -ne $note.Tag -and $note.Tag.Checked) {
            $note.Tag.KeepInPersistence = $false
        }
    }
    Save-GalorePostIts
    foreach($note in @($script:GalorePostIts)
    ) {
        if($null -ne $note -and -not $note.IsDisposed) {
            $note.Close()
        }
    }
}
