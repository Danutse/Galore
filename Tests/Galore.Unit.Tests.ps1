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



. (Join-Path $moduleRoot "LauncherLogging.ps1")

. (Join-Path $moduleRoot "LauncherSettings.ps1")

. (Join-Path $moduleRoot "LauncherConfiguration.ps1")

. (Join-Path $moduleRoot "UI.ps1")

. (Join-Path $moduleRoot "LauncherSearch.ps1")

. (Join-Path $moduleRoot "LauncherStartMenu.ps1")

. (Join-Path $moduleRoot "LauncherBrowser.ps1")

. (Join-Path $moduleRoot "LauncherAlphaOverlay.ps1")

. (Join-Path $moduleRoot "LauncherQuickAccess.ps1")

. (Join-Path $moduleRoot "LauncherPostIts.ps1")

. (Join-Path $moduleRoot "LauncherWindowTaskbar.ps1")

. (Join-Path $moduleRoot "LauncherBackup.ps1")

. (Join-Path $moduleRoot "LauncherHotkeys.ps1")

. (Join-Path $moduleRoot "LauncherHotkeySettings.ps1")

. (Join-Path $moduleRoot "LauncherCategories.ps1")

. (Join-Path $moduleRoot "LauncherMaintenance.ps1")



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

Describe "Quick Access persistence" {

    BeforeEach {

        $script:GaloreQuickAccessPath = Join-Path $TestDrive "quick-access.json"
        $script:GaloreQuickAccessItems = New-Object System.Collections.ArrayList
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

        Set-Content -LiteralPath $script:GaloreQuickAccessPath -Value "not json" -Encoding UTF8

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
        Set-Content -LiteralPath $script:GaloreQuickAccessPath -Encoding UTF8

        $items = @(Get-GaloreQuickAccessItems)

        $items.Count |
        Should Be 2

        ($items.Path -contains $existingFile) |
        Should Be $true

        ($items.Path -contains $existingFolder) |
        Should Be $true

    }

    It "saves only the expected version and item paths" {

        [void]$script:GaloreQuickAccessItems.Add([pscustomobject]@{ Path = "C:\\Tools\\One.exe" })
        [void]$script:GaloreQuickAccessItems.Add([pscustomobject]@{ Path = "C:\\Tools\\Two.exe" })

        Save-GaloreQuickAccessItems

        $saved = Get-Content -LiteralPath $script:GaloreQuickAccessPath -Raw | ConvertFrom-Json

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
        [void]$script:GaloreQuickAccessItems.Add($first)
        [void]$script:GaloreQuickAccessItems.Add($second)

        Remove-GaloreQuickAccessItem -Path $first.Path

        @($script:GaloreQuickAccessItems).Count |
        Should Be 1

        $script:GaloreQuickAccessItems[0].Path |
        Should Be $second.Path

        Assert-MockCalled Update-GaloreQuickAccessBar -Times 1 -Exactly

    }

    It "leaves the collection untouched when the requested item is absent" {

        [void]$script:GaloreQuickAccessItems.Add([pscustomobject]@{ Path = "C:\\Tools\\One.exe" })

        Remove-GaloreQuickAccessItem -Path "C:\\Tools\\Missing.exe"

        @($script:GaloreQuickAccessItems).Count |
        Should Be 1

    }

}

Describe "Quick Access drop handling" {

    BeforeEach {

        $script:GaloreQuickAccessPath = Join-Path $TestDrive "quick-access.json"
        $script:GaloreQuickAccessItems = New-Object System.Collections.ArrayList
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

        @($script:GaloreQuickAccessItems).Count |
        Should Be 4

        foreach($path in @($executable, $shortcut, $internetShortcut, $folder))
        {
            ($script:GaloreQuickAccessItems.Path -contains $path) |
            Should Be $true
        }

        ($script:GaloreQuickAccessItems.Path -contains $textFile) |
        Should Be $false

        Assert-MockCalled Save-GaloreQuickAccessItems -Times 1 -Exactly
        Assert-MockCalled Update-GaloreQuickAccessBar -Times 1 -Exactly

    }

    It "ignores null and non-file-drop data without changing state" {

        [void]$script:GaloreQuickAccessItems.Add(
            [pscustomobject]@{ Path = "C:\\Tools\\Existing.exe" }
        )

        $plainData = New-Object System.Windows.Forms.DataObject
        $plainData.SetData(
            [System.Windows.Forms.DataFormats]::Text,
            "plain text"
        )

        Add-GaloreQuickAccessDroppedItems -Data $null
        Add-GaloreQuickAccessDroppedItems -Data $plainData

        @($script:GaloreQuickAccessItems).Count |
        Should Be 1

        Assert-MockCalled Save-GaloreQuickAccessItems -Times 0 -Exactly -Scope It
        Assert-MockCalled Update-GaloreQuickAccessBar -Times 0 -Exactly -Scope It

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

        $script:GaloreWindowTaskbar = $null
        $script:GaloreWindowTaskbarTimer = New-Object System.Windows.Forms.Timer
        $script:GaloreWindowTaskbarSignature = "previous-state"

        Stop-GaloreWindowTaskbar

        $script:GaloreWindowTaskbar |
        Should Be $null

        $script:GaloreWindowTaskbarTimer |
        Should Be $null

        $script:GaloreWindowTaskbarSignature |
        Should Be $null

    }

}

Describe "Alpha overlay helpers" {

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

}

Describe "Category state contracts" {

    BeforeEach {

        $script:GaloreCategoryTestSettingsFolder = Join-Path $TestDrive "CategorySettings"

        New-Item -ItemType Directory -Path $script:GaloreCategoryTestSettingsFolder -Force | Out-Null

        Mock Get-LauncherSettingsFolder { $script:GaloreCategoryTestSettingsFolder }

        Mock Write-LauncherDiagnostic {}

        $script:GaloreCategoryState = $null

        $script:GaloreCategoryFile = $null

    }

    It "creates four categories with five uniquely identified slots each" {

        $state = New-GaloreCategoryState

        @($state.Categories).Count |
        Should Be 4

        $slots = @($state.Categories | ForEach-Object { $_.Slots })

        $slots.Count |
        Should Be 20

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

        $script:GaloreCategoryState = $null

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

        Assert-MockCalled Write-LauncherDiagnostic -Times 1 -Exactly

    }

    It "recognizes only slots that have a non-empty executable path" {

        Test-GaloreCategorySlotConfigured ([pscustomobject]@{ Path = "C:\\App.exe" }) |
        Should Be $true

        Test-GaloreCategorySlotConfigured ([pscustomobject]@{ Path = "   " }) |
        Should Be $false

    }

}

Describe "Configuration discovery contracts" {

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

    It "builds every launcher program with the process contract required by status logic" {

        $programs = New-LauncherProgramConfiguration -EnvPaths @{
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

        $programs.Count |
        Should Be 9

        foreach($program in $programs.Values) {

            $program.ContainsKey("Path") |
            Should Be $true

            $program.ContainsKey("Args") |
            Should Be $true

            $program.ContainsKey("StatusProcess") |
            Should Be $true

            $program.ContainsKey("WindowProcess") |
            Should Be $true

        }

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
