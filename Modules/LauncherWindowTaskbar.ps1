# ============================================================
# LAUNCHER WINDOW TASKBAR MODULE
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherWindowTaskbar"
    LoadOrder = 250
    RequiresModules = @("LauncherAlphaOverlay", "LauncherDomain", "LauncherLogging")
    RequiresFunctions = [ordered]@{
        "Write-GaloreLog" = "LauncherLogging"
        "Write-LauncherDiagnostic" = "LauncherLogging"
        "Invoke-GaloreEventSafely" = "LauncherLogging"
        "Register-GaloreOverlayForm" = "LauncherAlphaOverlay"
        "Unregister-GaloreOverlayForm" = "LauncherAlphaOverlay"
        "Set-GaloreOverlayLifecycleReady" = "LauncherAlphaOverlay"
    }
    RequiresTypes = [ordered]@{
        "GaloreAlphaOverlay.PerPixelAlphaForm" = "LauncherAlphaOverlay"
        "GaloreWindowTaskbarRuntimeState" = "LauncherDomain"
    }
    RequiresVariables = @()
    RequiresFolders = @()
    RequiresFiles = @()
    ProvidesTypes = @("GaloreWindowTaskbar.Native")
}
if(-not ("GaloreWindowTaskbar.Native" -as [type])) {
    Add-Type @"
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace GaloreWindowTaskbar
{
    public sealed class WindowInfo
    {
        public IntPtr Handle { get; set; }
        public uint ProcessId { get; set; }
        public string Title { get; set; }
    }

    public static class Native
    {
        private const int GWL_EXSTYLE = -20;
        private const long WS_EX_TOOLWINDOW = 0x00000080L;
        private const int GW_OWNER = 4;
        private const int SW_RESTORE = 9;
        private const int SW_MINIMIZE = 6;
        private const uint WM_CLOSE = 0x0010;

        private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        [DllImport("user32.dll")]
        private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

        [DllImport("user32.dll")]
        private static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern int GetWindowTextLength(IntPtr hWnd);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int maxCount);

        [DllImport("user32.dll", EntryPoint = "GetWindowLongPtr", SetLastError = true)]
        private static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int index);

        [DllImport("user32.dll", EntryPoint = "GetWindowLong", SetLastError = true)]
        private static extern IntPtr GetWindowLong32(IntPtr hWnd, int index);

        [DllImport("user32.dll")]
        private static extern IntPtr GetWindow(IntPtr hWnd, int command);

        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

        [DllImport("user32.dll")]
        public static extern bool IsIconic(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int command);

        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        public static extern bool PostMessage(IntPtr hWnd, uint message, IntPtr wParam, IntPtr lParam);

        private static long GetExtendedStyle(IntPtr hWnd)
        {
            return IntPtr.Size == 8
                ? GetWindowLongPtr64(hWnd, GWL_EXSTYLE).ToInt64()
                : GetWindowLong32(hWnd, GWL_EXSTYLE).ToInt64();
        }

        public static bool IsTaskbarWindowCandidate(
            bool isVisible,
            bool hasOwner,
            bool isToolWindow,
            bool isMainWindow,
            int titleLength,
            bool isExcludedProcess
        )
        {
            return isVisible &&
                !hasOwner &&
                !isToolWindow &&
                isMainWindow &&
                titleLength > 0 &&
                !isExcludedProcess;
        }

        public static WindowInfo[] GetTaskbarWindows(int excludedProcessId)
        {
            List<WindowInfo> windows = new List<WindowInfo>();

            EnumWindows(delegate(IntPtr hWnd, IntPtr lParam)
            {
                uint processId;
                GetWindowThreadProcessId(hWnd, out processId);

                bool isMainWindow = false;

                try
                {
                    using(Process process = Process.GetProcessById((int)processId))
                    {
                        isMainWindow = process.MainWindowHandle == hWnd;
                    }
                }
                catch
                {
                    return true;
                }

                int length = GetWindowTextLength(hWnd);
                bool isCandidate = IsTaskbarWindowCandidate(
                    IsWindowVisible(hWnd),
                    GetWindow(hWnd, GW_OWNER) != IntPtr.Zero,
                    (GetExtendedStyle(hWnd) & WS_EX_TOOLWINDOW) != 0,
                    isMainWindow,
                    length,
                    processId == (uint)excludedProcessId
                );

                if(!isCandidate)
                    return true;

                StringBuilder title = new StringBuilder(length + 1);
                GetWindowText(hWnd, title, title.Capacity);

                windows.Add(new WindowInfo {
                    Handle = hWnd,
                    ProcessId = processId,
                    Title = title.ToString()
                });

                return true;
            }, IntPtr.Zero);

            return windows.ToArray();
        }

        public static void ActivateOrMinimize(IntPtr hWnd)
        {
            if(GetForegroundWindow() == hWnd)
            {
                ShowWindow(hWnd, SW_MINIMIZE);
                return;
            }

            if(IsIconic(hWnd))
                ShowWindow(hWnd, SW_RESTORE);

            SetForegroundWindow(hWnd);
        }

        public static void RequestClose(IntPtr hWnd)
        {
            PostMessage(hWnd, WM_CLOSE, IntPtr.Zero, IntPtr.Zero);
        }
    }
}
"@
}
$script:GaloreWindowTaskbarRuntime = [GaloreWindowTaskbarRuntimeState]::new()

function Get-GaloreWindowTaskbarSignature {
    param([object[]]$Windows)
    return (@($Windows | ForEach-Object {
            "$($_.Handle)|$($_.Title)"
        }) -join "`n"
    )
}

function Get-GaloreWindowTaskbarIcon {
    param([uint32]$ProcessId)
    $process = $null
    $icon = $null
    $bitmap = $null
    $foundProcess = $false
    try {
        $process = [System.Diagnostics.Process]::GetProcessById($ProcessId)
        $foundProcess = $true
        $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($process.MainModule.FileName)
        if($icon) {
            $bitmap = [GaloreAlphaOverlay.PerPixelAlphaForm]::IconToAlphaBitmap($icon, 32, 32)
        }
    } catch {
    } finally {
        if($icon) { $icon.Dispose() }
        if($process) { $process.Dispose() }
    }
    if($bitmap) {
        return $bitmap
    }
    if($foundProcess) {
        try {
            return [GaloreAlphaOverlay.PerPixelAlphaForm]::IconToAlphaBitmap([System.Drawing.SystemIcons]::Application, 32, 32)
        } catch {
        }
    }
    return $null
}

function Set-GaloreWindowTaskbarLocation {
    param([System.Windows.Forms.Form]$Form, $Runtime = $script:GaloreWindowTaskbarRuntime)
    $runtime = $Runtime
    if($null -eq $runtime.Bar -or $runtime.Bar.IsDisposed -or $Form.IsDisposed -or $Form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized -or $Form.ClientSize.Width -le 0 -or $Form.ClientSize.Height -le 0) {
        return
    }
    $bar = $runtime.Bar
    $top = 44
    $height = [Math]::Max(44, ($Form.ClientSize.Height - $top))
    $screenPoint = $Form.PointToScreen([System.Drawing.Point]::new(0, $top))
    $screen = [System.Windows.Forms.Screen]::FromControl($Form)
    $left = $screenPoint.X - 50
    if($left -lt $screen.WorkingArea.Left) {
        $left = $screen.WorkingArea.Left
    }
    $targetSize = [System.Drawing.Size]::new(46, $height)
    $sizeChanged = $bar.ClientSize -ne $targetSize
    if($sizeChanged) {
        $bar.ClientSize = $targetSize
    }
    $bar.Location = [System.Drawing.Point]::new($left, $screenPoint.Y)
    if($sizeChanged) {
        Render-GaloreWindowTaskbar
    }
}

function Update-GaloreWindowTaskbar {
    param($Runtime = $script:GaloreWindowTaskbarRuntime)
    if($null -eq $Runtime -or $null -eq $Runtime.Bar -or $Runtime.Bar.IsDisposed) {
        return
    }
    try {
        $bar = $Runtime.Bar
        $ownerForm = $Runtime.OwnerForm
        $shouldBeVisible = $ownerForm -and -not $ownerForm.IsDisposed -and $ownerForm.Visible -and $ownerForm.WindowState -ne [System.Windows.Forms.FormWindowState]::Minimized -and $script:GaloreOverlayRuntime.TargetVisible
        if($shouldBeVisible -and -not $bar.Visible) {
            $bar.Show()
            Set-GaloreWindowTaskbarLocation -Form $ownerForm -Runtime $Runtime
            $bar.SetLayeredOpacity(255)
            $bar.BringToFront()
            Write-GaloreLog -Level "INFO" -Component "WindowTaskbar" -Message "Restored the live window taskbar display."
        }
        $windows = @([GaloreWindowTaskbar.Native]::GetTaskbarWindows($PID))
        $signature = Get-GaloreWindowTaskbarSignature -Windows $windows
        if($signature -eq $Runtime.Signature) {
            return
        }
        $Runtime.Signature = $signature
        Write-GaloreLog -Level "INFO" -Component "WindowTaskbar" -Message "Rendered $($windows.Count) visible Windows taskbar item(s)."
        if(-not $Runtime.ToolTip) {
            $Runtime.ToolTip = New-Object System.Windows.Forms.ToolTip
        }
        $Runtime.ToolTip.RemoveAll()
        foreach($control in @($bar.Controls)) {
            if($control.Image) {
                $image = $control.Image
                $control.Image = $null
                $image.Dispose()
            }
            $control.Dispose()
        }
        $bar.Controls.Clear()
        [int]$top = 6
        foreach($window in $windows) {
            if(($top + 34) -gt $bar.ClientSize.Height) {
                break
            }
            $entry = New-Object System.Windows.Forms.PictureBox
            $entry.Size = [System.Drawing.Size]::new(34, 34)
            $entry.Location = [System.Drawing.Point]::new(6, $top)
            $entry.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
            $entry.Cursor = [System.Windows.Forms.Cursors]::Hand
            $entry.BackColor = Get-GaloreWindowTaskbarKeyColor -Runtime $Runtime
            $entry.Image = Get-GaloreWindowTaskbarIcon -ProcessId $window.ProcessId
            $entry.Tag = $window
            $Runtime.ToolTip.SetToolTip($entry, "$($window.Title)`nRight-click to close")
            $entry.Visible = $false
            $bar.Controls.Add($entry)
            $top += 40
        }
        Render-GaloreWindowTaskbar
    } catch {
        Write-LauncherDiagnostic -Exception $_ -Context "Failed to refresh the window taskbar."
    }
}

function Render-GaloreWindowTaskbar {
    param($Runtime = $script:GaloreWindowTaskbarRuntime)
    if($null -eq $Runtime) {
        return
    }
    $bar = $Runtime.Bar
    if($null -eq $bar -or $bar.IsDisposed -or -not $bar.IsHandleCreated) {
        return
    }
    if($bar.ClientSize.Width -le 0 -or $bar.ClientSize.Height -le 0) {
        return
    }
    $bitmap = New-Object System.Drawing.Bitmap($bar.ClientSize.Width, $bar.ClientSize.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        foreach($control in @($bar.Controls)) {
            if($control.Image) {
                $graphics.DrawImage($control.Image, $control.Bounds)
            }
        }
        $bar.SetLayeredBitmap($bitmap)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Initialize-GaloreWindowTaskbar {
    param([System.Windows.Forms.Form]$Form, $Runtime = $script:GaloreWindowTaskbarRuntime)
    if($null -eq $Form -or $Form.IsDisposed -or $null -eq $Runtime) { return }
    if([object]::ReferenceEquals($Runtime.OwnerForm, $Form) -and $Runtime.IsInitialized -and $Runtime.Bar -and -not $Runtime.Bar.IsDisposed -and $Runtime.Timer) { return }
    Stop-GaloreWindowTaskbar -Runtime $Runtime
    $bar = New-Object GaloreAlphaOverlay.PerPixelAlphaForm
    $bar.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $bar.ShowInTaskbar = $false
    $bar.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $bar.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $bar.Owner = $Form
    $bar.Add_MouseUp({
        param($sender, $e)
        Invoke-GaloreEventSafely -Context "Window taskbar icon interaction failed." -Action {
            $entry = @($sender.Controls | Where-Object { $_.Bounds.Contains($e.Location) }) | Select-Object -First 1
            if($null -eq $entry) {
                return
            }
            if($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
                [GaloreWindowTaskbar.Native]::RequestClose($entry.Tag.Handle)
            } elseif($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
                [GaloreWindowTaskbar.Native]::ActivateOrMinimize($entry.Tag.Handle)
            }
        }.GetNewClosure() | Out-Null
    }.GetNewClosure())
    $bar.Add_FormClosed({
        param($sender, $e)
        foreach($control in @($sender.Controls)) {
            if($control.Image) {
                $control.Image.Dispose()
                $control.Image = $null
            }
        }
    })
    $runtime = $Runtime
    $runtime.OwnerForm = $Form
    $runtime.Bar = $bar
    Register-GaloreOverlayForm -Form $bar
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 1000
    $timer.Add_Tick({
        try {
            Update-GaloreWindowTaskbar -Runtime $this.Tag
        } catch {
            try {
                Write-LauncherDiagnostic -Exception $_ -Context "Window taskbar timer stopped after an internal error."
            } catch {
            }
        }
    }.GetNewClosure())
    $timer.Tag = $runtime
    $timer.Start()
    $runtime.Timer = $timer
    Register-GaloreOverlayLifecycle -Form $Form
    $runtime.MoveHandler = { param($sender, $e) Set-GaloreWindowTaskbarLocation -Form $sender -Runtime $runtime }.GetNewClosure()
    $runtime.SizeChangedHandler = { param($sender, $e) Set-GaloreWindowTaskbarLocation -Form $sender -Runtime $runtime }.GetNewClosure()
    $runtime.FormClosedHandler = { param($sender, $e) if([object]::ReferenceEquals($runtime.OwnerForm, $sender)) { Stop-GaloreWindowTaskbar -Runtime $runtime } }.GetNewClosure()
    $runtime.ShownHandler = {
        Invoke-GaloreEventSafely -Context "Window taskbar startup lifecycle failed." -Action {
            if($null -eq $runtime.Bar -or $runtime.Bar.IsDisposed) {
                return
            }
            $runtime.Bar.SetLayeredOpacity(0)
            $runtime.Bar.Show()
            Set-GaloreWindowTaskbarLocation -Form $Form -Runtime $runtime
            Update-GaloreWindowTaskbar -Runtime $runtime
            $runtime.Bar.SetLayeredOpacity(255)
            $runtime.Bar.BringToFront()
            Set-GaloreOverlayLifecycleReady -Ready $true
            Show-GaloreLauncherOverlayBars -DurationMilliseconds 420
        }.GetNewClosure() | Out-Null
    }.GetNewClosure()
    $Form.Add_Move($runtime.MoveHandler)
    $Form.Add_SizeChanged($runtime.SizeChangedHandler)
    $Form.Add_FormClosed($runtime.FormClosedHandler)
    $Form.Add_Shown($runtime.ShownHandler)
    $runtime.IsInitialized = $true
}

function Stop-GaloreWindowTaskbar {
    param($Runtime = $script:GaloreWindowTaskbarRuntime)
    $runtime = $Runtime
    if($null -eq $runtime) { return }
    $ownerForm = $runtime.OwnerForm
    if($ownerForm -and -not $ownerForm.IsDisposed) {
        if($runtime.MoveHandler) { try { $ownerForm.Remove_Move($runtime.MoveHandler) } catch {} }
        if($runtime.SizeChangedHandler) { try { $ownerForm.Remove_SizeChanged($runtime.SizeChangedHandler) } catch {} }
        if($runtime.ShownHandler) { try { $ownerForm.Remove_Shown($runtime.ShownHandler) } catch {} }
        if($runtime.FormClosedHandler) { try { $ownerForm.Remove_FormClosed($runtime.FormClosedHandler) } catch {} }
    }
    if($runtime.Timer) {
        $runtime.Timer.Stop()
        $runtime.Timer.Tag = $null
        $runtime.Timer.Dispose()
        $runtime.Timer = $null
    }
    if($runtime.Bar -and -not $runtime.Bar.IsDisposed) {
        Unregister-GaloreOverlayForm -Form $runtime.Bar
        $runtime.Bar.Close()
    }
    if($runtime.ToolTip) {
        try {
            $runtime.ToolTip.Dispose()
        } catch {
        } finally {
            $runtime.ToolTip = $null
        }
    }
    $runtime.Bar = $null
    $runtime.Signature = "<uninitialized>"
    $runtime.OwnerForm = $null
    $runtime.MoveHandler = $null
    $runtime.SizeChangedHandler = $null
    $runtime.ShownHandler = $null
    $runtime.FormClosedHandler = $null
    $runtime.IsInitialized = $false
}

function Get-GaloreWindowTaskbarKeyColor {
    param($Runtime = $script:GaloreWindowTaskbarRuntime)
    if($null -eq $Runtime.KeyColor) {
        $Runtime.KeyColor = [System.Drawing.Color]::FromArgb(1, 2, 3)
    }
    return $Runtime.KeyColor
}
foreach($callbackName in @("Get-GaloreWindowTaskbarIcon", "Set-GaloreWindowTaskbarLocation", "Update-GaloreWindowTaskbar", "Render-GaloreWindowTaskbar", "Stop-GaloreWindowTaskbar")) {
    $callback = Get-Command -Name $callbackName -CommandType Function -ErrorAction Stop
    Set-Item -Path ("Function:global:{0}" -f $callbackName) -Value $callback.ScriptBlock -Force
}
