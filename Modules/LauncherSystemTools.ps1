# ============================================================
# LAUNCHER SYSTEM TOOLS MODULE
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherSystemTools"
    LoadOrder = 200
    RequiresModules = @("LauncherBrowser", "LauncherLogging", "UI")
    RequiresFunctions = [ordered]@{
        "Close-GaloreBrowserSelectorAnimated" = "LauncherBrowser"
        "New-CalculatorButton" = "UI"
        "New-InternetButton" = "UI"
        "New-KeyboardLanguageButton" = "UI"
        "New-VolumeButton" = "UI"
        "Start-GaloreBrowserSelectorFade" = "LauncherBrowser"
        "Write-LauncherDiagnostic" = "LauncherLogging"
    }
    RequiresTypes = [ordered]@{}
    RequiresVariables = @("AppRoot")
    RequiresFolders = @("resources")
    RequiresFiles = @()
    ProvidesTypes = @()
}

$script:GaloreSystemToolPopup = $null

function Get-GaloreNetworkConnection {

    try
    {
        $profile =
        Get-NetConnectionProfile `
        -ErrorAction Stop |
        Where-Object {
            $_.IPv4Connectivity -ne "Disconnected" -or
            $_.IPv6Connectivity -ne "Disconnected"
        } |
        Select-Object `
        -First 1

        if($null -eq $profile)
        {
            return $null
        }

        $connectionType =
        if(
            $profile.InterfaceAlias -match "Wi-?Fi|Wireless|WLAN"
        )
        {
            "WiFi"
        }
        else
        {
            "Ethernet"
        }

        return [pscustomobject]@{
            Name = $profile.Name
            InterfaceAlias = $profile.InterfaceAlias
            InterfaceIndex = $profile.InterfaceIndex
            Type = $connectionType
        }

    }
    catch
    {

        return $null

    }

}

function Get-GaloreNetworkToolTip {

    $connection =
    Get-GaloreNetworkConnection

    if($null -eq $connection)
    {
        return "Internet: Not connected"
    }

    return (
        "Internet: " +
        "$($connection.Name) ($($connection.Type))"
    )

}

function Invoke-GaloreNetworkRetry {

    $connection =
    Get-GaloreNetworkConnection

    if($null -eq $connection)
    {
        return
    }

    $confirmation =
    [System.Windows.Forms.MessageBox]::Show(
        "Disconnect and retry '$($connection.Name)'?",
        "Galore Internet",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )

    if(
        $confirmation -ne
        [System.Windows.Forms.DialogResult]::Yes
    )
    {
        return
    }

    try
    {
        if($connection.Type -eq "WiFi")
        {
            Start-Process `
            -FilePath "netsh.exe" `
            -ArgumentList "wlan disconnect interface=`"$($connection.InterfaceAlias)`"" `
            -WindowStyle Hidden `
            -Wait

            Start-Process `
            -FilePath "netsh.exe" `
            -ArgumentList "wlan connect name=`"$($connection.Name)`" interface=`"$($connection.InterfaceAlias)`"" `
            -WindowStyle Hidden

        }
        else
        {
            $command = "Disable-NetAdapter -InterfaceIndex $($connection.InterfaceIndex) -Confirm:`$false; Start-Sleep -Seconds 1; Enable-NetAdapter -InterfaceIndex $($connection.InterfaceIndex) -Confirm:`$false"

            Start-Process `
            -FilePath "powershell.exe" `
            -ArgumentList "-NoProfile -WindowStyle Hidden -Command `"$command`"" `
            -Verb RunAs

        }

    }
    catch
    {

        Write-LauncherDiagnostic `
        -Exception $_ `
        -Context "Failed to retry the active network connection."

    }

}

function Initialize-GaloreAudioApi {

    if("GaloreAudio.EndpointVolume" -as [type])
    {
        return
    }
    Add-Type @"
using System;
using System.Runtime.InteropServices;

namespace GaloreAudio
{
    public enum EDataFlow { eRender, eCapture, eAll }
    public enum ERole { eConsole, eMultimedia, eCommunications }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDeviceEnumerator
    {
        int EnumAudioEndpoints(EDataFlow dataFlow, int dwStateMask, out object devices);
        int GetDefaultAudioEndpoint(EDataFlow dataFlow, ERole role, out IMMDevice endpoint);
    }

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    internal class MMDeviceEnumeratorComObject { }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDevice
    {
        int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object interfacePointer);
    }

    [ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAudioEndpointVolume
    {
        int RegisterControlChangeNotify(IntPtr notify);
        int UnregisterControlChangeNotify(IntPtr notify);
        int GetChannelCount(out uint channelCount);
        int SetMasterVolumeLevel(float levelDB, Guid eventContext);
        int SetMasterVolumeLevelScalar(float level, Guid eventContext);
        int GetMasterVolumeLevel(out float levelDB);
        int GetMasterVolumeLevelScalar(out float level);
        int SetChannelVolumeLevel(uint channel, float levelDB, Guid eventContext);
        int SetChannelVolumeLevelScalar(uint channel, float level, Guid eventContext);
        int GetChannelVolumeLevel(uint channel, out float levelDB);
        int GetChannelVolumeLevelScalar(uint channel, out float level);
        int SetMute(bool isMuted, Guid eventContext);
        int GetMute(out bool isMuted);
        int GetVolumeStepInfo(out uint step, out uint stepCount);
        int VolumeStepUp(Guid eventContext);
        int VolumeStepDown(Guid eventContext);
        int QueryHardwareSupport(out uint hardwareSupportMask);
        int GetVolumeRange(out float minDB, out float maxDB, out float incrementDB);
    }

    public static class EndpointVolume
    {
        private static IAudioEndpointVolume GetEndpoint()
        {
            var enumerator = (IMMDeviceEnumerator)new MMDeviceEnumeratorComObject();
            IMMDevice device;
            Marshal.ThrowExceptionForHR(enumerator.GetDefaultAudioEndpoint(EDataFlow.eRender, ERole.eMultimedia, out device));
            Guid iid = typeof(IAudioEndpointVolume).GUID;
            object endpointObject;
            Marshal.ThrowExceptionForHR(device.Activate(ref iid, 23, IntPtr.Zero, out endpointObject));
            return (IAudioEndpointVolume)endpointObject;
        }

        public static float GetMasterVolume()
        {
            float value;
            Marshal.ThrowExceptionForHR(GetEndpoint().GetMasterVolumeLevelScalar(out value));
            return value;
        }

        public static void SetMasterVolume(float value)
        {
            value = Math.Max(0f, Math.Min(1f, value));
            Marshal.ThrowExceptionForHR(GetEndpoint().SetMasterVolumeLevelScalar(value, Guid.Empty));
        }
    }
}
"@
}

function Get-GaloreMasterVolume {

    try
    {
        Initialize-GaloreAudioApi

        return [int][Math]::Round(
            ([GaloreAudio.EndpointVolume]::GetMasterVolume() * 100)
        )
    }
    catch
    {

        return 0

    }

}

function Set-GaloreMasterVolume {

    param(
        [int]$Volume
    )

    try
    {
        Initialize-GaloreAudioApi

        [GaloreAudio.EndpointVolume]::SetMasterVolume(
            ([Math]::Max(0, [Math]::Min(100, $Volume)) / 100.0)
        )
    }
    catch
    {

        Write-LauncherDiagnostic `
        -Exception $_ `
        -Context "Failed to set the master volume."

    }

}

function New-GaloreSystemToolPopup {

    param(
        $Anchor,
        [string]$BackgroundImageName,
        [int]$FallbackWidth,
        [int]$FallbackHeight
    )

    $popup =
    New-Object System.Windows.Forms.Form

    $popup.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $popup.ShowInTaskbar = $false
    $popup.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $popup.TopMost = $true
    $popup.BackColor = [System.Drawing.Color]::Black

    $ownedImage = $null
    $imagePath = Get-GaloreResourcePath $BackgroundImageName

    if(Test-Path -LiteralPath $imagePath -PathType Leaf)
    {
        try
        {
            $sourceImage = [System.Drawing.Image]::FromFile($imagePath)
            $ownedImage = New-Object System.Drawing.Bitmap($sourceImage)
            $sourceImage.Dispose()
            $popup.BackgroundImage = $ownedImage
            $popup.BackgroundImageLayout = [System.Windows.Forms.ImageLayout]::None
            $popup.ClientSize = [System.Drawing.Size]::new($ownedImage.Width, $ownedImage.Height)
        }
        catch
        {
            Write-LauncherDiagnostic -Exception $_ -Context "Failed to load '$BackgroundImageName'."
        }
    }

    if($null -eq $ownedImage)
    {
        $popup.ClientSize = [System.Drawing.Size]::new($FallbackWidth, $FallbackHeight)
    }

    $popup.Tag = [pscustomobject]@{ SelectorImage = $ownedImage; FadeTimer = $null; IsClosing = $false }

    $popup.Add_FormClosing({
        param($sender, $e)
        if(-not $this.Tag.IsClosing)
        {
            $e.Cancel = $true
            Close-GaloreBrowserSelectorAnimated -Form $this
        }
    })

    $popup.Add_FormClosed({
        $context = $this.Tag
        if($context.SelectorImage) { $context.SelectorImage.Dispose() }
        if($script:GaloreSystemToolPopup -eq $this) { $script:GaloreSystemToolPopup = $null }
    })

    $popup.Add_Deactivate({
        if(-not $this.IsDisposed) { Close-GaloreBrowserSelectorAnimated -Form $this }
    })

    $anchorPoint = $Anchor.PointToScreen([System.Drawing.Point]::Empty)
    $area = [System.Windows.Forms.Screen]::FromPoint($anchorPoint).WorkingArea
    $x = [Math]::Min([Math]::Max($area.Left, $anchorPoint.X), $area.Right - $popup.Width)
    $y = $anchorPoint.Y - $popup.Height - 2
    if($y -lt $area.Top) { $y = [Math]::Min($area.Bottom - $popup.Height, $anchorPoint.Y + $Anchor.Height + 2) }
    $popup.Location = [System.Drawing.Point]::new($x, $y)
    return $popup

}

function Show-GaloreSystemToolPopup {

    param($Popup, $Owner)

    if($script:GaloreSystemToolPopup -and -not $script:GaloreSystemToolPopup.IsDisposed)
    {
        Close-GaloreBrowserSelectorAnimated -Form $script:GaloreSystemToolPopup
    }

    $script:GaloreSystemToolPopup = $Popup
    $Popup.Opacity = 0
    if(
        $Owner -and
        -not $Owner.IsDisposed
    )
    {

        $Popup.Show($Owner)

    }
    else
    {

        $Popup.Show()

    }

    Start-GaloreBrowserSelectorFade -Form $Popup -TargetOpacity 1

}

function Show-GaloreVolumePopup {

    param($Anchor)

    $popup = New-GaloreSystemToolPopup -Anchor $Anchor -BackgroundImageName "volumeselector.png" -FallbackWidth 250 -FallbackHeight 75

    $slider = New-Object System.Windows.Forms.TrackBar
    $slider.Minimum = 0
    $slider.Maximum = 100
    $slider.TickStyle = [System.Windows.Forms.TickStyle]::None
    $slider.Value = Get-GaloreMasterVolume
    $sliderHeight = 45
    $slider.Bounds = [System.Drawing.Rectangle]::new(
        15,
        [Math]::Max(0, [int](($popup.ClientSize.Height - $sliderHeight) / 2)),
        $popup.ClientSize.Width - 30,
        $sliderHeight
    )
    $slider.Add_Scroll({ Set-GaloreMasterVolume -Volume $this.Value })

    $popup.Controls.Add($slider)
    Show-GaloreSystemToolPopup -Popup $popup -Owner $Anchor.FindForm()

}

function Show-GaloreKeyboardLanguagePopup {

    param($Anchor)

    $popup = New-GaloreSystemToolPopup -Anchor $Anchor -BackgroundImageName "keyboardselector.png" -FallbackWidth 260 -FallbackHeight 180
    $languages = @([System.Windows.Forms.InputLanguage]::InstalledInputLanguages)
    $languageList = New-Object System.Windows.Forms.Panel
    $languageList.AutoScroll = $true
    $languageList.BackColor = [System.Drawing.Color]::Transparent
    $languageList.Bounds = [System.Drawing.Rectangle]::new(
        15,
        15,
        $popup.ClientSize.Width - 30,
        $popup.ClientSize.Height - 30
    )

    $languageList.Add_MouseWheel({
        param($sender, $e)

        $maximum =
        [Math]::Max(
            0,
            $sender.VerticalScroll.Maximum -
            $sender.VerticalScroll.LargeChange +
            1
        )

        $target =
        [Math]::Max(
            0,
            [Math]::Min(
                $maximum,
                $sender.VerticalScroll.Value - $e.Delta
            )
        )

        $sender.AutoScrollPosition =
        New-Object System.Drawing.Point(
            0,
            $target
        )
    })

    $top = 0
    foreach($language in $languages)
    {
        $choice = New-Object System.Windows.Forms.Label
        $choice.Text = $language.Culture.DisplayName
        $choice.Tag = $language
        $choice.ForeColor = [System.Drawing.Color]::White
        $choice.BackColor = [System.Drawing.Color]::Transparent
        $choice.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $choice.Cursor = [System.Windows.Forms.Cursors]::Hand
        $choice.Bounds = [System.Drawing.Rectangle]::new(0, $top, $languageList.ClientSize.Width - 20, 28)
        $choice.Add_MouseEnter({ $this.ForeColor = [System.Drawing.Color]::Blue })
        $choice.Add_MouseLeave({ $this.ForeColor = [System.Drawing.Color]::White })
        $choice.Add_MouseWheel({
            param($sender, $e)

            $list =
            $sender.Parent

            $maximum =
            [Math]::Max(
                0,
                $list.VerticalScroll.Maximum -
                $list.VerticalScroll.LargeChange +
                1
            )

            $target =
            [Math]::Max(
                0,
                [Math]::Min(
                    $maximum,
                    $list.VerticalScroll.Value - $e.Delta
                )
            )

            $list.AutoScrollPosition =
            New-Object System.Drawing.Point(
                0,
                $target
            )
        })
        $choice.Add_Click({ [System.Windows.Forms.InputLanguage]::CurrentInputLanguage = $this.Tag; Close-GaloreBrowserSelectorAnimated -Form $this.FindForm() })
        $languageList.Controls.Add($choice)
        $top += 30
    }

    $popup.Controls.Add($languageList)
    Show-GaloreSystemToolPopup -Popup $popup -Owner $Anchor.FindForm()

}

function Initialize-GaloreSystemTools {

    param([System.Windows.Forms.Form]$Form)

    $toolTip = New-Object System.Windows.Forms.ToolTip
    $toolTip.InitialDelay = 400
    $toolTip.AutoPopDelay = 5000

    $internetButton = New-InternetButton
    $internetButton.Add_MouseEnter({
        param($sender, $e)
        $toolTip.SetToolTip($sender, (Get-GaloreNetworkToolTip))
    }.GetNewClosure())
    $internetButton.Add_MouseDoubleClick({
        param($sender, $e)
        Invoke-GaloreNetworkRetry
    })
    $Form.Controls.Add($internetButton)

    $volumeButton = New-VolumeButton
    $volumeButton.Add_Click({
        param($sender, $e)
        Show-GaloreVolumePopup -Anchor $sender
    })
    $toolTip.SetToolTip($volumeButton, "Volume")
    $Form.Controls.Add($volumeButton)

    $keyboardButton = New-KeyboardLanguageButton
    $keyboardButton.Add_MouseEnter({
        param($sender, $e)
        $toolTip.SetToolTip($sender, "Keyboard: $([System.Windows.Forms.InputLanguage]::CurrentInputLanguage.Culture.DisplayName)")
    }.GetNewClosure())
    $keyboardButton.Add_Click({
        param($sender, $e)
        Show-GaloreKeyboardLanguagePopup -Anchor $sender
    })
    $Form.Controls.Add($keyboardButton)

    $calculatorButton = New-CalculatorButton
    $calculatorButton.Add_Click({
        Start-Process `
        -FilePath "calc.exe"
    })
    $toolTip.SetToolTip($calculatorButton, "Calculator")
    $Form.Controls.Add($calculatorButton)

}
