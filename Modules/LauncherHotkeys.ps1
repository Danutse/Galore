# ============================================================
# LAUNCHER HOTKEYS MODULE
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherHotkeys"
    LoadOrder = 70
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

function Initialize-HotkeySupport
{

Add-Type -AssemblyName System.Windows.Forms

if(
    -not (
        "GlobalHotkey" -as [type]
    )
)
{

Add-Type -ReferencedAssemblies @(
    "System.Windows.Forms.dll"
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

function Initialize-GlobalHotkey
{

param(
    $WindowHandle
)

$script:GlobalHotkeyHandle = $WindowHandle

# ==========================
# CREATE LISTENER
# ==========================

$script:GlobalHotkeyWindow =
New-Object GlobalHotkey(
    $WindowHandle
)

}

# ==========================
# UNREGISTER GLOBAL HOTKEY
# ==========================

function Stop-GlobalHotkey
{

if(
    $script:GlobalHotkeyHandle
)
{

    try
    {

        foreach($hotkeyId in 5000..5104)
        {
            [GlobalHotkey]::UnregisterHotKey(
                $script:GlobalHotkeyHandle,
                $hotkeyId
            ) | Out-Null
        }

    }
    catch
    {

    }

}

if(
    $script:GlobalHotkeyWindow
)
{

    try
    {

        $script:GlobalHotkeyWindow.ReleaseHandle()

    }
    catch
    {

    }

}

$script:GlobalHotkeyWindow = $null

$script:GlobalHotkeyHandle = $null

}

# ==========================
# TOGGLE WINDOW
# ==========================

function Register-LauncherToggleHotkey
{

param(
    $Form
)

$hotkey =
Get-GaloreLauncherToggleHotkey

if(
    -not [GlobalHotkey]::RegisterHotKey(
        $script:GlobalHotkeyHandle,
        5000,
        $hotkey.ModifierMask,
        $hotkey.VirtualKey
    )
)
{
    Write-LauncherDiagnostic `
    -Exception ([System.InvalidOperationException]::new("The launcher hotkey '$($hotkey.DisplayText)' is already in use.")) `
    -Context "Failed to register the launcher toggle hotkey."
}

$script:GlobalHotkeyWindow.add_HotkeyPressed({

    if($script:GlobalHotkeyWindow.LastHotkeyId -ne 5000)
    {
        return
    }

    if(
        $script:LauncherWindowTargetVisible
    )
    {

        Close-StartSearchWindowAnimated

        $script:LauncherLocation =
        $Form.Location

        $script:LauncherSize =
        $Form.Size

        Hide-LauncherWindowAnimated `
        -Form $Form `
        -DurationMilliseconds 170

    }

    else
    {

        $Form.WindowState =
        [System.Windows.Forms.FormWindowState]::Normal

        $Form.Location =
        $script:LauncherLocation

        $Form.Size =
        $script:LauncherSize

        Show-LauncherWindowAnimated `
        -Form $Form `
        -DurationMilliseconds 220

    }

})

}

# ==========================
# HOTKEY SETTINGS
# ==========================

function Get-GaloreDefaultLauncherHotkey {
    [pscustomobject]@{ ModifierMask = 6; VirtualKey = 32; DisplayText = "Ctrl+Shift+Space" }
}

function Initialize-GaloreHotkeySettings {
    $script:GaloreHotkeySettingsFile = Join-Path (Get-LauncherSettingsFolder) "hotkeys.json"
    $script:GaloreLauncherHotkey = Get-GaloreDefaultLauncherHotkey
    if(Test-Path -LiteralPath $script:GaloreHotkeySettingsFile -PathType Leaf)
    {
        try {
            $saved = Get-Content -LiteralPath $script:GaloreHotkeySettingsFile -Raw | ConvertFrom-Json
            $modifierMask = [int]$saved.LauncherToggle.ModifierMask
            $virtualKey = [int]$saved.LauncherToggle.VirtualKey
            $displayText = [string]$saved.LauncherToggle.DisplayText
            if($modifierMask -lt 1 -or $modifierMask -gt 15 -or $virtualKey -lt 1 -or $virtualKey -gt 255 -or [string]::IsNullOrWhiteSpace($displayText)) { throw "Saved hotkey settings are invalid." }
            $script:GaloreLauncherHotkey = [pscustomobject]@{ ModifierMask = $modifierMask; VirtualKey = $virtualKey; DisplayText = $displayText }
        }
        catch { Write-LauncherDiagnostic -Exception $_ -Context "Failed to load saved hotkey settings; the default was restored." }
    }
    Save-GaloreHotkeySettings
}

function Save-GaloreHotkeySettings {
    if([string]::IsNullOrWhiteSpace([string]$script:GaloreHotkeySettingsFile) -or $null -eq $script:GaloreLauncherHotkey) { return }
    $temporaryFile = "$script:GaloreHotkeySettingsFile.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporaryFile, ([pscustomobject]@{ Version = 1; LauncherToggle = $script:GaloreLauncherHotkey } | ConvertTo-Json -Depth 3), (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temporaryFile -Destination $script:GaloreHotkeySettingsFile -Force
    }
    catch { Write-LauncherDiagnostic -Exception $_ -Context "Failed to save hotkey settings." }
    finally { Remove-Item -LiteralPath $temporaryFile -Force -ErrorAction SilentlyContinue }
}

function Get-GaloreLauncherToggleHotkey {
    if($null -eq $script:GaloreLauncherHotkey) { return Get-GaloreDefaultLauncherHotkey }
    return $script:GaloreLauncherHotkey
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
    Save-GaloreHotkeySettings
    return $true
}

# ==========================
# CATEGORY HOTKEYS
# ==========================

function Register-GaloreCategoryHotkeys {
    param($Programs, $Checks, $Statuses, $AppRoot)
    for($categoryNumber = 1; $categoryNumber -le 4; $categoryNumber++) {
        $categoryId = "Category$categoryNumber"
        $hotkeyId = 5100 + $categoryNumber
        $virtualKey = 0x70 + ($categoryNumber - 1)
        $action = {
            $category = @($script:GaloreCategoryState.Categories | Where-Object { $_.Id -eq $categoryId }) | Select-Object -First 1
            if($null -eq $category) { return }
            $programNames = @($category.Slots | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Path) -and $_.Selected } | ForEach-Object { $_.Id })
            if($programNames.Count -gt 0) { Invoke-ProgramLaunch -Programs $Programs -Statuses $Statuses -ProgramNames $programNames -AppRoot $AppRoot -ShowStartingStatus }
        }.GetNewClosure()
        if([GlobalHotkey]::RegisterHotKey($script:GlobalHotkeyHandle, $hotkeyId, 0x0002, $virtualKey)) {
            $script:GlobalHotkeyWindow.add_HotkeyPressed({ if($script:GlobalHotkeyWindow.LastHotkeyId -eq $hotkeyId) { & $action } }.GetNewClosure())
        }
        else { Write-LauncherDiagnostic -Exception ([System.InvalidOperationException]::new("Ctrl+F$categoryNumber is already in use.")) -Context "Failed to register the category hotkey for '$categoryId'." }
    }
}
