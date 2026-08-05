# ============================================================
# ALPHA OVERLAY SUPPORT
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherAlphaOverlay"
    LoadOrder = 230
    RequiresModules = @("LauncherLogging")
    RequiresFunctions = [ordered]@{
        "Write-LauncherDiagnostic" = "LauncherLogging"
    }
    RequiresTypes = [ordered]@{}
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
$script:GaloreOverlayFadeTimers = @{}
$script:GaloreOverlayLifecycleRegistered = $false
$script:GaloreOverlayLifecycleReady = $false

function Start-GaloreOverlayFade {
    param([GaloreAlphaOverlay.PerPixelAlphaForm]$Form, [int]$TargetOpacity, [int]$DurationMilliseconds = 170, [switch]$HideOnComplete)
    if($null -eq $Form -or $Form.IsDisposed) {
        return
    }
    try {
        $context = $Form.Tag
        if($null -eq $context -or -not ($context -is [System.Collections.IDictionary])) {
            $context = @{
                FadeTimer = $null
            }
            $Form.Tag = $context
        }
        $existingTimer = $context["FadeTimer"]
        if($null -ne $existingTimer) {
            $existingTimer.Stop()
            $existingTimer.Dispose()
            $context["FadeTimer"] = $null
        }
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
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $timer.Add_Tick({
            try {
                if($null -eq $Form -or $Form.IsDisposed) {
                    $timer.Stop()
                    $timer.Dispose()
                    $context["FadeTimer"] = $null
                    return
                }
                $progress = [Math]::Min(1.0, ($stopwatch.ElapsedMilliseconds / [double]$DurationMilliseconds))
                $opacity = [int][Math]::Round($start + (($target - $start) * $progress))
                $Form.SetLayeredOpacity($opacity)
                if($progress -ge 1.0) {
                    $timer.Stop()
                    $timer.Dispose()
                    $context["FadeTimer"] = $null
                    if($HideOnComplete) {
                        $Form.Hide()
                        $Form.SetLayeredOpacity(255)
                    }
                }
            } catch {
                try {
                    $timer.Stop()
                    $timer.Dispose()
                    $context["FadeTimer"] = $null
                } catch {
                }
                try {
                    Write-LauncherDiagnostic -Exception $_ -Context "Overlay fade timer stopped after an internal error."
                } catch {
                }
            }
        }.GetNewClosure())
        $context["FadeTimer"] = $timer
        $timer.Start()
    } catch {
        try {
            Write-LauncherDiagnostic -Exception $_ -Context "Overlay fade could not be started."
        } catch {
        }
    }
}

function Show-GaloreLauncherOverlayBars {
    param([int]$DurationMilliseconds = 220)
    $taskbarBar = if($script:GaloreWindowTaskbarRuntime) { $script:GaloreWindowTaskbarRuntime.Bar } else { $null }
    foreach($bar in @($script:GaloreQuickAccessBar, $taskbarBar)) {
        if($null -ne $bar -and -not $bar.IsDisposed) {
            Start-GaloreOverlayFade -Form $bar -TargetOpacity 255 -DurationMilliseconds $DurationMilliseconds
        }
    }
}

function Hide-GaloreLauncherOverlayBars {
    param([int]$DurationMilliseconds = 170)
    $taskbarBar = if($script:GaloreWindowTaskbarRuntime) { $script:GaloreWindowTaskbarRuntime.Bar } else { $null }
    foreach($bar in @($script:GaloreQuickAccessBar, $taskbarBar)) {
        if($null -ne $bar -and -not $bar.IsDisposed -and $bar.Visible) {
            Start-GaloreOverlayFade -Form $bar -TargetOpacity 0 -DurationMilliseconds $DurationMilliseconds -HideOnComplete
        }
    }
}

function Register-GaloreOverlayLifecycle {
    param([System.Windows.Forms.Form]$Form)
    if($script:GaloreOverlayLifecycleRegistered) {
        return
    }
    $script:GaloreOverlayLifecycleRegistered = $true
    $Form.Add_Resize({
        if(-not $script:GaloreOverlayLifecycleReady) {
            return
        }
        if($this.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
            Hide-GaloreLauncherOverlayBars -DurationMilliseconds 170
        } elseif($this.Visible -and $this.WindowState -eq [System.Windows.Forms.FormWindowState]::Normal -and $script:LauncherWindowTargetVisible) {
            Show-GaloreLauncherOverlayBars -DurationMilliseconds 220
        }
    }.GetNewClosure())
}
foreach($callbackName in @("Start-GaloreOverlayFade", "Show-GaloreLauncherOverlayBars", "Hide-GaloreLauncherOverlayBars", "Register-GaloreOverlayLifecycle")) {
    $callback = Get-Command -Name $callbackName -CommandType Function -ErrorAction Stop
    Set-Item -Path ("Function:global:{0}" -f $callbackName) -Value $callback.ScriptBlock -Force
}
