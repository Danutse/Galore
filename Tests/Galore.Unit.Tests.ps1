param(
    [Parameter(Mandatory = $true)]
    [string]$GaloreRoot
)



$moduleRoot =
Join-Path `
$GaloreRoot `
"Modules"



if(
    -not (
        Test-Path `
        -LiteralPath $moduleRoot `
        -PathType Container
    )
)
{

    throw "Galore module folder was not found: '$moduleRoot'."

}



Add-Type `
-AssemblyName System.Windows.Forms



Add-Type `
-AssemblyName System.Drawing



$script:AppRoot =
$GaloreRoot



. (Join-Path $moduleRoot "LauncherDomain.ps1")



. (Join-Path $moduleRoot "LauncherLogging.ps1")

. (Join-Path $moduleRoot "LauncherSettings.ps1")

. (Join-Path $moduleRoot "LauncherConfiguration.ps1")

. (Join-Path $moduleRoot "UI.ps1")

. (Join-Path $moduleRoot "LauncherSearch.ps1")

. (Join-Path $moduleRoot "LauncherStartMenu.ps1")

. (Join-Path $moduleRoot "LauncherPopup.ps1")

. (Join-Path $moduleRoot "LauncherBrowser.ps1")

. (Join-Path $moduleRoot "LauncherSystemTools.ps1")

. (Join-Path $moduleRoot "LauncherAlphaOverlay.ps1")

. (Join-Path $moduleRoot "LauncherQuickAccess.ps1")

. (Join-Path $moduleRoot "LauncherPostIts.ps1")

. (Join-Path $moduleRoot "LauncherWindowTaskbar.ps1")

. (Join-Path $moduleRoot "LauncherBackup.ps1")

. (Join-Path $moduleRoot "LauncherHotkeys.ps1")

. (Join-Path $moduleRoot "LauncherHotkeySettings.ps1")

. (Join-Path $moduleRoot "LauncherCategories.ps1")

. (Join-Path $moduleRoot "LauncherMaintenance.ps1")

. (Join-Path $moduleRoot "LauncherHardware.ps1")

. (Join-Path $moduleRoot "LauncherIntegrationAdapters.ps1")

. (Join-Path $moduleRoot "LauncherProcess.ps1")

. (Join-Path $moduleRoot "LauncherPrograms.ps1")

. (Join-Path $moduleRoot "LauncherAction.ps1")



Describe "Launcher settings validation" {

    It "accepts valid settings with a saved browser" {

        $settings =
        ConvertTo-ValidatedLauncherSettings `
        -Settings ([pscustomobject]@{
            Selected = @("Spotify")
            Width = 1100
            Height = 550
            X = 200
            Y = 150
            BrowserId = "OperaGX"
        })



        $settings.GetType().Name |
        Should Be "GaloreLauncherSettings"



        $settings.BrowserId |
        Should Be "OperaGX"



        $settings.Selected.Count |
        Should Be 1

    }



    It "accepts existing settings that do not yet have a browser field" {

        $settings =
        ConvertTo-ValidatedLauncherSettings `
        -Settings ([pscustomobject]@{
            Selected = @()
            Width = 1100
            Height = 550
            X = 0
            Y = 0
        })



        $settings.BrowserId |
        Should Be $null

    }



    It "rejects an invalid window width" {

        {

            ConvertTo-ValidatedLauncherSettings `
            -Settings ([pscustomobject]@{
                Selected = @()
                Width = 100
                Height = 550
                X = 0
                Y = 0
            })

        } |
        Should Throw

    }



    It "rejects a non-string browser identifier" {

        {

            ConvertTo-ValidatedLauncherSettings `
            -Settings ([pscustomobject]@{
                Selected = @()
                Width = 1100
                Height = 550
                X = 0
                Y = 0
                BrowserId = 123
            })

        } |
        Should Throw

    }

}



Describe "Browser selection" {

    It "updates the Browser program definition without changing its key" {

        $programs = @{
            Browser = @{
                Path = $null
                StatusProcess = "browser"
                WindowProcess = "browser"
                BrowserId = $null
                BrowserDisplayName = "No browser detected"
            }
        }



        $browser =
        [pscustomobject]@{
            Id = "Firefox"
            DisplayName = "Mozilla Firefox"
            Path = "C:\\Program Files\\Mozilla Firefox\\firefox.exe"
            ProcessName = "firefox"
        }



        Set-GaloreBrowserProgram `
        -Programs $programs `
        -Browser $browser



        $programs.Contains("Browser") |
        Should Be $true



        $programs["Browser"]["BrowserId"] |
        Should Be "Firefox"



        $programs["Browser"]["Path"] |
        Should Be $browser.Path



        $programs["Browser"]["WindowProcess"] |
        Should Be "firefox"

    }



    It "updates a typed Browser program definition in place" {

        $browserProgram = [GaloreProgramDefinition]::new("", "", "browser", "browser")

        $programs = @{ Browser = $browserProgram }

        $browser = [pscustomobject]@{
            Id = "Firefox"
            DisplayName = "Mozilla Firefox"
            Path = "C:\Program Files\Mozilla Firefox\firefox.exe"
            ProcessName = "firefox"
        }

        Set-GaloreBrowserProgram -Programs $programs -Browser $browser

        [object]::ReferenceEquals($browserProgram, $programs.Browser) |
        Should Be $true

        $browserProgram.Path |
        Should Be $browser.Path

        $browserProgram.StatusProcess |
        Should Be "firefox"

        $browserProgram.WindowProcess |
        Should Be "firefox"

        $browserProgram.BrowserId |
        Should Be "Firefox"

        $browserProgram.BrowserDisplayName |
        Should Be "Mozilla Firefox"

    }

    It "only reports browsers whose executable path exists" {

        $browsers =
        Get-InstalledBrowsers



        ($browsers -is [System.Collections.IDictionary]) |
        Should Be $true



        foreach($browser in $browsers.Values)
        {

            Test-Path `
            -LiteralPath $browser.Path `
            -PathType Leaf |
            Should Be $true

        }

    }

    It "keeps a typed Browser definition unconfigured when no browser is installed" {

        Mock Get-InstalledBrowsers { [ordered]@{} }

        $browserProgram = [GaloreProgramDefinition]::new("C:\Apps\OldBrowser.exe", "", "oldbrowser", "oldbrowser")

        $browserProgram.BrowserId = "OldBrowser"

        $browserProgram.BrowserDisplayName = "Old Browser"

        $programs = @{ Browser = $browserProgram }

        Initialize-GaloreBrowser -Programs $programs -AppRoot $GaloreRoot

        $browserProgram.Path |
        Should Be ""

        $browserProgram.BrowserId |
        Should Be ""

        $browserProgram.BrowserDisplayName |
        Should Be "No browser detected"

    }

}



Describe "Search result images" {

    It "creates an image thumbnail for an image result" {

        $image =
        Get-SearchResultImage `
        -Item ([pscustomobject]@{
            Name = "image.png"
            Path = (Join-Path $GaloreRoot "resources\\image.png")
            Type = "Image"
        })



        try
        {

            $image.Width |
            Should Be 30



            $image.Height |
            Should Be 30

        }
        finally
        {

            if($image)
            {

                $image.Dispose()

            }

        }

    }



    It "creates a fallback icon for an installed application result" {

        $image =
        Get-SearchResultImage `
        -Item ([pscustomobject]@{
            Name = "Application"
            Path = "shell:AppsFolder\\Example"
            Type = "Application"
        })



        try
        {

            $image.Width |
            Should Be 30

        }
        finally
        {

            if($image)
            {

                $image.Dispose()

            }

        }

    }

}



Describe "Search result data" {

    It "preserves the name, path, and type supplied by the search engine" {

        $result =
        New-SearchResult -Name "Galore" -Path "D:\Example\Galore.exe" -Type "EXE"



        $result.Name |
        Should Be "Galore"



        $result.Path |
        Should Be "D:\Example\Galore.exe"



        $result.Type |
        Should Be "EXE"

    }

}

Describe "Start menu lifecycle" {

    BeforeEach {

        Stop-StartMenuResources

    }

    It "keeps Windows icon animation state on the timer instead of a local closure" {

        $windowsUI = New-WindowsStartButton

        try {
            $windowsUI.Timer.Tag |
            Should Not BeNullOrEmpty

            [object]::ReferenceEquals($windowsUI.Timer.Tag.Button, $windowsUI.Button) |
            Should Be $true

            [object]::ReferenceEquals($windowsUI.Timer.Tag.RotationState, $windowsUI.Button.Tag) |
            Should Be $true

            $initialRotation = [double]$windowsUI.Timer.Tag.RotationState.Rotation
            Start-Sleep -Milliseconds 80
            [System.Windows.Forms.Application]::DoEvents()

            ([double]$windowsUI.Timer.Tag.RotationState.Rotation -gt $initialRotation) |
            Should Be $true

        } finally {
            $windowsUI.Timer.Stop()
            $windowsUI.Timer.Tag = $null
            $windowsUI.Timer.Dispose()
            $windowsUI.Button.Dispose()
        }

    }

    It "does not create duplicate Windows toggle controls for the same form" {

        $form = New-Object System.Windows.Forms.Form

        Mock New-WindowsStartButton {
            [pscustomobject]@{
                Button = New-Object System.Windows.Forms.Button
                Timer = New-Object System.Windows.Forms.Timer
            }
        }

        try {
            Initialize-StartMenu -Form $form
            $firstButton = $script:GaloreStartMenuRuntime.WindowsButton
            $firstTimer = $script:GaloreStartMenuRuntime.WindowsTimer

            Initialize-StartMenu -Form $form

            [object]::ReferenceEquals($firstButton, $script:GaloreStartMenuRuntime.WindowsButton) |
            Should Be $true

            [object]::ReferenceEquals($firstTimer, $script:GaloreStartMenuRuntime.WindowsTimer) |
            Should Be $true

            Assert-MockCalled New-WindowsStartButton -Times 1 -Exactly -Scope It
        } finally {
            Stop-StartMenuResources
            $form.Dispose()
        }

    }

}

Describe "Quick Access persistence" {

    BeforeEach {

        Stop-GaloreQuickAccessResources
        $script:GaloreQuickAccessRuntime = [GaloreQuickAccessRuntimeState]::new()
        $script:GaloreQuickAccessRuntime.StatePath = Join-Path $TestDrive "quick-access.json"
        Mock Update-GaloreQuickAccessBar {}
        Mock Write-LauncherDiagnostic {}

    }

    It "returns no items when its state file is missing" {

        @(
            Get-GaloreQuickAccessItems
        ).Count |
        Should Be 0

    }

    It "returns no items when its state file is malformed" {

        Set-Content -LiteralPath $script:GaloreQuickAccessRuntime.StatePath -Value "not json" -Encoding UTF8

        @(
            Get-GaloreQuickAccessItems
        ).Count |
        Should Be 0

        Assert-MockCalled Write-LauncherDiagnostic -Times 1 -Exactly

    }

    It "keeps only saved items whose paths still exist" {

        $existingFile = Join-Path $TestDrive "tool.exe"
        $existingFolder = Join-Path $TestDrive "Folder"
        New-Item -ItemType File -Path $existingFile | Out-Null
        New-Item -ItemType Directory -Path $existingFolder | Out-Null

        [pscustomobject]@{
            Version = 1
            Items = @(
                [pscustomobject]@{ Path = $existingFile }
                [pscustomobject]@{ Path = $existingFolder }
                [pscustomobject]@{ Path = (Join-Path $TestDrive "missing.exe") }
                [pscustomobject]@{ Path = "" }
            )
        } |
        ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath $script:GaloreQuickAccessRuntime.StatePath -Encoding UTF8

        $items = @(Get-GaloreQuickAccessItems)

        $items.Count |
        Should Be 2

        ($items.Path -contains $existingFile) |
        Should Be $true

        ($items.Path -contains $existingFolder) |
        Should Be $true

    }

    It "saves only the expected version and item paths" {

        [void]$script:GaloreQuickAccessRuntime.Items.Add([pscustomobject]@{ Path = "C:\\Tools\\One.exe" })
        [void]$script:GaloreQuickAccessRuntime.Items.Add([pscustomobject]@{ Path = "C:\\Tools\\Two.exe" })

        Save-GaloreQuickAccessItems

        $saved = Get-Content -LiteralPath $script:GaloreQuickAccessRuntime.StatePath -Raw | ConvertFrom-Json

        $saved.Version |
        Should Be 1

        @($saved.Items).Count |
        Should Be 2

        $saved.Items[0].Path |
        Should Be "C:\\Tools\\One.exe"

        $saved.Items[0].PSObject.Properties.Name |
        Should Be "Path"

    }

    It "removes one matching item and refreshes the visual bar" {

        $first = [pscustomobject]@{ Path = "C:\\Tools\\One.exe" }
        $second = [pscustomobject]@{ Path = "C:\\Tools\\Two.exe" }
        [void]$script:GaloreQuickAccessRuntime.Items.Add($first)
        [void]$script:GaloreQuickAccessRuntime.Items.Add($second)

        Remove-GaloreQuickAccessItem -Path $first.Path

        @($script:GaloreQuickAccessRuntime.Items).Count |
        Should Be 1

        $script:GaloreQuickAccessRuntime.Items[0].Path |
        Should Be $second.Path

        Assert-MockCalled Update-GaloreQuickAccessBar -Times 1 -Exactly

    }

    It "leaves the collection untouched when the requested item is absent" {

        [void]$script:GaloreQuickAccessRuntime.Items.Add([pscustomobject]@{ Path = "C:\\Tools\\One.exe" })

        Remove-GaloreQuickAccessItem -Path "C:\\Tools\\Missing.exe"

        @($script:GaloreQuickAccessRuntime.Items).Count |
        Should Be 1

    }

}

Describe "Quick Access drop handling" {

    BeforeEach {

        Stop-GaloreQuickAccessResources
        $script:GaloreQuickAccessRuntime = [GaloreQuickAccessRuntimeState]::new()
        $script:GaloreQuickAccessRuntime.StatePath = Join-Path $TestDrive "quick-access.json"
        Mock Save-GaloreQuickAccessItems {}
        Mock Update-GaloreQuickAccessBar {}
        Mock Write-LauncherDiagnostic {}

    }

    It "adds each supported dropped item once and ignores unsupported duplicates" {

        $executable = Join-Path $TestDrive "tool.exe"
        $shortcut = Join-Path $TestDrive "tool.lnk"
        $internetShortcut = Join-Path $TestDrive "site.url"
        $folder = Join-Path $TestDrive "Folder"
        $textFile = Join-Path $TestDrive "notes.txt"

        New-Item -ItemType File -Path $executable | Out-Null
        New-Item -ItemType File -Path $shortcut | Out-Null
        New-Item -ItemType File -Path $internetShortcut | Out-Null
        New-Item -ItemType Directory -Path $folder | Out-Null
        New-Item -ItemType File -Path $textFile | Out-Null

        $data = New-Object System.Windows.Forms.DataObject
        $data.SetData(
            [System.Windows.Forms.DataFormats]::FileDrop,
            [string[]]@(
                $executable,
                $shortcut,
                $internetShortcut,
                $folder,
                $textFile,
                $executable
            )
        )

        Add-GaloreQuickAccessDroppedItems -Data $data

        @($script:GaloreQuickAccessRuntime.Items).Count |
        Should Be 4

        foreach($path in @($executable, $shortcut, $internetShortcut, $folder))
        {
            ($script:GaloreQuickAccessRuntime.Items.Path -contains $path) |
            Should Be $true
        }

        ($script:GaloreQuickAccessRuntime.Items.Path -contains $textFile) |
        Should Be $false

        Assert-MockCalled Save-GaloreQuickAccessItems -Times 1 -Exactly
        Assert-MockCalled Update-GaloreQuickAccessBar -Times 1 -Exactly

    }

    It "ignores null and non-file-drop data without changing state" {

        [void]$script:GaloreQuickAccessRuntime.Items.Add(
            [pscustomobject]@{ Path = "C:\\Tools\\Existing.exe" }
        )

        $plainData = New-Object System.Windows.Forms.DataObject
        $plainData.SetData(
            [System.Windows.Forms.DataFormats]::Text,
            "plain text"
        )

        Add-GaloreQuickAccessDroppedItems -Data $null
        Add-GaloreQuickAccessDroppedItems -Data $plainData

        @($script:GaloreQuickAccessRuntime.Items).Count |
        Should Be 1

        Assert-MockCalled Save-GaloreQuickAccessItems -Times 0 -Exactly -Scope It
        Assert-MockCalled Update-GaloreQuickAccessBar -Times 0 -Exactly -Scope It

    }

}

Describe "Quick Access runtime ownership" {

    BeforeEach {

        Stop-GaloreQuickAccessResources
        $script:GaloreQuickAccessRuntime = [GaloreQuickAccessRuntimeState]::new()
        $script:SettingsFolder = $TestDrive

    }

    AfterEach {

        Stop-GaloreQuickAccessResources

    }

    It "starts with one typed empty runtime" {

        $runtime = $script:GaloreQuickAccessRuntime

        $runtime.OwnerForm |
        Should BeNullOrEmpty

        $runtime.Bar |
        Should BeNullOrEmpty

        $runtime.Items.Count |
        Should Be 0

        $runtime.IsInitialized |
        Should Be $false

    }

    It "registers an interactive quick-access drop target" {

        $target = New-Object System.Windows.Forms.Panel
        try {
            Register-GaloreQuickAccessDropTarget -Target $target -Runtime $script:GaloreQuickAccessRuntime

            $target.AllowDrop | Should Be $true
            $script:GaloreQuickAccessRuntime.Items.Count | Should Be 0
        } finally {
            $target.Dispose()
        }
    }

    It "reuses one bar when initialized twice for the same form" {

        $form = New-Object System.Windows.Forms.Form

        try {
            Initialize-GaloreQuickAccessBar -Form $form
            $firstBar = $script:GaloreQuickAccessRuntime.Bar

            Initialize-GaloreQuickAccessBar -Form $form

            [object]::ReferenceEquals($firstBar, $script:GaloreQuickAccessRuntime.Bar) |
            Should Be $true

            $script:GaloreQuickAccessRuntime.IsInitialized |
            Should Be $true

        } finally {
            $form.Dispose()
        }

    }

    It "releases the old owner before moving to a new form" {

        $firstForm = New-Object System.Windows.Forms.Form
        $secondForm = New-Object System.Windows.Forms.Form

        try {
            Initialize-GaloreQuickAccessBar -Form $firstForm
            $firstBar = $script:GaloreQuickAccessRuntime.Bar

            Initialize-GaloreQuickAccessBar -Form $secondForm

            [object]::ReferenceEquals($script:GaloreQuickAccessRuntime.OwnerForm, $secondForm) |
            Should Be $true

            [object]::ReferenceEquals($firstBar, $script:GaloreQuickAccessRuntime.Bar) |
            Should Be $false

            $firstForm.Close()

            [object]::ReferenceEquals($script:GaloreQuickAccessRuntime.OwnerForm, $secondForm) |
            Should Be $true

        } finally {
            $firstForm.Dispose()
            $secondForm.Dispose()
        }

    }

    It "stops and clears owned resources idempotently" {

        $form = New-Object System.Windows.Forms.Form

        try {
            Initialize-GaloreQuickAccessBar -Form $form

            { Stop-GaloreQuickAccessResources; Stop-GaloreQuickAccessResources } |
            Should Not Throw

            $runtime = $script:GaloreQuickAccessRuntime
            $runtime.OwnerForm |
            Should BeNullOrEmpty

            $runtime.Bar |
            Should BeNullOrEmpty

            $runtime.ToolTip |
            Should BeNullOrEmpty

            $runtime.MoveHandler |
            Should BeNullOrEmpty

            $runtime.IsInitialized |
            Should Be $false

        } finally {
            $form.Dispose()
        }

    }

}

Describe "Window taskbar filtering" {

    It "accepts a visible, titled main window" {

        [GaloreWindowTaskbar.Native]::IsTaskbarWindowCandidate(
            $true, $false, $false, $true, 1, $false
        ) |
        Should Be $true

    }

    It "rejects windows that Windows does not show as taskbar applications" {

        foreach($candidate in @(
            @($false, $false, $false, $true, 1, $false),
            @($true, $true, $false, $true, 1, $false),
            @($true, $false, $true, $true, 1, $false),
            @($true, $false, $false, $false, 1, $false),
            @($true, $false, $false, $true, 0, $false),
            @($true, $false, $false, $true, 1, $true)
        ))
        {
            [GaloreWindowTaskbar.Native]::IsTaskbarWindowCandidate(
                $candidate[0], $candidate[1], $candidate[2], $candidate[3], $candidate[4], $candidate[5]
            ) |
            Should Be $false
        }

    }

    It "changes the visual signature only when the tracked windows change" {

        $first = @(
            [pscustomobject]@{ Handle = [IntPtr]1; Title = "One" }
            [pscustomobject]@{ Handle = [IntPtr]2; Title = "Two" }
        )

        $same = @(
            [pscustomobject]@{ Handle = [IntPtr]1; Title = "One" }
            [pscustomobject]@{ Handle = [IntPtr]2; Title = "Two" }
        )

        $changed = @(
            [pscustomobject]@{ Handle = [IntPtr]1; Title = "One updated" }
            [pscustomobject]@{ Handle = [IntPtr]2; Title = "Two" }
        )

        (Get-GaloreWindowTaskbarSignature -Windows $first) |
        Should Be (Get-GaloreWindowTaskbarSignature -Windows $same)

        (Get-GaloreWindowTaskbarSignature -Windows $first) |
        Should Not Be (Get-GaloreWindowTaskbarSignature -Windows $changed)

    }

    It "returns no icon for an unavailable process" {

        $image =
        Get-GaloreWindowTaskbarIcon `
        -ProcessId ([uint32]::MaxValue)

        $image |
        Should Be $null

    }

    It "stops and clears taskbar runtime state safely" {

        $script:GaloreWindowTaskbarRuntime = [GaloreWindowTaskbarRuntimeState]::new()
        $script:GaloreWindowTaskbarRuntime.Timer = New-Object System.Windows.Forms.Timer
        $script:GaloreWindowTaskbarRuntime.Signature = "previous-state"

        Stop-GaloreWindowTaskbar

        $script:GaloreWindowTaskbarRuntime.Bar |
        Should Be $null

        $script:GaloreWindowTaskbarRuntime.Timer |
        Should Be $null

        $script:GaloreWindowTaskbarRuntime.Signature |
        Should Be "<uninitialized>"

    }

    It "uses one typed runtime owner for the taskbar timer and display state" {

        $runtime = [GaloreWindowTaskbarRuntimeState]::new()

        $runtime.Bar |
        Should BeNullOrEmpty

        $runtime.Timer |
        Should BeNullOrEmpty

        $runtime.ToolTip |
        Should BeNullOrEmpty

        $runtime.Signature |
        Should Be "<uninitialized>"

        $runtime.KeyColor |
        Should BeNullOrEmpty

    }

}

Describe "Alpha overlay helpers" {

    BeforeEach {

        Stop-GaloreOverlayResources
        $script:GaloreOverlayRuntime = [GaloreOverlayRuntimeState]::new()

    }

    AfterEach {

        Stop-GaloreOverlayResources

    }

    It "starts with one typed empty overlay runtime" {

        $runtime = $script:GaloreOverlayRuntime

        $runtime.OwnerForm |
        Should BeNullOrEmpty

        $runtime.OverlayForms.Count |
        Should Be 0

        $runtime.FadeTimers.Count |
        Should Be 0

        $runtime.TargetVisible |
        Should Be $true

    }

    It "registers overlay forms once and releases only the requested form" {

        $first = New-Object GaloreAlphaOverlay.PerPixelAlphaForm
        $second = New-Object GaloreAlphaOverlay.PerPixelAlphaForm

        try {
            Register-GaloreOverlayForm -Form $first
            Register-GaloreOverlayForm -Form $first
            Register-GaloreOverlayForm -Form $second

            $script:GaloreOverlayRuntime.OverlayForms.Count |
            Should Be 2

            Unregister-GaloreOverlayForm -Form $first

            $script:GaloreOverlayRuntime.OverlayForms.Count |
            Should Be 1

            [object]::ReferenceEquals($script:GaloreOverlayRuntime.OverlayForms[0], $second) |
            Should Be $true

        } finally {
            $first.Dispose()
            $second.Dispose()
        }

    }

    It "replaces a prior fade timer without retaining stale runtime state" {

        $form = New-Object GaloreAlphaOverlay.PerPixelAlphaForm

        try {
            Start-GaloreOverlayFade -Form $form -TargetOpacity 0 -DurationMilliseconds 500
            $firstTimer = $script:GaloreOverlayRuntime.FadeTimers[$form]

            Start-GaloreOverlayFade -Form $form -TargetOpacity 0 -DurationMilliseconds 500
            $secondTimer = $script:GaloreOverlayRuntime.FadeTimers[$form]

            [object]::ReferenceEquals($firstTimer, $secondTimer) |
            Should Be $false

            $script:GaloreOverlayRuntime.FadeTimers.Count |
            Should Be 1

            Stop-GaloreOverlayFade -Form $form

            $script:GaloreOverlayRuntime.FadeTimers.Count |
            Should Be 0

        } finally {
            $form.Dispose()
        }

    }

    It "fades every registered overlay form without touching unregistered forms" {

        $first = New-Object GaloreAlphaOverlay.PerPixelAlphaForm
        $second = New-Object GaloreAlphaOverlay.PerPixelAlphaForm

        try {
            Register-GaloreOverlayForm -Form $first
            Register-GaloreOverlayForm -Form $second
            Mock Start-GaloreOverlayFade {}

            Show-GaloreLauncherOverlayBars
            Show-GaloreLauncherOverlayBars -DurationMilliseconds 123
            Assert-MockCalled Start-GaloreOverlayFade -Times 2 -Exactly -ParameterFilter { $TargetOpacity -eq 255 -and $DurationMilliseconds -eq 123 }
            Assert-MockCalled Start-GaloreOverlayFade -Times 4 -Exactly -ParameterFilter { $TargetOpacity -eq 255 }
        } finally {
            $first.Dispose()
            $second.Dispose()
        }
    }

    It "owns lifecycle registration and clears it idempotently" {

        $firstForm = New-Object System.Windows.Forms.Form
        $secondForm = New-Object System.Windows.Forms.Form

        try {
            Register-GaloreOverlayLifecycle -Form $firstForm
            Register-GaloreOverlayLifecycle -Form $firstForm

            [object]::ReferenceEquals($script:GaloreOverlayRuntime.OwnerForm, $firstForm) |
            Should Be $true

            Register-GaloreOverlayLifecycle -Form $secondForm

            [object]::ReferenceEquals($script:GaloreOverlayRuntime.OwnerForm, $secondForm) |
            Should Be $true

            { Stop-GaloreOverlayResources; Stop-GaloreOverlayResources } |
            Should Not Throw

            $script:GaloreOverlayRuntime.OwnerForm |
            Should BeNullOrEmpty

            $script:GaloreOverlayRuntime.ResizeHandler |
            Should BeNullOrEmpty

        } finally {
            $firstForm.Dispose()
            $secondForm.Dispose()
        }

    }

    It "converts an icon to a correctly sized premultiplied-alpha bitmap" {

        $image = $null

        try
        {
            $image = [GaloreAlphaOverlay.PerPixelAlphaForm]::IconToAlphaBitmap(
                [System.Drawing.SystemIcons]::Application,
                19,
                23
            )

            $image.Width |
            Should Be 19

            $image.Height |
            Should Be 23

            $image.PixelFormat |
            Should Be ([System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
        }
        finally
        {
            if($image)
            {
                $image.Dispose()
            }
        }

    }

    It "clamps layered opacity without requiring a visible form" {

        $form = New-Object GaloreAlphaOverlay.PerPixelAlphaForm

        try
        {
            $form.SetLayeredOpacity(-1)
            $form.LayeredOpacity |
            Should Be 0

            $form.SetLayeredOpacity(999)
            $form.LayeredOpacity |
            Should Be 255
        }
        finally
        {
            $form.Dispose()
        }

    }

    It "uses image alpha to exclude transparent form areas" {

        $form = New-Object System.Windows.Forms.Form
        $bitmap = New-Object System.Drawing.Bitmap(
            4,
            4,
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
        )

        try
        {
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)

            try
            {
                $graphics.Clear([System.Drawing.Color]::Transparent)
                $bitmap.SetPixel(1, 1, [System.Drawing.Color]::White)
                $bitmap.SetPixel(2, 1, [System.Drawing.Color]::White)
                $bitmap.SetPixel(1, 2, [System.Drawing.Color]::White)
                $bitmap.SetPixel(2, 2, [System.Drawing.Color]::White)
            }
            finally
            {
                $graphics.Dispose()
            }

            Set-GaloreTransparentWindowRegion `
            -Form $form `
            -Bitmap $bitmap

            $form.Region.IsVisible(1, 1) |
            Should Be $true

            $form.Region.IsVisible(0, 0) |
            Should Be $false
        }
        finally
        {
            $bitmap.Dispose()
            $form.Dispose()
        }

    }

    It "accepts null form or bitmap without throwing" {

        { Set-GaloreTransparentWindowRegion -Form $null -Bitmap $null } |
        Should Not Throw

    }

}

Describe "Post-it persistence reads" {

    BeforeEach {

        $script:GalorePostItStorePath = Join-Path $TestDrive "postits.json"
        Mock Write-LauncherDiagnostic {}

    }

    It "returns no notes when no post-it state exists" {

        @(Read-GalorePostItStates).Count |
        Should Be 0

    }

    It "keeps valid saved note state" {

        [pscustomobject]@{
            Version = 1
            Notes = @(
                [pscustomobject]@{
                    Id = "note-one"
                    Text = "Remember this"
                    X = -200
                    Y = 120
                    Checked = $false
                }
            )
        } |
        ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath $script:GalorePostItStorePath -Encoding UTF8

        $notes = @(Read-GalorePostItStates)

        $notes.Count |
        Should Be 1

        $notes[0].Id |
        Should Be "note-one"

        $notes[0].Text |
        Should Be "Remember this"

        $notes[0].X |
        Should Be -200

    }

    It "rejects malformed post-it state without throwing" {

        Set-Content -LiteralPath $script:GalorePostItStorePath -Value "not json" -Encoding UTF8

        @(Read-GalorePostItStates).Count |
        Should Be 0

        Assert-MockCalled Write-LauncherDiagnostic -Times 1 -Exactly

    }

}

Describe "Settings backup selection" {

    BeforeEach {

        $script:GaloreBackupSettingsFolder = Join-Path $TestDrive "Settings"

        New-Item -ItemType Directory -Path $script:GaloreBackupSettingsFolder -Force | Out-Null

        Mock Get-LauncherSettingsFolder { $script:GaloreBackupSettingsFolder }

    }

    It "includes only Galore state files that exist" {

        Set-Content -LiteralPath (Join-Path $script:GaloreBackupSettingsFolder "settings.json") -Value "{}"

        Set-Content -LiteralPath (Join-Path $script:GaloreBackupSettingsFolder "categories.json") -Value "{}"

        Set-Content -LiteralPath (Join-Path $script:GaloreBackupSettingsFolder "hotkeys.json") -Value "{}"

        $files = @(Get-GaloreSettingsBackupFiles)

        $files.Count |
        Should Be 3

        @($files | ForEach-Object { Split-Path $_ -Leaf }) |
        Should Contain "settings.json"

        @($files | ForEach-Object { Split-Path $_ -Leaf }) |
        Should Contain "categories.json"

        @($files | ForEach-Object { Split-Path $_ -Leaf }) |
        Should Contain "hotkeys.json"

        @($files | ForEach-Object { Split-Path $_ -Leaf }) |
        Should Not Contain "maintenance-state.json"

    }

}

Describe "Hotkey settings persistence" {

    BeforeEach {

        $script:GaloreHotkeyTestSettingsFolder = Join-Path $TestDrive "Settings"

        New-Item -ItemType Directory -Path $script:GaloreHotkeyTestSettingsFolder -Force | Out-Null

        Mock Get-LauncherSettingsFolder { $script:GaloreHotkeyTestSettingsFolder }

        Mock Write-LauncherDiagnostic {}

    }

    It "saves and restores the launcher and category hotkeys" {

        Initialize-GaloreHotkeySettings

        $script:GaloreLauncherHotkey = [pscustomobject]@{ ModifierMask = 6; VirtualKey = 72; DisplayText = "Ctrl+Shift+H" }

        $script:GaloreCategoryHotkeys["Category2"] = [pscustomobject]@{ ModifierMask = 6; VirtualKey = 74; DisplayText = "Ctrl+Shift+J" }

        Save-GaloreHotkeySettings

        $script:GaloreLauncherHotkey = $null

        $script:GaloreCategoryHotkeys = $null

        Initialize-GaloreHotkeySettings

        (Get-GaloreLauncherToggleHotkey).DisplayText |
        Should Be "Ctrl+Shift+H"

        (Get-GaloreCategoryHotkey -CategoryId "Category2").DisplayText |
        Should Be "Ctrl+Shift+J"

        (Get-Content -LiteralPath (Join-Path $script:GaloreHotkeyTestSettingsFolder "hotkeys.json") -Raw | ConvertFrom-Json).Version |
        Should Be 2

    }

    It "loads a saved shortcut override without rewriting it with the default" {

        $savedSettings =
        [pscustomobject]@{
            Version = 2
            LauncherToggle = [pscustomobject]@{
                ModifierMask = 2
                VirtualKey = 84
                DisplayText = "Ctrl+T"
            }
            Categories = [pscustomobject]@{}
        }

        $savedSettings |
        ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath (Join-Path $script:GaloreHotkeyTestSettingsFolder "hotkeys.json")

        Mock Save-GaloreHotkeySettings {}

        Initialize-GaloreHotkeySettings

        (Get-GaloreLauncherToggleHotkey).DisplayText |
        Should Be "Ctrl+T"

        Assert-MockCalled Save-GaloreHotkeySettings `
        -Times 0 `
        -Exactly

    }

    It "formats a captured Ctrl+T shortcut for immediate display" {

        $event = [pscustomobject]@{
            Control = $true
            Alt = $false
            Shift = $false
            KeyCode = [System.Windows.Forms.Keys]::T
        }

        $hotkey =
        ConvertFrom-GaloreHotkeyKeyEvent `
        -Event $event

        $hotkey.DisplayText |
        Should Be "Ctrl+T"

        $hotkey.ModifierMask |
        Should Be 2

    }

    It "keeps capture and apply state shared across hotkey events" {

        Initialize-GaloreHotkeySettings

        Mock Set-GaloreHotkeyDefinitions { return $true }

        $field =
        [pscustomobject]@{
            Tag = "LauncherToggle"
            Text = "Ctrl+Shift+Space"
            IsDisposed = $false
        }

        $captureState =
        [pscustomobject]@{
            Field = $field
            Pending = @{}
        }

        $status =
        [pscustomobject]@{
            Text = ""
            ForeColor = $null
        }

        $captureEvent =
        [pscustomobject]@{
            Control = $true
            Alt = $false
            Shift = $false
            KeyCode = [System.Windows.Forms.Keys]::T
            SuppressKeyPress = $false
            Handled = $false
        }

        Invoke-GaloreHotkeyCaptureInput `
        -Event $captureEvent `
        -StatusLabel $status `
        -CaptureState $captureState

        $field.Text |
        Should Be "Ctrl+T"

        $captureState.Pending["LauncherToggle"].DisplayText |
        Should Be "Ctrl+T"

        $applyEvent =
        [pscustomobject]@{
            Control = $false
            Alt = $false
            Shift = $false
            KeyCode = [System.Windows.Forms.Keys]::Back
            SuppressKeyPress = $false
            Handled = $false
        }

        Invoke-GaloreHotkeyCaptureInput `
        -Event $applyEvent `
        -StatusLabel $status `
        -CaptureState $captureState

        $captureState.Field |
        Should BeNullOrEmpty

        $captureState.Pending.Count |
        Should Be 0

        $status.Text |
        Should Be "Shortcut applied and saved."

        Assert-MockCalled Set-GaloreHotkeyDefinitions `
        -Times 1 `
        -Exactly `
        -ParameterFilter {
            $LauncherToggle.DisplayText -eq "Ctrl+T"
        }

    }

    It "reuses taskbar resources for repeated initialization on one form" {

        Stop-GaloreWindowTaskbar
        $script:GaloreWindowTaskbarRuntime = [GaloreWindowTaskbarRuntimeState]::new()
        $form = New-Object System.Windows.Forms.Form
        Mock Register-GaloreOverlayForm {}
        Mock Register-GaloreOverlayLifecycle {}

        try {
            Initialize-GaloreWindowTaskbar -Form $form
            $firstBar = $script:GaloreWindowTaskbarRuntime.Bar
            $firstTimer = $script:GaloreWindowTaskbarRuntime.Timer

            Initialize-GaloreWindowTaskbar -Form $form

            $script:GaloreWindowTaskbarRuntime.Bar | Should Be $firstBar
            $script:GaloreWindowTaskbarRuntime.Timer | Should Be $firstTimer
            $script:GaloreWindowTaskbarRuntime.OwnerForm | Should Be $form
            Assert-MockCalled Register-GaloreOverlayForm -Times 1 -Exactly
        } finally {
            Stop-GaloreWindowTaskbar
            $form.Dispose()
        }

        $script:GaloreWindowTaskbarRuntime.IsInitialized | Should Be $false
    }

}

Describe "Category state contracts" {

    BeforeEach {

        $script:GaloreCategoryTestSettingsFolder = Join-Path $TestDrive "CategorySettings"

        New-Item -ItemType Directory -Path $script:GaloreCategoryTestSettingsFolder -Force | Out-Null

        Mock Get-LauncherSettingsFolder { $script:GaloreCategoryTestSettingsFolder }

        Mock Write-LauncherDiagnostic {}

        $script:GaloreCategoryRuntime = [GaloreCategoryRuntimeState]::new()

    }

    It "creates four categories with five uniquely identified slots each" {

        $state = New-GaloreCategoryState

        $state.GetType().Name |
        Should Be "GaloreCategoryState"

        @($state.Categories).Count |
        Should Be 4

        $slots = @($state.Categories | ForEach-Object { $_.Slots })

        $slots.Count |
        Should Be 20

        @($slots | Where-Object { $_ -isnot [GaloreCategorySlot] }).Count |
        Should Be 0

        @($slots.Id | Select-Object -Unique).Count |
        Should Be 20

        @($slots | Where-Object { $_.DisplayName -ne "Empty" -or $_.Selected -or $_.Path }).Count |
        Should Be 0

    }

    It "round-trips category names, paths, labels, and selection state" {

        $state = Initialize-GaloreCategoryState

        $state.Categories[1].Name = "Recording"

        $state.Categories[1].Slots[2].Path = "C:\\Tools\\Recorder.exe"

        $state.Categories[1].Slots[2].DisplayName = "Recorder"

        $state.Categories[1].Slots[2].Selected = $true

        Save-GaloreCategoryState

        $script:GaloreCategoryRuntime = [GaloreCategoryRuntimeState]::new()

        $restored = Initialize-GaloreCategoryState

        $restored.Categories[1].Name |
        Should Be "Recording"

        $restored.Categories[1].Slots[2].Path |
        Should Be "C:\\Tools\\Recorder.exe"

        $restored.Categories[1].Slots[2].DisplayName |
        Should Be "Recorder"

        $restored.Categories[1].Slots[2].Selected |
        Should Be $true

    }

    It "restores defaults when saved category data has the wrong shape" {

        [pscustomobject]@{
            Version = 1
            Categories = @([pscustomobject]@{ Name = "Incomplete"; Slots = @() })
        } |
        ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath (Join-Path $script:GaloreCategoryTestSettingsFolder "categories.json") -Encoding UTF8

        $state = Initialize-GaloreCategoryState

        @($state.Categories).Count |
        Should Be 4

        $state.Categories[0].Name |
        Should Be "Category 1"

        Assert-MockCalled Write-LauncherDiagnostic -Times 1 -Exactly -Scope It

    }

    It "recognizes only slots that have a non-empty executable path" {

        Test-GaloreCategorySlotConfigured ([pscustomobject]@{ Path = "C:\\App.exe" }) |
        Should Be $true

        Test-GaloreCategorySlotConfigured ([pscustomobject]@{ Path = "   " }) |
        Should Be $false

    }

    It "rejects a non-boolean saved slot selection and restores defaults" {

        $state = New-GaloreCategoryState

        $state.Categories[0].Slots[0].Selected = $true

        $saved = $state | ConvertTo-Json -Depth 6 | ConvertFrom-Json

        $saved.Categories[0].Slots[0].Selected = "yes"

        $saved |
        ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath (Join-Path $script:GaloreCategoryTestSettingsFolder "categories.json") -Encoding UTF8

        $restored = Initialize-GaloreCategoryState

        $restored.Categories[0].Slots[0].Selected |
        Should Be $false

        Assert-MockCalled Write-LauncherDiagnostic -Times 1 -Exactly -Scope It

    }

    It "rejects a string category schema version instead of coercing it" {

        $saved = New-GaloreCategoryState | ConvertTo-Json -Depth 6 | ConvertFrom-Json

        $saved.Version = "1"

        $saved |
        ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath (Join-Path $script:GaloreCategoryTestSettingsFolder "categories.json") -Encoding UTF8

        $restored = Initialize-GaloreCategoryState

        $restored.Categories[0].Name |
        Should Be "Category 1"

        Assert-MockCalled Write-LauncherDiagnostic -Times 1 -Exactly -Scope It

    }

    It "rejects a non-string category name instead of coercing it" {

        $saved = New-GaloreCategoryState | ConvertTo-Json -Depth 6 | ConvertFrom-Json

        $saved.Categories[0].Name = 42

        $saved |
        ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath (Join-Path $script:GaloreCategoryTestSettingsFolder "categories.json") -Encoding UTF8

        $restored = Initialize-GaloreCategoryState

        $restored.Categories[0].Name |
        Should Be "Category 1"

        Assert-MockCalled Write-LauncherDiagnostic -Times 1 -Exactly -Scope It

    }

    It "calculates unchecked, partial, and fully checked master category state" {

        $category = (New-GaloreCategoryState).Categories[0]

        $master = New-Object System.Windows.Forms.CheckBox

        try {

            $category.Slots[0].Path = "C:\Apps\One.exe"

            $category.Slots[1].Path = "C:\Apps\Two.exe"

            Update-GaloreCategoryMaster -Category $category -Master $master

            $master.CheckState |
            Should Be ([System.Windows.Forms.CheckState]::Unchecked)

            $category.Slots[0].Selected = $true

            Update-GaloreCategoryMaster -Category $category -Master $master

            $master.CheckState |
            Should Be ([System.Windows.Forms.CheckState]::Indeterminate)

            $category.Slots[1].Selected = $true

            Update-GaloreCategoryMaster -Category $category -Master $master

            $master.CheckState |
            Should Be ([System.Windows.Forms.CheckState]::Checked)

        } finally {

            $master.Dispose()

        }

    }

    It "clears typed slot state and its existing view and program projections" {

        $category = (New-GaloreCategoryState).Categories[0]

        $slot = $category.Slots[0]

        $slot.Path = "C:\Apps\One.exe"

        $slot.DisplayName = "One"

        $slot.Selected = $true

        $master = New-Object System.Windows.Forms.CheckBox

        $label = New-Object System.Windows.Forms.Label

        $label.Text = "One"

        $check = New-Object System.Windows.Forms.CheckBox

        $check.Checked = $true

        $program = [GaloreProgramDefinition]::new($slot.Path, "--test", "One", "One")

        $program.DisplayName = "One"

        $programs = @{ $slot.Id = $program }

        $checks = @{
            $slot.Id = [pscustomobject]@{ Checked = $true }
        }

        try {

            Clear-GaloreCategorySlot -Slot $slot -Category $category -Master $master -Label $label -Check $check -Programs $programs -Checks $checks

            $slot.IsConfigured() |
            Should Be $false

            $slot.DisplayName |
            Should Be "Empty"

            $slot.Selected |
            Should Be $false

            $programs[$slot.Id].Path |
            Should Be ""

            $programs[$slot.Id].DisplayName |
            Should Be "Empty"

            $programs[$slot.Id].Args |
            Should Be ""

            $programs[$slot.Id].StatusProcess |
            Should Be ""

            $programs[$slot.Id].WindowProcess |
            Should Be ""

            $checks[$slot.Id].Checked |
            Should Be $false

            $label.Text |
            Should Be "Empty"

            $check.Checked |
            Should Be $false

        } finally {

            $master.Dispose()

            $label.Dispose()

            $check.Dispose()

        }

    }

}

Describe "Category program projections" {

    It "projects every category slot into a typed program definition" {

        Mock Initialize-GaloreCategoryState { New-GaloreCategoryState }

        $form = New-Object System.Windows.Forms.Form

        try {

            $projection = Initialize-GaloreCategories -Form $form

            $projection.Programs.Count |
            Should Be 20

            @($projection.Programs.Values | Where-Object { $_ -isnot [GaloreProgramDefinition] }).Count |
            Should Be 0

            $projection.Programs.Category1Slot1.DisplayName |
            Should Be "Empty"

        } finally {

            $form.Dispose()

        }

    }

}

Describe "Category and hotkey settings runtime ownership" {

    It "keeps category state, popups, and projection ownership in one typed runtime" {

        $runtime = [GaloreCategoryRuntimeState]::new()
        $script:GaloreCategoryRuntimeTestSettingsFolder = Join-Path $TestDrive "CategoryRuntimeSettings"
        New-Item -ItemType Directory -Path $script:GaloreCategoryRuntimeTestSettingsFolder -Force | Out-Null
        Mock Get-LauncherSettingsFolder { $script:GaloreCategoryRuntimeTestSettingsFolder }
        $runtime.State | Should BeNullOrEmpty
        $runtime.Windows.Count | Should Be 0

        $form = New-Object System.Windows.Forms.Form
        try {
            $projection = Initialize-GaloreCategories -Form $form -Runtime $runtime
            (Initialize-GaloreCategories -Form $form -Runtime $runtime) | Should Be $projection
            $runtime.OwnerForm | Should Be $form
            $runtime.Projection | Should Be $projection
            $runtime.Masters.Count | Should Be 4
            @($form.Controls | Where-Object { $_.Name -match '^Category[1-4]$' }).Count | Should Be 4
        } finally {
            Stop-GaloreCategoryResources -Runtime $runtime
            Stop-GaloreCategoryResources -Runtime $runtime
            $form.Dispose()
        }

        $runtime.Windows.Count | Should Be 0
        $runtime.OwnerForm | Should BeNullOrEmpty
        $runtime.Projection | Should BeNullOrEmpty
        $runtime.Masters.Count | Should Be 0
    }

    It "stops a category popup registry safely and idempotently" {

        $runtime = [GaloreCategoryRuntimeState]::new()
        $window = New-Object System.Windows.Forms.Form
        $runtime.Windows["Category1"] = $window

        Stop-GaloreCategoryResources -Runtime $runtime
        Stop-GaloreCategoryResources -Runtime $runtime

        $runtime.Windows.Count | Should Be 0
        $window.IsDisposed | Should Be $true
    }

    It "owns hotkey settings controls and releases them safely" {

        $runtime = [GaloreHotkeySettingsRuntimeState]::new()
        $runtime.Popup | Should BeNullOrEmpty
        $runtime.Button | Should BeNullOrEmpty

        $runtime.Popup = New-Object System.Windows.Forms.Form
        $runtime.Button = New-Object System.Windows.Forms.Button
        $runtime.ToolTip = New-Object System.Windows.Forms.ToolTip

        Stop-GaloreHotkeySettingsResources -Runtime $runtime
        Stop-GaloreHotkeySettingsResources -Runtime $runtime

        $runtime.Popup | Should BeNullOrEmpty
        $runtime.Button | Should BeNullOrEmpty
        $runtime.ToolTip | Should BeNullOrEmpty
        $runtime.OwnerForm | Should BeNullOrEmpty
    }

    It "keeps the hotkey icon bitmap separate from its runtime state" {

        $runtime = [GaloreHotkeySettingsRuntimeState]::new()
        $form = New-Object System.Windows.Forms.Form
        $button = New-Object System.Windows.Forms.Panel
        $iconBitmap = [System.Drawing.Bitmap]::new(1, 1)
        $button.Tag = $iconBitmap

        Mock New-HotkeysButton { $button }

        try {
            $result = Initialize-GaloreHotkeyButton -Form $form -Runtime $runtime

            $result | Should Be $button
            $button.Tag | Should Be $iconBitmap
            $button.HotkeySettingsRuntime | Should Be $runtime
        } finally {
            Stop-GaloreHotkeySettingsResources -Runtime $runtime
            $iconBitmap.Dispose()
            $form.Dispose()
        }
    }
}

Describe "Configuration discovery contracts" {

    It "applies a saved executable override without replacing its program entry" {

        $overridePath = Join-Path $TestDrive "Recorder.exe"

        Set-Content -LiteralPath $overridePath -Value "fixture"

        $programs = @{
            Recorder = @{
                Path = "C:\Old\Recorder.exe"
                Args = "-silent"
                StatusProcess = "OldRecorder"
                WindowProcess = "OldRecorder"
                DisplayName = "Old Recorder"
            }
        }

        $originalProgram = $programs.Recorder

        Mock Get-LauncherProgramOverrides {
            @{
                Recorder = [pscustomobject]@{
                    Path = $overridePath
                    DisplayName = "Recording"
                }
            }
        }

        Apply-GaloreProgramOverrides -Programs $programs

        $programs.Contains("Recorder") |
        Should Be $true

        [object]::ReferenceEquals($originalProgram, $programs.Recorder) |
        Should Be $true

        $programs.Recorder.Path |
        Should Be $overridePath

        $programs.Recorder.Args |
        Should Be ""

        $programs.Recorder.StatusProcess |
        Should Be "Recorder"

        $programs.Recorder.WindowProcess |
        Should Be "Recorder"

        $programs.Recorder.DisplayName |
        Should Be "Recording"

    }

    It "applies a saved executable override to a typed program definition" {

        $overridePath = Join-Path $TestDrive "TypedRecorder.exe"

        Set-Content -LiteralPath $overridePath -Value "fixture"

        $program = [GaloreProgramDefinition]::new("C:\Old\Recorder.exe", "-silent", "OldRecorder", "OldRecorder")

        $programs = @{ Recorder = $program }

        Mock Get-LauncherProgramOverrides {
            @{
                Recorder = [pscustomobject]@{
                    Path = $overridePath
                    DisplayName = "Typed Recording"
                }
            }
        }

        Apply-GaloreProgramOverrides -Programs $programs

        [object]::ReferenceEquals($program, $programs.Recorder) |
        Should Be $true

        $program.Path |
        Should Be $overridePath

        $program.Args |
        Should Be ""

        $program.StatusProcess |
        Should Be "TypedRecorder"

        $program.WindowProcess |
        Should Be "TypedRecorder"

        $program.DisplayName |
        Should Be "Typed Recording"

    }

    It "returns the first existing candidate path" {

        $first = Join-Path $TestDrive "first.exe"

        $second = Join-Path $TestDrive "second.exe"

        Set-Content -LiteralPath $first -Value "first"

        Set-Content -LiteralPath $second -Value "second"

        Find-ProgramPath -PossiblePaths @($first, $second) |
        Should Be $first

    }

    It "returns null when no candidate exists" {

        Find-ProgramPath -PossiblePaths @("", (Join-Path $TestDrive "missing.exe")) |
        Should BeNullOrEmpty

    }

    It "prefers the portable BattleState executable under the application root" {

        $portablePath = Join-Path $TestDrive "Programs\BattleState\BsgLauncher.exe"

        New-Item -ItemType Directory -Path (Split-Path -Parent $portablePath) -Force | Out-Null

        Set-Content -LiteralPath $portablePath -Value "launcher"

        Find-BattleStateLauncherPath -ProgramRoot $TestDrive |
        Should Be $portablePath

    }

    It "builds typed launcher programs without changing their process contracts" {

        $programs = New-LauncherProgramConfiguration -EnvPaths @{
            ScrcpyVBS = "C:\\Galore\\Programs\\scrcpy\\playphone.vbs"
            Discord = "C:\\Apps\\Discord.exe"
            Steam = "C:\\Apps\\Steam.exe"
            Browsers = [ordered]@{
                Firefox = [pscustomobject]@{
                    Id = "Firefox"
                    DisplayName = "Mozilla Firefox"
                    Path = "C:\\Apps\\Firefox.exe"
                    ProcessName = "firefox"
                }
            }
            BSG = "C:\\Apps\\BsgLauncher.exe"
            RivaTuner = "C:\\Apps\\RTSS.exe"
            MSIAfterBurner = "C:\\Apps\\MSIAfterburner.exe"
            ShareX = "C:\\Apps\\ShareX.exe"
            Spotify = "C:\\Apps\\Spotify.exe"
        }

        $programs.Count |
        Should Be 9

        foreach($program in $programs.Values) {

            ($program -is [GaloreProgramDefinition]) |
            Should Be $true

        }

        $programs.Phone.Path |
        Should Be "C:\\Galore\\Programs\\scrcpy\\playphone.vbs"

        $programs.Phone.Args |
        Should Be ""

        $programs.Phone.StatusProcess |
        Should Be "scrcpy"

        $programs.Discord.Args |
        Should Be "--processStart Discord.exe"

        $programs.Discord.StatusProcess |
        Should Be "Discord"

        $programs.Browser.Path |
        Should Be "C:\\Apps\\Firefox.exe"

        $programs.Browser.BrowserId |
        Should Be "Firefox"

        $programs.Browser.BrowserDisplayName |
        Should Be "Mozilla Firefox"

        $programs.Browser.StatusProcess |
        Should Be "firefox"

    }

    It "uses empty typed paths for unavailable optional programs" {

        $programs = New-LauncherProgramConfiguration -EnvPaths @{
            ScrcpyVBS = "C:\\Galore\\Programs\\scrcpy\\playphone.vbs"
            Discord = $null
            Steam = $null
            Browsers = [ordered]@{}
            BSG = $null
            RivaTuner = $null
            MSIAfterBurner = $null
            ShareX = $null
            Spotify = $null
        }

        $programs.Discord.Path |
        Should Be ""

        $programs.Discord.IsConfigured() |
        Should Be $false

        $programs.Browser.Path |
        Should Be ""

        $programs.Browser.BrowserId |
        Should Be ""

        $programs.Browser.BrowserDisplayName |
        Should Be "No browser detected"

    }

    It "validates typed definitions and rejects legacy or invalid program entries" {

        Mock Test-Path { $true }

        $envPaths = @{
            AppIcon = "C:\\Galore\\resources\\Galore.ico"
            ScrcpyVBS = "C:\\Galore\\Programs\\scrcpy\\playphone.vbs"
            Discord = "C:\\Apps\\Discord.exe"
            Steam = "C:\\Apps\\Steam.exe"
            Browsers = [ordered]@{}
            BSG = "C:\\Apps\\BsgLauncher.exe"
            RivaTuner = "C:\\Apps\\RTSS.exe"
            MSIAfterBurner = "C:\\Apps\\MSIAfterburner.exe"
            ShareX = "C:\\Apps\\ShareX.exe"
            Spotify = "C:\\Apps\\Spotify.exe"
        }

        $configuration = [pscustomobject]@{
            ProgramRoot = "C:\\Galore"
            EnvPaths = $envPaths
            Programs = New-LauncherProgramConfiguration -EnvPaths $envPaths
        }

        (Test-LauncherConfigurationSchema -Configuration $configuration).IsValid |
        Should Be $true

        $configuration.Programs.Spotify = @{ Path = "C:\\Apps\\Spotify.exe"; Args = "-silent"; StatusProcess = "Spotify"; WindowProcess = "Spotify" }

        (Test-LauncherConfigurationSchema -Configuration $configuration).IsValid |
        Should Be $false

        $configuration.Programs = New-LauncherProgramConfiguration -EnvPaths $envPaths

        $configuration.Programs.Spotify.StatusProcess = ""

        (Test-LauncherConfigurationSchema -Configuration $configuration).IsValid |
        Should Be $false

    }

}

Describe "Program display text" {

    It "resolves browser, custom, and fallback labels for typed and legacy definitions" {

        $typedBrowser = [GaloreProgramDefinition]::new()

        $typedBrowser.BrowserDisplayName = "Opera GX"

        Get-GaloreProgramDisplayText -Name "Browser" -Program $typedBrowser |
        Should Be "Browser: Opera GX"

        $typedProgram = [GaloreProgramDefinition]::new()

        $typedProgram.DisplayName = "Recording"

        Get-GaloreProgramDisplayText -Name "Recorder" -Program $typedProgram |
        Should Be "Recording"

        Get-GaloreProgramDisplayText -Name "Discord" -Program ([GaloreProgramDefinition]::new()) |
        Should Be "Discord"

        Get-GaloreProgramDisplayText -Name "Browser" -Program @{ BrowserDisplayName = "Firefox" } |
        Should Be "Browser: Firefox"

        Get-GaloreProgramDisplayText -Name "Tool" -Program @{ DisplayName = "Legacy Tool" } |
        Should Be "Legacy Tool"

    }

}

Describe "Typed program action and status consumers" {

    BeforeEach {

        Mock Start-GaloreProgramAdapter { $true }

        Mock Start-Process {}

        Mock Refresh-StatusDelayed {}

        Mock Start-GaloreSpotifyAutoplayAdapter { $true }

        Mock Write-LauncherDiagnostic {}

    }

    It "launches a typed program with its preserved argument list" {

        $program = [GaloreProgramDefinition]::new("C:\Apps\DiscordUpdate.exe", "--processStart Discord.exe", "Discord", "Discord")

        Invoke-ProgramLaunch -Programs @{ Discord = $program } -Statuses @{} -ProgramNames @("Discord") -AppRoot $GaloreRoot

        Assert-MockCalled Start-GaloreProgramAdapter -Times 1 -Exactly -Scope It -ParameterFilter {
            $Program.Path -eq "C:\Apps\DiscordUpdate.exe" -and $Program.Args -eq "--processStart Discord.exe"
        }

        Assert-MockCalled Refresh-StatusDelayed -Times 1 -Exactly -Scope It -ParameterFilter {
            @($ProgramsToUpdate).Count -eq 1 -and $ProgramsToUpdate[0] -eq "Discord"
        }

    }

    It "terminates a typed program by its status process" {

        $program = [GaloreProgramDefinition]::new("C:\Apps\Discord.exe", "", "Discord", "Discord")

        Invoke-ProgramTermination -Programs @{ Discord = $program } -Statuses @{} -ProgramNames @("Discord")

        Assert-MockCalled Start-Process -Times 1 -Exactly -Scope It -ParameterFilter {
            $FilePath -eq "powershell.exe" -or $null -eq $FilePath
        }

        Assert-MockCalled Refresh-StatusDelayed -Times 1 -Exactly -Scope It -ParameterFilter {
            @($ProgramsToUpdate).Count -eq 1 -and $ProgramsToUpdate[0] -eq "Discord"
        }

    }

    It "updates a status label from a typed program process identity" {

        Mock Get-ProgramStatus { $true }

        Mock Update-GaloreApplicationMaintenanceState {}

        $program = [GaloreProgramDefinition]::new("C:\Apps\Discord.exe", "", "Discord", "Discord")

        $label = New-Object System.Windows.Forms.Label

        try {

            Update-ProgramStatus -Programs @{ Discord = $program } -Statuses @{ Discord = $label } -ProgramsToUpdate @("Discord")

            $label.Text |
            Should Be "$([char]0x25CF) Running"

            $label.ForeColor |
            Should Be ([System.Drawing.Color]::Green)

            Assert-MockCalled Get-ProgramStatus -Times 1 -Exactly -Scope It -ParameterFilter { $ProcessName -eq "Discord" }

        } finally {

            $label.Dispose()

        }

    }

}

Describe "Integration adapter contracts" {

    It "keeps empty process identities safely stopped" {

        Mock Get-Process {}

        (Test-GaloreProcessRunning -ProcessName "") | Should Be $false
        (Get-GaloreVisibleProcess -ProcessName "") | Should BeNullOrEmpty
        Assert-MockCalled Get-Process -Times 0 -Exactly
    }

    It "routes VBS programs through the hidden script adapter" {

        $program = [GaloreProgramDefinition]::new("C:\\Tools\\Phone.vbs", "--safe", "scrcpy", "scrcpy")
        Mock Start-GaloreHiddenWscript { $true }

        (Start-GaloreProgramAdapter -Program $program) | Should Be $true

        Assert-MockCalled Start-GaloreHiddenWscript -Times 1 -Exactly -ParameterFilter {
            $ScriptPath -eq "C:\\Tools\\Phone.vbs" -and $ArgumentList -eq "--safe"
        }
    }

    It "routes normal programs through the standard process launcher" {

        $program = [GaloreProgramDefinition]::new("C:\\Tools\\Tool.exe", "--silent", "Tool", "Tool")
        Mock Start-Process {}

        (Start-GaloreProgramAdapter -Program $program) | Should Be $true

        Assert-MockCalled Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq "C:\\Tools\\Tool.exe" -and $ArgumentList -eq "--silent"
        }
    }

    It "does not launch unconfigured automation adapters" {

        Mock Start-Process {}

        (Start-GaloreSpotifyAutoplayAdapter -AppRoot "") | Should Be $false
        Assert-MockCalled Start-Process -Times 0 -Exactly -Scope It
    }
}

Describe "Program status runtime ownership" {

    BeforeEach {

        $script:GaloreProgramStatusRuntime = [GaloreProgramStatusRuntime]::new()

    }

    AfterEach {

        Stop-ProgramStatusResources

    }

    It "starts with one stable empty timer collection" {

        $script:GaloreProgramStatusRuntime.StatusTimer |
        Should Be $null

        ($script:GaloreProgramStatusRuntime.RefreshTimers -is [System.Collections.ArrayList]) |
        Should Be $true

        $script:GaloreProgramStatusRuntime.RefreshTimers.Count |
        Should Be 0

    }

    It "registers delayed refresh timers with their owning runtime" {

        Refresh-StatusDelayed -Programs @{} -Statuses @{} -ProgramsToUpdate @()

        $script:GaloreProgramStatusRuntime.RefreshTimers.Count |
        Should Be 1

        $script:GaloreProgramStatusRuntime.RefreshTimers[0].Tag.Runtime |
        Should Be $script:GaloreProgramStatusRuntime

    }

    It "reuses the periodic status timer across repeated initialization" {

        $first = Initialize-StatusTimer -Programs @{} -Statuses @{}

        $second = Initialize-StatusTimer -Programs @{ Discord = [GaloreProgramDefinition]::new() } -Statuses @{}

        [object]::ReferenceEquals($first, $second) |
        Should Be $true

        $second.Tag.Programs.ContainsKey("Discord") |
        Should Be $true

    }

    It "stops and clears owned timers idempotently" {

        $statusTimer = New-Object System.Windows.Forms.Timer

        $refreshTimer = New-Object System.Windows.Forms.Timer

        $script:GaloreProgramStatusRuntime.StatusTimer = $statusTimer

        $script:GaloreProgramStatusRuntime.RefreshTimers.Add($refreshTimer) | Out-Null

        Stop-ProgramStatusResources

        $script:GaloreProgramStatusRuntime.StatusTimer |
        Should Be $null

        $script:GaloreProgramStatusRuntime.RefreshTimers.Count |
        Should Be 0

        { Stop-ProgramStatusResources } |
        Should Not Throw

    }

}

Describe "Maintenance state contracts" {

    BeforeEach {

        $script:GaloreMaintenanceMutex = $null

        $script:GaloreMaintenanceMaximumStateBytes = 262144

    }

    It "normalizes invalid counters and shortcut candidates" {

        $state = ConvertTo-ValidatedGaloreMaintenanceState -State ([pscustomobject]@{
            TotalRuntimeSeconds = 7200
            LastQuickRuntimeSeconds = -10
            LastWeeklyRuntimeSeconds = "invalid"
            LastMonthlyRuntimeSeconds = 30
            LastSixtyDayRuntimeSeconds = 60
            BrokenShortcutCandidates = @(
                [pscustomobject]@{ Path = "C:\Missing.lnk"; FirstSeenRuntimeSeconds = 100 }
                [pscustomobject]@{ Path = ""; FirstSeenRuntimeSeconds = 100 }
                42
            )
        })

        $state.TotalRuntimeSeconds |
        Should Be 7200

        $state.LastQuickRuntimeSeconds |
        Should Be 0

        $state.LastWeeklyRuntimeSeconds |
        Should Be 0

        @($state.BrokenShortcutCandidates).Count |
        Should Be 1

        $state.BrokenShortcutCandidates[0].Path |
        Should Be "C:\Missing.lnk"

    }

    It "round-trips maintenance state through an atomic state file" {

        $stateFile = Join-Path $TestDrive "State\\maintenance-state.json"

        $state = New-GaloreMaintenanceState

        $state.TotalRuntimeSeconds = 9876

        $state.BrokenShortcutCandidates = @(
            [pscustomobject]@{ Path = "C:\Old.lnk"; FirstSeenRuntimeSeconds = 500 }
        )

        Write-GaloreMaintenanceStateUnlocked -StateFile $stateFile -State $state |
        Should Be $true

        $restored = Read-GaloreMaintenanceStateUnlocked -StateFile $stateFile

        $restored.TotalRuntimeSeconds |
        Should Be 9876

        $restored.BrokenShortcutCandidates[0].Path |
        Should Be "C:\Old.lnk"

        Test-Path -LiteralPath "$stateFile.tmp" |
        Should Be $false

    }

    It "rejects oversized state files instead of parsing unbounded JSON" {

        $stateFile = Join-Path $TestDrive "oversized.json"

        Set-Content -LiteralPath $stateFile -Value ("x" * 5000) -Encoding UTF8

        $script:GaloreMaintenanceMaximumStateBytes = 128

        $state = Read-GaloreMaintenanceStateUnlocked -StateFile $stateFile

        $state.TotalRuntimeSeconds |
        Should Be 0

        @($state.BrokenShortcutCandidates).Count |
        Should Be 0

    }

    It "reports maintenance due only after a runtime interval is reached" {

        $state = New-GaloreMaintenanceState

        Test-GaloreMaintenanceIsDue -State $state |
        Should Be $false

        $state.TotalRuntimeSeconds = (2 * 60 * 60)

        Test-GaloreMaintenanceIsDue -State $state |
        Should Be $true

    }

}

Describe "Domain model contracts" {

    It "keeps program definitions safe when unconfigured and derives process identity when configured" {

        $program = [GaloreProgramDefinition]::new()

        $program.IsConfigured() |
        Should Be $false

        $program.ApplyExecutable("C:\Apps\Recorder.exe", "Recorder")

        $program.IsConfigured() |
        Should Be $true

        $program.StatusProcess |
        Should Be "Recorder"

        $program.WindowProcess |
        Should Be "Recorder"

        $program.Clear()

        $program.IsConfigured() |
        Should Be $false

    }

    It "keeps category slot defaults and reset behavior compatible with persisted state" {

        $slot = [GaloreCategorySlot]::new("Category1Slot1")

        $slot.DisplayName |
        Should Be "Empty"

        $slot.Selected |
        Should Be $false

        $slot.Path = "C:\Apps\Tool.exe"

        $slot.DisplayName = "Tool"

        $slot.Selected = $true

        $slot.Clear()

        $slot.Path |
        Should Be ""

        $slot.DisplayName |
        Should Be "Empty"

        $slot.Selected |
        Should Be $false

    }

    It "serializes category domain objects without PowerShell type metadata" {

        $state = [GaloreCategoryState]::new()

        $slot = [GaloreCategorySlot]::new("Category1Slot1")

        $category = [GaloreCategory]::new("Category1", "Category 1", @($slot))

        $state.Categories = @($category)

        $json = $state | ConvertTo-Json -Depth 5

        $saved = $json | ConvertFrom-Json

        $saved.Version |
        Should Be 1

        $saved.Categories[0].Slots[0].Id |
        Should Be "Category1Slot1"

        $json |
        Should Not Match "GaloreCategory"

    }

    It "provides stable launcher setting defaults" {

        $settings = [GaloreLauncherSettings]::new()

        $settings.Width |
        Should Be 1100

        $settings.Height |
        Should Be 550

        @($settings.Selected).Count |
        Should Be 0

        $settings.ProgramOverrides.Count |
        Should Be 0

        $json = $settings | ConvertTo-Json -Depth 4

        $json |
        Should Match '"Width"'

        $json |
        Should Not Match '"WindowPlacement"'

    }

    It "preserves the hardware property names consumed by the current UI" {

        $snapshot = [GaloreHardwareSnapshot]::new(12, 34, 56, 78)

        $snapshot.CPU |
        Should Be 12

        $snapshot.RAM |
        Should Be 34

        $snapshot.GPU |
        Should Be 56

        $snapshot.GPUTemp |
        Should Be 78

    }

}

Describe "Hardware snapshot conversion" {

    BeforeEach {

        $script:GaloreHardwareRuntime = [GaloreHardwareRuntimeState]::new()

    }

    AfterEach {

        foreach($timer in @(
                $script:GaloreHardwareRuntime.HardwareReadTimer,
                $script:GaloreHardwareRuntime.SystemTimer,
                $script:GaloreHardwareRuntime.RAMCleanupTimer
            )
        ) {
            if($timer) {
                $timer.Tag = $null
                $timer.Dispose()
            }
        }

    }

    It "does not start the background monitor as an import side effect" {

        $script:GaloreHardwareRuntime.HardwareJob |
        Should BeNullOrEmpty

    }

    It "starts with a typed zero-value hardware runtime" {

        $script:GaloreHardwareRuntime.GetType().Name |
        Should Be "GaloreHardwareRuntimeState"

        $script:GaloreHardwareRuntime.SystemUsageCache.GetType().Name |
        Should Be "GaloreHardwareSnapshot"

        $script:GaloreHardwareRuntime.SystemUsageCache.CPU |
        Should Be 0

        $script:GaloreHardwareRuntime.HardwareReadTimer |
        Should BeNullOrEmpty

        $script:GaloreHardwareRuntime.SystemTimer |
        Should BeNullOrEmpty

        $script:GaloreHardwareRuntime.RAMCleanupTimer |
        Should BeNullOrEmpty

        $script:GaloreHardwareRuntime.RAMCleanerPowerShell |
        Should BeNullOrEmpty

    }

    It "normalizes serialized numeric values into a typed snapshot" {

        $snapshot = ConvertTo-GaloreHardwareSnapshot ([pscustomobject]@{
            CPU = "12"
            RAM = 34
            GPU = "56.5"
            GPUTemp = 78
        })

        $snapshot.GetType().Name |
        Should Be "GaloreHardwareSnapshot"

        $snapshot.CPU |
        Should Be 12

        $snapshot.RAM |
        Should Be 34

        $snapshot.GPU |
        Should Be 56.5

        $snapshot.GPUTemp |
        Should Be 78

    }

    It "uses safe zero values for missing, malformed, or non-finite readings" {

        $snapshot = ConvertTo-GaloreHardwareSnapshot ([pscustomobject]@{
            CPU = $null
            RAM = "invalid"
            GPU = "NaN"
            GPUTemp = "Infinity"
        })

        $snapshot.CPU |
        Should Be 0

        $snapshot.RAM |
        Should Be 0

        $snapshot.GPU |
        Should Be 0

        $snapshot.GPUTemp |
        Should Be 0

    }

    It "reuses an existing running hardware job" {

        $script:GaloreHardwareRuntime.HardwareJob = [pscustomobject]@{
            State = [System.Management.Automation.JobState]::Running
        }

        Mock Start-Job {}

        Initialize-HardwareMonitorJob

        Assert-MockCalled Start-Job -Times 0 -Exactly -Scope It

    }

    It "does not start hardware resources after shutdown has begun" {

        $script:GaloreHardwareRuntime.Stopping = $true

        Mock Start-Job {}

        Initialize-HardwareMonitorJob
        Initialize-HardwareCacheReader
        Initialize-RAMCleanupSchedule

        Assert-MockCalled Start-Job -Times 0 -Exactly -Scope It

        $script:GaloreHardwareRuntime.HardwareReadTimer |
        Should BeNullOrEmpty

        $script:GaloreHardwareRuntime.RAMCleanupTimer |
        Should BeNullOrEmpty

    }

    It "removes a stale hardware job before starting its replacement" {

        $staleJob = [pscustomobject]@{
            Id = 42
            State = [System.Management.Automation.JobState]::Failed
        }

        $replacementJob = [pscustomobject]@{
            State = [System.Management.Automation.JobState]::Running
        }

        $script:GaloreHardwareRuntime.HardwareJob = $staleJob

        Mock Stop-Job {}

        Mock Receive-Job {}

        Mock Remove-Job {}

        Mock Start-Job { $replacementJob }

        Initialize-HardwareMonitorJob

        Assert-MockCalled Stop-Job -Times 1 -Exactly -Scope It -ParameterFilter { $Id -eq 42 }

        Assert-MockCalled Receive-Job -Times 1 -Exactly -Scope It -ParameterFilter { $Id -eq 42 }

        Assert-MockCalled Remove-Job -Times 1 -Exactly -Scope It -ParameterFilter { $Id -eq 42 }

        Assert-MockCalled Start-Job -Times 1 -Exactly -Scope It

        $script:GaloreHardwareRuntime.HardwareJob |
        Should Be $replacementJob

    }

    It "keeps one cache-reader timer across repeated initialization" {

        $script:GaloreHardwareRuntime.HardwareJob = [pscustomobject]@{
            Id = 21
            State = [System.Management.Automation.JobState]::Running
        }

        Mock Start-Job {}

        Initialize-HardwareCacheReader

        $firstTimer = $script:GaloreHardwareRuntime.HardwareReadTimer

        Initialize-HardwareCacheReader

        [object]::ReferenceEquals($firstTimer, $script:GaloreHardwareRuntime.HardwareReadTimer) |
        Should Be $true

        Assert-MockCalled Start-Job -Times 0 -Exactly -Scope It

        $script:GaloreHardwareRuntime.HardwareReadTimer.Tag |
        Should Be $script:GaloreHardwareRuntime

    }

    It "replaces a failed job while retaining the existing cache-reader timer" {

        $timer = New-Object System.Windows.Forms.Timer

        $timer.Interval = 100

        $script:GaloreHardwareRuntime.HardwareReadTimer = $timer

        $script:GaloreHardwareRuntime.HardwareJob = [pscustomobject]@{
            Id = 84
            State = [System.Management.Automation.JobState]::Failed
        }

        $replacementJob = [pscustomobject]@{
            State = [System.Management.Automation.JobState]::Running
        }

        Mock Stop-Job {}

        Mock Receive-Job {}

        Mock Remove-Job {}

        Mock Start-Job { $replacementJob }

        Initialize-HardwareCacheReader

        [object]::ReferenceEquals($timer, $script:GaloreHardwareRuntime.HardwareReadTimer) |
        Should Be $true

        $script:GaloreHardwareRuntime.HardwareJob |
        Should Be $replacementJob

        Assert-MockCalled Remove-Job -Times 1 -Exactly -Scope It -ParameterFilter { $Id -eq 84 }

        Assert-MockCalled Start-Job -Times 1 -Exactly -Scope It

    }

    It "reuses the display timer while refreshing its current UI bindings" {

        $firstForm = New-Object System.Windows.Forms.Form
        $secondForm = New-Object System.Windows.Forms.Form
        $firstCPU = New-Object System.Windows.Forms.Label
        $firstRAM = New-Object System.Windows.Forms.Label
        $firstGPU = New-Object System.Windows.Forms.Label
        $firstTemp = New-Object System.Windows.Forms.Label
        $secondCPU = New-Object System.Windows.Forms.Label
        $secondRAM = New-Object System.Windows.Forms.Label
        $secondGPU = New-Object System.Windows.Forms.Label
        $secondTemp = New-Object System.Windows.Forms.Label

        try {
            Initialize-SystemMonitorDisplay $firstCPU $firstRAM $firstGPU $firstTemp $firstForm
            $firstTimer = $script:GaloreHardwareRuntime.SystemTimer

            Initialize-SystemMonitorDisplay $secondCPU $secondRAM $secondGPU $secondTemp $secondForm

            [object]::ReferenceEquals($firstTimer, $script:GaloreHardwareRuntime.SystemTimer) |
            Should Be $true

            $script:GaloreHardwareRuntime.SystemTimer.Tag.Form |
            Should Be $secondForm

            $script:GaloreHardwareRuntime.SystemTimer.Tag.CPULabel |
            Should Be $secondCPU
        } finally {
            $firstForm.Dispose()
            $secondForm.Dispose()
        }

    }

    It "keeps one hourly RAM cleanup timer across repeated initialization" {

        Initialize-RAMCleanupSchedule

        $firstTimer = $script:GaloreHardwareRuntime.RAMCleanupTimer

        Initialize-RAMCleanupSchedule

        [object]::ReferenceEquals($firstTimer, $script:GaloreHardwareRuntime.RAMCleanupTimer) |
        Should Be $true

        $script:GaloreHardwareRuntime.RAMCleanupTimer.Interval |
        Should Be 3600000

        $script:GaloreHardwareRuntime.RAMCleanupTimer.Enabled |
        Should Be $true

    }

    It "stops and clears owned hardware resources idempotently" {

        $script:GaloreHardwareRuntime.HardwareReadTimer = New-Object System.Windows.Forms.Timer
        $script:GaloreHardwareRuntime.HardwareReadTimer.Tag = $script:GaloreHardwareRuntime
        $script:GaloreHardwareRuntime.SystemTimer = New-Object System.Windows.Forms.Timer
        $script:GaloreHardwareRuntime.SystemTimer.Tag = [pscustomobject]@{ Form = $null }
        $script:GaloreHardwareRuntime.RAMCleanupTimer = New-Object System.Windows.Forms.Timer
        $script:GaloreHardwareRuntime.RAMCleanerPowerShell = [powershell]::Create()

        Stop-HardwareMonitor

        $script:GaloreHardwareRuntime.Stopping |
        Should Be $true

        $script:GaloreHardwareRuntime.HardwareReadTimer |
        Should BeNullOrEmpty

        $script:GaloreHardwareRuntime.SystemTimer |
        Should BeNullOrEmpty

        $script:GaloreHardwareRuntime.RAMCleanupTimer |
        Should BeNullOrEmpty

        $script:GaloreHardwareRuntime.RAMCleanerPowerShell |
        Should BeNullOrEmpty

        { Stop-HardwareMonitor } |
        Should Not Throw

    }

}

Describe "Popup runtime ownership" {

    BeforeEach {

        $script:GalorePopupRuntime = [GalorePopupRuntimeState]::new()

    }

    It "starts with no owned selector, system popup, or tooltip" {

        $script:GalorePopupRuntime.SelectorForm |
        Should BeNullOrEmpty

        $script:GalorePopupRuntime.ActiveSystemToolPopup |
        Should BeNullOrEmpty

        $script:GalorePopupRuntime.ToolTip |
        Should BeNullOrEmpty

    }

    It "clears popup ownership only for the form that is still current" {

        $previousPopup = New-Object object
        $currentPopup = New-Object object

        $script:GalorePopupRuntime.SelectorForm = $currentPopup

        Clear-GalorePopupOwner -Runtime $script:GalorePopupRuntime -PropertyName "SelectorForm" -Form $previousPopup

        [object]::ReferenceEquals($script:GalorePopupRuntime.SelectorForm, $currentPopup) |
        Should Be $true

        Clear-GalorePopupOwner -Runtime $script:GalorePopupRuntime -PropertyName "SelectorForm" -Form $currentPopup

        $script:GalorePopupRuntime.SelectorForm |
        Should BeNullOrEmpty

    }

    It "applies the same reference-safe release rule to system-tool popups" {

        $previousPopup = New-Object object
        $currentPopup = New-Object object

        $script:GalorePopupRuntime.ActiveSystemToolPopup = $currentPopup

        Clear-GalorePopupOwner -Runtime $script:GalorePopupRuntime -PropertyName "ActiveSystemToolPopup" -Form $previousPopup

        [object]::ReferenceEquals($script:GalorePopupRuntime.ActiveSystemToolPopup, $currentPopup) |
        Should Be $true

        Clear-GalorePopupOwner -Runtime $script:GalorePopupRuntime -PropertyName "ActiveSystemToolPopup" -Form $currentPopup

        $script:GalorePopupRuntime.ActiveSystemToolPopup |
        Should BeNullOrEmpty

    }

    It "creates a fallback system-tool popup with owned fade and image state" {

        $anchorForm = New-Object System.Windows.Forms.Form
        $anchor = New-Object System.Windows.Forms.Button
        $anchorForm.Controls.Add($anchor)
        $anchorForm.CreateControl()
        $anchor.CreateControl()
        if(-not (Get-Command Get-GaloreResourcePath -ErrorAction SilentlyContinue)) {
            function Get-GaloreResourcePath { param([string]$Name) return $Name }
        }
        Mock Get-GaloreResourcePath { Join-Path $TestDrive "missing-popup-art.png" }

        $popup = $null
        try {
            $popup = New-GaloreSystemToolPopup -Anchor $anchor -BackgroundImageName "missing-popup-art.png" -FallbackWidth 123 -FallbackHeight 87

            $popup.ClientSize.Width | Should Be 123
            $popup.ClientSize.Height | Should Be 87
            $popup.Tag.FadeTimer | Should BeNullOrEmpty
            $popup.Tag.Runtime | Should Be $script:GalorePopupRuntime
        } finally {
            if($popup -and -not $popup.IsDisposed) { $popup.Dispose() }
            $anchorForm.Dispose()
        }
    }

}

Describe "Launcher settings domain and placement" {

    It "keeps the serialized settings schema flat and backward compatible" {

        $settings = ConvertTo-ValidatedLauncherSettings -Settings ([pscustomobject]@{
            Selected = @("Spotify")
            Width = 1100
            Height = 550
            X = -900
            Y = 100
            BrowserId = $null
            ProgramOverrides = [ordered]@{}
        })

        $json = $settings | ConvertTo-Json -Depth 4

        $saved = $json | ConvertFrom-Json

        $saved.Width |
        Should Be 1100

        $saved.X |
        Should Be -900

        $saved.PSObject.Properties.Name |
        Should Not Contain "WindowPlacement"

        $saved.PSObject.Properties.Name |
        Should Not Contain "Version"

    }

    It "validates dictionary and object program override representations" {

        $dictionarySettings = ConvertTo-ValidatedLauncherSettings -Settings ([pscustomobject]@{
            Selected = @()
            Width = 1100
            Height = 550
            X = 0
            Y = 0
            ProgramOverrides = [ordered]@{
                Spotify = [pscustomobject]@{ Path = "C:\Apps\Spotify.exe"; DisplayName = "Music" }
            }
        })

        $objectSettings = ConvertTo-ValidatedLauncherSettings -Settings ([pscustomobject]@{
            Selected = @()
            Width = 1100
            Height = 550
            X = 0
            Y = 0
            ProgramOverrides = [pscustomobject]@{
                Discord = [pscustomobject]@{ Path = "C:\Apps\Discord.exe"; DisplayName = "Chat" }
            }
        })

        $dictionarySettings.ProgramOverrides["Spotify"].DisplayName |
        Should Be "Music"

        $objectSettings.ProgramOverrides["Discord"].Path |
        Should Be "C:\Apps\Discord.exe"

    }

    It "preserves visible negative coordinates and rejects truly off-screen placements" {

        $leftMonitor = [System.Drawing.Rectangle]::new(-1920, 0, 1920, 1080)

        $visibleSettings = [GaloreLauncherSettings]::new()

        $visibleSettings.X = -900

        $visibleSettings.Y = 100

        Test-GaloreWindowPlacementVisible -Settings $visibleSettings -WorkingAreas @($leftMonitor) |
        Should Be $true

        $offScreenSettings = [GaloreLauncherSettings]::new()

        $offScreenSettings.X = -5000

        $offScreenSettings.Y = -5000

        Test-GaloreWindowPlacementVisible -Settings $offScreenSettings -WorkingAreas @($leftMonitor) |
        Should Be $false

    }

    It "round-trips the typed flat settings document" {

        $path = Join-Path $TestDrive "settings-roundtrip.json"

        $settings = ConvertTo-ValidatedLauncherSettings -Settings ([pscustomobject]@{
            Selected = @("Spotify", "Discord")
            Width = 1100
            Height = 550
            X = 25
            Y = 50
            BrowserId = "Firefox"
            ProgramOverrides = [ordered]@{}
        })

        $settings | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $path -Encoding UTF8

        $restored = Read-LauncherSettingsFile -Path $path

        $restored.GetType().Name |
        Should Be "GaloreLauncherSettings"

        @($restored.Selected) |
        Should Contain "Spotify"

        $restored.BrowserId |
        Should Be "Firefox"

    }

}
