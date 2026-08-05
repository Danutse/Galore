# ============================================================
# PROGRAM WINDOW UI
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "ProgramWindowUI"
    LoadOrder = 160
    RequiresModules = @("LauncherDesktop", "LauncherSettings", "LauncherStartMenu", "UI")
    RequiresFunctions = [ordered]@{
        "New-CloseButton" = "LauncherDesktop"
        "New-MaximizeButton" = "LauncherDesktop"
        "New-MinimizeButton" = "LauncherDesktop"
        "Load-WindowSettings" = "LauncherSettings"
        "Close-StartSearchWindowAnimated" = "LauncherStartMenu"
        "Apply-Background" = "UI"
        "Get-AppIcon" = "UI"
        "Get-ResourceIcon" = "UI"
        "Hide-LauncherWindowAnimated" = "UI"
        "New-CmdButton" = "UI"
        "New-TaskManagerButton" = "UI"
        "Start-WindowOpacityAnimation" = "UI"
    }
    RequiresTypes = [ordered]@{
        "WindowTheme" = "UI"
    }
    RequiresVariables = @()
    RequiresFolders = @("Resources")
    RequiresFiles = @("Resources\searchbackground.png", "Resources\titlebar.png")
    ProvidesTypes = @("WindowMove")
}

function New-ProgramWindow {

    # ============================================================
    # FORM
    # ============================================================

    $form =
    New-Object System.Windows.Forms.Form

    $form.GetType().GetProperty(
        "DoubleBuffered",
        [System.Reflection.BindingFlags]"Instance,NonPublic"
    ).SetValue(
        $form,
        $true,
        $null
    )

    $darkMode = 1

    [WindowTheme]::DwmSetWindowAttribute(
        $form.Handle,
        20,
        [ref]$darkMode,
        4
    ) | Out-Null

    $black = 0

    [WindowTheme]::DwmSetWindowAttribute(
        $form.Handle,
        35,
        [ref]$black,
        4
    ) | Out-Null

    $form.Text =
    "Program Manager"

    $windowSettings =
    Load-WindowSettings

    $form.Size =
    New-Object System.Drawing.Size(
        1100,
        550
    )

    $form.MinimumSize =
    $form.Size

    $form.MaximumSize =
    $form.Size

    if(
        $windowSettings -and
        $null -ne $windowSettings.X -and
        $null -ne $windowSettings.Y
    )
    {

        $form.StartPosition =
        "Manual"

        $form.Location =
        New-Object System.Drawing.Point(
            $windowSettings.X,
            $windowSettings.Y
        )

    }

    else
    {

        $form.StartPosition =
        "CenterScreen"

    }

    Apply-Background `
    $form

    # ============================================================
    # RETURN FORM
    # ============================================================

    return $form

}

# ============================================================
# INITIALIZE LAUNCHER WINDOW STATE
# ============================================================

function Initialize-LauncherWindowState {

    param(
        $Form
    )

    $script:LauncherLocation =
    $Form.Location

    $script:LauncherSize =
    $Form.Size

}

# ============================================================
# CLOCK LABEL
# ============================================================

function New-ClockLabel {

    $clockLabel =
    New-Object System.Windows.Forms.Label

    $clockLabel.AutoSize =
    $false

    $clockLabel.Width =
    165

    $clockLabel.Height =
    35

    $clockLabel.TextAlign =
    [System.Drawing.ContentAlignment]::MiddleRight

    $clockLabel.Font =
    New-Object System.Drawing.Font(
        "Segoe UI",
        24,
        [System.Drawing.FontStyle]::Bold
    )

    $clockLabel.ForeColor =
    [System.Drawing.Color]::White

    $clockLabel.BackColor =
    [System.Drawing.Color]::Transparent

    $clockLabel.Location =
    New-Object System.Drawing.Point(
        895,
        44
    )

    $clockLabel.Text =
    (Get-Date).ToString(
        "HH:mm:ss"
    )

    return $clockLabel

}

# ============================================================
# DATE CALENDAR LABEL
# ============================================================

function New-DateCalendarLabel {

    $dateLabel =
    New-Object System.Windows.Forms.Label

    $dateLabel.AutoSize =
    $false

    $dateLabel.Size =
    [System.Drawing.Size]::new(165, 20)

    $dateLabel.TextAlign =
    [System.Drawing.ContentAlignment]::MiddleRight

    $dateLabel.Font =
    New-Object System.Drawing.Font(
        "Segoe UI",
        10,
        [System.Drawing.FontStyle]::Bold
    )

    $dateLabel.ForeColor =
    [System.Drawing.Color]::Gainsboro

    $dateLabel.BackColor =
    [System.Drawing.Color]::Transparent

    $dateLabel.Location =
    [System.Drawing.Point]::new(889, 80)

    $dateLabel.Text =
    (Get-Date).ToString("yyyy / MMMM / dd")

    return $dateLabel

}

# ============================================================
# PROGRAM TITLE BAR
# ============================================================

function New-ProgramTitleBar {

param(
    $Form
)

# ============================================================
# REMOVE WINDOWS TITLE BAR
# ============================================================

$Form.FormBorderStyle =
[System.Windows.Forms.FormBorderStyle]::None

# ==========================
# REDUCE STARTUP FLICKER
# ==========================

$Form.GetType().GetProperty(
    "DoubleBuffered",
    [System.Reflection.BindingFlags]"Instance,NonPublic"
).SetValue(
    $Form,
    $true,
    $null
)

$Form.SuspendLayout()

$Form.WindowState =
[System.Windows.Forms.FormWindowState]::Normal

# ==========================
# CREATE TITLE BAR
# ==========================

$titleBar =
New-Object System.Windows.Forms.Panel

$titleBar.Name =
"ProgramTitleBar"

$titleBar.GetType().GetProperty(
    "DoubleBuffered",
    [System.Reflection.BindingFlags]"Instance,NonPublic"
).SetValue(
    $titleBar,
    $true,
    $null
)

$titleBar.Height =
40

$titleBar.Width =
$Form.ClientSize.Width

$titleBar.Location =
New-Object System.Drawing.Point(
    0,
    0
)

$titleBar.Anchor =
[System.Windows.Forms.AnchorStyles]::Top -bor
[System.Windows.Forms.AnchorStyles]::Left -bor
[System.Windows.Forms.AnchorStyles]::Right

$titleBar.BackColor =
[System.Drawing.Color]::FromArgb(
    5,
    5,
    5
)

$titleBarImage =
Get-ResourceIcon `
"titlebar.png"

if(
    $titleBarImage
)
{

    try
    {

        $titleBar.BackgroundImage =
        New-Object System.Drawing.Bitmap(
            $titleBarImage
        )

    }
    finally
    {

        $titleBarImage.Dispose()

    }

    $titleBar.BackgroundImageLayout =
    [System.Windows.Forms.ImageLayout]::Stretch

    $titleBar.Add_Disposed({

        $ownedImage =
        $this.BackgroundImage

        if(
            $ownedImage
        )
        {

            $this.BackgroundImage =
            $null

            $ownedImage.Dispose()

        }

    })

}

return $titleBar

}

# ============================================================
# SYSTEM MONITOR PANEL
# ============================================================

function New-SystemMonitorPanel {

    $systemPanel =
    New-Object System.Windows.Forms.Panel

    $systemPanel.GetType().GetProperty(
        "DoubleBuffered",
        [System.Reflection.BindingFlags]"Instance,NonPublic"
    ).SetValue(
        $systemPanel,
        $true,
        $null
    )

    $systemPanel.Width =
    220

    $systemPanel.Height =
    80

    $systemPanel.Anchor =
    [System.Windows.Forms.AnchorStyles]::Bottom -bor
    [System.Windows.Forms.AnchorStyles]::Right

    $systemPanel.Location =
    New-Object System.Drawing.Point(
        850,
        425
    )

    $systemPanel.BackColor =
    [System.Drawing.Color]::Transparent

    # ==========================
    # CREATE LABELS
    # ==========================

    $labels =
    1..4 | ForEach-Object {

        New-Object System.Windows.Forms.Label

    }

    $cpuLabel     = $labels[0]
    $ramLabel     = $labels[1]
    $gpuLabel     = $labels[2]
    $gpuTempLabel = $labels[3]

    $y = 0

    foreach($label in $labels)
    {

        $label.AutoSize =
        $false

        $label.Width =
        220

        $label.Height =
        20

        $label.Location =
        New-Object System.Drawing.Point(
            0,
            $y
        )

        $label.ForeColor =
        [System.Drawing.Color]::White

        $label.BackColor =
        [System.Drawing.Color]::Transparent

        $label.TextAlign =
        [System.Drawing.ContentAlignment]::MiddleRight

        $label.Font =
        New-Object System.Drawing.Font(
            "Segoe UI",
            9,
            [System.Drawing.FontStyle]::Bold
        )

        $label.Cursor =
        [System.Windows.Forms.Cursors]::Hand

        $systemPanel.Controls.Add(
            $label
        )

        $y += 20

    }

    return @{

        Panel =
        $systemPanel

        CPU =
        $cpuLabel

        RAM =
        $ramLabel

        GPU =
        $gpuLabel

        GPUTemp =
        $gpuTempLabel

    }

}

# ============================================================
# EMBEDDED SEARCH PANEL UI
# ============================================================

function New-SearchPanelUI {

param(
    [System.Windows.Forms.Form]$Form
)

$searchPanel =
New-Object System.Windows.Forms.Panel

$searchPanel.Name =
"StartSearchPanel"

$searchPanel.AccessibleName =
"StartSearchPanel"

$searchPanel.GetType().GetProperty(
    "DoubleBuffered",
    [System.Reflection.BindingFlags]"Instance,NonPublic"
).SetValue(
    $searchPanel,
    $true,
    $null
)

$searchPanel.Visible =
$false

$searchTop = 40

$programTitleBar =
$Form.Controls["ProgramTitleBar"]

if(
    $programTitleBar
)
{

    $searchTop =
    $programTitleBar.Bottom

}

$searchPanel.Width =
350

$searchPanel.Height =
[Math]::Max(
    0,
    (
        $Form.ClientSize.Height -
        $searchTop
    )
)

$searchPanel.Location =
New-Object System.Drawing.Point(
    $Form.ClientSize.Width,
    $searchTop
)

$searchPanel.Anchor =
[System.Windows.Forms.AnchorStyles]::Top -bor
[System.Windows.Forms.AnchorStyles]::Bottom -bor
[System.Windows.Forms.AnchorStyles]::Right

$searchPanel.BackColor =
[System.Drawing.Color]::FromArgb(
    25,
    25,
    25
)

# ==========================
# CUSTOM BACKGROUND
# ==========================

$searchBackground =
Get-GaloreResourcePath `
"searchbackground.png"

if(
    Test-Path $searchBackground
)
{

    $searchImage =
    [System.Drawing.Image]::FromFile(
        $searchBackground
    )

    $searchPanel.BackgroundImage =
    $searchImage

    $searchPanel.BackgroundImageLayout =
    [System.Windows.Forms.ImageLayout]::Stretch

    $searchPanel.Add_Disposed({

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

}

$Form.Controls.Add(
    $searchPanel
)

return $searchPanel

}

# ============================================================
# SEARCH BOX
# ============================================================

function New-SearchBox {

param(
    [System.Windows.Forms.Panel]$SearchPanel
)

$searchBox =
New-Object System.Windows.Forms.TextBox

$searchBox.Width =
(
    $SearchPanel.ClientSize.Width -
    50
)

$searchBox.Height =
35

$searchBox.Location =
New-Object System.Drawing.Point(
    25,
    ($SearchPanel.ClientSize.Height - 45)
)

$searchBox.Font =
New-Object System.Drawing.Font(
    "Segoe UI",
    12
)

$searchBox.BackColor =
[System.Drawing.Color]::FromArgb(
    40,
    40,
    40
)

$searchBox.ForeColor =
[System.Drawing.Color]::White

$searchBox.BorderStyle =
[System.Windows.Forms.BorderStyle]::FixedSingle

$searchBox.Anchor =
[System.Windows.Forms.AnchorStyles]::Bottom -bor
[System.Windows.Forms.AnchorStyles]::Left -bor
[System.Windows.Forms.AnchorStyles]::Right

$SearchPanel.Controls.Add(
    $searchBox
)

return $searchBox

}

# ============================================================
# SEARCH RESULTS PANEL
# ============================================================

function New-SearchResultsPanel {

param(
    [System.Windows.Forms.Panel]$SearchPanel
)

$searchResults =
New-Object System.Windows.Forms.FlowLayoutPanel

$searchResults.Location =
New-Object System.Drawing.Point(
    0,
    0
)

$searchResults.Width =
$SearchPanel.ClientSize.Width

$searchResults.Height =
(
    $SearchPanel.ClientSize.Height - 55
)

$searchResults.Anchor =
"Top,Bottom,Left,Right"

$searchResults.FlowDirection =
[System.Windows.Forms.FlowDirection]::TopDown

$searchResults.WrapContents =
$false

$searchResults.AutoScroll =
$true

$searchResults.BackColor =
[System.Drawing.Color]::Transparent

$searchResults.Padding =
New-Object System.Windows.Forms.Padding(
    5,
    5,
    5,
    5
)

$SearchPanel.Controls.Add(
    $searchResults
)

return $searchResults

}

# ==========================
# WINDOW CONTROL BUTTONS
# ==========================

# ==========================
# TITLE BAR BUTTON HELPER
# ==========================

function Initialize-TitleBarButton {

param(
    [System.Windows.Forms.Control]$Button,
    [scriptblock]$ClickAction
)

$Button.Add_Click(
    $ClickAction
)

$Button.Dock =
[System.Windows.Forms.DockStyle]::Right

$titleBar.Controls.Add(
    $Button
)

}

# ==========================
# MINIMIZE BUTTON
# ==========================

function Initialize-MinimizeButton {

$minimizeButton =
New-MinimizeButton

Initialize-TitleBarButton `
-Button $minimizeButton `
-ClickAction {

    $script:LauncherSize =
    $form.Size

    $script:LauncherLocation =
    $form.Location

    $form.WindowState =
    [System.Windows.Forms.FormWindowState]::Minimized

}

}

# ==========================
# MAXIMIZE BUTTON
# ==========================

function Initialize-MaximizeButton {

$maximizeButton =
New-MaximizeButton

Initialize-TitleBarButton `
-Button $maximizeButton `
-ClickAction {

    $form.WindowState =
    [System.Windows.Forms.FormWindowState]::Normal

}

}

# ==========================
# CLOSE BUTTON
# ==========================

function Initialize-CloseButton {

$closeButton =
New-CloseButton

Initialize-TitleBarButton `
-Button $closeButton `
-ClickAction {

    $script:LauncherSize =
    $form.Size

    $script:LauncherLocation =
    $form.Location

    # ==========================
    # CLOSE SEARCH WINDOW
    # ==========================

    Close-StartSearchWindowAnimated

    Hide-LauncherWindowAnimated `
    -Form $form `
    -DurationMilliseconds 170

}

}

# ============================================================
# WINDOW DRAGGING
# ============================================================

function Initialize-WindowDragging {

if(
    -not (
        "WindowMove" -as [type]
    )
)
{
Add-Type @"

using System;
using System.Runtime.InteropServices;

public class WindowMove {

    [DllImport("user32.dll")]
    public static extern bool ReleaseCapture();


    [DllImport("user32.dll")]
    public static extern int SendMessage(
        IntPtr hWnd,
        int Msg,
        int wParam,
        int lParam
    );

}

"@
}

$titleBar.Add_MouseDown({

param($sender,$e)

if($e.Button -eq
[System.Windows.Forms.MouseButtons]::Left)
{

[WindowMove]::ReleaseCapture()

[WindowMove]::SendMessage(
$form.Handle,
0xA1,
0x2,
0
)

}

})

}

# ============================================================
# INITIALIZE CLOCK
# ============================================================

function Initialize-Clock {

param(
    [System.Windows.Forms.Form]$Form
)

    $clockLabel =
    New-ClockLabel

    $dateLabel =
    New-DateCalendarLabel

    $clockTimer =
New-Object System.Windows.Forms.Timer

$clockTimer.Interval =
1000

$clockTimer.Tag =
[pscustomobject]@{
    ClockLabel = $clockLabel
    DateLabel = $dateLabel
}

$clockTimer.Add_Tick({

    $this.Tag.ClockLabel.Text =
    (Get-Date).ToString(
        "HH:mm:ss"
    )

    $this.Tag.DateLabel.Text =
    (Get-Date).ToString(
        "yyyy / MMMM / dd"
    )

})

$clockTimer.Start()

$script:ClockTimer = $clockTimer

    $Form.Controls.Add(
        $clockLabel
    )

    $Form.Controls.Add(
        $dateLabel
    )

    $script:ClockLabel = $clockLabel

    $script:DateLabel = $dateLabel

}

# ============================================================
# RESTORE HEADER CONTROL ORDER
# ============================================================

function Restore-GaloreHeaderControlZOrder {

    param(
        [System.Windows.Forms.Form]$Form
    )

    foreach($control in @(
        $script:WindowsButton,
        $script:ClockLabel,
        $script:DateLabel,
        $script:TaskManagerButton,
        $script:CmdButton,
        $script:GaloreHotkeysButton
    ))
    {

        if(
            $null -ne $control -and
            -not $control.IsDisposed -and
            $control.Parent -eq $Form
        )
        {

            $control.BringToFront()

        }

    }

}

# ============================================================
# INITIALIZE PROGRAM ICON
# ============================================================

function Initialize-ProgramIcon {

param(
    [System.Windows.Forms.Form]$Form
)

    $windowIcon =
    Get-AppIcon

    if(
        $windowIcon
    )
    {

        $Form.Icon =
        $windowIcon

        $script:ProgramWindowIcon = $windowIcon

    }

    $Form.CreateControl()

}

# ============================================================
# STOP PROGRAM WINDOW RESOURCES
# ============================================================

function Stop-ProgramWindowResources {

param(
    [System.Windows.Forms.Form]$Form
)

if(
    $script:ClockTimer
)
{

    $script:ClockTimer.Stop()

    $script:ClockTimer.Tag =
    $null

    $script:ClockTimer.Dispose()

    $script:ClockTimer = $null

}

if(
    $script:ProgramWindowIcon
)
{

    if(
        $Form -and
        -not $Form.IsDisposed
    )
    {

        $Form.Icon =
        $null

    }

    $script:ProgramWindowIcon.Dispose()

    $script:ProgramWindowIcon = $null

}

}

# ============================================================
# INITIALIZE PROGRAM TITLE BAR
# ============================================================

function Initialize-ProgramTitleBar {

param(
    [System.Windows.Forms.Form]$Form
)

    $titleBar =
    New-ProgramTitleBar `
    -Form $Form

    $Form.Controls.Add(
        $titleBar
    )

    return $titleBar

}

# ============================================================
# TITLE BAR RESIZE HANDLER
# ============================================================

function Register-TitleBarResizeHandler {

    param(
        $Form,
        $TitleBar
    )

    $resizeHandler =
    {

        param(
            $sender,
            $e
        )

        $TitleBar.Width =
        $sender.ClientSize.Width

        $TitleBar.Height =
        40

        foreach(
            $control in
            $TitleBar.Controls
        )
        {

            if(
                $control -is
                [System.Windows.Forms.Button]
            )
            {

                $control.Height =
                $TitleBar.Height

                $control.Width =
                40

            }

        }

    }.GetNewClosure()

    $Form.Add_Resize(
        $resizeHandler
    )

}

# ============================================================
# INITIALIZE TASK MANAGER BUTTON
# ============================================================

function Initialize-TaskManagerButton {

param(
    [System.Windows.Forms.Form]$Form
)

    $taskManagerButton =
    New-TaskManagerButton

    $taskManagerButton.Anchor =
    [System.Windows.Forms.AnchorStyles]::Bottom -bor
    [System.Windows.Forms.AnchorStyles]::Right

    $taskManagerButton.Location =
    [System.Drawing.Point]::new(
        $Form.ClientSize.Width - 320,
        $Form.ClientSize.Height - 47
    )

    $taskManagerButton.Add_Click({

        Start-Process `
        "taskmgr.exe"

    })

    $Form.Controls.Add(
        $taskManagerButton
    )

    $taskManagerButton.BringToFront()
    $script:TaskManagerButton = $taskManagerButton

}

# ============================================================
# INITIALIZE CMD BUTTON
# ============================================================

function Initialize-CmdButton {

param(
    [System.Windows.Forms.Form]$Form
)

    $cmdButton =
    New-CmdButton

    $cmdButton.Anchor =
    [System.Windows.Forms.AnchorStyles]::Bottom -bor
    [System.Windows.Forms.AnchorStyles]::Right

    $cmdButton.Location =
    [System.Drawing.Point]::new(
        $Form.ClientSize.Width - 285,
        $Form.ClientSize.Height - 47
    )

    $cmdButton.Add_Click({

        Start-Process `
        "cmd.exe" `
        -Verb RunAs

    })

    $Form.Controls.Add(
        $cmdButton
    )

    $cmdButton.BringToFront()
    $script:CmdButton = $cmdButton

}

# ============================================================
# SHOW WINDOW WITH CLEAN FADE IN
# ============================================================

function Show-ProgramWindowWithFade {

    param(
        $Form
    )

    $Form.ResumeLayout(
        $true
    )

    $Form.CreateControl()

    $Form.Opacity =
    0

    $Form.ShowInTaskbar =
    $true

    $script:LauncherWindowTargetVisible = $true

    $Form.Add_Shown({

        Start-WindowOpacityAnimation `
        -Form $this `
        -TargetOpacity 1 `
        -DurationMilliseconds 420

    })

    [System.Windows.Forms.Application]::Run(
        $Form
    )

}
