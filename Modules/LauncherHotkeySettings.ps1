# ============================================================
# HOTKEY SETTINGS MODULE
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherHotkeySettings"
    LoadOrder = 260
    RequiresModules = @("LauncherAlphaOverlay", "LauncherHotkeys", "LauncherLogging", "LauncherSystemTools", "UI")
    RequiresFunctions = [ordered]@{
        "Get-GaloreLauncherToggleHotkey" = "LauncherHotkeys"
        "Set-GaloreLauncherToggleHotkey" = "LauncherHotkeys"
        "New-GaloreSystemToolPopup" = "LauncherSystemTools"
        "Show-GaloreSystemToolPopup" = "LauncherSystemTools"
        "New-HotkeysButton" = "UI"
        "Set-GaloreTransparentWindowRegion" = "LauncherAlphaOverlay"
        "Write-LauncherDiagnostic" = "LauncherLogging"
    }
    RequiresTypes = [ordered]@{}
    RequiresVariables = @()
    RequiresFolders = @()
    RequiresFiles = @()
    ProvidesTypes = @()
}

# ============================================================
# HOTKEY DISPLAY
# ============================================================

function Get-GaloreHotkeyDisplayText {
    param([int]$ModifierMask, [int]$VirtualKey)
    $parts = @()
    if(($ModifierMask -band 2) -ne 0) { $parts += "Ctrl" }
    if(($ModifierMask -band 1) -ne 0) { $parts += "Alt" }
    if(($ModifierMask -band 4) -ne 0) { $parts += "Shift" }
    $keyName = ([System.Windows.Forms.Keys]$VirtualKey).ToString()
    if($keyName -eq "Space") { $keyName = "Space" }
    return (($parts + $keyName) -join "+")
}

function ConvertFrom-GaloreHotkeyKeyEvent {
    param($Event)
    $modifierMask = 0
    if($Event.Control) { $modifierMask = $modifierMask -bor 2 }
    if($Event.Alt) { $modifierMask = $modifierMask -bor 1 }
    if($Event.Shift) { $modifierMask = $modifierMask -bor 4 }
    $key = $Event.KeyCode
    if($modifierMask -eq 0 -or $key -in @([System.Windows.Forms.Keys]::ControlKey, [System.Windows.Forms.Keys]::ShiftKey, [System.Windows.Forms.Keys]::Menu)) { return $null }
    [pscustomobject]@{ ModifierMask = $modifierMask; VirtualKey = [int]$key; DisplayText = Get-GaloreHotkeyDisplayText -ModifierMask $modifierMask -VirtualKey ([int]$key) }
}

# ============================================================
# HOTKEY SETTINGS WINDOW
# ============================================================

function Show-GaloreHotkeySettingsPopup {
    param($Anchor)
    $popup = New-GaloreSystemToolPopup -Anchor $Anchor -BackgroundImageName "hotkeyselector.png" -FallbackWidth 420 -FallbackHeight 300
    if($popup.Tag.SelectorImage) { Set-GaloreTransparentWindowRegion -Form $popup -Bitmap $popup.Tag.SelectorImage }
    $popup.KeyPreview = $true
    $heading = New-Object System.Windows.Forms.Label
    $heading.Bounds = [System.Drawing.Rectangle]::new(28, 24, $popup.ClientSize.Width - 56, 25)
    $heading.Text = "Launcher Hotkeys"
    $heading.ForeColor = [System.Drawing.Color]::White
    $heading.BackColor = [System.Drawing.Color]::Transparent
    $heading.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $popup.Controls.Add($heading)
    $label = New-Object System.Windows.Forms.Label
    $label.Bounds = [System.Drawing.Rectangle]::new(28, 65, 155, 24)
    $label.Text = "Show / hide Galore"
    $label.ForeColor = [System.Drawing.Color]::White
    $label.BackColor = [System.Drawing.Color]::Transparent
    $popup.Controls.Add($label)
    $capture = New-Object System.Windows.Forms.TextBox
    $capture.Bounds = [System.Drawing.Rectangle]::new(185, 61, $popup.ClientSize.Width - 213, 28)
    $capture.ReadOnly = $true
    $capture.BackColor = [System.Drawing.Color]::FromArgb(28, 28, 28)
    $capture.ForeColor = [System.Drawing.Color]::White
    $capture.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $capture.Text = (Get-GaloreLauncherToggleHotkey).DisplayText
    $popup.Controls.Add($capture)
    $hint = New-Object System.Windows.Forms.Label
    $hint.Bounds = [System.Drawing.Rectangle]::new(28, 94, $popup.ClientSize.Width - 56, 20)
    $hint.Text = "Click the field, then press a key combination."
    $hint.ForeColor = [System.Drawing.Color]::Gainsboro
    $hint.BackColor = [System.Drawing.Color]::Transparent
    $popup.Controls.Add($hint)
    $savedHotkey = $null
    $capture.Add_KeyDown({
        param($sender, $event)
        $candidate = ConvertFrom-GaloreHotkeyKeyEvent -Event $event
        if($candidate) {
            $script:GalorePendingHotkey = $candidate
            $sender.Text = $candidate.DisplayText
            $event.SuppressKeyPress = $true
            $event.Handled = $true
        }
    })
    $categoryTop = 132
    for($number = 1; $number -le 4; $number++) {
        $category = @($script:GaloreCategoryState.Categories | Where-Object { $_.Id -eq "Category$number" }) | Select-Object -First 1
        $categoryName = if($category) { [string]$category.Name } else { "Category $number" }
        $row = New-Object System.Windows.Forms.Label
        $row.Bounds = [System.Drawing.Rectangle]::new(28, $categoryTop + (($number - 1) * 27), $popup.ClientSize.Width - 56, 22)
        $row.Text = "Ctrl+F$number     $categoryName"
        $row.ForeColor = [System.Drawing.Color]::White
        $row.BackColor = [System.Drawing.Color]::Transparent
        $popup.Controls.Add($row)
    }
    $saveButton = New-Object System.Windows.Forms.Button
    $saveButton.Bounds = [System.Drawing.Rectangle]::new($popup.ClientSize.Width - 128, $popup.ClientSize.Height - 47, 100, 28)
    $saveButton.Text = "Save"
    $popup.Controls.Add($saveButton)
    $saveButton.Add_Click({
        $candidate = $script:GalorePendingHotkey
        if($null -eq $candidate) { return }
        if(Set-GaloreLauncherToggleHotkey -ModifierMask $candidate.ModifierMask -VirtualKey $candidate.VirtualKey -DisplayText $candidate.DisplayText) {
            $script:GalorePendingHotkey = $null
            $popup.Close()
        }
        else {
            [System.Windows.Forms.MessageBox]::Show("That key combination is already used by Windows or another application.", "Galore Launcher", "OK", "Warning") | Out-Null
        }
    }.GetNewClosure())
    $popup.Add_FormClosed({ $script:GalorePendingHotkey = $null })
    Show-GaloreSystemToolPopup -Popup $popup -Owner $Anchor.FindForm()
}

# ============================================================
# HOTKEY BUTTON
# ============================================================

function Initialize-GaloreHotkeyButton {
    param([System.Windows.Forms.Form]$Form)
    $button = New-HotkeysButton
    $button.Name = "GaloreHotkeysButton"
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $toolTip = New-Object System.Windows.Forms.ToolTip
    $toolTip.SetToolTip($button, "Hotkeys")
    $button.Add_Click({ param($sender, $event) Show-GaloreHotkeySettingsPopup -Anchor $sender })
    $Form.Controls.Add($button)
    $button.BringToFront()
    $script:GaloreHotkeysButton = $button
}
