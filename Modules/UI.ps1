# ============================================================
# UI.PS1
# GALORE LAUNCHER USER INTERFACE
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "UI"
    LoadOrder = 140
    RequiresModules = @("LauncherLogging")
    RequiresFunctions = [ordered]@{
        "Write-LauncherDiagnostic" = "LauncherLogging"
    }
    RequiresTypes = [ordered]@{}
    RequiresVariables = @("AppRoot", "EnvPaths")
    RequiresFolders = @("Resources")
    RequiresFiles = @(
        "Resources\background.png", "Resources\cmd.png",
        "Resources\taskmanager.png", "Resources\windows.png"
    )
    ProvidesTypes = @("WindowTheme")
}

# ============================================================
# STYLE BUTTON
# ============================================================

function Initialize-UIStyleColors {

    $script:Dark =
    [System.Drawing.Color]::FromArgb(
        25,
        25,
        25
    )

}

# ============================================================
# WINDOW THEME HELPERS
# ============================================================

if(
    -not (
        "WindowTheme" -as [type]
    )
)
{
    Add-Type @"

using System;
using System.Runtime.InteropServices;


public class WindowTheme
{


    [DllImport(
        "dwmapi.dll"
    )]
    public static extern int DwmSetWindowAttribute(
        IntPtr hwnd,
        int attr,
        ref int attrValue,
        int attrSize
    );


}

"@
}

# ============================================================
# LOAD CUSTOM ICON
# ============================================================

function Get-AppIcon {

    if(
        $EnvPaths.AppIcon -and
        (Test-Path $EnvPaths.AppIcon)
    ){

        try {

            return New-Object System.Drawing.Icon($EnvPaths.AppIcon)

        }

        catch {

            Write-LauncherDiagnostic `
            -Exception $_ `
            -Context "Failed to load application icon '$($EnvPaths.AppIcon)'."

            return $null

        }

    }

    return $null

}

# ============================================================
# APPLY BACKGROUND IMAGE
# ============================================================

function Apply-Background {

param(
    $Window
)

$backgroundPath =
Get-GaloreResourcePath `
"background.png"

if(
    Test-Path $backgroundPath
){

    try {

        $image =
        [System.Drawing.Image]::FromFile(
            $backgroundPath
        )

        $Window.BackgroundImage =
        $image

        $Window.BackgroundImageLayout =
        [System.Windows.Forms.ImageLayout]::Stretch

        $Window.Add_Disposed({

            $backgroundImage =
            $this.BackgroundImage

            if(
                $backgroundImage
            )
            {

                $this.BackgroundImage =
                $null

                $backgroundImage.Dispose()

            }

        })

        if(
            [System.Drawing.ImageAnimator]::CanAnimate($image)
        )
        {

            $gifState = [PSCustomObject]@{

                Image = $image

                FrameDimension =
                [System.Drawing.Imaging.FrameDimension]::Time

                Frame = 0

                Count =
                $image.GetFrameCount(
                    [System.Drawing.Imaging.FrameDimension]::Time
                )

                Window = $Window

            }

            $gifTimer =
            New-Object System.Windows.Forms.Timer

            $property =
            $gifState.Image.GetPropertyItem(
                0x5100
            )

            $gifDelays = @()

            for(
                $i = 0;
                $i -lt $gifState.Count;
                $i++
            )
            {

                $delay =
                [BitConverter]::ToInt32(
                    $property.Value,
                    $i * 4
                )

                $gifDelays +=
                ($delay * 10)

            }

            $gifState | Add-Member `
                -MemberType NoteProperty `
                -Name Delays `
                -Value $gifDelays

            $gifTimer.Interval =
            $gifState.Delays[0]

            $gifTimer.Add_Tick({

                if(
                    $gifState.Image -and
                    $gifState.Window
                )
                {

                    try {

                        $gifState.Image.SelectActiveFrame(
                            $gifState.FrameDimension,
                            $gifState.Frame
                        )

                        $gifState.Window.BackgroundImage =
                        $gifState.Image

                        $gifState.Window.Invalidate()

                        $gifState.Frame++

                        if(
                            $gifState.Frame -ge $gifState.Count
                        )
                        {

                            $gifState.Frame = 0

                        }

                    }

                    catch {

                    }

                }

            })

            $gifTimer.Start()

            $script:GifTimer = $gifTimer

            $script:GifState = $gifState

        }

    }

    catch {

        Write-LauncherDiagnostic `
        -Exception $_ `
        -Context "Failed to load background image '$backgroundPath'."

        $Window.BackColor =
        $Dark

    }

}

else {

    $Window.BackColor =
    $Dark

}

}

# ============================================================
# RESOURCE ICON LOADER
# ============================================================

function Get-ResourceIcon {

param(
    [string]$Name
)

if(
    [string]::IsNullOrWhiteSpace($Name)
){

    return $null

}

$path = if(Get-Command -Name Get-GaloreResourcePath -ErrorAction SilentlyContinue) { Get-GaloreResourcePath $Name } else { Join-Path $AppRoot "resources\$Name" }

if(Test-Path $path){

    return [System.Drawing.Image]::FromFile($path)

}

return $null

}

# ==========================
# ICON BUTTON CREATOR
# ==========================

function New-IconButton {

param(
    [string]$IconName
)

$button =
New-Object System.Windows.Forms.Button

$button.Width  = 40
$button.Height = 40

$button.FlatStyle =
[System.Windows.Forms.FlatStyle]::Flat

$button.FlatAppearance.BorderSize = 0

$button.BackColor =
[System.Drawing.Color]::Transparent

$button.UseVisualStyleBackColor =
$false

$button.FlatAppearance.MouseOverBackColor =
[System.Drawing.Color]::FromArgb(
    20,
    255,
    255,
    255
)

$button.FlatAppearance.MouseDownBackColor =
[System.Drawing.Color]::FromArgb(
    100,
    255,
    255,
    255
)

$image =
Get-ResourceIcon $IconName

if($image)
{

    try
    {

        $button.Image =
        New-Object System.Drawing.Bitmap(
            $image,
            26,
            26
        )

    }
    finally
    {

        $image.Dispose()

    }

}

$button.Add_Disposed({

    $ownedImage =
    $this.Image

    if(
        $ownedImage
    )
    {

        $this.Image =
        $null

        $ownedImage.Dispose()

    }

})

return $button

}

# ==========================
# WINDOW BUTTON CREATOR
# ==========================

function New-WindowButton {

param(
    $IconName
)

$button =
New-IconButton `
-IconName $IconName

return $button

}

# ============================================================
# STYLE BUTTON
# ============================================================

function Style-Button {

param(
    $button
)

$button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat

$button.FlatAppearance.BorderSize = 0

$button.UseVisualStyleBackColor = $false

$button.BackColor = [System.Drawing.Color]::Black

$button.ForeColor = [System.Drawing.Color]::White

$button.Size = New-Object System.Drawing.Size(
    170,
    35
)

$button.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter

$button.Font = New-Object System.Drawing.Font(
    $button.Font.FontFamily,
    $button.Font.Size,
    [System.Drawing.FontStyle]::Bold
)

}

# ==========================
# MULTI-TASK BAR FUNCTION
# ==========================

function New-TaskbarFolderButton {

param(
    [System.Windows.Forms.Control]$Parent,
    [int]$X,
    [string]$Icon,
    [string]$Folder,
    [string]$Tooltip
)

if(
    -not (
        Test-Path variable:script:FolderToolTip
    )
)
{

    $script:FolderToolTip =
    New-Object System.Windows.Forms.ToolTip

    $script:FolderToolTip.InitialDelay = 1000
    $script:FolderToolTip.ReshowDelay  = 200
    $script:FolderToolTip.AutoPopDelay = 5000
    $script:FolderToolTip.ShowAlways   = $true

}

$button =
New-IconButton `
-IconName $Icon

$button.Location =
New-Object System.Drawing.Point(
    $X,
    0
)

$button.Tag =
$Folder

$button.ImageAlign =
[System.Drawing.ContentAlignment]::MiddleCenter

$button.Text = ""

$button.UseVisualStyleBackColor = $false

$script:FolderToolTip.SetToolTip(
    $button,
    $Tooltip
)

$button.Add_Click({

    param($sender,$e)

    Invoke-Item `
    -LiteralPath $sender.Tag

})

$button.AllowDrop =
$true

$button.Add_DragEnter({

    param($sender,$e)

    if(
        $e.Data.GetDataPresent(
            [System.Windows.Forms.DataFormats]::FileDrop
        )
    )
    {

        $e.Effect =
        [System.Windows.Forms.DragDropEffects]::Move

    }
    else
    {

        $e.Effect =
        [System.Windows.Forms.DragDropEffects]::None

    }

})

$button.Add_DragOver({

    param($sender,$e)

    $e.Effect =
    [System.Windows.Forms.DragDropEffects]::Move

})

$button.Add_DragDrop({

    param($sender,$e)

    try
    {

        $folder =
        [string]$sender.Tag

        if(
            -not (Test-Path $folder)
        )
        {

            return

        }

        $files =
        $e.Data.GetData(
            [System.Windows.Forms.DataFormats]::FileDrop,
            $true
        )

        if(
            -not $files
        )
        {

            return

        }

        foreach(
            $file in $files
        )
        {

            $destination =
            Join-Path `
            $folder `
            ([System.IO.Path]::GetFileName($file))

            Move-Item `
                -LiteralPath $file `
                -Destination $destination `
                -Force `
                -ErrorAction Stop

        }

    }
    catch
    {

        Write-LauncherDiagnostic `
        -Exception $_ `
        -Context "Failed to move dropped item into taskbar folder '$folder'."

    }

})

$Parent.Controls.Add(
    $button
)

return $button

}

# ============================================================
# PROGRAM CHECKBOX CREATOR
# ============================================================

function New-ProgramCheckbox {

param(
    [string]$Name,
    [int]$X,
    [int]$Y
)

$box =
New-Object System.Windows.Forms.CheckBox

$box.Appearance =
[System.Windows.Forms.Appearance]::Normal

$box.FlatStyle =
[System.Windows.Forms.FlatStyle]::Flat

$box.UseVisualStyleBackColor =
$false

$box.BackColor =
[System.Drawing.Color]::Transparent

$box.ForeColor =
[System.Drawing.Color]::Black

$box.Font =
New-Object System.Drawing.Font(
    $box.Font.FontFamily,
    $box.Font.Size,
    [System.Drawing.FontStyle]::Bold
)

$box.Text =
$Name

$box.Location =
New-Object System.Drawing.Point(
    $X,
    $Y
)

$box.Size =
New-Object System.Drawing.Size(
    200,
    25
)

# ==========================
# COLOR UPDATE
# ==========================

$updateColor = {

    if($this.Checked)
    {

        $this.ForeColor =
        [System.Drawing.Color]::Red

    }
    else
    {

        $this.ForeColor =
        [System.Drawing.Color]::Black

    }

}

# ==========================
# HOVER EFFECT
# ==========================

$box.Add_MouseEnter({

    $this.ForeColor =
    [System.Drawing.Color]::Red

})

$box.Add_MouseLeave(
    $updateColor
)

# ==========================
# SELECTED EFFECT
# ==========================

$box.Add_CheckedChanged(
    $updateColor
)

return $box

}

# ============================================================
# PROGRAM STATUS LABEL CREATOR
# ============================================================

function New-ProgramStatusLabel {

param(
    [string]$Text,
    [int]$X,
    [int]$Y
)

$label =
New-Object System.Windows.Forms.Label

$label.AutoSize = $false

$label.Width = 200

$label.Height = 25

$label.Location =
New-Object System.Drawing.Point(
    $X,
    $Y
)

$label.TextAlign =
[System.Drawing.ContentAlignment]::MiddleLeft

$label.Font =
New-Object System.Drawing.Font(
    "Segoe UI",
    9,
    [System.Drawing.FontStyle]::Bold
)

$label.ForeColor =
[System.Drawing.Color]::Black

$label.BackColor =
[System.Drawing.Color]::Transparent

$label.Text =
$Text

return $label

}

# ==========================
# IMAGE PANEL CREATOR
# ==========================

function New-ImagePanel {

param(
    [string]$IconName,
    [int]$X,
    [int]$Y,
    [int]$PanelWidth,
    [int]$PanelHeight,
    [int]$ImageWidth,
    [int]$ImageHeight
)

$panel =
New-Object System.Windows.Forms.Panel

$panel.Width  = $PanelWidth
$panel.Height = $PanelHeight

$panel.Location =
New-Object System.Drawing.Point(
    $X,
    $Y
)

$panel.BackColor =
[System.Drawing.Color]::Transparent

$image =
Get-ResourceIcon $IconName

if($null -ne $image)
{

    try
    {

        $bitmap =
        New-Object System.Drawing.Bitmap(
            $image,
            $ImageWidth,
            $ImageHeight
        )

    }
    finally
    {

        $image.Dispose()

    }

    $panel.Tag = $bitmap

}

$panel.Add_Disposed({

    $ownedImage =
    $this.Tag

    if(
        $ownedImage -is [System.Drawing.Image]
    )
    {

        $this.Tag =
        $null

        $ownedImage.Dispose()

    }

})

$panel.Add_Paint({

    $bitmap = $this.Tag

    if($null -eq $bitmap)
    {
        return
    }

    $_.Graphics.DrawImage(
        $bitmap,
        0,
        0,
        $bitmap.Width,
        $bitmap.Height
    )

})

return $panel

}

# ==========================
# TASK MANAGER ICON
# ==========================

function New-TaskManagerButton {

    New-ImagePanel `
        -IconName "taskmanager.png" `
        -X 907 `
        -Y 499 `
        -PanelWidth 30 `
        -PanelHeight 30 `
        -ImageWidth 30 `
        -ImageHeight 30

}

# ==========================
# CMD ADMIN ICON
# ==========================

function New-CmdButton {

    New-ImagePanel `
        -IconName "cmd.png" `
        -X 942 `
        -Y 499 `
        -PanelWidth 30 `
        -PanelHeight 30 `
        -ImageWidth 30 `
        -ImageHeight 30

}

# ==========================
# INTERNET ICON
# ==========================

function New-InternetButton {

    New-ImagePanel `
        -IconName "internet.png" `
        -X 5 `
        -Y 45 `
        -PanelWidth 30 `
        -PanelHeight 30 `
        -ImageWidth 30 `
        -ImageHeight 30

}

# ==========================
# VOLUME ICON
# ==========================

function New-VolumeButton {

    New-ImagePanel `
        -IconName "volume.png" `
        -X 40 `
        -Y 45 `
        -PanelWidth 30 `
        -PanelHeight 30 `
        -ImageWidth 30 `
        -ImageHeight 30

}

# ==========================
# KEYBOARD LANGUAGE ICON
# ==========================

function New-KeyboardLanguageButton {

    New-ImagePanel `
        -IconName "keyboard.png" `
        -X 75 `
        -Y 45 `
        -PanelWidth 30 `
        -PanelHeight 30 `
        -ImageWidth 30 `
        -ImageHeight 30

}

# ==========================
# POST-IT ICON
# ==========================

function New-PostItButton {

    New-ImagePanel `
        -IconName "postit.png" `
        -X 110 `
        -Y 45 `
        -PanelWidth 30 `
        -PanelHeight 30 `
        -ImageWidth 30 `
        -ImageHeight 30

}

# ==========================
# CALCULATOR ICON
# ==========================

function New-CalculatorButton {

    New-ImagePanel `
        -IconName "Calculator.png" `
        -X 145 `
        -Y 45 `
        -PanelWidth 30 `
        -PanelHeight 30 `
        -ImageWidth 30 `
        -ImageHeight 30

}

# ==========================
# WINDOWS START ICON
# ==========================

function New-WindowsStartButton {

    $windowsButton =
    New-Object System.Windows.Forms.Panel

    $windowsButton.Width = 180
    $windowsButton.Height = 180

    $windowsButton.Location =
    New-Object System.Drawing.Point(
        902,
        108
    )

    $windowsButton.BackColor =
    [System.Drawing.Color]::Transparent

    # ==========================
    # LOAD WINDOWS ICON
    # ==========================

    $windowsImage =
    Get-ResourceIcon "windows.png"

    if($null -ne $windowsImage)
    {
        try
        {

            $windowsBitmap =
            New-Object System.Drawing.Bitmap(
                $windowsImage,
                $windowsButton.Width,
                $windowsButton.Height
            )

        }
        finally
        {

            $windowsImage.Dispose()

        }

        $windowsButton.Tag = $windowsBitmap
    }

    $windowsButton.Add_Disposed({

        $ownedImage =
        $this.Tag

        if(
            $ownedImage -is [System.Drawing.Image]
        )
        {

            $this.Tag =
            $null

            $ownedImage.Dispose()

        }

    })

    # ==========================
    # ENABLE DOUBLE BUFFER
    # ==========================

    $doubleBufferProperty =
    $windowsButton.GetType().GetProperty(
        "DoubleBuffered",
        [System.Reflection.BindingFlags] "Instance,NonPublic"
    )

    $doubleBufferProperty.SetValue(
        $windowsButton,
        $true,
        $null
    )

    $script:WindowsRotation = 0

    $windowsButton.Add_Paint({

        $thisBitmap = $this.Tag

        if($null -eq $thisBitmap)
        {
            return
        }

        $g = $_.Graphics

        $g.SmoothingMode =
        [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

        $g.InterpolationMode =
        [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

        $g.PixelOffsetMode =
        [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

        $centerX = $this.Width / 2
        $centerY = $this.Height / 2

        $g.TranslateTransform(
            $centerX,
            $centerY
        )

        $g.RotateTransform(
            $script:WindowsRotation
        )

        $g.DrawImage(
            $thisBitmap,
            -$centerX,
            -$centerY,
            $this.Width,
            $this.Height
        )

        $g.ResetTransform()

    })

    $windowsTimer =
    New-Object System.Windows.Forms.Timer

    $windowsTimer.Interval = 60

    $windowsTimer.Add_Tick({

        $script:WindowsRotation += 0.2

        if($script:WindowsRotation -ge 360)
        {
            $script:WindowsRotation = 0
        }

        $windowsButton.Invalidate()

    })

    $windowsTimer.Start()

    return @{
        Button = $windowsButton
        Timer  = $windowsTimer
    }

}

# ============================================================
# WINDOW OPACITY ANIMATION
# ============================================================

function Start-WindowOpacityAnimation {

param(
    [System.Windows.Forms.Form]$Form,
    [double]$TargetOpacity,
    [int]$DurationMilliseconds = 160,
    [switch]$HideOnComplete
)

if(
    $null -eq $Form -or
    $Form.IsDisposed
)
{

    return

}

if(
    $script:WindowFadeTimer
)
{

    $script:WindowFadeTimer.Stop()

    $script:WindowFadeTimer.Tag =
    $null

    $script:WindowFadeTimer.Dispose()

    $script:WindowFadeTimer = $null

}

$target =
[Math]::Max(
    0.0,
    [Math]::Min(
        1.0,
        $TargetOpacity
    )
)

if(
    $DurationMilliseconds -le 0
)
{

    $Form.Opacity =
    $target

    if(
        $HideOnComplete
    )
    {

        $Form.Hide()

        $Form.Opacity =
        1

    }

    return

}

$fadeTimer =
New-Object System.Windows.Forms.Timer

$fadeTimer.Interval =
15

$fadeTimer.Tag =
[PSCustomObject]@{

    Form =
    $Form

    StartOpacity =
    [double]$Form.Opacity

    TargetOpacity =
    $target

    DurationMilliseconds =
    $DurationMilliseconds

    Stopwatch =
    [System.Diagnostics.Stopwatch]::StartNew()

    HideOnComplete =
    [bool]$HideOnComplete

}

$fadeTimer.Add_Tick({

    $timer = $this

    $state =
    $timer.Tag

    if(
        $null -eq $state -or
        $null -eq $state.Form -or
        $state.Form.IsDisposed
    )
    {

        $timer.Stop()

        $timer.Dispose()

        if(
            $script:WindowFadeTimer -eq $timer
        )
        {

            $script:WindowFadeTimer = $null

        }

        return

    }

    $progress =
    [Math]::Min(
        1.0,
        (
            $state.Stopwatch.Elapsed.TotalMilliseconds /
            $state.DurationMilliseconds
        )
    )

    $easedProgress =
    $progress * $progress * (
        3 -
        (2 * $progress)
    )

    $state.Form.Opacity =
    $state.StartOpacity +
    (
        (
            $state.TargetOpacity -
            $state.StartOpacity
        ) *
        $easedProgress
    )

    if(
        $progress -ge 1
    )
    {

        $state.Form.Opacity =
        $state.TargetOpacity

        $timer.Stop()

        $timer.Tag =
        $null

        if(
            $script:WindowFadeTimer -eq $timer
        )
        {

            $script:WindowFadeTimer = $null

        }

        $timer.Dispose()

        if(
            $state.HideOnComplete -and
            -not $state.Form.IsDisposed
        )
        {

            $state.Form.Hide()

            $state.Form.Opacity =
            1

        }

    }

})

$script:WindowFadeTimer = $fadeTimer

$fadeTimer.Start()

}

# ============================================================
# SHOW LAUNCHER WINDOW SMOOTHLY
# ============================================================

function Show-LauncherWindowAnimated {

param(
    [System.Windows.Forms.Form]$Form,
    [int]$DurationMilliseconds = 170
)

if(
    $null -eq $Form -or
    $Form.IsDisposed
)
{

    return

}

$script:LauncherWindowTargetVisible = $true

if(
    -not $Form.Visible
)
{

    $Form.Opacity =
    0

}

$Form.WindowState =
[System.Windows.Forms.FormWindowState]::Normal

$Form.ShowInTaskbar =
$true

$Form.Show()

if(
    Get-Command `
    Show-GaloreLauncherOverlayBars `
    -ErrorAction SilentlyContinue
)
{

    Show-GaloreLauncherOverlayBars `
    -DurationMilliseconds $DurationMilliseconds

}

$Form.BringToFront()

$Form.Activate()

Start-WindowOpacityAnimation `
-Form $Form `
-TargetOpacity 1 `
-DurationMilliseconds $DurationMilliseconds

}

# ============================================================
# HIDE LAUNCHER WINDOW SMOOTHLY
# ============================================================

function Hide-LauncherWindowAnimated {

param(
    [System.Windows.Forms.Form]$Form,
    [int]$DurationMilliseconds = 130
)

if(
    $null -eq $Form -or
    $Form.IsDisposed
)
{

    return

}

$script:LauncherWindowTargetVisible = $false

if(
    -not $Form.Visible
)
{

    $Form.Opacity =
    1

    return

}

if(
    Get-Command `
    Hide-GaloreLauncherOverlayBars `
    -ErrorAction SilentlyContinue
)
{

    Hide-GaloreLauncherOverlayBars `
    -DurationMilliseconds $DurationMilliseconds

}

Start-WindowOpacityAnimation `
-Form $Form `
-TargetOpacity 0 `
-DurationMilliseconds $DurationMilliseconds `
-HideOnComplete

}

# ============================================================
# STOP UI RESOURCES
# ============================================================

function Stop-UIResources {

param(
    [System.Windows.Forms.Form]$Form
)

if(
    $script:WindowFadeTimer
)
{

    $script:WindowFadeTimer.Stop()

    $script:WindowFadeTimer.Tag =
    $null

    $script:WindowFadeTimer.Dispose()

    $script:WindowFadeTimer = $null

}

if(
    $Form -and
    -not $Form.IsDisposed
)
{

    $Form.Opacity =
    1

}

if(
    $script:GifTimer
)
{

    $script:GifTimer.Stop()

    $script:GifTimer.Dispose()

    $script:GifTimer = $null

}

$script:GifState = $null

if(
    $script:FolderToolTip
)
{

    $script:FolderToolTip.Dispose()

    $script:FolderToolTip = $null

}

if(
    $Form -and
    -not $Form.IsDisposed -and
    $Form.BackgroundImage
)
{

    $backgroundImage =
    $Form.BackgroundImage

    $Form.BackgroundImage =
    $null

    $backgroundImage.Dispose()

}

}
