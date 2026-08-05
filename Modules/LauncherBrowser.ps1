# ============================================================
# LAUNCHER BROWSER MODULE
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherBrowser"
    LoadOrder = 200
    RequiresModules = @("LauncherConfiguration", "LauncherDomain", "LauncherLogging", "LauncherPopup", "LauncherSettings")
    RequiresFunctions = [ordered]@{
        "Get-InstalledBrowsers" = "LauncherConfiguration"
        "Write-LauncherDiagnostic" = "LauncherLogging"
        "Load-WindowSettings" = "LauncherSettings"
        "Close-GalorePopupAnimated" = "LauncherPopup"
        "Clear-GalorePopupOwner" = "LauncherPopup"
        "Start-GalorePopupFade" = "LauncherPopup"
        "Stop-GalorePopupFade" = "LauncherPopup"
    }
    RequiresTypes = [ordered]@{
        "GalorePopupRuntimeState" = "LauncherDomain"
    }
    RequiresVariables = @("AppRoot", "GalorePopupRuntime")
    RequiresFolders = @("resources")
    RequiresFiles = @()
    ProvidesTypes = @()
}
# ============================================================
# BROWSER SELECTION STATE
# ============================================================

function Set-GaloreBrowserProgram {
    param($Programs, $Browser)
    if($null -eq $Programs -or -not $Programs.Contains("Browser") -or $null -eq $Browser) {
        return
    }
    $browserProgram = $Programs["Browser"]
    $browserProgram.Path = $Browser.Path
    $browserProgram.StatusProcess = $Browser.ProcessName
    $browserProgram.WindowProcess = $Browser.ProcessName
    $browserProgram.BrowserId = $Browser.Id
    $browserProgram.BrowserDisplayName = $Browser.DisplayName
    $script:SelectedBrowserId = $Browser.Id
}

function Initialize-GaloreBrowser {
    param($Programs, [string]$AppRoot)
    $browsers = Get-InstalledBrowsers
    if($browsers.Count -eq 0) {
        if($Programs -and $Programs.Contains("Browser")) {
            $browserProgram = $Programs["Browser"]
            $browserProgram.Path = $null
            $browserProgram.BrowserId = $null
            $browserProgram.BrowserDisplayName = "No browser detected"
        }
        $script:SelectedBrowserId = $null
        return
    }
    $windowSettings = Load-WindowSettings
    $selectedBrowserId = if($windowSettings) {
        $windowSettings.BrowserId
    } else {
        $null
    }
    if(-not $selectedBrowserId -or -not $browsers.Contains($selectedBrowserId)) {
        $selectedBrowserId = @($browsers.Keys)[0]
    }
    Set-GaloreBrowserProgram -Programs $Programs -Browser $browsers[$selectedBrowserId]
}

# ============================================================
# BROWSER SELECTOR
# ============================================================

function Show-GaloreBrowserSelector {
    param($Programs, $BrowserLabel, [string]$AppRoot)
    $runtime = $script:GalorePopupRuntime
    if($runtime.SelectorForm -and -not $runtime.SelectorForm.IsDisposed) {
        $runtime.SelectorForm.Activate()
        return
    }
    $browsers = Get-InstalledBrowsers
    $selector = New-Object System.Windows.Forms.Form
    $selector.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $selector.ShowInTaskbar = $false
    $selector.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $selector.BackColor = [System.Drawing.Color]::Black
    $selector.TransparencyKey = [System.Drawing.Color]::Empty
    $selector.TopMost = $true
    $selectorImage = $null
    $choiceFont = $null
    $selectorImagePath = Get-GaloreResourcePath "browserselector.png"
    if(Test-Path -LiteralPath $selectorImagePath -PathType Leaf) {
        $sourceImage = $null
        try {
            $sourceImage = [System.Drawing.Image]::FromFile($selectorImagePath)
            $selectorImage = New-Object System.Drawing.Bitmap($sourceImage)
            $selector.BackgroundImage = $selectorImage
            $selector.BackgroundImageLayout = [System.Windows.Forms.ImageLayout]::None
            $selector.ClientSize = New-Object System.Drawing.Size($selectorImage.Width, $selectorImage.Height)
        } catch {
            Write-LauncherDiagnostic -Exception $_ -Context "Failed to load browser selector artwork from '$selectorImagePath'."
        } finally {
            if($sourceImage) {
                $sourceImage.Dispose()
            }
        }
    }
    if($null -eq $selectorImage) {
        $fallbackHeight = [Math]::Max(110, 40 + ($browsers.Count * 34))
        $selector.ClientSize = New-Object System.Drawing.Size(260, $fallbackHeight)
    }
    $selector.Tag = [pscustomobject]@{
        Programs = $Programs
        BrowserLabel = $BrowserLabel
        AppRoot = $AppRoot
        Runtime = $runtime
        SelectorImage = $selectorImage
        ChoiceFont = $choiceFont
        FadeTimer = $null
        IsClosing = $false
    }
    $runtime.SelectorForm = $selector
    $top = 20
    $selectorContentWidth = [Math]::Max(1, ([int]$selector.ClientSize.Width - 30))
    if($browsers.Count -eq 0) {
        $emptyLabel = New-Object System.Windows.Forms.Label
        $emptyLabel.Text = "No installed browsers found."
        $emptyLabel.ForeColor = [System.Drawing.Color]::White
        $emptyLabel.BackColor = [System.Drawing.Color]::Transparent
        $emptyLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $emptyLabel.Bounds = [System.Drawing.Rectangle]::new(15, $top, $selectorContentWidth, 30)
        $selector.Controls.Add($emptyLabel)
    } else {
        $choiceFont = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
        $selector.Tag.ChoiceFont = $choiceFont
        foreach($browser in $browsers.Values) {
            $browserChoice = New-Object System.Windows.Forms.Label
            $browserChoice.Text = $browser.DisplayName
            $browserChoice.Tag = $browser
            $browserChoice.ForeColor = [System.Drawing.Color]::White
            $browserChoice.BackColor = [System.Drawing.Color]::Transparent
            $browserChoice.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
            $browserChoice.Font = $choiceFont
            $browserChoice.Cursor = [System.Windows.Forms.Cursors]::Hand
            $browserChoice.Bounds = [System.Drawing.Rectangle]::new(15, $top, $selectorContentWidth, 30)
            $browserChoice.Add_MouseEnter({
                $this.ForeColor = [System.Drawing.Color]::Blue
            })
            $browserChoice.Add_MouseLeave({
                $this.ForeColor = [System.Drawing.Color]::White
            })
            $browserChoice.Add_Click({
                $selectedBrowser = $this.Tag
                $selectorContext = $this.FindForm().Tag
                Set-GaloreBrowserProgram -Programs $selectorContext.Programs -Browser $selectedBrowser
                if($selectorContext.BrowserLabel -and -not $selectorContext.BrowserLabel.IsDisposed) {
                    $selectorContext.BrowserLabel.Text = "Browser: $($selectedBrowser.DisplayName)"
                }
                Close-GalorePopupAnimated -Form $this.FindForm()
            })
            $selector.Controls.Add($browserChoice)
            $top += 34
        }
    }
    $selector.Add_Deactivate({
        if(-not $this.IsDisposed) {
            Close-GalorePopupAnimated -Form $this
        }
    })
    $selector.Add_FormClosing({
        param($sender, $e)
        $selectorContext = $this.Tag
        if($null -eq $selectorContext) {
            return
        }
        if($e.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing -and -not $selectorContext.IsClosing) {
            $e.Cancel = $true
            Close-GalorePopupAnimated -Form $this
            return
        }
        $selectorContext.IsClosing = $true
    })
    $selector.Add_FormClosed({
        $selectorContext = $this.Tag
        if($selectorContext) {
            Stop-GalorePopupFade -Form $this
            if($selectorContext.ChoiceFont) {
                $selectorContext.ChoiceFont.Dispose()
            }
            if($selectorContext.SelectorImage) {
                $selectorContext.SelectorImage.Dispose()
            }
            $this.BackgroundImage = $null
            Clear-GalorePopupOwner -Runtime $selectorContext.Runtime -PropertyName "SelectorForm" -Form $this
            $this.Tag = $null
        }
    })
    $owner = if($BrowserLabel) {
        $BrowserLabel.FindForm()
    } else {
        $null
    }
    if($owner) {
        $browserScreenLocation = $BrowserLabel.PointToScreen([System.Drawing.Point]::Empty)
        $workingArea = [System.Windows.Forms.Screen]::FromPoint($browserScreenLocation).WorkingArea
        $selectorX = [int]$browserScreenLocation.X
        $selectorY = [int]($browserScreenLocation.Y + $BrowserLabel.Height + 2)
        if(($selectorX + $selector.Width) -gt $workingArea.Right) {
            $selectorX = [Math]::Max($workingArea.Left, ($workingArea.Right - $selector.Width))
        }
        if(($selectorY + $selector.Height) -gt $workingArea.Bottom) {
            $selectorY = [Math]::Max($workingArea.Top, ($browserScreenLocation.Y - $selector.Height - 2))
        }
        $selector.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
        $selector.Location = [System.Drawing.Point]::new($selectorX, $selectorY)
        $selector.Opacity = 0
        $selector.Show($owner)
        Start-GalorePopupFade -Form $selector -TargetOpacity 1
    } else {
        $selector.Opacity = 0
        $selector.Show()
        Start-GalorePopupFade -Form $selector -TargetOpacity 1
    }
}

function Stop-GaloreBrowserResources {
    $runtime = $script:GalorePopupRuntime
    $selector = $runtime.SelectorForm
    if($null -eq $selector) {
        return
    }
    if(-not $selector.IsDisposed) {
        if($selector.Tag) {
            $selector.Tag.IsClosing = $true
        }
        Stop-GalorePopupFade -Form $selector
        $selector.Close()
    }
    Clear-GalorePopupOwner -Runtime $runtime -PropertyName "SelectorForm" -Form $selector
}
