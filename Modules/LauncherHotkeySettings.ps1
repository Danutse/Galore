# ============================================================
# HOTKEY SETTINGS MODULE
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherHotkeySettings"
    LoadOrder = 260
    RequiresModules = @("LauncherAlphaOverlay", "LauncherHotkeys", "LauncherLogging", "LauncherSystemTools", "UI")
    RequiresFunctions = [ordered]@{
        "Get-GaloreLauncherToggleHotkey" = "LauncherHotkeys"
        "Get-GaloreCategoryHotkey" = "LauncherHotkeys"
        "Set-GaloreLauncherToggleHotkey" = "LauncherHotkeys"
        "Set-GaloreCategoryHotkey" = "LauncherHotkeys"
        "Set-GaloreHotkeyDefinitions" = "LauncherHotkeys"
        "Suspend-GaloreHotkeys" = "LauncherHotkeys"
        "Resume-GaloreHotkeys" = "LauncherHotkeys"
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
    $popup = New-GaloreSystemToolPopup -Anchor $Anchor -BackgroundImageName "HotkeyBackground.png" -FallbackWidth 420 -FallbackHeight 300
    if($popup.Tag.SelectorImage) { Set-GaloreTransparentWindowRegion -Form $popup -Bitmap $popup.Tag.SelectorImage }
    $popup.KeyPreview = $true
    $heading = New-Object System.Windows.Forms.Label
    $heading.Bounds = [System.Drawing.Rectangle]::new(28, 24, $popup.ClientSize.Width - 56, 25)
    $heading.Text = "Launcher Hotkeys"
    $heading.ForeColor = [System.Drawing.Color]::White
    $heading.BackColor = [System.Drawing.Color]::Transparent
    $heading.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $popup.Controls.Add($heading)
    $hint = New-Object System.Windows.Forms.Label
    $hint.Bounds = [System.Drawing.Rectangle]::new(28, 53, $popup.ClientSize.Width - 56, 20)
    $hint.Text = "Click the field, then press a key combination."
    $hint.ForeColor = [System.Drawing.Color]::Gainsboro
    $hint.BackColor = [System.Drawing.Color]::Transparent
    $popup.Controls.Add($hint)
    $script:GalorePendingHotkeys = @{}
    $script:GaloreHotkeyCaptureField = $null
    $captureStatus = New-Object System.Windows.Forms.Label
    $captureStatus.Bounds = [System.Drawing.Rectangle]::new(28, $popup.ClientSize.Height - 84, $popup.ClientSize.Width - 56, 20)
    $captureStatus.Text = "Select a shortcut field to change it."
    $captureStatus.ForeColor = [System.Drawing.Color]::Gainsboro
    $captureStatus.BackColor = [System.Drawing.Color]::Transparent
    $popup.Controls.Add($captureStatus)
    $hotkeyFields = [ordered]@{}
    $hotkeyRows = @([pscustomobject]@{ Id = "LauncherToggle"; Name = "Show / hide Galore"; Hotkey = Get-GaloreLauncherToggleHotkey })
    for($number = 1; $number -le 4; $number++) {
        $categoryId = "Category$number"
        $category = @($script:GaloreCategoryState.Categories | Where-Object { $_.Id -eq $categoryId }) | Select-Object -First 1
        $categoryName = if($category) { [string]$category.Name } else { "Category $number" }
        $hotkeyRows += [pscustomobject]@{ Id = $categoryId; Name = $categoryName; Hotkey = Get-GaloreCategoryHotkey -CategoryId $categoryId }
    }
    for($index = 0; $index -lt $hotkeyRows.Count; $index++) {
        $row = $hotkeyRows[$index]
        $top = 74 + ($index * 26)
        $label = New-Object System.Windows.Forms.Label
        $label.Bounds = [System.Drawing.Rectangle]::new(28, $top, 160, 22)
        $label.Text = $row.Name
        $label.ForeColor = [System.Drawing.Color]::White
        $label.BackColor = [System.Drawing.Color]::Transparent
        $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $popup.Controls.Add($label)
        $capture = New-Object System.Windows.Forms.TextBox
        $capture.Bounds = [System.Drawing.Rectangle]::new(190, $top - 1, $popup.ClientSize.Width - 218, 24)
        $capture.ReadOnly = $true
        $capture.TabStop = $true
        $capture.Cursor = [System.Windows.Forms.Cursors]::Hand
        $capture.BackColor = [System.Drawing.Color]::FromArgb(28, 28, 28)
        $capture.ForeColor = [System.Drawing.Color]::White
        $capture.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $capture.Text = $row.Hotkey.DisplayText
        $capture.Tag = $row.Id
        $capture.Add_Click({
            param($sender, $event)
            $script:GaloreHotkeyCaptureField = $sender
            Suspend-GaloreHotkeys
            $sender.Text = "Press shortcut..."
            $captureStatus.Text = "Listening for a shortcut. Press Esc to cancel."
            $captureStatus.ForeColor = [System.Drawing.Color]::Gold
            $sender.Focus()
        }.GetNewClosure())
        $capture.Add_PreviewKeyDown({ param($sender, $event) $event.IsInputKey = $true })
        $hotkeyFields[$row.Id] = $capture
        $popup.Controls.Add($capture)
    }
    $captureStatus.Location = [System.Drawing.Point]::new(28, $popup.ClientSize.Height - 76)
    $popup.Add_KeyDown({
        param($sender, $event)
        $field = $script:GaloreHotkeyCaptureField
        if($null -eq $field -or $field.IsDisposed) { return }
        if($event.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
            $field.Text = if($script:GalorePendingHotkeys.ContainsKey($field.Tag)) { $script:GalorePendingHotkeys[$field.Tag].DisplayText } elseif($field.Tag -eq "LauncherToggle") { (Get-GaloreLauncherToggleHotkey).DisplayText } else { (Get-GaloreCategoryHotkey -CategoryId $field.Tag).DisplayText }
            $script:GaloreHotkeyCaptureField = $null
            Resume-GaloreHotkeys | Out-Null
            $captureStatus.Text = "Shortcut capture cancelled."
            $captureStatus.ForeColor = [System.Drawing.Color]::Gainsboro
            $event.SuppressKeyPress = $true
            $event.Handled = $true
            return
        }
        $candidate = ConvertFrom-GaloreHotkeyKeyEvent -Event $event
        if($candidate) {
            $script:GalorePendingHotkeys[$field.Tag] = $candidate
            $field.Text = $candidate.DisplayText
            $script:GaloreHotkeyCaptureField = $null
            $captureStatus.Text = "Shortcut ready. Click Save Changes to apply it."
            $captureStatus.ForeColor = [System.Drawing.Color]::LightGreen
        }
        elseif($event.KeyCode -notin @([System.Windows.Forms.Keys]::ControlKey, [System.Windows.Forms.Keys]::ShiftKey, [System.Windows.Forms.Keys]::Menu)) {
            $captureStatus.Text = "Use Ctrl, Alt, or Shift with another key."
            $captureStatus.ForeColor = [System.Drawing.Color]::Salmon
        }
        $event.SuppressKeyPress = $true
        $event.Handled = $true
    }.GetNewClosure())
    $resetButton = New-Object System.Windows.Forms.Button
    $resetButton.Bounds = [System.Drawing.Rectangle]::new(28, $popup.ClientSize.Height - 47, 115, 28)
    $resetButton.Text = "Reset Defaults"
    $popup.Controls.Add($resetButton)
    $resetButton.Add_Click({
        $script:GalorePendingHotkeys["LauncherToggle"] = [pscustomobject]@{ ModifierMask = 6; VirtualKey = 32; DisplayText = "Ctrl+Shift+Space" }
        foreach($number in 1..4) { $categoryId = "Category$number"; $script:GalorePendingHotkeys[$categoryId] = [pscustomobject]@{ ModifierMask = 2; VirtualKey = (0x70 + ($number - 1)); DisplayText = "Ctrl+F$number" } }
        foreach($entry in $script:GalorePendingHotkeys.GetEnumerator()) { $hotkeyFields[$entry.Key].Text = $entry.Value.DisplayText }
        $captureStatus.Text = "Default shortcuts are ready. Click Save Changes to apply them."
        $captureStatus.ForeColor = [System.Drawing.Color]::LightGreen
    }.GetNewClosure())
    $saveButton = New-Object System.Windows.Forms.Button
    $saveButton.Bounds = [System.Drawing.Rectangle]::new($popup.ClientSize.Width - 128, $popup.ClientSize.Height - 47, 100, 28)
    $saveButton.Text = "Save Changes"
    $popup.Controls.Add($saveButton)
    $saveButton.Add_Click({
        if($script:GalorePendingHotkeys.Count -eq 0) {
            $captureStatus.Text = "No shortcut changes are waiting to be saved."
            $captureStatus.ForeColor = [System.Drawing.Color]::Gainsboro
            return
        }
        $launcherToggle = Get-GaloreLauncherToggleHotkey
        $categoryHotkeys = [ordered]@{}
        foreach($number in 1..4) { $categoryId = "Category$number"; $categoryHotkeys[$categoryId] = Get-GaloreCategoryHotkey -CategoryId $categoryId }
        if($script:GalorePendingHotkeys.ContainsKey("LauncherToggle")) { $launcherToggle = $script:GalorePendingHotkeys["LauncherToggle"] }
        foreach($number in 1..4) { $categoryId = "Category$number"; if($script:GalorePendingHotkeys.ContainsKey($categoryId)) { $categoryHotkeys[$categoryId] = $script:GalorePendingHotkeys[$categoryId] } }
        if(-not (Set-GaloreHotkeyDefinitions -LauncherToggle $launcherToggle -CategoryHotkeys $categoryHotkeys)) {
            $captureStatus.Text = "The selected set conflicts with Windows or another application."
            $captureStatus.ForeColor = [System.Drawing.Color]::Salmon
            return
        }
        $script:GalorePendingHotkeys = @{}
        [System.Windows.Forms.MessageBox]::Show("Galore hotkeys were saved successfully.", "Galore Launcher", "OK", "Information") | Out-Null
        $popup.Close()
    }.GetNewClosure())
    $popup.Add_FormClosed({ Resume-GaloreHotkeys | Out-Null; $script:GalorePendingHotkeys = @{}; $script:GaloreHotkeyCaptureField = $null; $script:GaloreHotkeySettingsPopup = $null })
    $script:GaloreHotkeySettingsPopup = $popup
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
    $button.Add_Click({
        param($sender, $event)
        if($script:GaloreHotkeySettingsPopup -and -not $script:GaloreHotkeySettingsPopup.IsDisposed) {
            $script:GaloreHotkeySettingsPopup.Close()
            return
        }
        Show-GaloreHotkeySettingsPopup -Anchor $sender
    })
    $Form.Controls.Add($button)
    $button.BringToFront()
    $script:GaloreHotkeysButton = $button
}
