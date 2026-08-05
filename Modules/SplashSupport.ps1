# ============================================================
# SPLASH SUPPORT MODULE
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "SplashSupport"
    LoadOrder = 150
    RequiresModules = @()
    RequiresFunctions = [ordered]@{}
    RequiresTypes = [ordered]@{}
    RequiresVariables = @()
    RequiresFolders = @("Resources")
    RequiresFiles = @("Resources\windows.png")
    ProvidesTypes = @("AlphaSplashV2")
}

# ============================================================
# ALPHA SPLASH WINDOW
# ============================================================

if(
    -not (
        "AlphaSplashV2" -as [type]
    )
)
{
Add-Type @"
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class AlphaSplashV2
{

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT
    {
        public int X;
        public int Y;

        public POINT(int x, int y)
        {
            X = x;
            Y = y;
        }
    }



    [StructLayout(LayoutKind.Sequential)]
    public struct SIZE
    {
        public int CX;
        public int CY;

        public SIZE(int cx, int cy)
        {
            CX = cx;
            CY = cy;
        }
    }



    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    public struct BLENDFUNCTION
    {
        public byte BlendOp;
        public byte BlendFlags;
        public byte SourceConstantAlpha;
        public byte AlphaFormat;
    }



    [DllImport("user32.dll", SetLastError=true)]
    static extern bool UpdateLayeredWindow(
        IntPtr hwnd,
        IntPtr hdcDst,
        ref POINT pptDst,
        ref SIZE psize,
        IntPtr hdcSrc,
        ref POINT pptSrc,
        int crKey,
        ref BLENDFUNCTION pblend,
        int dwFlags
    );



    [DllImport("user32.dll")]
    static extern int SetWindowLong(
        IntPtr hWnd,
        int nIndex,
        int dwNewLong
    );



    [DllImport("user32.dll")]
    static extern int GetWindowLong(
        IntPtr hWnd,
        int nIndex
    );



    [DllImport("gdi32.dll")]
    static extern IntPtr CreateCompatibleDC(
        IntPtr hdc
    );



    [DllImport("gdi32.dll")]
    static extern bool DeleteDC(
        IntPtr hdc
    );



    [DllImport("gdi32.dll")]
    static extern IntPtr SelectObject(
        IntPtr hdc,
        IntPtr hgdiobj
    );



    [DllImport("gdi32.dll")]
    static extern bool DeleteObject(
        IntPtr hObject
    );



    [DllImport("user32.dll")]
    static extern IntPtr GetDC(
        IntPtr hwnd
    );



    [DllImport("user32.dll")]
    static extern int ReleaseDC(
        IntPtr hwnd,
        IntPtr hdc
    );



    const int GWL_EXSTYLE = -20;

    const int WS_EX_LAYERED = 0x80000;

    const int ULW_ALPHA = 0x2;

    const byte AC_SRC_OVER = 0x00;

    const byte AC_SRC_ALPHA = 0x01;



    private static void Render(
        Form form,
        Bitmap bitmap,
        byte alpha
    )
    {

        IntPtr screenDC =
        GetDC(IntPtr.Zero);



        IntPtr memoryDC =
        CreateCompatibleDC(
            screenDC
        );



        IntPtr hBitmap =
        bitmap.GetHbitmap();



        IntPtr oldBitmap =
        SelectObject(
            memoryDC,
            hBitmap
        );



        POINT source =
        new POINT(
            0,
            0
        );



        POINT position =
        new POINT(
            form.Left,
            form.Top
        );



        SIZE size =
        new SIZE(
            bitmap.Width,
            bitmap.Height
        );



        BLENDFUNCTION blend =
        new BLENDFUNCTION();



        blend.BlendOp =
        AC_SRC_OVER;



        blend.BlendFlags =
        0;



        blend.SourceConstantAlpha =
        alpha;



        blend.AlphaFormat =
        AC_SRC_ALPHA;



        UpdateLayeredWindow(
            form.Handle,
            screenDC,
            ref position,
            ref size,
            memoryDC,
            ref source,
            0,
            ref blend,
            ULW_ALPHA
        );



        SelectObject(
            memoryDC,
            oldBitmap
        );



        DeleteObject(
            hBitmap
        );



        DeleteDC(
            memoryDC
        );



        ReleaseDC(
            IntPtr.Zero,
            screenDC
        );

    }



    public static Form Show(Bitmap bitmap)
    {

        Form form =
        new Form();



        form.FormBorderStyle =
        FormBorderStyle.None;



        form.ShowInTaskbar =
        false;



        form.TopMost =
        true;



        form.StartPosition =
        FormStartPosition.Manual;



        int style =
        GetWindowLong(
            form.Handle,
            GWL_EXSTYLE
        );



        SetWindowLong(
            form.Handle,
            GWL_EXSTYLE,
            style | WS_EX_LAYERED
        );



        form.Width =
        bitmap.Width;



        form.Height =
        bitmap.Height;



        form.Left =
        (
            Screen.PrimaryScreen.Bounds.Width -
            bitmap.Width
        ) / 2;



        form.Top =
        (
            Screen.PrimaryScreen.Bounds.Height -
            bitmap.Height
        ) / 2;



        Render(
            form,
            bitmap,
            0
        );



        form.Show();



        Render(
            form,
            bitmap,
            0
        );



        return form;

    }



    public static void SetAlpha(
        Form form,
        Bitmap bitmap,
        byte alpha
    )
    {

        Render(
            form,
            bitmap,
            alpha
        );

    }

}

"@ `
-ReferencedAssemblies `
"System.Windows.Forms.dll","System.Drawing.dll"

}


# ============================================================
# SHOW LAUNCHER SPLASH
# ============================================================

function Set-SplashAlphaTransition {


    param(
        [System.Windows.Forms.Form]$Window,
        [System.Drawing.Bitmap]$Image,
        [int]$FromAlpha,
        [int]$ToAlpha,
        [int]$DurationMilliseconds
    )



    if(
        $null -eq $Window -or
        $null -eq $Image
    )
    {

        return

    }



    if(
        $DurationMilliseconds -le 0
    )
    {

        [AlphaSplashV2]::SetAlpha(
            $Window,
            $Image,
            [byte]$ToAlpha
        )



        return

    }



    $transitionWatch =
    [System.Diagnostics.Stopwatch]::StartNew()



    do
    {

        $progress =
        [Math]::Min(
            1.0,
            (
                $transitionWatch.Elapsed.TotalMilliseconds /
                $DurationMilliseconds
            )
        )



        $easedProgress =
        $progress * $progress * (
            3 -
            (2 * $progress)
        )



        $alpha =
        [Math]::Round(
            $FromAlpha +
            (
                (
                    $ToAlpha -
                    $FromAlpha
                ) *
                $easedProgress
            )
        )



        [AlphaSplashV2]::SetAlpha(
            $Window,
            $Image,
            [byte][Math]::Max(
                0,
                [Math]::Min(
                    255,
                    $alpha
                )
            )
        )



        [System.Windows.Forms.Application]::DoEvents()



        if(
            $progress -lt 1
        )
        {

            Start-Sleep -Milliseconds 15

        }

    }
    while(
        $progress -lt 1
    )


}

function Show-LauncherSplash {


    param(
        $AppRoot
    )


    # ========================================================
    # SPLASH SETTINGS
    # ========================================================

    $SplashFadeInDuration =
    420


    $SplashFadeOutDuration =
    320


    $SplashHoldDuration =
    750



    # ========================================================
    # CREATE SPLASH
    # ========================================================

    $splashPath =
    Get-GaloreResourcePath `
    "windows.png"



    $script:SplashImage =
    $null


    $script:SplashWindow =
    $null



    if(
        Test-Path $splashPath
    )
    {

        $script:SplashImage =
        [System.Drawing.Bitmap]::FromFile(
            $splashPath
        )



        $script:SplashWindow =
        [AlphaSplashV2]::Show(
            $script:SplashImage
        )



        # ====================================================
        # START INVISIBLE
        # ====================================================

        [AlphaSplashV2]::SetAlpha(
            $script:SplashWindow,
            $script:SplashImage,
            0
        )



        # ====================================================
        # FADE IN
        # ====================================================

        Set-SplashAlphaTransition `
        -Window $script:SplashWindow `
        -Image $script:SplashImage `
        -FromAlpha 0 `
        -ToAlpha 255 `
        -DurationMilliseconds $SplashFadeInDuration



        [AlphaSplashV2]::SetAlpha(
            $script:SplashWindow,
            $script:SplashImage,
            255
        )

    }



    # ========================================================
    # HOLD SPLASH
    # ========================================================

    Start-Sleep `
    -Milliseconds $SplashHoldDuration



    # ========================================================
    # FADE OUT
    # ========================================================

    if(
        $script:SplashWindow
    )
    {

        Set-SplashAlphaTransition `
        -Window $script:SplashWindow `
        -Image $script:SplashImage `
        -FromAlpha 255 `
        -ToAlpha 0 `
        -DurationMilliseconds $SplashFadeOutDuration



        $script:SplashWindow.Close()

        $script:SplashWindow.Dispose()

        $script:SplashWindow = $null

    }



    if(
        $script:SplashImage
    )
    {

        $script:SplashImage.Dispose()

        $script:SplashImage = $null

    }


}

# ============================================================
# STOP SPLASH RESOURCES
# ============================================================

function Stop-SplashResources {


    if(
        $script:SplashWindow
    )
    {

        try
        {

            $script:SplashWindow.Close()



            $script:SplashWindow.Dispose()

        }
        catch
        {



        }



        $script:SplashWindow =
        $null

    }



    if(
        $script:SplashImage
    )
    {

        try
        {

            $script:SplashImage.Dispose()

        }
        catch
        {



        }



        $script:SplashImage =
        $null

    }


}
