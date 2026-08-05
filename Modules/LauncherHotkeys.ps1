# ============================================================
# LAUNCHER HOTKEYS MODULE
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherHotkeys"
    LoadOrder = 70
    RequiresModules = @("LauncherStartMenu", "UI")
    RequiresFunctions = [ordered]@{
        "Close-StartSearchWindowAnimated" = "LauncherStartMenu"
        "Hide-LauncherWindowAnimated" = "UI"
        "Show-LauncherWindowAnimated" = "UI"
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

$HOTKEY_ID = 5000

$MOD_CONTROL =
0x0002

$MOD_SHIFT =
0x0004

$VK_SPACE =
0x20

[GlobalHotkey]::RegisterHotKey(
    $WindowHandle,
    $HOTKEY_ID,
    ($MOD_CONTROL -bor $MOD_SHIFT),
    $VK_SPACE
) | Out-Null

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

        [GlobalHotkey]::UnregisterHotKey(
            $script:GlobalHotkeyHandle,
            5000
        ) | Out-Null

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

$script:GlobalHotkeyWindow.add_HotkeyPressed({

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
