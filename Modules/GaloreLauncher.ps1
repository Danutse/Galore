# ============================================================
# APPLICATION ROOT PATH
# ============================================================

$script:LauncherRunningAsScript = $MyInvocation.MyCommand.CommandType -eq "ExternalScript"
if($script:LauncherRunningAsScript) {
    $ModuleRoot = $PSScriptRoot
    $AppRoot = Split-Path $ModuleRoot -Parent
} else {
    $AppRoot = Split-Path ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) -Parent
    $ModuleRoot = Join-Path $AppRoot "Modules"
}
$OutputEncoding = [System.Text.Encoding]::UTF8

# ============================================================
# EMBEDDED RELEASE RESOURCES
# ============================================================

$script:GaloreUseEmbeddedResources = $script:GaloreEmbeddedResourceFiles -is [System.Collections.IDictionary] -and $script:GaloreEmbeddedResourceFiles.Count -gt 0
$script:GaloreResourceRoot = Join-Path $AppRoot "resources"

function Initialize-GaloreResourceStore {
    if(-not $script:GaloreUseEmbeddedResources) { return $script:GaloreResourceRoot }
    $cacheVersion = if([string]::IsNullOrWhiteSpace([string]$script:GaloreEmbeddedResourceVersion)) { "default" } else { [string]$script:GaloreEmbeddedResourceVersion }
    $cacheRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) "GaloreLauncher\RuntimeResources\$cacheVersion"
    foreach($resourceName in $script:GaloreEmbeddedResourceFiles.Keys) {
        $relativeName = [string]$resourceName
        if([string]::IsNullOrWhiteSpace($relativeName) -or $relativeName -match '(^|[\\/])\.\.([\\/]|$)') { throw "Invalid embedded resource path '$relativeName'." }
        $targetPath = Join-Path $cacheRoot $relativeName
        $targetFolder = Split-Path -Path $targetPath -Parent
        $resourceBytes = [Convert]::FromBase64String([string]$script:GaloreEmbeddedResourceFiles[$resourceName])
        New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null
        if(-not (Test-Path -LiteralPath $targetPath -PathType Leaf) -or ([IO.FileInfo]$targetPath).Length -ne $resourceBytes.Length) { [IO.File]::WriteAllBytes($targetPath, $resourceBytes) }
    }
    return $cacheRoot
}
$script:GaloreResourceRoot = Initialize-GaloreResourceStore

function Get-GaloreResourcePath {
    param([string]$Name)
    $relativeName = ([string]$Name).TrimStart('\', '/') -replace '^(?i:resources)[\\/]', ''
    if([string]::IsNullOrWhiteSpace($relativeName) -or $relativeName -match '(^|[\\/])\.\.([\\/]|$)') { throw "Invalid Galore resource path '$Name'." }
    return Join-Path $script:GaloreResourceRoot $relativeName
}

# ============================================================
# EMBEDDED RELEASE MODULES
# ============================================================

$script:GaloreUseEmbeddedModules = $script:GaloreEmbeddedModuleSources -is [System.Collections.IDictionary] -and $script:GaloreEmbeddedModuleSources.Count -gt 0

function Get-GaloreModuleSource {
    param([string]$FileName)
    if($script:GaloreUseEmbeddedModules) {
        if(-not $script:GaloreEmbeddedModuleSources.Contains($FileName)) {
            throw "$FileName is missing from the embedded Galore release."
        }
        return [string]$script:GaloreEmbeddedModuleSources[$FileName]
    }
    $modulePath = Join-Path $ModuleRoot $FileName
    if(-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
        throw "$FileName missing: $modulePath"
    }
    return Get-Content -LiteralPath $modulePath -Raw -ErrorAction Stop
}

function Publish-GaloreModuleFunctions {
    param([string]$ModuleSource)
    $functionNames = @(
        [regex]::Matches($ModuleSource, '(?m)^\s*function\s+([A-Za-z][A-Za-z0-9_-]*)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
    )
    foreach($functionName in $functionNames) {
        $functionCommand = Get-Command -Name $functionName -CommandType Function -ErrorAction Stop
        Set-Item -Path ("Function:global:{0}" -f $functionName) -Value $functionCommand.ScriptBlock -Force
    }
}

# ============================================================
# LOGGING BOOTSTRAP
# ============================================================

try {
    $LauncherLoggingModuleSource = Get-GaloreModuleSource -FileName "LauncherLogging.ps1"
    . ([scriptblock]::Create($LauncherLoggingModuleSource))
    Publish-GaloreModuleFunctions -ModuleSource $LauncherLoggingModuleSource
    $script:GaloreBootstrapLoggingManifest = $GaloreModuleManifest
    Write-GaloreLog -Level "INFO" -Component "Startup" -Message "Galore logging subsystem initialized."
} catch {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        [System.Windows.Forms.MessageBox]::Show("Galore Launcher could not start its logging subsystem. $($_.Exception.Message)", "Galore Launcher - Startup Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    } catch {
    }
    throw
}

# ============================================================
# SINGLE INSTANCE STATE
# ============================================================

$script:LauncherInstanceMutex = $null
$script:LauncherInstanceMutexOwned = $false

# ============================================================
# RELEASE SINGLE INSTANCE PROTECTION
# ============================================================

function Stop-LauncherSingleInstance {
    if($null -eq $script:LauncherInstanceMutex) {
        return
    }
    if($script:LauncherInstanceMutexOwned) {
        try {
            $script:LauncherInstanceMutex.ReleaseMutex()
        } catch {
        }
    }
    try {
        $script:LauncherInstanceMutex.Dispose()
    } catch {
    }
    $script:LauncherInstanceMutex = $null
    $script:LauncherInstanceMutexOwned = $false
}

# ============================================================
# GLOBAL ERROR HANDLER
# ============================================================

trap {
    try {
        Write-LauncherLog -Exception $_ -Context "Unhandled launcher error."
    } finally {
        if(Get-Command -Name Stop-LauncherRuntimeResources -CommandType Function -ErrorAction SilentlyContinue) {
            try {
                Stop-LauncherRuntimeResources -Form $script:LauncherForm
            } catch {
            }
        }
        Stop-LauncherSingleInstance
    }
    break
}

# ============================================================
# ACQUIRE SINGLE INSTANCE PROTECTION
# ============================================================

function Initialize-LauncherSingleInstance {
    $mutexName = "Local\GaloreLauncher.SingleInstance.4F5F915C-F01B-4E8F-A5CA-9195137D789B"
    try {
        $script:LauncherInstanceMutex = New-Object System.Threading.Mutex($false, $mutexName)
        try {
            $script:LauncherInstanceMutexOwned = $script:LauncherInstanceMutex.WaitOne(0, $false)
        } catch [System.Threading.AbandonedMutexException] {
            $script:LauncherInstanceMutexOwned = $true
        }
        if(-not $script:LauncherInstanceMutexOwned) {
            $script:LauncherInstanceMutex.Dispose()
            $script:LauncherInstanceMutex = $null
            return $false
        }
        return $true
    } catch {
        if($script:LauncherInstanceMutex) {
            $script:LauncherInstanceMutex.Dispose()
            $script:LauncherInstanceMutex = $null
        }
        $script:LauncherInstanceMutexOwned = $false
        throw
    }
}

# ============================================================
# SHOW DUPLICATE INSTANCE MESSAGE
# ============================================================

function Show-LauncherAlreadyRunningMessage {
    $message = "Galore Launcher is already running"
    if($script:LauncherRunningAsScript) {
        try {
            Write-Host $message -ForegroundColor Yellow
        } catch {
        }
    }
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        [System.Windows.Forms.MessageBox]::Show($message, "Galore Launcher", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    } catch {
    }
}
if(-not (Initialize-LauncherSingleInstance)) {
    Show-LauncherAlreadyRunningMessage
    return
}

# ============================================================
# MODULE DEPENDENCY VALIDATOR
# ============================================================

function Test-GaloreModuleDependencies {
    param([object[]]$LoadedModules, [string]$ModuleRoot, [string]$AppRoot, [switch]$RuntimeVariablesOnly)
    $errors = New-Object System.Collections.ArrayList
    $moduleByName = @{}
    foreach($loadedModule in $LoadedModules) {
        $manifest = $loadedModule.Manifest
        if(-not ($manifest -is [System.Collections.IDictionary]) -or -not $manifest.Contains("Name") -or [string]::IsNullOrWhiteSpace([string]$manifest.Name)) {
            if(-not $RuntimeVariablesOnly) {
                $null = $errors.Add("$($loadedModule.FileName) has an invalid or missing manifest Name.")
            }
            continue
        }
        $moduleName = [string]$manifest.Name
        if($moduleByName.ContainsKey($moduleName)) {
            if(-not $RuntimeVariablesOnly) {
                $null = $errors.Add("Module manifest Name '$moduleName' is declared more than once.")
            }
        } else {
            $moduleByName[$moduleName] = $loadedModule
        }
    }
    if($RuntimeVariablesOnly) {
        foreach($loadedModule in $LoadedModules) {
            $manifest = $loadedModule.Manifest
            if(-not ($manifest -is [System.Collections.IDictionary]) -or -not $manifest.Contains("RequiresVariables")) {
                continue
            }
            foreach($variableName in @($manifest.RequiresVariables)
            ) {
                $runtimeVariable = Get-Variable -Name $variableName -Scope Script -ErrorAction SilentlyContinue
                if($null -eq $runtimeVariable -or $null -eq $runtimeVariable.Value) {
                    $null = $errors.Add("$($manifest.Name) requires runtime variable '$variableName', but it is unavailable.")
                }
            }
        }
        return [PSCustomObject]@{
            IsValid = $errors.Count -eq 0
            Errors = @($errors)
            ModuleCount = $moduleByName.Count
            FunctionCount = 0
            RequiredTypeCount = 0
            RequiredFileCount = 0
        }
    }
    $requiredManifestProperties = @(
    "Name"
    "LoadOrder"
    "RequiresModules"
    "RequiresFunctions"
    "RequiresTypes"
    "RequiresVariables"
    "RequiresFolders"
    "RequiresFiles"
    "ProvidesTypes"
    )
    $functionOwners = @{}
    $typeProviders = @{}
    $requiredFiles = @{}
    $requiredTypes = @{}
    foreach($loadedModule in $LoadedModules) {
        $manifest = $loadedModule.Manifest
        if(-not ($manifest -is [System.Collections.IDictionary])) {
            $null = $errors.Add("$($loadedModule.FileName) did not declare a dictionary manifest.")
            continue
        }
        $missingManifestProperties = @(
        $requiredManifestProperties | Where-Object {
            -not $manifest.Contains($_)
        }
        )
        if($missingManifestProperties.Count -gt 0) {
            $null = $errors.Add("$($loadedModule.FileName) manifest is missing: $($missingManifestProperties -join ', ').")
            continue
        }
        $moduleName = [string]$manifest.Name
        $expectedModuleName = [System.IO.Path]::GetFileNameWithoutExtension($loadedModule.FileName)
        if($moduleName -cne $expectedModuleName) {
            $null = $errors.Add("$($loadedModule.FileName) declares Name '$moduleName'; expected '$expectedModuleName'.")
        }
        $expectedLoadOrder = $loadedModule.ActualOrder * 10
        if($manifest.LoadOrder -ne $expectedLoadOrder) {
            $null = $errors.Add("$moduleName loaded at position $($loadedModule.ActualOrder), but its manifest requires order $($manifest.LoadOrder).")
        }
        if(-not ($manifest.RequiresFunctions -is [System.Collections.IDictionary])) {
            $null = $errors.Add("$moduleName RequiresFunctions must be a dictionary.")
        }
        if(-not ($manifest.RequiresTypes -is [System.Collections.IDictionary])) {
            $null = $errors.Add("$moduleName RequiresTypes must be a dictionary.")
        }
        foreach($providedType in @($manifest.ProvidesTypes)
        ) {
            if([string]::IsNullOrWhiteSpace([string]$providedType)) {
                $null = $errors.Add("$moduleName declares an empty provided type.")
                continue
            }
            if($typeProviders.ContainsKey($providedType)) {
                $null = $errors.Add("Type '$providedType' is provided by both $($typeProviders[$providedType]) and $moduleName.")
            } else {
                $typeProviders[$providedType] = $moduleName
            }
        }
        foreach($requiredFolder in @($manifest.RequiresFolders)
        ) {
            $folderPath = if($requiredFolder -match '^(?i:resources)$' -and $script:GaloreResourceRoot) { $script:GaloreResourceRoot } else { Join-Path $AppRoot $requiredFolder }
            if(-not (Test-Path -LiteralPath $folderPath -PathType Container)) {
                $null = $errors.Add("$moduleName requires folder '$requiredFolder', but it was not found.")
            }
        }
        foreach($requiredFile in @($manifest.RequiresFiles)
        ) {
            $requiredFiles[$requiredFile] = $true
            $filePath = if($requiredFile -match '^(?i:resources)[\\/](.+)$' -and (Get-Command -Name Get-GaloreResourcePath -ErrorAction SilentlyContinue)) { Get-GaloreResourcePath $Matches[1] } else { Join-Path $AppRoot $requiredFile }
            if(-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
                $null = $errors.Add("$moduleName requires file '$requiredFile', but it was not found.")
            }
        }
        $tokens = $null
        $parseErrors = $null
        $moduleAst = [System.Management.Automation.Language.Parser]::ParseInput([string]$loadedModule.Source, $loadedModule.FileName, [ref]$tokens, [ref]$parseErrors)
        if($parseErrors.Count -gt 0) {
            $null = $errors.Add("$moduleName could not be inspected: $($parseErrors[0].Message)")
            continue
        }
        foreach($functionAst in $moduleAst.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Parent -isnot [System.Management.Automation.Language.FunctionMemberAst]
            }, $true
        )
        ) {
            $functionName = $functionAst.Name
            if($functionOwners.ContainsKey($functionName)) {
                $null = $errors.Add("Function '$functionName' is declared by both $($functionOwners[$functionName]) and $moduleName.")
            } else {
                $functionOwners[$functionName] = $moduleName
            }
        }
    }
    foreach($loadedModule in $LoadedModules) {
        $manifest = $loadedModule.Manifest
        if(-not ($manifest -is [System.Collections.IDictionary]) -or -not $manifest.Contains("Name")) {
            continue
        }
        $moduleName = [string]$manifest.Name
        foreach($requiredModule in @($manifest.RequiresModules)
        ) {
            if(-not $moduleByName.ContainsKey($requiredModule)) {
                $null = $errors.Add("$moduleName requires module '$requiredModule', but its manifest was not loaded.")
            }
        }
        if($manifest.RequiresFunctions -is [System.Collections.IDictionary]) {
            foreach($requiredFunction in $manifest.RequiresFunctions.Keys) {
                $declaredOwner = [string]$manifest.RequiresFunctions[$requiredFunction]
                if(-not $functionOwners.ContainsKey($requiredFunction)) {
                    $null = $errors.Add("$moduleName requires function '$requiredFunction' from $declaredOwner, but it is not declared.")
                    continue
                }
                if($functionOwners[$requiredFunction] -cne $declaredOwner) {
                    $null = $errors.Add("$moduleName expects function '$requiredFunction' from $declaredOwner, but it is owned by $($functionOwners[$requiredFunction]).")
                }
                if(-not (Get-Command -Name $requiredFunction -CommandType Function -ErrorAction SilentlyContinue)) {
                    $null = $errors.Add("$moduleName requires function '$requiredFunction', but it did not load into the runtime.")
                }
            }
        }
        if($manifest.RequiresTypes -is [System.Collections.IDictionary]) {
            foreach($requiredType in $manifest.RequiresTypes.Keys) {
                $declaredOwner = [string]$manifest.RequiresTypes[$requiredType]
                $requiredTypes[$requiredType] = $true
                if(-not $typeProviders.ContainsKey($requiredType) -or $typeProviders[$requiredType] -cne $declaredOwner) {
                    $null = $errors.Add("$moduleName requires type '$requiredType' from $declaredOwner, but that provider was not declared.")
                }
                if($null -eq ($requiredType -as [type])) {
                    $null = $errors.Add("$moduleName requires runtime type '$requiredType', but it was not loaded.")
                }
            }
        }
    }
    return [PSCustomObject]@{
        IsValid = $errors.Count -eq 0
        Errors = @($errors)
        ModuleCount = $moduleByName.Count
        FunctionCount = $functionOwners.Count
        RequiredTypeCount = $requiredTypes.Count
        RequiredFileCount = $requiredFiles.Count
    }
}

# ============================================================
# MODULE LOADING
# ============================================================

$GaloreModuleFiles = @(
    "LauncherDomain.ps1"
    "LauncherLogging.ps1"
    "LauncherProcess.ps1"
    "LauncherStartup.ps1"
    "LauncherEvents.ps1"
    "LauncherHardware.ps1"
    "LauncherSearch.ps1"
    "LauncherHotkeys.ps1"
    "LauncherDesktop.ps1"
    "LauncherRecycleHelper.ps1"
    "LauncherPrograms.ps1"
    "LauncherSettings.ps1"
    "LauncherMaintenance.ps1"
    "LauncherAction.ps1"
    "UI.ps1"
    "SplashSupport.ps1"
    "ProgramWindowUI.ps1"
    "LauncherStartMenu.ps1"
    "LauncherConfiguration.ps1"
    "LauncherBrowser.ps1"
    "LauncherSystemTools.ps1"
    "LauncherPostIts.ps1"
    "LauncherAlphaOverlay.ps1"
    "LauncherQuickAccess.ps1"
    "LauncherWindowTaskbar.ps1"
    "LauncherCategories.ps1"
    "LauncherHotkeySettings.ps1"
    "LauncherBackup.ps1"
    "LauncherPopup.ps1"
)
$script:GaloreLoadedModules = New-Object System.Collections.ArrayList
for($moduleIndex = 0; $moduleIndex -lt $GaloreModuleFiles.Count; $moduleIndex++) {
    $GaloreModuleFile = $GaloreModuleFiles[$moduleIndex]
    $GaloreModuleSource = Get-GaloreModuleSource -FileName $GaloreModuleFile
    Remove-Variable -Name GaloreModuleManifest -Scope Script -ErrorAction SilentlyContinue
    if($GaloreModuleFile -eq "LauncherLogging.ps1") {
        $GaloreModuleManifest = $script:GaloreBootstrapLoggingManifest
    } else {
        . ([scriptblock]::Create($GaloreModuleSource))
    }
    if($null -eq $GaloreModuleManifest) {
        throw "$GaloreModuleFile did not declare GaloreModuleManifest."
    }
    Publish-GaloreModuleFunctions -ModuleSource $GaloreModuleSource
    $null = $script:GaloreLoadedModules.Add([PSCustomObject]@{
            FileName = $GaloreModuleFile
            ActualOrder = $moduleIndex + 1
            Manifest = $GaloreModuleManifest
            Source = $GaloreModuleSource
        }
    )
    Write-GaloreLog -Level "INFO" -Component "Modules" -Message "Loaded $GaloreModuleFile."
}
Remove-Variable -Name GaloreModuleManifest -Scope Script -ErrorAction SilentlyContinue
$script:GaloreDependencySummary = Test-GaloreModuleDependencies -LoadedModules $script:GaloreLoadedModules -ModuleRoot $ModuleRoot -AppRoot $AppRoot
if(-not $script:GaloreDependencySummary.IsValid) {
    throw ("Galore module dependency validation failed:`r`n- " + ($script:GaloreDependencySummary.Errors -join "`r`n- "))
}
Write-GaloreLog -Level "INFO" -Component "Dependencies" -Message ("Validation passed: " + "$($script:GaloreDependencySummary.ModuleCount) modules, " + "$($script:GaloreDependencySummary.FunctionCount) functions, " + "$($script:GaloreDependencySummary.RequiredTypeCount) required types, " + "$($script:GaloreDependencySummary.RequiredFileCount) files.")

# ============================================================
# LOAD LIBRARIES
# ============================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ============================================================
# INITIALIZE LAUNCHER CONFIGURATION
# ============================================================

$LauncherConfiguration = Initialize-LauncherConfiguration -AppRoot $AppRoot
if($null -eq $LauncherConfiguration) {
    Stop-LauncherSingleInstance
    return
}
$ProgramRoot = $LauncherConfiguration.ProgramRoot
Initialize-LauncherSettings -ProgramRoot $ProgramRoot
$EnvPaths = $LauncherConfiguration.EnvPaths
$Programs = $LauncherConfiguration.Programs
Initialize-GaloreBrowser -Programs $Programs -AppRoot $AppRoot
Apply-GaloreProgramOverrides -Programs $Programs
Write-GaloreLog -Level "INFO" -Component "Configuration" -Message "Launcher configuration initialized."
$runtimeDependencyValidation = Test-GaloreModuleDependencies -LoadedModules $script:GaloreLoadedModules -ModuleRoot $ModuleRoot -AppRoot $AppRoot -RuntimeVariablesOnly
if(-not $runtimeDependencyValidation.IsValid) {
    throw ("Galore runtime dependency validation failed:`r`n- " + ($runtimeDependencyValidation.Errors -join "`r`n- "))
}
if($script:LauncherRunningAsScript) {
    Write-Host ("Dependency validation passed: " + "$($script:GaloreDependencySummary.ModuleCount) modules, " + "$($script:GaloreDependencySummary.FunctionCount) functions, " + "$($script:GaloreDependencySummary.RequiredTypeCount) required types, " + "$($script:GaloreDependencySummary.RequiredFileCount) files.") -ForegroundColor DarkGreen
}

# ============================================================
# STYLE BUTTON
# ============================================================

Initialize-UIStyleColors

# ============================================================
# PROGRAM WINDOW
# CUSTOM BORDERLESS WINDOW
# ============================================================

function Open-ProgramWindow {

    # ============================================================
    # CREATE PROGRAM WINDOW
    # ============================================================

    $form = New-ProgramWindow
    $script:LauncherForm = $form

    # ==========================
    # BACKGROUND MAINTENANCE
    # ==========================

    Initialize-GaloreMaintenance -ProgramRoot $ProgramRoot
    Write-GaloreLog -Level "INFO" -Component "Maintenance" -Message "Background maintenance initialized."

    # ==========================
    # GLOBAL HOTKEY SUPPORT
    # ==========================

    Initialize-HotkeySupport
    Initialize-GaloreHotkeySettings

    # ==========================
    # REGISTER CTRL + SHIFT + SPACE
    # ==========================

    Initialize-GlobalHotkey $form.Handle

    # ==========================
    # SAVE POSITION / SIZE
    # ==========================

    Initialize-LauncherWindowState -Form $form

    # ==========================
    # TOGGLE WINDOW
    # ==========================

    Register-LauncherToggleHotkey $form

    # ==========================
    # REAL TIME CLOCK
    # ==========================

    Initialize-Clock $form

    # ============================================================
    # APPLY PROGRAM ICON TO WINDOW + TASKBAR
    # ============================================================

    Initialize-ProgramIcon $form

    # ============================================================
    # REMOVE WINDOWS TITLE BAR
    # ============================================================

    $titleBar = Initialize-ProgramTitleBar -Form $form

    # ============================================================
    # WINDOW BUTTONS
    # ============================================================

    Initialize-MinimizeButton
    Initialize-MaximizeButton
    Initialize-CloseButton

    # ============================================================
    # SYSTEM MONITOR PANEL
    # ============================================================

    $systemMonitor = New-SystemMonitorPanel
    $systemPanel = $systemMonitor.Panel
    $cpuLabel = $systemMonitor.CPU
    $ramLabel = $systemMonitor.RAM
    $gpuLabel = $systemMonitor.GPU
    $gpuTempLabel = $systemMonitor.GPUTemp
    $form.Controls.Add($systemPanel)

    # ============================================================
    # HARDWARE EVENTS
    # ============================================================

    Register-HardwareMonitorEvents -SystemPanel $systemPanel
    Initialize-HardwareCacheReader
    Initialize-RAMCleanupSchedule

    # ============================================================
    # TITLE BAR RESIZE HANDLER
    # ============================================================

    Register-TitleBarResizeHandler -Form $form -TitleBar $titleBar

    # ==========================
    # TASK MANAGER ICON
    # ==========================

    Initialize-TaskManagerButton -Form $form

    # ==========================
    # CMD ADMIN ICON
    # ==========================

    Initialize-CmdButton -Form $form

    # ==========================
    # SYSTEM TOOLS
    # ==========================

    Initialize-GaloreSystemTools -Form $form

    # ==========================
    # POST-ITS
    # ==========================

    Initialize-GalorePostIts -Form $form

    # ==========================
    # QUICK ACCESS BAR
    # ==========================

    Initialize-GaloreQuickAccessBar -Form $form

    # ==========================
    # LIVE WINDOW TASKBAR
    # ==========================

    Initialize-GaloreWindowTaskbar -Form $form

    # ==========================
    # WINDOWS SEARCH
    # ==========================

    Initialize-StartMenu -Form $form

    # ==========================
    # DESKTOP BUTTONS
    # ==========================

    Initialize-DesktopButtons -Form $form -TitleBar $titleBar

    # ============================================================
    # PROGRAM CONTROLS
    # ============================================================

    $ProgramControls = Initialize-ProgramControls -Form $form -Programs $Programs
    $checks = $ProgramControls.Checks
    $statuses = $ProgramControls.Statuses
    $CategoryControls = Initialize-GaloreCategories -Form $form
    foreach($categoryProgramName in $CategoryControls.Programs.Keys) {
        $Programs[$categoryProgramName] = $CategoryControls.Programs[$categoryProgramName]
        $checks[$categoryProgramName] = $CategoryControls.Checks[$categoryProgramName]
    }
    Register-GaloreCategoryHotkeys -Programs $Programs -Checks $checks -Statuses $statuses -AppRoot $AppRoot
    Initialize-GaloreHotkeyButton -Form $form

    # ============================================================
    # LAUNCHER ACTION BUTTONS
    # ============================================================

    Initialize-LauncherButtons -Form $form -Programs $Programs -Checks $checks -Statuses $statuses
    Restore-GaloreHeaderControlZOrder -Form $form

    # ============================================================
    # SYSTEM TRAY ICON
    # ============================================================

    Initialize-SystemTray
    Write-GaloreLog -Level "INFO" -Component "Tray" -Message "System tray initialized."

    # ============================================================
    # SAVE SETTINGS WHEN CLOSING
    # ============================================================

    Register-LauncherClosingEvent -Form $form -Checks $checks

    # ============================================================
    # SYSTEM MONITOR DISPLAY TIMER
    # ============================================================

    Initialize-SystemMonitorDisplay $cpuLabel $ramLabel $gpuLabel $gpuTempLabel $form

    # ============================================================
    # SHOW WINDOW WITH CLEAN FADE IN
    # ============================================================

    Show-ProgramWindowWithFade $form
    Write-GaloreLog -Level "INFO" -Component "Window" -Message "Main program window shown."
}

# ============================================================
# SPLASH SUPPORT
# ============================================================

try {
    Show-LauncherSplash -AppRoot $AppRoot

    # ========================================================
    # OPEN PROGRAM WINDOW
    # ========================================================

    Open-ProgramWindow
} catch {
    Write-LauncherLog -Exception $_ -Context "Launcher startup or main-window execution failed."
    throw
} finally {
    if(Get-Command -Name Stop-LauncherRuntimeResources -CommandType Function -ErrorAction SilentlyContinue) {
        try {
            Stop-LauncherRuntimeResources -Form $script:LauncherForm
        } catch {
        }
    }
    Stop-LauncherSingleInstance
}
