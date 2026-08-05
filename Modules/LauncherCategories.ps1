# ============================================================
# LAUNCHER CATEGORIES MODULE
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherCategories"
    LoadOrder = 260
    RequiresModules = @("LauncherDomain", "LauncherAlphaOverlay", "LauncherLogging", "LauncherSettings", "LauncherPrograms")
    RequiresFunctions = [ordered]@{
        "Get-LauncherSettingsFolder" = "LauncherSettings"
        "Write-LauncherDiagnostic" = "LauncherLogging"
        "Show-GaloreProgramNameDialog" = "LauncherPrograms"
        "Set-GaloreTransparentWindowRegion" = "LauncherAlphaOverlay"
    }
    RequiresTypes = [ordered]@{
        "GaloreCategorySlot" = "LauncherDomain"
        "GaloreCategory" = "LauncherDomain"
        "GaloreCategoryState" = "LauncherDomain"
    }
    RequiresVariables = @("AppRoot")
    RequiresFolders = @("resources")
    RequiresFiles = @()
    ProvidesTypes = @()
}
$script:GaloreCategoryState = $null
$script:GaloreCategoryFile = $null
$script:GaloreCategoryWindows = @{}

# ============================================================
# PERSISTENCE
# ============================================================

function New-GaloreCategoryState {
    $categories = @()
    for($categoryIndex = 1; $categoryIndex -le 4; $categoryIndex++) {
        $slots = @()
        for($slotIndex = 1; $slotIndex -le 5; $slotIndex++) {
            $slots += [GaloreCategorySlot]::new("Category$categoryIndex`Slot$slotIndex")
        }
        $categories += [GaloreCategory]::new("Category$categoryIndex", "Category $categoryIndex", [GaloreCategorySlot[]]$slots)
    }
    $state = [GaloreCategoryState]::new()
    $state.Categories = [GaloreCategory[]]$categories
    return $state
}

function Save-GaloreCategoryState {
    if($script:GaloreCategoryState -and $script:GaloreCategoryFile) {
        $temporaryFile = "$script:GaloreCategoryFile.$([guid]::NewGuid().ToString('N')).tmp"
        try {
            [IO.File]::WriteAllText($temporaryFile, ($script:GaloreCategoryState | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
            Move-Item -LiteralPath $temporaryFile -Destination $script:GaloreCategoryFile -Force
        } catch { Write-LauncherDiagnostic -Exception $_ -Context "Failed to save Galore categories." }
        finally { Remove-Item -LiteralPath $temporaryFile -Force -ErrorAction SilentlyContinue }
    }
}

function Initialize-GaloreCategoryState {
    $script:GaloreCategoryFile = Join-Path (Get-LauncherSettingsFolder) "categories.json"
    $state = New-GaloreCategoryState
    if(Test-Path -LiteralPath $script:GaloreCategoryFile -PathType Leaf) {
        try {
            $saved = Get-Content -LiteralPath $script:GaloreCategoryFile -Raw | ConvertFrom-Json
            if(($saved.Version -isnot [int] -and $saved.Version -isnot [long]) -or [long]$saved.Version -ne 1 -or @($saved.Categories).Count -ne 4) { throw "Invalid category data." }
            for($categoryIndex = 0; $categoryIndex -lt 4; $categoryIndex++) {
                $savedCategory = @($saved.Categories)[$categoryIndex]
                if($null -eq $savedCategory -or $savedCategory.Name -isnot [string] -or [string]::IsNullOrWhiteSpace($savedCategory.Name) -or @($savedCategory.Slots).Count -ne 5) { throw "Invalid category data." }
                $state.Categories[$categoryIndex].Name = [string]$savedCategory.Name
                for($slotIndex = 0; $slotIndex -lt 5; $slotIndex++) {
                    $savedSlot = @($savedCategory.Slots)[$slotIndex]
                    if($null -eq $savedSlot -or $savedSlot.Path -isnot [string] -or $savedSlot.DisplayName -isnot [string] -or $null -eq $savedSlot.PSObject.Properties["Selected"] -or $savedSlot.Selected -isnot [bool]) { throw "Invalid category slot data." }
                    $slot = $state.Categories[$categoryIndex].Slots[$slotIndex]
                    $slot.Path = [string]$savedSlot.Path
                    $slot.DisplayName = if([string]::IsNullOrWhiteSpace([string]$savedSlot.DisplayName)) { "Empty" } else { [string]$savedSlot.DisplayName }
                    $slot.Selected = [bool]$savedSlot.Selected
                }
            }
        } catch { Write-LauncherDiagnostic -Exception $_ -Context "Failed to load Galore categories; default categories were restored." }
    }
    $script:GaloreCategoryState = $state
    Save-GaloreCategoryState
    $state
}

function Test-GaloreCategorySlotConfigured {
    param($Slot)
    if($Slot -is [GaloreCategorySlot]) {
        return $Slot.IsConfigured()
    }
    return $null -ne $Slot -and -not [string]::IsNullOrWhiteSpace([string]$Slot.Path)
}

function Update-GaloreCategoryMaster {
    param($Category, [System.Windows.Forms.CheckBox]$Master)
    $configured = @($Category.Slots | Where-Object { Test-GaloreCategorySlotConfigured $_ })
    $selected = @($configured | Where-Object { $_.Selected })
    if($configured.Count -eq 0 -or $selected.Count -eq 0) { $Master.CheckState = [System.Windows.Forms.CheckState]::Unchecked }
    elseif($configured.Count -eq $selected.Count) { $Master.CheckState = [System.Windows.Forms.CheckState]::Checked }
    else { $Master.CheckState = [System.Windows.Forms.CheckState]::Indeterminate }
}

# ============================================================
# CATEGORY EDITING
# ============================================================

function Rename-GaloreCategory {
    param($Category, [System.Windows.Forms.CheckBox]$Master)
    $name = Show-GaloreProgramNameDialog -Prompt "Choose the name shown in Galore for this category." -DefaultName $Category.Name -Owner $Master.FindForm()
    if(-not [string]::IsNullOrWhiteSpace($name)) { $Category.Name = $name; $Master.Text = $name; Save-GaloreCategoryState }
}

function Set-GaloreCategorySlot {
    param($Slot, $Category, [System.Windows.Forms.CheckBox]$Master, [System.Windows.Forms.Label]$Label, [System.Windows.Forms.CheckBox]$Check, $Programs, $Checks, [System.Windows.Forms.Form]$Window)
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "Choose the executable for $($Category.Name)"
    $dialog.Filter = "Applications (*.exe)|*.exe"
    $dialog.CheckFileExists = $true
    try {
        $Window.Tag.IsSelecting = $true
        if($dialog.ShowDialog($Window) -ne [System.Windows.Forms.DialogResult]::OK) { return }
        $defaultName = [IO.Path]::GetFileNameWithoutExtension($dialog.FileName)
        $displayName = Show-GaloreProgramNameDialog -Prompt "Choose the name shown in Galore for this item." -DefaultName $defaultName -Owner $Window
        $Slot.Path = $dialog.FileName
        $Slot.DisplayName = $displayName
        $Slot.Selected = $true
        $processName = [IO.Path]::GetFileNameWithoutExtension($dialog.FileName)
        $program = $Programs[$Slot.Id]
        $program.Path = $Slot.Path
        $program.Args = ""
        $program.StatusProcess = $processName
        $program.WindowProcess = $processName
        $program.DisplayName = $displayName
        $Checks[$Slot.Id].Checked = $true
        if(-not $Label.IsDisposed) { $Label.Text = $displayName }
        if(-not $Check.IsDisposed) { $Check.Checked = $true }
        Update-GaloreCategoryMaster -Category $Category -Master $Master
        Save-GaloreCategoryState
    } catch { Write-LauncherDiagnostic -Exception $_ -Context "Failed to configure category slot '$($Slot.Id)'." }
    finally { $Window.Tag.IsSelecting = $false; $dialog.Dispose() }
}

function Clear-GaloreCategorySlot {
    param($Slot, $Category, [System.Windows.Forms.CheckBox]$Master, [System.Windows.Forms.Label]$Label, [System.Windows.Forms.CheckBox]$Check, $Programs, $Checks)
    if($Slot -is [GaloreCategorySlot]) {
        $Slot.Clear()
    } else {
        $Slot.Path = ""
        $Slot.DisplayName = "Empty"
        $Slot.Selected = $false
    }
    $program = $Programs[$Slot.Id]
    $program.Path = ""
    $program.Args = ""
    $program.StatusProcess = ""
    $program.WindowProcess = ""
    $program.DisplayName = "Empty"
    $Checks[$Slot.Id].Checked = $false
    if(-not $Label.IsDisposed) { $Label.Text = "Empty" }
    if(-not $Check.IsDisposed -and $Check.Checked) { $Check.Checked = $false }
    Update-GaloreCategoryMaster -Category $Category -Master $Master
    Save-GaloreCategoryState
}

# ============================================================
# CATEGORY WINDOW
# ============================================================

function Show-GaloreCategoryWindow {
    param($Category, [System.Windows.Forms.CheckBox]$Master, $Programs, $Checks)
    if($script:GaloreCategoryWindows.ContainsKey($Category.Id) -and -not $script:GaloreCategoryWindows[$Category.Id].IsDisposed) { $script:GaloreCategoryWindows[$Category.Id].Close(); return }
    $window = New-Object System.Windows.Forms.Form
    $window.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $window.ShowInTaskbar = $false
    $window.TopMost = $true
    $window.BackColor = [System.Drawing.Color]::Black
    $window.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $imagePath = Get-GaloreResourcePath "categoryselector.png"
    if(Test-Path -LiteralPath $imagePath -PathType Leaf) {
        try { $source = [System.Drawing.Image]::FromFile($imagePath); $window.BackgroundImage = New-Object System.Drawing.Bitmap($source); $source.Dispose(); $window.BackgroundImageLayout = [System.Windows.Forms.ImageLayout]::None; $window.ClientSize = $window.BackgroundImage.Size; Set-GaloreTransparentWindowRegion -Form $window -Bitmap $window.BackgroundImage }
        catch { Write-LauncherDiagnostic -Exception $_ -Context "Failed to load category selector artwork." }
    }
    if($null -eq $window.BackgroundImage) { $window.ClientSize = [System.Drawing.Size]::new(300, 260) }
    $window.Tag = [pscustomobject]@{ IsSelecting = $false; CategoryId = [string]$Category.Id; HoveredSlot = $null }
    $window.KeyPreview = $true
    $script:GaloreCategoryWindows[$Category.Id] = $window
    $window.Add_Disposed({ if($this.BackgroundImage) { $this.BackgroundImage.Dispose(); $this.BackgroundImage = $null } })
    $top = 20
    foreach($slot in $Category.Slots) {
        $check = New-Object System.Windows.Forms.CheckBox
        $check.Bounds = [System.Drawing.Rectangle]::new(34, $top, 22, 24)
        $check.BackColor = [System.Drawing.Color]::Transparent
        $check.AutoCheck = $false
        $check.Checked = [bool]$slot.Selected
        $label = New-Object System.Windows.Forms.Label
        $label.Bounds = [System.Drawing.Rectangle]::new(62, $top, [Math]::Max(35, $window.ClientSize.Width - 78), 24)
        $label.Text = $slot.DisplayName
        $label.ForeColor = [System.Drawing.Color]::White
        $label.BackColor = [System.Drawing.Color]::Transparent
        $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $label.Cursor = [System.Windows.Forms.Cursors]::Hand
        $context = [pscustomobject]@{ Slot = $slot; Category = $Category; Master = $Master; Label = $label; Check = $check; Programs = $Programs; Checks = $Checks }
        $check.Tag = $context
        $label.Tag = $context
        $check.Add_CheckedChanged({ $state = $this.Tag; $state.Slot.Selected = [bool]$this.Checked; $state.Checks[$state.Slot.Id].Checked = [bool]$this.Checked; Update-GaloreCategoryMaster -Category $state.Category -Master $state.Master; Save-GaloreCategoryState })
        $slotMouseUp = { param($sender, $event) $state = $sender.Tag; if($event.Button -eq [System.Windows.Forms.MouseButtons]::Right) { Set-GaloreCategorySlot -Slot $state.Slot -Category $state.Category -Master $state.Master -Label $state.Label -Check $state.Check -Programs $state.Programs -Checks $state.Checks -Window $sender.FindForm() } elseif($event.Button -eq [System.Windows.Forms.MouseButtons]::Left) { $state.Check.Checked = -not $state.Check.Checked } }
        $setHoveredSlot = { $this.FindForm().Tag.HoveredSlot = $this.Tag }
        $clearHoveredSlot = { $window = $this.FindForm(); if($window -and $window.Tag.HoveredSlot -eq $this.Tag) { $window.Tag.HoveredSlot = $null } }
        $check.Add_MouseUp($slotMouseUp)
        $label.Add_MouseUp($slotMouseUp)
        $check.Add_MouseEnter($setHoveredSlot)
        $label.Add_MouseEnter($setHoveredSlot)
        $check.Add_MouseLeave($clearHoveredSlot)
        $label.Add_MouseLeave($clearHoveredSlot)
        $window.Controls.Add($check)
        $window.Controls.Add($label)
        $top += 44
    }
    $window.Add_KeyDown({ param($sender, $event) if($event.KeyCode -eq [System.Windows.Forms.Keys]::Delete -and $this.Tag.HoveredSlot) { $state = $this.Tag.HoveredSlot; Clear-GaloreCategorySlot -Slot $state.Slot -Category $state.Category -Master $state.Master -Label $state.Label -Check $state.Check -Programs $state.Programs -Checks $state.Checks; $event.SuppressKeyPress = $true; $event.Handled = $true } })
    $window.Add_Deactivate({ if(-not $this.IsDisposed -and -not $this.Tag.IsSelecting) { $this.Close() } })
    $window.Add_FormClosed({ $categoryId = [string]$this.Tag.CategoryId; if(-not [string]::IsNullOrWhiteSpace($categoryId) -and $script:GaloreCategoryWindows.ContainsKey($categoryId) -and [object]::ReferenceEquals($script:GaloreCategoryWindows[$categoryId], $this)) { $script:GaloreCategoryWindows.Remove($categoryId) | Out-Null } })
    $point = $Master.PointToScreen([System.Drawing.Point]::new(0, $Master.Height + 2))
    $area = [System.Windows.Forms.Screen]::FromPoint($point).WorkingArea
    $window.Location = [System.Drawing.Point]::new([Math]::Min($area.Right - $window.Width, [Math]::Max($area.Left, $point.X)), [Math]::Min($area.Bottom - $window.Height, [Math]::Max($area.Top, $point.Y)))
    $window.Show($Master.FindForm())
}

# ============================================================
# CATEGORY CONTROLS
# ============================================================

function Initialize-GaloreCategories {
    param([System.Windows.Forms.Form]$Form)
    $state = Initialize-GaloreCategoryState
    $programs = @{}
    $checks = @{}
    foreach($category in $state.Categories) { foreach($slot in $category.Slots) { $processName = if(Test-GaloreCategorySlotConfigured $slot) { [IO.Path]::GetFileNameWithoutExtension($slot.Path) } else { "" }; $programs[$slot.Id] = @{ Path = $slot.Path; Args = ""; StatusProcess = $processName; WindowProcess = $processName; DisplayName = $slot.DisplayName }; $checks[$slot.Id] = [pscustomobject]@{ Checked = [bool]$slot.Selected } } }
    for($index = 0; $index -lt 4; $index++) {
        $category = $state.Categories[$index]
        $master = New-Object System.Windows.Forms.CheckBox
        $master.Name = $category.Id
        $master.Text = $category.Name
        $master.AutoCheck = $false
        $master.ThreeState = $true
        $master.Bounds = [System.Drawing.Rectangle]::new((195 + ($index * 165)), 45, 155, 30)
        $master.ForeColor = [System.Drawing.Color]::White
        $master.BackColor = [System.Drawing.Color]::Transparent
        $master.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $master.Cursor = [System.Windows.Forms.Cursors]::Hand
        $master.Tag = [pscustomobject]@{ Category = $category; Programs = $programs; Checks = $checks; SuppressRightClick = $false }
        Update-GaloreCategoryMaster -Category $category -Master $master
        $master.Add_Click({ $state = $this.Tag; $configured = @($state.Category.Slots | Where-Object { Test-GaloreCategorySlotConfigured $_ }); $all = $configured.Count -gt 0 -and @($configured | Where-Object { $_.Selected }).Count -eq $configured.Count; foreach($slot in $state.Category.Slots) { $slot.Selected = (Test-GaloreCategorySlotConfigured $slot) -and -not $all; $state.Checks[$slot.Id].Checked = [bool]$slot.Selected }; Update-GaloreCategoryMaster -Category $state.Category -Master $this; Save-GaloreCategoryState })
        $master.Add_MouseDown({ param($sender, $event) if($event.Button -eq [System.Windows.Forms.MouseButtons]::Right) { $state = $sender.Tag; $state.SuppressRightClick = $false; $categoryId = [string]$state.Category.Id; if($script:GaloreCategoryWindows.ContainsKey($categoryId) -and -not $script:GaloreCategoryWindows[$categoryId].IsDisposed) { $state.SuppressRightClick = $true; $script:GaloreCategoryWindows[$categoryId].Close() } } })
        $master.Add_MouseUp({ param($sender, $event) if($event.Button -eq [System.Windows.Forms.MouseButtons]::Right) { $state = $sender.Tag; if($state.SuppressRightClick) { $state.SuppressRightClick = $false; return }; if(([System.Windows.Forms.Control]::ModifierKeys -band [System.Windows.Forms.Keys]::Control) -eq [System.Windows.Forms.Keys]::Control) { Rename-GaloreCategory -Category $state.Category -Master $sender } else { Show-GaloreCategoryWindow -Category $state.Category -Master $sender -Programs $state.Programs -Checks $state.Checks } } })
        $Form.Controls.Add($master)
        $master.BringToFront()
    }
    [pscustomobject]@{ Programs = $programs; Checks = $checks }
}
