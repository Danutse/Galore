# ============================================================
# LAUNCHER PROCESS MODULE
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherProcess"
    LoadOrder = 30
    RequiresModules = @("LauncherIntegrationAdapters")
    RequiresFunctions = [ordered]@{
        "Get-GaloreVisibleProcess" = "LauncherIntegrationAdapters"
        "Test-GaloreProcessRunning" = "LauncherIntegrationAdapters"
    }
    RequiresTypes = [ordered]@{}
    RequiresVariables = @()
    RequiresFolders = @()
    RequiresFiles = @()
    ProvidesTypes = @("WindowFocus")
}

# ============================================================
# BRING PROGRAM WINDOW TO FRONT (FORCED)
# ============================================================

if(-not ("WindowFocus" -as [type])) {
Add-Type @"

using System;
using System.Runtime.InteropServices;

public class WindowFocus {

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(
        IntPtr hWnd,
        int nCmdShow
    );


    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(
        IntPtr hWnd
    );


    [DllImport("user32.dll")]
    public static extern bool IsIconic(
        IntPtr hWnd
    );


    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(
        IntPtr hWnd,
        IntPtr ProcessId
    );


    [DllImport("kernel32.dll")]
    public static extern uint GetCurrentThreadId();


    [DllImport("user32.dll")]
    public static extern bool AttachThreadInput(
        uint idAttach,
        uint idAttachTo,
        bool fAttach
    );

}

"@
}

function Bring-ProgramToFront {
    param([string]$ProcessName)
    $process = Get-GaloreVisibleProcess -ProcessName $ProcessName
    if(!$process) {
        return
    }
    $handle = $process.MainWindowHandle
    if([WindowFocus]::IsIconic($handle)) {
        [WindowFocus]::ShowWindow($handle, 9)
    }
    $windowThread = [WindowFocus]::GetWindowThreadProcessId($handle, [IntPtr]::Zero)
    $currentThread = [WindowFocus]::GetCurrentThreadId()
    $inputAttached = $false
    if($windowThread -ne $currentThread) {
        $inputAttached = [WindowFocus]::AttachThreadInput($currentThread, $windowThread, $true)
    }
    try {
        [WindowFocus]::ShowWindow($handle, 5)
        [WindowFocus]::SetForegroundWindow($handle)
    } finally {
        if($inputAttached) {
            [WindowFocus]::AttachThreadInput($currentThread, $windowThread, $false) | Out-Null
        }
    }
}

# ============================================================
# CHECK PROGRAM STATUS
# ============================================================

function Get-ProgramStatus {
    param([string]$ProcessName)
    return Test-GaloreProcessRunning -ProcessName $ProcessName
}
