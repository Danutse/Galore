# ============================================================
# HOTKEY SETTINGS MODULE
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherHotkeySettings"
    LoadOrder = 270
    RequiresModules = @("LauncherAlphaOverlay", "LauncherCategories", "LauncherDomain", "LauncherHotkeys", "LauncherLogging", "LauncherSystemTools", "UI")
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
        "Get-GaloreCategoryById" = "LauncherCategories"
    }
    RequiresTypes = [ordered]@{
        "GaloreHotkeySettingsRuntimeState" = "LauncherDomain"
    }
    RequiresVariables = @()
    RequiresFolders = @()
    RequiresFiles = @()
    ProvidesTypes = @()
}
$script:GaloreHotkeySettingsRuntime = [GaloreHotkeySettingsRuntimeState]::new()

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

function Save-GalorePendingHotkeys {
    param($StatusLabel, $CaptureState)
    if($null -eq $CaptureState -or $CaptureState.Pending.Count -eq 0) { return $true }
    $launcherToggle = Get-GaloreLauncherToggleHotkey
    $categoryHotkeys = [ordered]@{}
    foreach($number in 1..4) { $categoryId = "Category$number"; $categoryHotkeys[$categoryId] = Get-GaloreCategoryHotkey -CategoryId $categoryId }
    if($CaptureState.Pending.ContainsKey("LauncherToggle")) { $launcherToggle = $CaptureState.Pending["LauncherToggle"] }
    foreach($number in 1..4) { $categoryId = "Category$number"; if($CaptureState.Pending.ContainsKey($categoryId)) { $categoryHotkeys[$categoryId] = $CaptureState.Pending[$categoryId] } }
    if(-not (Set-GaloreHotkeyDefinitions -LauncherToggle $launcherToggle -CategoryHotkeys $categoryHotkeys)) {
        $StatusLabel.Text = "The selected set conflicts with Windows or another application."
        $StatusLabel.ForeColor = [System.Drawing.Color]::Salmon
        return $false
    }
    $CaptureState.Pending.Clear()
    return $true
}

function Invoke-GaloreHotkeyCaptureInput {
    param($Event, $StatusLabel, $CaptureState)
    if($null -eq $CaptureState) { return }
    $field = $CaptureState.Field
    if($null -eq $field -or $field.IsDisposed) { return }
    if($Event.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        $field.Text = if($field.Tag -eq "LauncherToggle") { (Get-GaloreLauncherToggleHotkey).DisplayText } else { (Get-GaloreCategoryHotkey -CategoryId $field.Tag).DisplayText }
        $CaptureState.Pending.Remove($field.Tag)
        $CaptureState.Field = $null
        Resume-GaloreHotkeys | Out-Null
        $StatusLabel.Text = "Shortcut capture cancelled."
        $StatusLabel.ForeColor = [System.Drawing.Color]::Gainsboro
    } elseif($Event.KeyCode -eq [System.Windows.Forms.Keys]::Back) {
        if(-not $CaptureState.Pending.ContainsKey($field.Tag)) {
            $StatusLabel.Text = "Press a shortcut combination first."
            $StatusLabel.ForeColor = [System.Drawing.Color]::Gold
        } elseif(Save-GalorePendingHotkeys -StatusLabel $StatusLabel -CaptureState $CaptureState) {
            $CaptureState.Field = $null
            $StatusLabel.Text = "Shortcut applied and saved."
            $StatusLabel.ForeColor = [System.Drawing.Color]::LightGreen
        }
    }
    else {
        $candidate = ConvertFrom-GaloreHotkeyKeyEvent -Event $Event
        if($candidate) {
            $CaptureState.Pending[$field.Tag] = $candidate
            $field.Text = $candidate.DisplayText
            $StatusLabel.Text = "Backspace or Close saves $($candidate.DisplayText)."
            $StatusLabel.ForeColor = [System.Drawing.Color]::Gold
        } elseif($Event.KeyCode -notin @([System.Windows.Forms.Keys]::ControlKey, [System.Windows.Forms.Keys]::ShiftKey, [System.Windows.Forms.Keys]::Menu)) {
            $StatusLabel.Text = "Use Ctrl, Alt, or Shift with another key."
            $StatusLabel.ForeColor = [System.Drawing.Color]::Salmon
        }
    }
    $Event.SuppressKeyPress = $true
    $Event.Handled = $true
}

# ============================================================
# HOTKEY SETTINGS WINDOW
# ============================================================

function Show-GaloreHotkeySettingsPopup {
    param($Anchor, $Runtime = $script:GaloreHotkeySettingsRuntime)
    if($null -eq $Anchor -or $Anchor.IsDisposed) { return }
    if($Runtime.Popup -and -not $Runtime.Popup.IsDisposed) { $Runtime.Popup.Close(); return }
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
    $hint.Text = "Enter a shortcut. Backspace or Close saves it."
    $hint.ForeColor = [System.Drawing.Color]::Gainsboro
    $hint.BackColor = [System.Drawing.Color]::Transparent
    $popup.Controls.Add($hint)
    $captureState = [pscustomobject]@{ Field = $null; Pending = @{} }
    $popup | Add-Member -MemberType NoteProperty -Name HotkeyCaptureState -Value $captureState -Force
    $captureStatus = New-Object System.Windows.Forms.Label
    $captureStatus.Bounds = [System.Drawing.Rectangle]::new(28, $popup.ClientSize.Height - 84, $popup.ClientSize.Width - 56, 20)
    $captureStatus.Text = "Select a shortcut field to change it."
    $captureStatus.ForeColor = [System.Drawing.Color]::Gainsboro
    $captureStatus.BackColor = [System.Drawing.Color]::Transparent
    $popup.Controls.Add($captureStatus)
    $popup | Add-Member -MemberType NoteProperty -Name HotkeyStatusLabel -Value $captureStatus -Force
    $hotkeyFields = [ordered]@{}
    $hotkeyRows = @([pscustomobject]@{ Id = "LauncherToggle"; Name = "Show / hide Galore"; Hotkey = Get-GaloreLauncherToggleHotkey })
    for($number = 1; $number -le 4; $number++) {
        $categoryId = "Category$number"
        $category = Get-GaloreCategoryById -CategoryId $categoryId
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
        $capture.ReadOnly = $false
        $capture.ShortcutsEnabled = $false
        $capture.TabStop = $true
        $capture.Cursor = [System.Windows.Forms.Cursors]::Hand
        $capture.BackColor = [System.Drawing.Color]::FromArgb(28, 28, 28)
        $capture.ForeColor = [System.Drawing.Color]::White
        $capture.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $capture.Text = $row.Hotkey.DisplayText
        $capture.Tag = $row.Id
        $capture.Add_Click({
            param($sender, $event)
            $previousField = $captureState.Field
            if($previousField -and $previousField -ne $sender -and -not $previousField.IsDisposed) {
                if($captureState.Pending.ContainsKey($previousField.Tag)) {
                    $previousField.Text = if($previousField.Tag -eq "LauncherToggle") { (Get-GaloreLauncherToggleHotkey).DisplayText } else { (Get-GaloreCategoryHotkey -CategoryId $previousField.Tag).DisplayText }
                    $captureState.Pending.Remove($previousField.Tag)
                }
            }
            $captureState.Field = $sender
            Suspend-GaloreHotkeys
            $captureStatus.Text = "Listening. Press your shortcut, then press Backspace to apply it."
            $captureStatus.ForeColor = [System.Drawing.Color]::Gold
            $sender.Focus()
        }.GetNewClosure())
        $capture.Add_PreviewKeyDown({ param($sender, $event) $event.IsInputKey = $true })
        $capture.Add_KeyDown({
            param($sender, $event)
            if($captureState.Field -eq $sender) {
                Invoke-GaloreHotkeyCaptureInput -Event $event -StatusLabel $captureStatus -CaptureState $captureState
            }
        }.GetNewClosure())
        $hotkeyFields[$row.Id] = $capture
        $popup.Controls.Add($capture)
    }
    $captureStatus.Location = [System.Drawing.Point]::new(28, $popup.ClientSize.Height - 76)
    $resetButton = New-Object System.Windows.Forms.Button
    $resetButton.Bounds = [System.Drawing.Rectangle]::new(28, $popup.ClientSize.Height - 47, 115, 28)
    $resetButton.Text = "Reset Defaults"
    $resetButton.ForeColor = [System.Drawing.Color]::White
    $resetButton.BackColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
    $resetButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $resetButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(180, 180, 180)
    $resetButton.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(80, 20, 20)
    $resetButton.UseVisualStyleBackColor = $false
    $popup.Controls.Add($resetButton)
    $resetButton.Add_Click({
        $captureState.Pending.Clear()
        $captureState.Pending["LauncherToggle"] = [pscustomobject]@{ ModifierMask = 6; VirtualKey = 32; DisplayText = "Ctrl+Shift+Space" }
        foreach($number in 1..4) { $categoryId = "Category$number"; $captureState.Pending[$categoryId] = [pscustomobject]@{ ModifierMask = 2; VirtualKey = (0x70 + ($number - 1)); DisplayText = "Ctrl+F$number" } }
        if(Save-GalorePendingHotkeys -StatusLabel $captureStatus -CaptureState $captureState) {
            foreach($number in 1..4) { $categoryId = "Category$number"; $hotkeyFields[$categoryId].Text = (Get-GaloreCategoryHotkey -CategoryId $categoryId).DisplayText }
            $hotkeyFields["LauncherToggle"].Text = (Get-GaloreLauncherToggleHotkey).DisplayText
            $captureState.Field = $null
            $captureStatus.Text = "Default shortcuts applied."
            $captureStatus.ForeColor = [System.Drawing.Color]::LightGreen
        }
    }.GetNewClosure())
    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Bounds = [System.Drawing.Rectangle]::new($popup.ClientSize.Width - 128, $popup.ClientSize.Height - 47, 100, 28)
    $closeButton.Text = "Close"
    $closeButton.ForeColor = [System.Drawing.Color]::White
    $closeButton.BackColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
    $closeButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $closeButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(180, 180, 180)
    $closeButton.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(80, 20, 20)
    $closeButton.UseVisualStyleBackColor = $false
    $popup.Controls.Add($closeButton)
    $closeButton.Add_Click({
        $popup.Close()
    }.GetNewClosure())
    $popup.Add_FormClosed({
        param($sender, $event)
        if($sender.HotkeyCaptureState -and $sender.HotkeyCaptureState.Pending.Count -gt 0) {
            Save-GalorePendingHotkeys -StatusLabel $sender.HotkeyStatusLabel -CaptureState $sender.HotkeyCaptureState | Out-Null
        }
        Resume-GaloreHotkeys | Out-Null
        if($sender.HotkeyCaptureState) {
            $sender.HotkeyCaptureState.Pending.Clear()
            $sender.HotkeyCaptureState.Field = $null
        }
        $runtime = $sender.HotkeySettingsRuntime
        if($runtime -and [object]::ReferenceEquals($runtime.Popup, $sender)) { $runtime.Popup = $null }
    })
    $popup | Add-Member -MemberType NoteProperty -Name HotkeySettingsRuntime -Value $Runtime -Force
    $Runtime.Popup = $popup
    Show-GaloreSystemToolPopup -Popup $popup -Owner $Anchor.FindForm()
}

# ============================================================
# HOTKEY BUTTON
# ============================================================

function Initialize-GaloreHotkeyButton {
    param([System.Windows.Forms.Form]$Form, $Runtime = $script:GaloreHotkeySettingsRuntime)
    if($null -eq $Form -or $Form.IsDisposed) { return $null }
    if($Runtime.OwnerForm -and -not $Runtime.OwnerForm.IsDisposed -and -not [object]::ReferenceEquals($Runtime.OwnerForm, $Form)) { Stop-GaloreHotkeySettingsResources -Runtime $Runtime }
    if([object]::ReferenceEquals($Runtime.OwnerForm, $Form) -and $Runtime.Button -and -not $Runtime.Button.IsDisposed) { return $Runtime.Button }
    $button = New-HotkeysButton
    $button.Name = "GaloreHotkeysButton"
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $Runtime.ToolTip = New-Object System.Windows.Forms.ToolTip
    $Runtime.ToolTip.SetToolTip($button, "Hotkeys")
    $button.Add_Click({
        param($sender, $event)
        $runtime = $this.HotkeySettingsRuntime
        if($runtime.Popup -and -not $runtime.Popup.IsDisposed) {
            $runtime.Popup.Close()
            return
        }
        Show-GaloreHotkeySettingsPopup -Anchor $sender -Runtime $runtime
    })
    $button | Add-Member -MemberType NoteProperty -Name HotkeySettingsRuntime -Value $Runtime -Force
    $Form.Controls.Add($button)
    $button.BringToFront()
    $Runtime.OwnerForm = $Form
    $Runtime.Button = $button
    return $button
}

function Get-GaloreHotkeySettingsButton {
    param($Runtime = $script:GaloreHotkeySettingsRuntime)
    return $Runtime.Button
}

function Stop-GaloreHotkeySettingsResources {
    param($Runtime = $script:GaloreHotkeySettingsRuntime)
    if($null -eq $Runtime) { return }
    if($Runtime.Popup -and -not $Runtime.Popup.IsDisposed) { try { $Runtime.Popup.Close() } catch { Write-LauncherDiagnostic -Exception $_ -Context "Failed to close the Galore hotkey settings popup." } }
    if($Runtime.ToolTip) { try { $Runtime.ToolTip.Dispose() } catch {} }
    if($Runtime.Button -and -not $Runtime.Button.IsDisposed) { try { $Runtime.Button.Dispose() } catch {} }
    $Runtime.Popup = $null
    $Runtime.ToolTip = $null
    $Runtime.Button = $null
    $Runtime.OwnerForm = $null
}
