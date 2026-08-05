# ============================================================
# ALPHA OVERLAY SUPPORT
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherAlphaOverlay"
    LoadOrder = 230
    RequiresModules = @("LauncherDomain", "LauncherLogging")
    RequiresFunctions = [ordered]@{
        "Write-LauncherDiagnostic" = "LauncherLogging"
    }
    RequiresTypes = [ordered]@{
        "GaloreOverlayRuntimeState" = "LauncherDomain"
    }
    RequiresVariables = @()
    RequiresFolders = @()
    RequiresFiles = @()
    ProvidesTypes = @("GaloreAlphaOverlay.PerPixelAlphaForm")
}
if(-not ("GaloreAlphaOverlay.PerPixelAlphaForm" -as [type])) {
    Add-Type -ReferencedAssemblies @([System.Windows.Forms.Form].Assembly.Location, [System.Drawing.Bitmap].Assembly.Location) `
    -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace GaloreAlphaOverlay
{
    public class PerPixelAlphaForm : Form
    {
        private const int WS_EX_LAYERED = 0x00080000;
        private const int ULW_ALPHA = 0x00000002;
        private const byte AC_SRC_OVER = 0;
        private const byte AC_SRC_ALPHA = 1;

        [StructLayout(LayoutKind.Sequential)]
        private struct POINT { public int x; public int y; }

        [StructLayout(LayoutKind.Sequential)]
        private struct SIZE { public int cx; public int cy; }

        [StructLayout(LayoutKind.Sequential, Pack = 1)]
        private struct BLENDFUNCTION
        {
            public byte BlendOp;
            public byte BlendFlags;
            public byte SourceConstantAlpha;
            public byte AlphaFormat;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct BITMAPINFOHEADER
        {
            public uint biSize;
            public int biWidth;
            public int biHeight;
            public ushort biPlanes;
            public ushort biBitCount;
            public uint biCompression;
            public uint biSizeImage;
            public int biXPelsPerMeter;
            public int biYPelsPerMeter;
            public uint biClrUsed;
            public uint biClrImportant;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct BITMAPINFO
        {
            public BITMAPINFOHEADER bmiHeader;
            public uint bmiColors;
        }

        private Bitmap layeredBitmap;
        private byte layeredOpacity = 255;

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr GetDC(IntPtr hWnd);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);

        [DllImport("gdi32.dll", SetLastError = true)]
        private static extern IntPtr CreateCompatibleDC(IntPtr hdc);

        [DllImport("gdi32.dll", SetLastError = true)]
        private static extern bool DeleteDC(IntPtr hdc);

        [DllImport("gdi32.dll", SetLastError = true)]
        private static extern IntPtr SelectObject(IntPtr hdc, IntPtr h);

        [DllImport("gdi32.dll", SetLastError = true)]
        private static extern bool DeleteObject(IntPtr hObject);

        [DllImport("gdi32.dll", SetLastError = true)]
        private static extern IntPtr CreateDIBSection(
            IntPtr hdc, ref BITMAPINFO info, uint usage,
            out IntPtr bits, IntPtr section, uint offset);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool UpdateLayeredWindow(
            IntPtr hWnd, IntPtr hdcDst, ref POINT pptDst, ref SIZE psize,
            IntPtr hdcSrc, ref POINT pptSrc, int crKey,
            ref BLENDFUNCTION pblend, int dwFlags);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool DrawIconEx(IntPtr hdc, int xLeft, int yTop,
            IntPtr hIcon, int cxWidth, int cyWidth, uint istepIfAniCur,
            IntPtr hbrFlickerFreeDraw, uint diFlags);

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams parameters = base.CreateParams;
                parameters.ExStyle |= WS_EX_LAYERED;
                return parameters;
            }
        }

        public int LayeredOpacity
        {
            get { return layeredOpacity; }
        }

        public void SetLayeredBitmap(Bitmap bitmap)
        {
            if(bitmap == null)
                return;

            Bitmap copy = new Bitmap(
                bitmap.Width,
                bitmap.Height,
                PixelFormat.Format32bppPArgb
            );

            using(Graphics graphics = Graphics.FromImage(copy))
            {
                graphics.CompositingMode = System.Drawing.Drawing2D.CompositingMode.SourceCopy;
                graphics.DrawImageUnscaled(bitmap, 0, 0);
            }

            if(layeredBitmap != null)
                layeredBitmap.Dispose();

            layeredBitmap = copy;
            UpdateLayeredBitmap();
        }

        public void SetLayeredOpacity(int opacity)
        {
            layeredOpacity = (byte)Math.Max(0, Math.Min(255, opacity));
            UpdateLayeredBitmap();
        }

        private static IntPtr CreateAlphaHBitmap(Bitmap bitmap)
        {
            BITMAPINFO info = new BITMAPINFO();
            info.bmiHeader.biSize = (uint)Marshal.SizeOf(typeof(BITMAPINFOHEADER));
            info.bmiHeader.biWidth = bitmap.Width;
            info.bmiHeader.biHeight = -bitmap.Height;
            info.bmiHeader.biPlanes = 1;
            info.bmiHeader.biBitCount = 32;
            info.bmiHeader.biCompression = 0;

            IntPtr bits;
            IntPtr hBitmap = CreateDIBSection(
                IntPtr.Zero,
                ref info,
                0,
                out bits,
                IntPtr.Zero,
                0
            );

            if(hBitmap == IntPtr.Zero || bits == IntPtr.Zero)
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());

            BitmapData data = null;
            try
            {
                Rectangle rectangle = new Rectangle(0, 0, bitmap.Width, bitmap.Height);
                data = bitmap.LockBits(rectangle, ImageLockMode.ReadOnly, PixelFormat.Format32bppPArgb);
                int rowLength = bitmap.Width * 4;
                byte[] row = new byte[rowLength];

                for(int y = 0; y < bitmap.Height; y++)
                {
                    Marshal.Copy(IntPtr.Add(data.Scan0, y * data.Stride), row, 0, rowLength);
                    Marshal.Copy(row, 0, IntPtr.Add(bits, y * rowLength), rowLength);
                }
            }
            catch
            {
                DeleteObject(hBitmap);
                throw;
            }
            finally
            {
                if(data != null)
                    bitmap.UnlockBits(data);
            }

            return hBitmap;
        }

        private void UpdateLayeredBitmap()
        {
            if(layeredBitmap == null || !IsHandleCreated)
                return;

            IntPtr screenDc = GetDC(IntPtr.Zero);
            IntPtr memoryDc = CreateCompatibleDC(screenDc);
            IntPtr hBitmap = IntPtr.Zero;
            IntPtr oldBitmap = IntPtr.Zero;

            try
            {
                hBitmap = CreateAlphaHBitmap(layeredBitmap);
                oldBitmap = SelectObject(memoryDc, hBitmap);

                POINT destination = new POINT { x = Left, y = Top };
                POINT source = new POINT { x = 0, y = 0 };
                SIZE size = new SIZE { cx = layeredBitmap.Width, cy = layeredBitmap.Height };
                BLENDFUNCTION blend = new BLENDFUNCTION {
                    BlendOp = AC_SRC_OVER,
                    BlendFlags = 0,
                    SourceConstantAlpha = layeredOpacity,
                    AlphaFormat = AC_SRC_ALPHA
                };

                UpdateLayeredWindow(Handle, screenDc, ref destination, ref size,
                    memoryDc, ref source, 0, ref blend, ULW_ALPHA);
            }
            finally
            {
                if(oldBitmap != IntPtr.Zero)
                    SelectObject(memoryDc, oldBitmap);
                if(hBitmap != IntPtr.Zero)
                    DeleteObject(hBitmap);
                if(memoryDc != IntPtr.Zero)
                    DeleteDC(memoryDc);
                if(screenDc != IntPtr.Zero)
                    ReleaseDC(IntPtr.Zero, screenDc);
            }
        }

        protected override void Dispose(bool disposing)
        {
            if(disposing && layeredBitmap != null)
            {
                layeredBitmap.Dispose();
                layeredBitmap = null;
            }

            base.Dispose(disposing);
        }

        public static Bitmap IconToAlphaBitmap(Icon icon, int width, int height)
        {
            using(Bitmap source = icon.ToBitmap())
            {
                Bitmap bitmap = new Bitmap(width, height, PixelFormat.Format32bppPArgb);
                using(Graphics graphics = Graphics.FromImage(bitmap))
                {
                    graphics.Clear(Color.Transparent);
                    graphics.DrawImage(
                        source,
                        new Rectangle(0, 0, width, height),
                        new Rectangle(0, 0, source.Width, source.Height),
                        GraphicsUnit.Pixel
                    );
                }
                return bitmap;
            }
        }
    }
}

"@
}

function Set-GaloreTransparentWindowRegion {
    param([System.Windows.Forms.Form]$Form, [System.Drawing.Bitmap]$Bitmap, [int]$AlphaThreshold = 20)
    if($null -eq $Form -or $null -eq $Bitmap) { return }
    $bounds = [System.Drawing.Rectangle]::new(0, 0, $Bitmap.Width, $Bitmap.Height)
    $bitmapData = $Bitmap.LockBits($bounds, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    try {
        $stride = [int]$bitmapData.Stride
        $pixelBytes = New-Object byte[] ($stride * $Bitmap.Height)
        [System.Runtime.InteropServices.Marshal]::Copy($bitmapData.Scan0, $pixelBytes, 0, $pixelBytes.Length)
    }
    finally { $Bitmap.UnlockBits($bitmapData) }
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    try {
        for([int]$y = 0; $y -lt $Bitmap.Height; $y++) {
            [int]$runStart = -1
            [int]$rowOffset = $y * $stride
            for([int]$x = 0; $x -lt $Bitmap.Width; $x++) {
                if($pixelBytes[$rowOffset + ($x * 4) + 3] -ge $AlphaThreshold) { if($runStart -eq -1) { $runStart = $x } }
                elseif($runStart -ne -1) { $path.AddRectangle([System.Drawing.Rectangle]::new($runStart, $y, $x - $runStart, 1)); $runStart = -1 }
            }
            if($runStart -ne -1) { $path.AddRectangle([System.Drawing.Rectangle]::new($runStart, $y, $Bitmap.Width - $runStart, 1)) }
        }
        if($Form.Region) { $Form.Region.Dispose() }
        $Form.Region = New-Object System.Drawing.Region($path)
    }
    finally { $path.Dispose() }
}
$script:GaloreOverlayRuntime = [GaloreOverlayRuntimeState]::new()

function Stop-GaloreOverlayFade {
    param([GaloreAlphaOverlay.PerPixelAlphaForm]$Form, $Runtime = $script:GaloreOverlayRuntime)
    if($null -eq $Runtime -or $null -eq $Form -or -not $Runtime.FadeTimers.ContainsKey($Form)) {
        return
    }
    $timer = $Runtime.FadeTimers[$Form]
    $Runtime.FadeTimers.Remove($Form)
    if($timer) {
        try {
            $timer.Stop()
            $timer.Tag = $null
            $timer.Dispose()
        } catch {
        }
    }
}

function Register-GaloreOverlayForm {
    param([GaloreAlphaOverlay.PerPixelAlphaForm]$Form, $Runtime = $script:GaloreOverlayRuntime)
    if($null -eq $Runtime -or $null -eq $Form -or $Form.IsDisposed) {
        return
    }
    foreach($staleForm in @($Runtime.OverlayForms | Where-Object { $null -eq $_ -or $_.IsDisposed })) {
        [void]$Runtime.OverlayForms.Remove($staleForm)
    }
    if(-not @($Runtime.OverlayForms | Where-Object { [object]::ReferenceEquals($_, $Form) })) {
        [void]$Runtime.OverlayForms.Add($Form)
    }
}

function Unregister-GaloreOverlayForm {
    param([GaloreAlphaOverlay.PerPixelAlphaForm]$Form, $Runtime = $script:GaloreOverlayRuntime)
    if($null -eq $Runtime -or $null -eq $Form) {
        return
    }
    Stop-GaloreOverlayFade -Form $Form -Runtime $Runtime
    $registeredForm = @($Runtime.OverlayForms | Where-Object { [object]::ReferenceEquals($_, $Form) }) | Select-Object -First 1
    if($registeredForm) {
        [void]$Runtime.OverlayForms.Remove($registeredForm)
    }
}

function Start-GaloreOverlayFade {
    param([GaloreAlphaOverlay.PerPixelAlphaForm]$Form, [int]$TargetOpacity, [int]$DurationMilliseconds = 170, [switch]$HideOnComplete, $Runtime = $script:GaloreOverlayRuntime)
    if($null -eq $Runtime -or $Runtime.IsStopping -or $null -eq $Form -or $Form.IsDisposed) {
        return
    }
    try {
        Stop-GaloreOverlayFade -Form $Form -Runtime $Runtime
        $target = [Math]::Max(0, [Math]::Min(255, $TargetOpacity))
        if($target -gt 0 -and -not $Form.Visible) {
            $Form.SetLayeredOpacity(0)
            $Form.Show()
        }
        $start = $Form.LayeredOpacity
        if($DurationMilliseconds -le 0 -or $start -eq $target) {
            $Form.SetLayeredOpacity($target)
            if($HideOnComplete) {
                $Form.Hide()
                $Form.SetLayeredOpacity(255)
            }
            return
        }
        $timer = New-Object System.Windows.Forms.Timer
        $timer.Interval = 15
        $timer.Tag = [pscustomobject]@{
            Form = $Form
            Runtime = $Runtime
            StartOpacity = [int]$start
            TargetOpacity = [int]$target
            DurationMilliseconds = [int]$DurationMilliseconds
            Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            HideOnComplete = [bool]$HideOnComplete
        }
        $timer.Add_Tick({
            $timer = $this
            $state = $timer.Tag
            try {
                if($null -eq $state -or $null -eq $state.Runtime -or $state.Runtime.IsStopping -or $null -eq $state.Form -or $state.Form.IsDisposed) {
                    $timer.Stop()
                    $timer.Tag = $null
                    $timer.Dispose()
                    if($state -and $state.Runtime -and $state.Runtime.FadeTimers.ContainsKey($state.Form) -and [object]::ReferenceEquals($state.Runtime.FadeTimers[$state.Form], $timer)) {
                        $state.Runtime.FadeTimers.Remove($state.Form)
                    }
                    return
                }
                $progress = [Math]::Min(1.0, ($state.Stopwatch.ElapsedMilliseconds / [double]$state.DurationMilliseconds))
                $opacity = [int][Math]::Round($state.StartOpacity + (($state.TargetOpacity - $state.StartOpacity) * $progress))
                $state.Form.SetLayeredOpacity($opacity)
                if($progress -ge 1.0) {
                    $timer.Stop()
                    $timer.Tag = $null
                    $timer.Dispose()
                    if($state.Runtime.FadeTimers.ContainsKey($state.Form) -and [object]::ReferenceEquals($state.Runtime.FadeTimers[$state.Form], $timer)) {
                        $state.Runtime.FadeTimers.Remove($state.Form)
                    }
                    if($state.HideOnComplete) {
                        $state.Form.Hide()
                        $state.Form.SetLayeredOpacity(255)
                    }
                }
            } catch {
                try {
                    $timer.Stop()
                    $timer.Tag = $null
                    $timer.Dispose()
                    if($state -and $state.Runtime -and $state.Runtime.FadeTimers.ContainsKey($state.Form) -and [object]::ReferenceEquals($state.Runtime.FadeTimers[$state.Form], $timer)) {
                        $state.Runtime.FadeTimers.Remove($state.Form)
                    }
                } catch {
                }
                try {
                    Write-LauncherDiagnostic -Exception $_ -Context "Overlay fade timer stopped after an internal error."
                } catch {
                }
            }
        })
        $Runtime.FadeTimers[$Form] = $timer
        $timer.Start()
    } catch {
        try {
            Write-LauncherDiagnostic -Exception $_ -Context "Overlay fade could not be started."
        } catch {
        }
    }
}

function Show-GaloreLauncherOverlayBars {
    param([int]$DurationMilliseconds = 220, $Runtime = $script:GaloreOverlayRuntime)
    if($null -eq $Runtime -or $Runtime.IsStopping) {
        return
    }
    foreach($bar in @($Runtime.OverlayForms)) {
        if($null -ne $bar -and -not $bar.IsDisposed) {
            Start-GaloreOverlayFade -Form $bar -TargetOpacity 255 -DurationMilliseconds $DurationMilliseconds -Runtime $Runtime
        } elseif($bar) {
            [void]$Runtime.OverlayForms.Remove($bar)
        }
    }
}

function Hide-GaloreLauncherOverlayBars {
    param([int]$DurationMilliseconds = 170, $Runtime = $script:GaloreOverlayRuntime)
    if($null -eq $Runtime -or $Runtime.IsStopping) {
        return
    }
    foreach($bar in @($Runtime.OverlayForms)) {
        if($null -ne $bar -and -not $bar.IsDisposed -and $bar.Visible) {
            Start-GaloreOverlayFade -Form $bar -TargetOpacity 0 -DurationMilliseconds $DurationMilliseconds -HideOnComplete -Runtime $Runtime
        } elseif($bar -and $bar.IsDisposed) {
            [void]$Runtime.OverlayForms.Remove($bar)
        }
    }
}

function Set-GaloreOverlayLifecycleReady {
    param([bool]$Ready = $true, $Runtime = $script:GaloreOverlayRuntime)
    if($null -ne $Runtime) {
        $Runtime.IsLifecycleReady = $Ready
    }
}

function Set-GaloreOverlayTargetVisible {
    param([bool]$Visible = $true, $Runtime = $script:GaloreOverlayRuntime)
    if($null -ne $Runtime) {
        $Runtime.TargetVisible = $Visible
    }
}

function Register-GaloreOverlayLifecycle {
    param([System.Windows.Forms.Form]$Form, $Runtime = $script:GaloreOverlayRuntime)
    if($null -eq $Runtime -or $null -eq $Form -or $Form.IsDisposed) {
        return
    }
    if([object]::ReferenceEquals($Runtime.OwnerForm, $Form) -and $Runtime.IsRegistered) {
        return
    }
    Stop-GaloreOverlayResources -Runtime $Runtime
    $Runtime.OwnerForm = $Form
    $Runtime.ResizeHandler = {
        param($sender, $e)
        if($Runtime.IsStopping -or -not $Runtime.IsLifecycleReady -or -not [object]::ReferenceEquals($Runtime.OwnerForm, $sender)) {
            return
        }
        if($sender.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
            Hide-GaloreLauncherOverlayBars -DurationMilliseconds 170 -Runtime $Runtime
        } elseif($sender.Visible -and $sender.WindowState -eq [System.Windows.Forms.FormWindowState]::Normal -and $Runtime.TargetVisible) {
            Show-GaloreLauncherOverlayBars -DurationMilliseconds 220 -Runtime $Runtime
        }
    }.GetNewClosure()
    $Form.Add_Resize($Runtime.ResizeHandler)
    $Runtime.IsRegistered = $true
}

function Stop-GaloreOverlayResources {
    param($Runtime = $script:GaloreOverlayRuntime)
    if($null -eq $Runtime -or $Runtime.IsStopping) {
        return
    }
    $Runtime.IsStopping = $true
    foreach($form in @($Runtime.FadeTimers.Keys)) {
        Stop-GaloreOverlayFade -Form $form -Runtime $Runtime
    }
    if($Runtime.OwnerForm -and -not $Runtime.OwnerForm.IsDisposed -and $Runtime.ResizeHandler) {
        try {
            $Runtime.OwnerForm.Remove_Resize($Runtime.ResizeHandler)
        } catch {
        }
    }
    $Runtime.OwnerForm = $null
    $Runtime.ResizeHandler = $null
    $Runtime.OverlayForms = [System.Collections.ArrayList]::new()
    $Runtime.FadeTimers = @{}
    $Runtime.IsLifecycleReady = $false
    $Runtime.IsRegistered = $false
    $Runtime.IsStopping = $false
    $Runtime.TargetVisible = $true
}

foreach($callbackName in @("Start-GaloreOverlayFade", "Stop-GaloreOverlayFade", "Register-GaloreOverlayForm", "Unregister-GaloreOverlayForm", "Show-GaloreLauncherOverlayBars", "Hide-GaloreLauncherOverlayBars", "Set-GaloreOverlayLifecycleReady", "Set-GaloreOverlayTargetVisible", "Register-GaloreOverlayLifecycle", "Stop-GaloreOverlayResources")) {
    $callback = Get-Command -Name $callbackName -CommandType Function -ErrorAction Stop
    Set-Item -Path ("Function:global:{0}" -f $callbackName) -Value $callback.ScriptBlock -Force
}
