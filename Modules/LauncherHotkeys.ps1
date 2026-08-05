# ============================================================
# LAUNCHER HOTKEYS MODULE
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherHotkeys"
    LoadOrder = 80
    RequiresModules = @("LauncherAction", "LauncherCategories", "LauncherLogging", "LauncherSettings", "LauncherStartMenu", "UI")
    RequiresFunctions = [ordered]@{
        "Close-StartSearchWindowAnimated" = "LauncherStartMenu"
        "Hide-LauncherWindowAnimated" = "UI"
        "Show-LauncherWindowAnimated" = "UI"
        "Get-LauncherSettingsFolder" = "LauncherSettings"
        "Invoke-ProgramLaunch" = "LauncherAction"
        "Save-GaloreCategoryState" = "LauncherCategories"
        "Write-LauncherDiagnostic" = "LauncherLogging"
    }
    RequiresTypes = [ordered]@{}
    RequiresVariables = @()
    RequiresFolders = @()
    RequiresFiles = @()
    ProvidesTypes = @("GlobalHotkey")
}

# ==========================
# GLOBAL HOTKEY SUPPORT
# ==========================

function Initialize-HotkeySupport {
    Add-Type -AssemblyName System.Windows.Forms
    if(-not ("GlobalHotkey" -as [type])) {
        Add-Type -ReferencedAssemblies @("System.Windows.Forms.dll"
) @"
using System;
using System.Windows.Forms;
using System.Runtime.InteropServices;


public class GlobalHotkey : NativeWindow
{

    public int LastHotkeyId { get; private set; }

    [DllImport("user32.dll")]
    public static extern bool RegisterHotKey(
        IntPtr hWnd,
        int id,
        uint fsModifiers,
        uint vk
    );


    [DllImport("user32.dll")]
    public static extern bool UnregisterHotKey(
        IntPtr hWnd,
        int id
    );


    public event EventHandler HotkeyPressed;



    public GlobalHotkey(IntPtr handle)
    {
        AssignHandle(handle);
    }



    protected override void WndProc(ref Message m)
    {

        if(m.Msg == 0x0312)
        {

            LastHotkeyId = m.WParam.ToInt32();

            if(HotkeyPressed != null)
            {
                HotkeyPressed(
                    this,
                    EventArgs.Empty
                );
            }

        }


        base.WndProc(ref m);

    }

}
"@
    }
}

# ==========================
# REGISTER CTRL + SHIFT + SPACE
# ==========================

function Initialize-GlobalHotkey {
    param($WindowHandle)
    $script:GlobalHotkeyHandle = $WindowHandle

    # ==========================
    # CREATE LISTENER
    # ==========================

    $script:GlobalHotkeyWindow = New-Object GlobalHotkey($WindowHandle)
}

# ==========================
# UNREGISTER GLOBAL HOTKEY
# ==========================

function Stop-GlobalHotkey {
    if($script:GlobalHotkeyHandle) {
        try {
            foreach($hotkeyId in 5000..5104) {
                [GlobalHotkey]::UnregisterHotKey($script:GlobalHotkeyHandle, $hotkeyId) | Out-Null
            }
        } catch {
        }
    }
    if($script:GlobalHotkeyWindow) {
        try {
            $script:GlobalHotkeyWindow.ReleaseHandle()
        } catch {
        }
    }
    $script:GlobalHotkeyWindow = $null
    $script:GlobalHotkeyHandle = $null
}

# ==========================
# TOGGLE WINDOW
# ==========================

function Register-LauncherToggleHotkey {
    param($Form)
    $hotkey = Get-GaloreLauncherToggleHotkey
    if(-not [GlobalHotkey]::RegisterHotKey($script:GlobalHotkeyHandle, 5000, $hotkey.ModifierMask, $hotkey.VirtualKey)) {
        Write-LauncherDiagnostic -Exception ([System.InvalidOperationException]::new("The launcher hotkey '$($hotkey.DisplayText)' is already in use.")) -Context "Failed to register the launcher toggle hotkey."
    }
    $script:GlobalHotkeyWindow.add_HotkeyPressed({
        if($script:GlobalHotkeyWindow.LastHotkeyId -ne 5000) {
            return
        }
        if($script:LauncherWindowTargetVisible) {
            Close-StartSearchWindowAnimated
            $script:LauncherLocation = $Form.Location
            $script:LauncherSize = $Form.Size
            Hide-LauncherWindowAnimated -Form $Form -DurationMilliseconds 170
        } else {
            $Form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
            $Form.Location = $script:LauncherLocation
            $Form.Size = $script:LauncherSize
            Show-LauncherWindowAnimated -Form $Form -DurationMilliseconds 220
        }
    })
}

# ==========================
# HOTKEY SETTINGS
# ==========================

function Get-GaloreDefaultLauncherHotkey {
    [pscustomobject]@{ ModifierMask = 6; VirtualKey = 32; DisplayText = "Ctrl+Shift+Space" }
}

function Get-GaloreDefaultCategoryHotkey {
    param([string]$CategoryId)
    $categoryNumber = [int]($CategoryId -replace "[^0-9]", "")
    if($categoryNumber -lt 1 -or $categoryNumber -gt 4) { throw "Unknown Galore category hotkey: '$CategoryId'." }
    [pscustomobject]@{ ModifierMask = 2; VirtualKey = (0x70 + ($categoryNumber - 1)); DisplayText = "Ctrl+F$categoryNumber" }
}

function Test-GaloreHotkeyDefinition {
    param($Definition)
    return ($null -ne $Definition -and [int]$Definition.ModifierMask -ge 1 -and [int]$Definition.ModifierMask -le 15 -and [int]$Definition.VirtualKey -ge 1 -and [int]$Definition.VirtualKey -le 255 -and -not [string]::IsNullOrWhiteSpace([string]$Definition.DisplayText))
}

function Initialize-GaloreHotkeySettings {
    $script:GaloreHotkeySettingsFile = Join-Path (Get-LauncherSettingsFolder) "hotkeys.json"
    $script:GaloreLauncherHotkey = Get-GaloreDefaultLauncherHotkey
    $script:GaloreCategoryHotkeys = [ordered]@{}
    foreach($categoryNumber in 1..4) { $categoryId = "Category$categoryNumber"; $script:GaloreCategoryHotkeys[$categoryId] = Get-GaloreDefaultCategoryHotkey -CategoryId $categoryId }
    $loadedSavedSettings = $false
    if(Test-Path -LiteralPath $script:GaloreHotkeySettingsFile -PathType Leaf) {
        try {
            $saved = Get-Content -LiteralPath $script:GaloreHotkeySettingsFile -Raw | ConvertFrom-Json
            if(Test-GaloreHotkeyDefinition $saved.LauncherToggle) {
                $script:GaloreLauncherHotkey = [pscustomobject]@{ ModifierMask = [int]$saved.LauncherToggle.ModifierMask; VirtualKey = [int]$saved.LauncherToggle.VirtualKey; DisplayText = [string]$saved.LauncherToggle.DisplayText }
                $loadedSavedSettings = $true
            }
            if($saved.Categories) {
                foreach($categoryProperty in $saved.Categories.PSObject.Properties) {
                    if($script:GaloreCategoryHotkeys.Contains($categoryProperty.Name) -and (Test-GaloreHotkeyDefinition $categoryProperty.Value)) {
                        $script:GaloreCategoryHotkeys[$categoryProperty.Name] = [pscustomobject]@{ ModifierMask = [int]$categoryProperty.Value.ModifierMask; VirtualKey = [int]$categoryProperty.Value.VirtualKey; DisplayText = [string]$categoryProperty.Value.DisplayText }
                    }
                }
            }
        } catch { Write-LauncherDiagnostic -Exception $_ -Context "Failed to load saved hotkey settings; the default was restored." }
    }
    if(-not $loadedSavedSettings) { Save-GaloreHotkeySettings | Out-Null }
}

function Save-GaloreHotkeySettings {
    if([string]::IsNullOrWhiteSpace([string]$script:GaloreHotkeySettingsFile) -or $null -eq $script:GaloreLauncherHotkey) { return $false }
    $temporaryFile = "$script:GaloreHotkeySettingsFile.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $settings = [pscustomobject]@{ Version = 2; LauncherToggle = $script:GaloreLauncherHotkey; Categories = [pscustomobject]$script:GaloreCategoryHotkeys }
        [IO.File]::WriteAllText($temporaryFile, ($settings | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temporaryFile -Destination $script:GaloreHotkeySettingsFile -Force
        return $true
    } catch {
        Write-LauncherDiagnostic -Exception $_ -Context "Failed to save hotkey settings."
        return $false
    }
    finally { Remove-Item -LiteralPath $temporaryFile -Force -ErrorAction SilentlyContinue }
}

function Get-GaloreLauncherToggleHotkey {
    if($null -eq $script:GaloreLauncherHotkey) { return Get-GaloreDefaultLauncherHotkey }
    return $script:GaloreLauncherHotkey
}

function Get-GaloreCategoryHotkey {
    param([string]$CategoryId)
    if($null -eq $script:GaloreCategoryHotkeys -or -not $script:GaloreCategoryHotkeys.Contains($CategoryId)) { return Get-GaloreDefaultCategoryHotkey -CategoryId $CategoryId }
    return $script:GaloreCategoryHotkeys[$CategoryId]
}

function Set-GaloreLauncherToggleHotkey {
    param([int]$ModifierMask, [int]$VirtualKey, [string]$DisplayText)
    if($ModifierMask -lt 1 -or $ModifierMask -gt 15 -or $VirtualKey -lt 1 -or $VirtualKey -gt 255 -or [string]::IsNullOrWhiteSpace($DisplayText)) { return $false }
    $previous = Get-GaloreLauncherToggleHotkey
    [GlobalHotkey]::UnregisterHotKey($script:GlobalHotkeyHandle, 5000) | Out-Null
    if(-not [GlobalHotkey]::RegisterHotKey($script:GlobalHotkeyHandle, 5000, $ModifierMask, $VirtualKey)) {
        [GlobalHotkey]::RegisterHotKey($script:GlobalHotkeyHandle, 5000, $previous.ModifierMask, $previous.VirtualKey) | Out-Null
        return $false
    }
    $script:GaloreLauncherHotkey = [pscustomobject]@{ ModifierMask = $ModifierMask; VirtualKey = $VirtualKey; DisplayText = $DisplayText }
    Save-GaloreHotkeySettings | Out-Null
    return $true
}

function Set-GaloreCategoryHotkey {
    param([string]$CategoryId, [int]$ModifierMask, [int]$VirtualKey, [string]$DisplayText)
    if(-not $script:GaloreCategoryHotkeys.Contains($CategoryId) -or $ModifierMask -lt 1 -or $ModifierMask -gt 15 -or $VirtualKey -lt 1 -or $VirtualKey -gt 255 -or [string]::IsNullOrWhiteSpace($DisplayText)) { return $false }
    $categoryNumber = [int]($CategoryId -replace "[^0-9]", "")
    $hotkeyId = 5100 + $categoryNumber
    $previous = Get-GaloreCategoryHotkey -CategoryId $CategoryId
    [GlobalHotkey]::UnregisterHotKey($script:GlobalHotkeyHandle, $hotkeyId) | Out-Null
    if(-not [GlobalHotkey]::RegisterHotKey($script:GlobalHotkeyHandle, $hotkeyId, $ModifierMask, $VirtualKey)) {
        [GlobalHotkey]::RegisterHotKey($script:GlobalHotkeyHandle, $hotkeyId, $previous.ModifierMask, $previous.VirtualKey) | Out-Null
        return $false
    }
    $script:GaloreCategoryHotkeys[$CategoryId] = [pscustomobject]@{ ModifierMask = $ModifierMask; VirtualKey = $VirtualKey; DisplayText = $DisplayText }
    Save-GaloreHotkeySettings | Out-Null
    return $true
}

function Set-GaloreHotkeyDefinitions {
    param($LauncherToggle, $CategoryHotkeys)
    if(-not (Test-GaloreHotkeyDefinition $LauncherToggle)) { return $false }
    foreach($categoryNumber in 1..4) {
        $categoryId = "Category$categoryNumber"
        if($null -eq $CategoryHotkeys[$categoryId] -or -not (Test-GaloreHotkeyDefinition $CategoryHotkeys[$categoryId])) { return $false }
    }
    $previousLauncherToggle = Get-GaloreLauncherToggleHotkey
    $previousCategoryHotkeys = [ordered]@{}
    foreach($categoryNumber in 1..4) { $categoryId = "Category$categoryNumber"; $previousCategoryHotkeys[$categoryId] = Get-GaloreCategoryHotkey -CategoryId $categoryId }
    foreach($hotkeyId in @(5000, 5101, 5102, 5103, 5104)) { [GlobalHotkey]::UnregisterHotKey($script:GlobalHotkeyHandle, $hotkeyId) | Out-Null }
    $registered = $true
    if(-not [GlobalHotkey]::RegisterHotKey($script:GlobalHotkeyHandle, 5000, $LauncherToggle.ModifierMask, $LauncherToggle.VirtualKey)) { $registered = $false }
    foreach($categoryNumber in 1..4) {
        if(-not $registered) { break }
        $categoryId = "Category$categoryNumber"
        if(-not [GlobalHotkey]::RegisterHotKey($script:GlobalHotkeyHandle, (5100 + $categoryNumber), $CategoryHotkeys[$categoryId].ModifierMask, $CategoryHotkeys[$categoryId].VirtualKey)) { $registered = $false }
    }
    if(-not $registered) {
        foreach($hotkeyId in @(5000, 5101, 5102, 5103, 5104)) { [GlobalHotkey]::UnregisterHotKey($script:GlobalHotkeyHandle, $hotkeyId) | Out-Null }
        [GlobalHotkey]::RegisterHotKey($script:GlobalHotkeyHandle, 5000, $previousLauncherToggle.ModifierMask, $previousLauncherToggle.VirtualKey) | Out-Null
        foreach($categoryNumber in 1..4) { $categoryId = "Category$categoryNumber"; [GlobalHotkey]::RegisterHotKey($script:GlobalHotkeyHandle, (5100 + $categoryNumber), $previousCategoryHotkeys[$categoryId].ModifierMask, $previousCategoryHotkeys[$categoryId].VirtualKey) | Out-Null }
        return $false
    }
    $script:GaloreLauncherHotkey = [pscustomobject]@{ ModifierMask = [int]$LauncherToggle.ModifierMask; VirtualKey = [int]$LauncherToggle.VirtualKey; DisplayText = [string]$LauncherToggle.DisplayText }
    foreach($categoryNumber in 1..4) { $categoryId = "Category$categoryNumber"; $definition = $CategoryHotkeys[$categoryId]; $script:GaloreCategoryHotkeys[$categoryId] = [pscustomobject]@{ ModifierMask = [int]$definition.ModifierMask; VirtualKey = [int]$definition.VirtualKey; DisplayText = [string]$definition.DisplayText } }
    Save-GaloreHotkeySettings | Out-Null
    $script:GaloreHotkeysSuspended = $false
    return $true
}

function Suspend-GaloreHotkeys {
    if($script:GaloreHotkeysSuspended -or -not $script:GlobalHotkeyHandle) { return }
    foreach($hotkeyId in @(5000, 5101, 5102, 5103, 5104)) { [GlobalHotkey]::UnregisterHotKey($script:GlobalHotkeyHandle, $hotkeyId) | Out-Null }
    $script:GaloreHotkeysSuspended = $true
}

function Resume-GaloreHotkeys {
    if(-not $script:GaloreHotkeysSuspended) { return $true }
    $categoryHotkeys = [ordered]@{}
    foreach($categoryNumber in 1..4) { $categoryId = "Category$categoryNumber"; $categoryHotkeys[$categoryId] = Get-GaloreCategoryHotkey -CategoryId $categoryId }
    return Set-GaloreHotkeyDefinitions -LauncherToggle (Get-GaloreLauncherToggleHotkey) -CategoryHotkeys $categoryHotkeys
}

# ==========================
# CATEGORY HOTKEYS
# ==========================

function Register-GaloreCategoryHotkeys {
    param($Programs, $Checks, $Statuses, $AppRoot)
    for($categoryNumber = 1; $categoryNumber -le 4; $categoryNumber++) {
        $categoryId = "Category$categoryNumber"
        $hotkeyId = 5100 + $categoryNumber
        $hotkey = Get-GaloreCategoryHotkey -CategoryId $categoryId
        $action = {
            $category = @($script:GaloreCategoryState.Categories | Where-Object { $_.Id -eq $categoryId }) | Select-Object -First 1
            if($null -eq $category) { return }
            $programNames = @($category.Slots | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Path) -and $_.Selected } | ForEach-Object { $_.Id })
            if($programNames.Count -gt 0) { Invoke-ProgramLaunch -Programs $Programs -Statuses $Statuses -ProgramNames $programNames -AppRoot $AppRoot -ShowStartingStatus }
        }.GetNewClosure()
        if([GlobalHotkey]::RegisterHotKey($script:GlobalHotkeyHandle, $hotkeyId, $hotkey.ModifierMask, $hotkey.VirtualKey)) {
            $script:GlobalHotkeyWindow.add_HotkeyPressed({ if($script:GlobalHotkeyWindow.LastHotkeyId -eq $hotkeyId) { & $action } }.GetNewClosure())
        }
        else { Write-LauncherDiagnostic -Exception ([System.InvalidOperationException]::new("The category hotkey '$($hotkey.DisplayText)' is already in use.")) -Context "Failed to register the category hotkey for '$categoryId'." }
    }
}
