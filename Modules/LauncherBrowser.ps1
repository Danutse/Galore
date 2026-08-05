# ============================================================
# LAUNCHER BROWSER MODULE
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherBrowser"
    LoadOrder = 190
    RequiresModules = @("LauncherConfiguration", "LauncherLogging", "LauncherSettings")
    RequiresFunctions = [ordered]@{
        "Get-InstalledBrowsers" = "LauncherConfiguration"
        "Write-LauncherDiagnostic" = "LauncherLogging"
        "Load-WindowSettings" = "LauncherSettings"
    }
    RequiresTypes = [ordered]@{}
    RequiresVariables = @("AppRoot")
    RequiresFolders = @("resources")
    RequiresFiles = @()
    ProvidesTypes = @()
}

$script:BrowserSelectorForm = $null

# ============================================================
# BROWSER SELECTION STATE
# ============================================================

function Set-GaloreBrowserProgram {

    param(
        $Programs,

        $Browser
    )

    if(
        $null -eq $Programs -or
        -not $Programs.Contains("Browser") -or
        $null -eq $Browser
    )
    {

        return

    }

    $Programs["Browser"]["Path"] =
    $Browser.Path

    $Programs["Browser"]["StatusProcess"] =
    $Browser.ProcessName

    $Programs["Browser"]["WindowProcess"] =
    $Browser.ProcessName

    $Programs["Browser"]["BrowserId"] =
    $Browser.Id

    $Programs["Browser"]["BrowserDisplayName"] =
    $Browser.DisplayName

    $script:SelectedBrowserId =
    $Browser.Id

}

function Initialize-GaloreBrowser {

    param(
        $Programs,

        [string]$AppRoot
    )

    $browsers =
    Get-InstalledBrowsers

    if($browsers.Count -eq 0)
    {

        if($Programs -and $Programs.Contains("Browser"))
        {

            $Programs["Browser"]["Path"] =
            $null

            $Programs["Browser"]["BrowserId"] =
            $null

            $Programs["Browser"]["BrowserDisplayName"] =
            "No browser detected"

        }

        $script:SelectedBrowserId = $null

        return

    }

    $windowSettings =
    Load-WindowSettings

    $selectedBrowserId =
    if($windowSettings)
    {

        $windowSettings.BrowserId

    }
    else
    {

        $null

    }

    if(
        -not $selectedBrowserId -or
        -not $browsers.Contains($selectedBrowserId)
    )
    {

        $selectedBrowserId =
        @($browsers.Keys)[0]

    }

    Set-GaloreBrowserProgram `
    -Programs $Programs `
    -Browser $browsers[$selectedBrowserId]

}

# ============================================================
# BROWSER SELECTOR
# ============================================================

function Start-GaloreBrowserSelectorFade {

    param(
        [System.Windows.Forms.Form]$Form,

        [double]$TargetOpacity,

        [switch]$CloseOnComplete
    )

    if(
        $null -eq $Form -or
        $Form.IsDisposed
    )
    {

        return

    }

    $selectorContext =
    $Form.Tag

    if(
        $selectorContext.FadeTimer
    )
    {

        $selectorContext.FadeTimer.Stop()

        $selectorContext.FadeTimer.Dispose()

        $selectorContext.FadeTimer =
        $null

    }

    $fadeTimer =
    New-Object System.Windows.Forms.Timer

    $fadeTimer.Interval =
    15

    $fadeTimer.Tag =
    [pscustomobject]@{
        Form = $Form
        SelectorContext = $selectorContext
        StartOpacity = [double]$Form.Opacity
        TargetOpacity = [Math]::Max(0.0, [Math]::Min(1.0, $TargetOpacity))
        Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        CloseOnComplete = [bool]$CloseOnComplete
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

            return

        }

        $progress =
        [Math]::Min(
            1.0,
            ($state.Stopwatch.Elapsed.TotalMilliseconds / 180)
        )

        $easedProgress =
        $progress * $progress * (
            3 -
            (2 * $progress)
        )

        $state.Form.Opacity =
        $state.StartOpacity +
        (
            ($state.TargetOpacity - $state.StartOpacity) *
            $easedProgress
        )

        if($progress -lt 1)
        {

            return

        }

        $state.Form.Opacity =
        $state.TargetOpacity

        $timer.Stop()

        $timer.Tag =
        $null

        $timer.Dispose()

        $state.SelectorContext.FadeTimer =
        $null

        if(
            $state.CloseOnComplete -and
            -not $state.Form.IsDisposed
        )
        {

            $state.Form.Close()

        }

    })

    $selectorContext.FadeTimer =
    $fadeTimer

    $fadeTimer.Start()

}

function Close-GaloreBrowserSelectorAnimated {

    param(
        [System.Windows.Forms.Form]$Form
    )

    if(
        $null -eq $Form -or
        $Form.IsDisposed
    )
    {

        return

    }

    $selectorContext =
    $Form.Tag

    if(
        $selectorContext.IsClosing
    )
    {

        return

    }

    $selectorContext.IsClosing =
    $true

    Start-GaloreBrowserSelectorFade `
    -Form $Form `
    -TargetOpacity 0 `
    -CloseOnComplete

}

function Show-GaloreBrowserSelector {

    param(
        $Programs,

        $BrowserLabel,

        [string]$AppRoot
    )

    if(
        $script:BrowserSelectorForm -and
        -not $script:BrowserSelectorForm.IsDisposed
    )
    {

        $script:BrowserSelectorForm.Activate()

        return

    }

    $browsers =
    Get-InstalledBrowsers

    $selector =
    New-Object System.Windows.Forms.Form

    $selector.FormBorderStyle =
    [System.Windows.Forms.FormBorderStyle]::None

    $selector.ShowInTaskbar =
    $false

    $selector.StartPosition =
    [System.Windows.Forms.FormStartPosition]::CenterParent

    $selector.BackColor =
    [System.Drawing.Color]::Black

    $selector.TransparencyKey =
    [System.Drawing.Color]::Empty

    $selector.TopMost =
    $true

    $selectorImage = $null

    $selectorImagePath =
    Get-GaloreResourcePath `
    "browserselector.png"

    if(
        Test-Path `
        -LiteralPath $selectorImagePath `
        -PathType Leaf
    )
    {

        try
        {

            $sourceImage =
            [System.Drawing.Image]::FromFile(
                $selectorImagePath
            )

            $selectorImage =
            New-Object System.Drawing.Bitmap($sourceImage)

            $sourceImage.Dispose()

            $selector.BackgroundImage =
            $selectorImage

            $selector.BackgroundImageLayout =
            [System.Windows.Forms.ImageLayout]::None

            $selector.ClientSize =
            New-Object System.Drawing.Size(
                $selectorImage.Width,
                $selectorImage.Height
            )

        }
        catch
        {

            Write-LauncherDiagnostic `
            -Exception $_ `
            -Context "Failed to load browser selector artwork from '$selectorImagePath'."

        }

    }

    if($null -eq $selectorImage)
    {

        $fallbackHeight =
        [Math]::Max(
            110,
            40 + ($browsers.Count * 34)
        )

        $selector.ClientSize =
        New-Object System.Drawing.Size(
            260,
            $fallbackHeight
        )

    }

    $selector.Tag =
    [pscustomobject]@{
        Programs = $Programs
        BrowserLabel = $BrowserLabel
        AppRoot = $AppRoot
        SelectorImage = $selectorImage
        FadeTimer = $null
        IsClosing = $false
    }

    $script:BrowserSelectorForm = $selector

    $top = 20

    $selectorContentWidth =
    [Math]::Max(
        1,
        (
            [int]$selector.ClientSize.Width -
            30
        )
    )

    if($browsers.Count -eq 0)
    {

        $emptyLabel =
        New-Object System.Windows.Forms.Label

        $emptyLabel.Text =
        "No installed browsers found."

        $emptyLabel.ForeColor =
        [System.Drawing.Color]::White

        $emptyLabel.BackColor =
        [System.Drawing.Color]::Transparent

        $emptyLabel.TextAlign =
        [System.Drawing.ContentAlignment]::MiddleCenter

        $emptyLabel.Bounds =
        [System.Drawing.Rectangle]::new(
            15,
            $top,
            $selectorContentWidth,
            30
        )

        $selector.Controls.Add($emptyLabel)

    }
    else
    {

        foreach($browser in $browsers.Values)
        {

            $browserChoice =
            New-Object System.Windows.Forms.Label

            $browserChoice.Text =
            $browser.DisplayName

            $browserChoice.Tag =
            $browser

            $browserChoice.ForeColor =
            [System.Drawing.Color]::White

            $browserChoice.BackColor =
            [System.Drawing.Color]::Transparent

            $browserChoice.TextAlign =
            [System.Drawing.ContentAlignment]::MiddleCenter

            $browserChoice.Font =
            New-Object System.Drawing.Font(
                "Segoe UI",
                10,
                [System.Drawing.FontStyle]::Bold
            )

            $browserChoice.Cursor =
            [System.Windows.Forms.Cursors]::Hand

            $browserChoice.Bounds =
            [System.Drawing.Rectangle]::new(
                15,
                $top,
                $selectorContentWidth,
                30
            )

            $browserChoice.Add_MouseEnter({

                $this.ForeColor =
                [System.Drawing.Color]::Blue

            })

            $browserChoice.Add_MouseLeave({

                $this.ForeColor =
                [System.Drawing.Color]::White

            })

            $browserChoice.Add_Click({

                $selectedBrowser =
                $this.Tag

                $selectorContext =
                $this.FindForm().Tag

                Set-GaloreBrowserProgram `
                -Programs $selectorContext.Programs `
                -Browser $selectedBrowser

                if(
                    $selectorContext.BrowserLabel -and
                    -not $selectorContext.BrowserLabel.IsDisposed
                )
                {

                    $selectorContext.BrowserLabel.Text =
                    "Browser: $($selectedBrowser.DisplayName)"

                }

                Close-GaloreBrowserSelectorAnimated `
                -Form $this.FindForm()

            })

            $selector.Controls.Add($browserChoice)

            $top +=
            34

        }

    }

    $selector.Add_Deactivate({

        if(
            -not $this.IsDisposed
        )
        {

            Close-GaloreBrowserSelectorAnimated `
            -Form $this

        }

    })

    $selector.Add_FormClosing({

        param(
            $sender,
            $e
        )

        $selectorContext =
        $this.Tag

        if(
            -not $selectorContext.IsClosing
        )
        {

            $e.Cancel =
            $true

            Close-GaloreBrowserSelectorAnimated `
            -Form $this

        }

    })

    $selector.Add_FormClosed({

        $selectorContext =
        $this.Tag

        if($selectorContext.FadeTimer)
        {

            $selectorContext.FadeTimer.Stop()

            $selectorContext.FadeTimer.Dispose()

            $selectorContext.FadeTimer =
            $null

        }

        if($selectorContext.SelectorImage)
        {

            $selectorContext.SelectorImage.Dispose()

        }

        $script:BrowserSelectorForm = $null

    })

    $owner =
    if($BrowserLabel)
    {
        $BrowserLabel.FindForm()
    }
    else
    {
        $null
    }

    if($owner)
    {

        $browserScreenLocation =
        $BrowserLabel.PointToScreen(
            [System.Drawing.Point]::Empty
        )

        $workingArea =
        [System.Windows.Forms.Screen]::FromPoint(
            $browserScreenLocation
        ).WorkingArea

        $selectorX =
        [int]$browserScreenLocation.X

        $selectorY =
        [int](
            $browserScreenLocation.Y +
            $BrowserLabel.Height +
            2
        )

        if(
            ($selectorX + $selector.Width) -gt
            $workingArea.Right
        )
        {

            $selectorX =
            [Math]::Max(
                $workingArea.Left,
                ($workingArea.Right - $selector.Width)
            )

        }

        if(
            ($selectorY + $selector.Height) -gt
            $workingArea.Bottom
        )
        {

            $selectorY =
            [Math]::Max(
                $workingArea.Top,
                ($browserScreenLocation.Y - $selector.Height - 2)
            )

        }

        $selector.StartPosition =
        [System.Windows.Forms.FormStartPosition]::Manual

        $selector.Location =
        [System.Drawing.Point]::new(
            $selectorX,
            $selectorY
        )

        $selector.Opacity =
        0

        $selector.Show($owner)

        Start-GaloreBrowserSelectorFade `
        -Form $selector `
        -TargetOpacity 1

    }
    else
    {

        $selector.Opacity =
        0

        $selector.Show()

        Start-GaloreBrowserSelectorFade `
        -Form $selector `
        -TargetOpacity 1

    }

}
