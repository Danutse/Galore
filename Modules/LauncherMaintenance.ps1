# ============================================================
# LAUNCHER MAINTENANCE MODULE
# ============================================================

param(
    [ValidateSet(
        "",
        "Due",
        "All",
        "Quick",
        "Weekly",
        "Monthly",
        "SixtyDay",
        "ClosedApplicationCaches"
    )]
    [string]$GaloreMaintenanceWorkerMode = "",

    [string]$GaloreMaintenanceStateFile = ""
)

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherMaintenance"
    LoadOrder = 120
    RequiresModules = @()
    RequiresFunctions = [ordered]@{}
    RequiresTypes = [ordered]@{}
    RequiresVariables = @()
    RequiresFolders = @()
    RequiresFiles = @()
    ProvidesTypes = @("GaloreMaintenance.IdleState", "GaloreMaintenance.RecycleBin")
}

$script:GaloreMaintenanceModulePath =
$MyInvocation.MyCommand.Path

$script:GaloreMaintenanceMaximumStateBytes =
5 * 1MB

$script:GaloreMaintenanceMaximumShortcutCandidates = 1500

$script:GaloreMaintenanceMaximumShortcutPathLength = 4096

$script:GaloreApprovedCacheLocations =
@()

# ============================================================
# MAINTENANCE STATE
# ============================================================

function New-GaloreMaintenanceState {

    return [pscustomobject]@{

        Version = 1

        TotalRuntimeSeconds = 0.0

        LastQuickRuntimeSeconds = 0.0

        LastWeeklyRuntimeSeconds = 0.0

        LastMonthlyRuntimeSeconds = 0.0

        LastSixtyDayRuntimeSeconds = 0.0

        BrokenShortcutCandidates = @()

    }

}

function Get-GaloreMaintenanceNumber {

    param(
        $Object,
        [string]$PropertyName,
        [double]$DefaultValue = 0.0
    )

    if(
        $null -eq $Object -or
        $null -eq $Object.PSObject.Properties[$PropertyName]
    )
    {

        return $DefaultValue

    }

    $value = 0.0

    if(
        [double]::TryParse(
            [string]$Object.$PropertyName,
            [ref]$value
        ) -and
        -not [double]::IsNaN($value) -and
        -not [double]::IsInfinity($value) -and
        $value -ge 0
    )
    {

        return $value

    }

    return $DefaultValue

}

function ConvertTo-ValidatedGaloreMaintenanceState {

    param(
        $State
    )

    $validated =
    New-GaloreMaintenanceState

    if(
        $null -eq $State
    )
    {

        return $validated

    }

    $validated.TotalRuntimeSeconds =
    Get-GaloreMaintenanceNumber `
    -Object $State `
    -PropertyName "TotalRuntimeSeconds"

    foreach(
        $propertyName in @(
            "LastQuickRuntimeSeconds"
            "LastWeeklyRuntimeSeconds"
            "LastMonthlyRuntimeSeconds"
            "LastSixtyDayRuntimeSeconds"
        )
    )
    {

        $lastRuntime =
        Get-GaloreMaintenanceNumber `
        -Object $State `
        -PropertyName $propertyName

        if(
            $lastRuntime -gt $validated.TotalRuntimeSeconds
        )
        {

            $lastRuntime =
            $validated.TotalRuntimeSeconds

        }

        $validated.$propertyName =
        $lastRuntime

    }

    if(
        $null -ne $State.PSObject.Properties["BrokenShortcutCandidates"] -and
        $null -ne $State.BrokenShortcutCandidates
    )
    {

        $validated.BrokenShortcutCandidates =
        @(
            $State.BrokenShortcutCandidates |
            Where-Object {
                $null -ne $_ -and
                $null -ne $_.PSObject.Properties["Path"] -and
                -not [string]::IsNullOrWhiteSpace([string]$_.Path) -and
                ([string]$_.Path).Length -le
                $script:GaloreMaintenanceMaximumShortcutPathLength
            } |
            Select-Object `
            -First $script:GaloreMaintenanceMaximumShortcutCandidates |
            ForEach-Object {
                [pscustomobject]@{
                    Path = [string]$_.Path
                    FirstSeenRuntimeSeconds =
                    Get-GaloreMaintenanceNumber `
                    -Object $_ `
                    -PropertyName "FirstSeenRuntimeSeconds"
                }
            }
        )

    }

    return $validated

}

function Read-GaloreMaintenanceStateUnlocked {

    param(
        [string]$StateFile
    )

    if(
        [string]::IsNullOrWhiteSpace($StateFile) -or
        -not (Test-Path -LiteralPath $StateFile -PathType Leaf)
    )
    {

        return New-GaloreMaintenanceState

    }

    try
    {

        $stateInfo =
        Get-Item `
        -LiteralPath $StateFile `
        -Force `
        -ErrorAction Stop

        if(
            $stateInfo.Length -gt
            $script:GaloreMaintenanceMaximumStateBytes
        )
        {

            return New-GaloreMaintenanceState

        }

        $state =
        Get-Content `
        -LiteralPath $StateFile `
        -Encoding UTF8 `
        -Raw `
        -ErrorAction Stop |
        ConvertFrom-Json `
        -ErrorAction Stop

        return ConvertTo-ValidatedGaloreMaintenanceState `
        -State $state

    }
    catch
    {

        return New-GaloreMaintenanceState

    }

}

function Write-GaloreMaintenanceStateUnlocked {

    param(
        [string]$StateFile,
        $State
    )

    if(
        [string]::IsNullOrWhiteSpace($StateFile)
    )
    {

        return $false

    }

    try
    {

        $stateFolder =
        Split-Path `
        -Parent $StateFile

        if(
            -not (Test-Path -LiteralPath $stateFolder -PathType Container)
        )
        {

            New-Item `
            -ItemType Directory `
            -Path $stateFolder `
            -Force `
            -ErrorAction Stop |
            Out-Null

        }

        $temporaryFile = "$StateFile.tmp"

        $json =
        ConvertTo-Json `
        -InputObject $State `
        -Depth 6

        $utf8 =
        New-Object System.Text.UTF8Encoding($false)

        [System.IO.File]::WriteAllText(
            $temporaryFile,
            $json,
            $utf8
        )

        Move-Item `
        -LiteralPath $temporaryFile `
        -Destination $StateFile `
        -Force `
        -ErrorAction Stop

        return $true

    }
    catch
    {

        try
        {

            Remove-Item `
            -LiteralPath "$StateFile.tmp" `
            -Force `
            -ErrorAction SilentlyContinue

        }
        catch
        {

        }

        return $false

    }

}

function Invoke-WithGaloreMaintenanceStateLock {

    param(
        [scriptblock]$Action,
        [int]$TimeoutMilliseconds = 100
    )

    $mutex = $null

    $owned = $false

    try
    {

        $mutex =
        New-Object System.Threading.Mutex(
            $false,
            "Local\GaloreLauncherMaintenanceState"
        )

        try
        {

            $owned =
            $mutex.WaitOne(
                $TimeoutMilliseconds,
                $false
            )

        }
        catch [System.Threading.AbandonedMutexException]
        {

            $owned = $true

        }

        if(
            -not $owned
        )
        {

            return $null

        }

        return & $Action

    }
    catch
    {

        return $null

    }
    finally
    {

        if(
            $owned -and
            $null -ne $mutex
        )
        {

            try
            {

                $mutex.ReleaseMutex()

            }
            catch
            {

            }

        }

        if(
            $null -ne $mutex
        )
        {

            $mutex.Dispose()

        }

    }

}

function Get-GaloreMaintenanceStateSnapshot {

    param(
        [string]$StateFile,
        [int]$TimeoutMilliseconds = 25
    )

    return Invoke-WithGaloreMaintenanceStateLock `
    -TimeoutMilliseconds $TimeoutMilliseconds `
    -Action {
        Read-GaloreMaintenanceStateUnlocked `
        -StateFile $StateFile
    }

}

function Update-GaloreMaintenanceState {

    param(
        [string]$StateFile,
        [scriptblock]$Update,
        [int]$TimeoutMilliseconds = 500
    )

    return Invoke-WithGaloreMaintenanceStateLock `
    -TimeoutMilliseconds $TimeoutMilliseconds `
    -Action {

        $state =
        Read-GaloreMaintenanceStateUnlocked `
        -StateFile $StateFile

        $null =
        & $Update $state

        $state =
        ConvertTo-ValidatedGaloreMaintenanceState `
        -State $state

        $stateWritten =
        Write-GaloreMaintenanceStateUnlocked `
        -StateFile $StateFile `
        -State $state

        if(
            -not $stateWritten
        )
        {

            return $null

        }

        return $state

    }

}

# ============================================================
# ACTIVE LAUNCHER RUNTIME CLOCK
# ============================================================

function Save-GaloreMaintenanceRuntime {

    if(
        -not $script:GaloreMaintenanceInitialized -or
        $null -eq $script:GaloreMaintenanceStopwatch
    )
    {

        return

    }

    $elapsedSeconds =
    [math]::Floor(
        $script:GaloreMaintenanceStopwatch.Elapsed.TotalSeconds
    )

    $runtimeToCommit =
    $elapsedSeconds -
    $script:GaloreMaintenanceCommittedSeconds

    if(
        $runtimeToCommit -lt 1
    )
    {

        return

    }

    $updatedState =
    Update-GaloreMaintenanceState `
    -StateFile $script:GaloreMaintenanceStateFile `
    -TimeoutMilliseconds 25 `
    -Update {

        param($state)

        $state.TotalRuntimeSeconds +=
        $runtimeToCommit

    }

    if(
        $null -ne $updatedState
    )
    {

        $script:GaloreMaintenanceCommittedSeconds = $elapsedSeconds

    }

}

function Initialize-GaloreMaintenanceIdleSupport {

    if(
        "GaloreMaintenance.IdleState" -as [type]
    )
    {

        return $true

    }

    try
    {
        Add-Type @"
using System;
using System.Runtime.InteropServices;

namespace GaloreMaintenance
{
    public static class IdleState
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct LASTINPUTINFO
        {
            public uint cbSize;
            public uint dwTime;
        }

        [DllImport("user32.dll")]
        private static extern bool GetLastInputInfo(ref LASTINPUTINFO info);

        public static uint GetIdleMilliseconds()
        {
            LASTINPUTINFO info = new LASTINPUTINFO();
            info.cbSize = (uint)Marshal.SizeOf(info);

            if(!GetLastInputInfo(ref info))
            {
                return 0;
            }

            return unchecked((uint)Environment.TickCount) - info.dwTime;
        }
    }
}
"@ `
        -ErrorAction Stop



        return $true

    }
    catch
    {

        return $false

    }

}



function Test-GaloreMaintenanceCanStart {

    if(
        -not (
            Initialize-GaloreMaintenanceIdleSupport
        )
    )
    {

        return $false

    }



    try
    {

        $powerStatus =
        [System.Windows.Forms.SystemInformation]::PowerStatus



        if(
            $powerStatus.PowerLineStatus -eq
            [System.Windows.Forms.PowerLineStatus]::Offline
        )
        {

            return $false

        }



        $idleMilliseconds =
        [GaloreMaintenance.IdleState]::GetIdleMilliseconds()



        return $idleMilliseconds -ge 1000

    }
    catch
    {

        return $false

    }

}



function Test-GaloreMaintenanceIsDue {

    param(
        $State
    )



    if(
        $null -eq $State
    )
    {

        return $false

    }



    $intervals =
    @{
        LastQuickRuntimeSeconds = 2 * 60 * 60
        LastWeeklyRuntimeSeconds = 7 * 24 * 60 * 60
        LastMonthlyRuntimeSeconds = 30 * 24 * 60 * 60
        LastSixtyDayRuntimeSeconds = 60 * 24 * 60 * 60
    }



    foreach(
        $propertyName in $intervals.Keys
    )
    {

        if(
            ($State.TotalRuntimeSeconds - $State.$propertyName) -ge
            $intervals[$propertyName]
        )
        {

            return $true

        }

    }



    return $false

}



# ============================================================
# CLOSED APPLICATION CACHE REQUESTS
# ============================================================

function Start-GalorePendingApplicationCacheCleanup {

    if(
        -not $script:GaloreMaintenanceInitialized -or
        -not $script:GaloreApplicationCacheCleanupPending
    )
    {

        return

    }



    if(
        $null -ne $script:GaloreMaintenanceWorkerProcess
    )
    {

        try
        {

            if(
                -not $script:GaloreMaintenanceWorkerProcess.HasExited
            )
            {

                return

            }



            $script:GaloreMaintenanceWorkerProcess.Dispose()

        }
        catch
        {

            return

        }



        $script:GaloreMaintenanceWorkerProcess =
        $null



        $script:GaloreMaintenanceWorkerMode =
        $null

    }



    $script:GaloreApplicationCacheCleanupPending =
    $false



    Start-GaloreMaintenanceWorker `
    -Mode "ClosedApplicationCaches"



    if(
        $null -eq $script:GaloreMaintenanceWorkerProcess
    )
    {

        $script:GaloreApplicationCacheCleanupPending =
        $true

    }

}



function Request-GaloreClosedApplicationCacheCleanup {

    if(
        -not $script:GaloreMaintenanceInitialized
    )
    {

        return

    }



    if(
        $null -ne $script:GaloreMaintenanceWorkerProcess -and
        $script:GaloreMaintenanceWorkerMode -eq "ClosedApplicationCaches"
    )
    {

        try
        {

            if(
                -not $script:GaloreMaintenanceWorkerProcess.HasExited
            )
            {

                return

            }

        }
        catch
        {



        }

    }



    $script:GaloreApplicationCacheCleanupPending =
    $true



    Start-GalorePendingApplicationCacheCleanup

}



function Update-GaloreApplicationMaintenanceState {

    param(
        [string]$ApplicationName,
        [bool]$IsRunning
    )



    if(
        $ApplicationName -notin @(
            "Discord"
            "Steam"
        )
    )
    {

        return

    }



    if(
        $null -eq $script:GaloreObservedApplicationStates
    )
    {

        $script:GaloreObservedApplicationStates =
        @{}

    }



    $wasObserved =
    $script:GaloreObservedApplicationStates.ContainsKey(
        $ApplicationName
    )



    $wasRunning =
    $false



    if(
        $wasObserved
    )
    {

        $wasRunning =
        [bool]$script:GaloreObservedApplicationStates[$ApplicationName]

    }



    $script:GaloreObservedApplicationStates[$ApplicationName] =
    $IsRunning



    if(
        -not $IsRunning -and
        (
            -not $wasObserved -or
            $wasRunning
        )
    )
    {

        Request-GaloreClosedApplicationCacheCleanup

    }

}



function Request-GaloreMaintenanceDueRun {

    if(
        -not $script:GaloreMaintenanceInitialized
    )
    {

        return

    }



    if(
        $null -ne $script:GaloreMaintenanceWorkerProcess
    )
    {

        try
        {

            if(
                -not $script:GaloreMaintenanceWorkerProcess.HasExited
            )
            {

                return

            }



            $script:GaloreMaintenanceWorkerProcess.Dispose()

        }
        catch
        {



        }



        $script:GaloreMaintenanceWorkerProcess =
        $null



        $script:GaloreMaintenanceWorkerMode =
        $null

    }



    Start-GalorePendingApplicationCacheCleanup



    if(
        $null -ne $script:GaloreMaintenanceWorkerProcess
    )
    {

        return

    }



    $state =
    Get-GaloreMaintenanceStateSnapshot `
    -StateFile $script:GaloreMaintenanceStateFile



    if(
        -not (
            Test-GaloreMaintenanceIsDue `
            -State $state
        )
    )
    {

        return

    }



    if(
        -not (
            Test-GaloreMaintenanceCanStart
        )
    )
    {

        return

    }



    Start-GaloreMaintenanceWorker `
    -Mode "Due"

}



function Initialize-GaloreMaintenance {

    param(
        [string]$ProgramRoot
    )



    if(
        $script:GaloreMaintenanceInitialized -or
        [string]::IsNullOrWhiteSpace($ProgramRoot)
    )
    {

        return

    }



    $settingsFolder =
    Join-Path `
    $ProgramRoot `
    "Settings"



    if(-not (Test-Path -LiteralPath $settingsFolder -PathType Container))
    {
        New-Item -ItemType Directory -Path $settingsFolder -Force -ErrorAction Stop | Out-Null
    }



    $script:GaloreMaintenanceStateFile =
    Join-Path `
    $settingsFolder `
    "maintenance-state.json"



    $legacyMaintenanceStateFile =
    Join-Path `
    $ProgramRoot `
    "maintenance-state.json"



    if(
        -not (Test-Path -LiteralPath $script:GaloreMaintenanceStateFile -PathType Leaf) -and
        (Test-Path -LiteralPath $legacyMaintenanceStateFile -PathType Leaf)
    )
    {
        Move-Item -LiteralPath $legacyMaintenanceStateFile -Destination $script:GaloreMaintenanceStateFile -ErrorAction Stop
    }



    $script:GaloreMaintenanceCommittedSeconds =
    0.0



    $script:GaloreMaintenanceWorkerProcess =
    $null



    $script:GaloreMaintenanceWorkerMode =
    $null



    $script:GaloreApplicationCacheCleanupPending =
    $false



    $script:GaloreObservedApplicationStates =
    @{}



    $script:GaloreMaintenanceStopwatch =
    [System.Diagnostics.Stopwatch]::StartNew()



    $script:GaloreMaintenanceInitialized =
    $true



    $script:GaloreMaintenanceTimer =
    New-Object System.Windows.Forms.Timer



    $script:GaloreMaintenanceTimer.Interval =
    60000



    $script:GaloreMaintenanceTimer.Add_Tick({

        Save-GaloreMaintenanceRuntime



        Request-GaloreMaintenanceDueRun

    })



    $script:GaloreMaintenanceTimer.Start()

}



function Stop-GaloreMaintenance {

    if(
        -not $script:GaloreMaintenanceInitialized
    )
    {

        return

    }



    if(
        $null -ne $script:GaloreMaintenanceTimer
    )
    {

        try
        {

            $script:GaloreMaintenanceTimer.Stop()

            $script:GaloreMaintenanceTimer.Dispose()

        }
        catch
        {



        }



        $script:GaloreMaintenanceTimer =
        $null

    }



    Save-GaloreMaintenanceRuntime



    if(
        $null -ne $script:GaloreMaintenanceStopwatch
    )
    {

        $script:GaloreMaintenanceStopwatch.Stop()

        $script:GaloreMaintenanceStopwatch =
        $null

    }



    if(
        $null -ne $script:GaloreMaintenanceWorkerProcess
    )
    {

        try
        {

            $script:GaloreMaintenanceWorkerProcess.Dispose()

        }
        catch
        {



        }



        $script:GaloreMaintenanceWorkerProcess =
        $null

    }



    $script:GaloreMaintenanceWorkerMode =
    $null



    $script:GaloreApplicationCacheCleanupPending =
    $false



    $script:GaloreObservedApplicationStates =
    $null



    $script:GaloreMaintenanceInitialized =
    $false

}



# ============================================================
# HIDDEN MAINTENANCE WORKER
# ============================================================

function Start-GaloreMaintenanceWorker {

    param(
        [ValidateSet(
            "Due",
            "All",
            "Quick",
            "Weekly",
            "Monthly",
            "SixtyDay",
            "ClosedApplicationCaches"
        )]
        [string]$Mode
    )



    if(
        -not $script:GaloreMaintenanceInitialized -or
        [string]::IsNullOrWhiteSpace($script:GaloreMaintenanceModulePath) -or
        -not (Test-Path -LiteralPath $script:GaloreMaintenanceModulePath -PathType Leaf)
    )
    {

        return

    }



    if(
        $null -ne $script:GaloreMaintenanceWorkerProcess
    )
    {

        try
        {

            if(
                -not $script:GaloreMaintenanceWorkerProcess.HasExited
            )
            {

                return

            }



            $script:GaloreMaintenanceWorkerProcess.Dispose()



            $script:GaloreMaintenanceWorkerProcess =
            $null



            $script:GaloreMaintenanceWorkerMode =
            $null

        }
        catch
        {

            return

        }

    }



    try
    {

        $powershellPath =
        Join-Path `
        $env:SystemRoot `
        "System32\WindowsPowerShell\v1.0\powershell.exe"



        if(
            -not (Test-Path -LiteralPath $powershellPath -PathType Leaf)
        )
        {

            return

        }



        $modulePath =
        $script:GaloreMaintenanceModulePath.Replace(
            "'",
            "''"
        )



        $stateFile =
        $script:GaloreMaintenanceStateFile.Replace(
            "'",
            "''"
        )



        $workerCommand =
        "& '$modulePath' -GaloreMaintenanceWorkerMode '$Mode' -GaloreMaintenanceStateFile '$stateFile'"



        $encodedCommand =
        [Convert]::ToBase64String(
            [System.Text.Encoding]::Unicode.GetBytes(
                $workerCommand
            )
        )



        $process =
        Start-Process `
        -FilePath $powershellPath `
        -ArgumentList @(
            "-NoLogo"
            "-NoProfile"
            "-NonInteractive"
            "-WindowStyle"
            "Hidden"
            "-ExecutionPolicy"
            "Bypass"
            "-EncodedCommand"
            $encodedCommand
        ) `
        -WindowStyle Hidden `
        -PassThru `
        -ErrorAction Stop



        try
        {

            $process.PriorityClass =
            [System.Diagnostics.ProcessPriorityClass]::BelowNormal

        }
        catch
        {



        }



        $script:GaloreMaintenanceWorkerProcess =
        $process



        $script:GaloreMaintenanceWorkerMode =
        $Mode

    }
    catch
    {



    }

}



function Resolve-GaloreMaintenanceRoot {

    param(
        [string]$Path
    )



    if(
        [string]::IsNullOrWhiteSpace($Path)
    )
    {

        return $null

    }



    try
    {

        $expandedPath =
        [Environment]::ExpandEnvironmentVariables($Path)



        $fullPath =
        [System.IO.Path]::GetFullPath($expandedPath).
        TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )



        $pathRoot =
        [System.IO.Path]::GetPathRoot($fullPath).
        TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )



        if(
            $fullPath.Length -le $pathRoot.Length -or
            -not (Test-Path -LiteralPath $fullPath -PathType Container)
        )
        {

            return $null

        }



        $attributes =
        [System.IO.File]::GetAttributes($fullPath)



        if(
            ($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
        )
        {

            return $null

        }



        return $fullPath

    }
    catch
    {

        return $null

    }

}



function Get-UniqueGaloreMaintenanceRoots {

    param(
        [string[]]$Paths
    )



    $seen =
    @{}



    foreach(
        $path in $Paths
    )
    {

        $resolvedPath =
        Resolve-GaloreMaintenanceRoot `
        -Path $path



        if(
            $null -ne $resolvedPath -and
            -not $seen.ContainsKey($resolvedPath)
        )
        {

            $seen[$resolvedPath] =
            $true



            $resolvedPath

        }

    }

}



function Invoke-GaloreAgedFileCleanup {

    param(
        [string[]]$Roots,
        [int]$AgeDays,
        [int]$ZeroByteAgeDays = -1,
        [scriptblock]$FilePredicate,
        [int]$MaxEntries = 5000,
        [int]$MaxDeletes = 250,
        [int]$MaxSeconds = 30,
        [int]$EmptyFolderAgeDays = -1
    )



    $deadline =
    [DateTime]::UtcNow.AddSeconds($MaxSeconds)



    $agedCutoff =
    [DateTime]::UtcNow.AddDays(-1 * $AgeDays)



    $zeroByteCutoff =
    if($ZeroByteAgeDays -ge 0)
    {
        [DateTime]::UtcNow.AddDays(-1 * $ZeroByteAgeDays)
    }
    else
    {
        [DateTime]::MinValue
    }



    $emptyFolderCutoff =
    if($EmptyFolderAgeDays -ge 0)
    {
        [DateTime]::UtcNow.AddDays(-1 * $EmptyFolderAgeDays)
    }
    else
    {
        [DateTime]::MinValue
    }



    $entriesExamined =
    0



    $itemsDeleted =
    0



    foreach(
        $root in (
            Get-UniqueGaloreMaintenanceRoots `
            -Paths $Roots
        )
    )
    {

        if(
            [DateTime]::UtcNow -ge $deadline -or
            $entriesExamined -ge $MaxEntries -or
            $itemsDeleted -ge $MaxDeletes
        )
        {

            break

        }



        $visitedDirectories =
        New-Object 'System.Collections.Generic.List[string]'



        $directories =
        New-Object 'System.Collections.Generic.Stack[string]'



        $directories.Push($root)



        while(
            $directories.Count -gt 0 -and
            [DateTime]::UtcNow -lt $deadline -and
            $entriesExamined -lt $MaxEntries -and
            $itemsDeleted -lt $MaxDeletes
        )
        {

            $currentDirectory =
            $directories.Pop()



            $visitedDirectories.Add($currentDirectory)



            $enumerator =
            $null



            try
            {

                $enumerator =
                [System.IO.Directory]::EnumerateFileSystemEntries(
                    $currentDirectory
                ).GetEnumerator()



                while(
                    [DateTime]::UtcNow -lt $deadline -and
                    $entriesExamined -lt $MaxEntries -and
                    $itemsDeleted -lt $MaxDeletes -and
                    $enumerator.MoveNext()
                )
                {

                    $entry =
                    [string]$enumerator.Current



                    $entriesExamined++



                    try
                    {

                        $attributes =
                        [System.IO.File]::GetAttributes($entry)



                        if(
                            ($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
                        )
                        {

                            continue

                        }



                        if(
                            ($attributes -band [System.IO.FileAttributes]::Directory) -ne 0
                        )
                        {

                            $directories.Push($entry)

                            continue

                        }



                        $file =
                        New-Object System.IO.FileInfo($entry)



                        $matchesPredicate =
                        $true



                        if(
                            $null -ne $FilePredicate
                        )
                        {

                            $matchesPredicate =
                            [bool](& $FilePredicate $file)

                        }



                        if(
                            -not $matchesPredicate
                        )
                        {

                            continue

                        }



                        $isAgedFile =
                        $file.LastWriteTimeUtc -le $agedCutoff



                        $isAgedZeroByteFile =
                        $ZeroByteAgeDays -ge 0 -and
                        $file.Length -eq 0 -and
                        $file.LastWriteTimeUtc -le $zeroByteCutoff



                        if(
                            -not $isAgedFile -and
                            -not $isAgedZeroByteFile
                        )
                        {

                            continue

                        }



                        [System.IO.File]::Delete($file.FullName)



                        $itemsDeleted++

                        if(
                            ($itemsDeleted % 100) -eq 0
                        )
                        {

                            Start-Sleep `
                            -Milliseconds 75

                        }

                    }
                    catch
                    {



                    }

                }

            }
            catch
            {



            }
            finally
            {

                if(
                    $null -ne $enumerator
                )
                {

                    $enumerator.Dispose()

                }

            }

        }



        if(
            $EmptyFolderAgeDays -ge 0
        )
        {

            foreach(
                $directory in @(
                    $visitedDirectories |
                    Where-Object {
                        $_ -ne $root
                    } |
                    Sort-Object Length -Descending
                )
            )
            {

                if(
                    [DateTime]::UtcNow -ge $deadline
                )
                {

                    break

                }



                try
                {

                    $directoryInfo =
                    New-Object System.IO.DirectoryInfo($directory)



                    $emptyEnumerator =
                    $null



                    $hasEntries =
                    $true



                    try
                    {

                        $emptyEnumerator =
                        [System.IO.Directory]::EnumerateFileSystemEntries(
                            $directory
                        ).GetEnumerator()



                        $hasEntries =
                        $emptyEnumerator.MoveNext()

                    }
                    finally
                    {

                        if(
                            $null -ne $emptyEnumerator
                        )
                        {

                            $emptyEnumerator.Dispose()

                        }

                    }



                    if(
                        $directoryInfo.LastWriteTimeUtc -le $emptyFolderCutoff -and
                        -not $hasEntries
                    )
                    {

                        [System.IO.Directory]::Delete(
                            $directory,
                            $false
                        )

                    }

                }
                catch
                {



                }

            }

        }

    }

}



function Get-GaloreTemporaryRoots {

    $paths =
    @(
        $env:TEMP
        $env:TMP
        (Join-Path $env:LOCALAPPDATA "Temp")
        (Join-Path $env:SystemRoot "Temp")
    )



    return @(
        Get-UniqueGaloreMaintenanceRoots `
        -Paths $paths
    )

}



# ============================================================
# GALORE LOG ROTATION
# ============================================================

function Invoke-GaloreLauncherLogMaintenance {

    param(
        [string]$StateFile
    )



    if(
        [string]::IsNullOrWhiteSpace($StateFile)
    )
    {

        return

    }



    try
    {

        $stateFolder =
        Split-Path `
        -Parent $StateFile



        $programRoot =
        $stateFolder



        if((Split-Path -Leaf $stateFolder) -ieq "Settings")
        {
            $programRoot =
            Split-Path `
            -Parent $stateFolder
        }



        $logFolder =
        Join-Path `
        $programRoot `
        "Logs"



        if(
            Test-Path -LiteralPath $logFolder -PathType Container
        )
        {

            foreach(
                $logName in @(
                    "Crash.log"
                    "Diagnostics.log"
                    "GaloreLauncher.log"
                    "Galore.log"
                )
            )
            {

                $logPath =
                Join-Path `
                $logFolder `
                $logName



                try
                {

                    if(
                        Test-Path -LiteralPath $logPath -PathType Leaf
                    )
                    {

                        $logInfo =
                        Get-Item `
                        -LiteralPath $logPath `
                        -Force `
                        -ErrorAction Stop



                        if(
                            $logInfo.Length -gt 5MB
                        )
                        {

                            $archivePath =
                            "$logPath.1"



                            Remove-Item `
                            -LiteralPath $archivePath `
                            -Force `
                            -ErrorAction SilentlyContinue



                            Move-Item `
                            -LiteralPath $logPath `
                            -Destination $archivePath `
                            -Force `
                            -ErrorAction Stop

                        }

                    }

                }
                catch
                {



                }

            }



            $oldLogCutoff =
            [DateTime]::UtcNow.AddDays(-60)



            foreach(
                $oldLog in Get-ChildItem `
                -LiteralPath $logFolder `
                -File `
                -Force `
                -ErrorAction SilentlyContinue
            )
            {

                if(
                    $oldLog.Name -notin @(
                        "Crash.log"
                        "Diagnostics.log"
                        "GaloreLauncher.log"
                        "Galore.log"
                    ) -and
                    (
                        $oldLog.Name -like "Crash.log.*" -or
                        $oldLog.Name -like "Diagnostics.log.*" -or
                        $oldLog.Name -like "GaloreLauncher.log.*" -or
                        $oldLog.Name -like "Galore.log.*"
                    ) -and
                    $oldLog.LastWriteTimeUtc -le $oldLogCutoff
                )
                {

                    try
                    {

                        Remove-Item `
                        -LiteralPath $oldLog.FullName `
                        -Force `
                        -ErrorAction Stop

                    }
                    catch
                    {



                    }

                }

            }

        }

    }
    catch
    {



    }



    Invoke-WithGaloreMaintenanceStateLock `
    -TimeoutMilliseconds 500 `
    -Action {

        try
        {

            $temporaryStateFile =
            "$StateFile.tmp"



            if(
                Test-Path -LiteralPath $temporaryStateFile -PathType Leaf
            )
            {

                $temporaryStateInfo =
                Get-Item `
                -LiteralPath $temporaryStateFile `
                -Force `
                -ErrorAction Stop



                if(
                    $temporaryStateInfo.LastWriteTimeUtc -le
                    [DateTime]::UtcNow.AddDays(-1)
                )
                {

                    Remove-Item `
                    -LiteralPath $temporaryStateFile `
                    -Force `
                    -ErrorAction Stop

                }

            }

        }
        catch
        {



        }

    } |
    Out-Null

}



function Remove-GaloreOldCrashData {

    $dumpRoots =
    @(
        (Join-Path $env:LOCALAPPDATA "CrashDumps")
        (Join-Path $env:SystemRoot "Minidump")
        (Join-Path $env:SystemRoot "LiveKernelReports")
    )



    $werRoots =
    @(
        (Join-Path $env:ProgramData "Microsoft\Windows\WER\ReportArchive")
        (Join-Path $env:ProgramData "Microsoft\Windows\WER\ReportQueue")
        (Join-Path $env:ProgramData "Microsoft\Windows\WER\Temp")
        (Join-Path $env:LOCALAPPDATA "Microsoft\Windows\WER\ReportArchive")
        (Join-Path $env:LOCALAPPDATA "Microsoft\Windows\WER\ReportQueue")
        (Join-Path $env:LOCALAPPDATA "Microsoft\Windows\WER\Temp")
    )



    Invoke-GaloreAgedFileCleanup `
    -Roots $dumpRoots `
    -AgeDays 30 `
    -MaxEntries 1500 `
    -MaxDeletes 100 `
    -MaxSeconds 8 `
    -EmptyFolderAgeDays 30



    Invoke-GaloreAgedFileCleanup `
    -Roots $werRoots `
    -AgeDays 30 `
    -MaxEntries 2000 `
    -MaxDeletes 150 `
    -MaxSeconds 10 `
    -EmptyFolderAgeDays 30



    try
    {

        $memoryDump =
        Join-Path `
        $env:SystemRoot `
        "MEMORY.DMP"



        if(
            Test-Path -LiteralPath $memoryDump -PathType Leaf
        )
        {

            $memoryDumpInfo =
            Get-Item `
            -LiteralPath $memoryDump `
            -Force `
            -ErrorAction Stop



            if(
                $memoryDumpInfo.LastWriteTimeUtc -le
                [DateTime]::UtcNow.AddDays(-30)
            )
            {

                Remove-Item `
                -LiteralPath $memoryDump `
                -Force `
                -ErrorAction Stop

            }

        }

    }
    catch
    {



    }

}



function Invoke-GaloreQuickMaintenance {

    param(
        [string]$StateFile
    )

    $quickRoots =
    @(
        Get-GaloreTemporaryRoots
        $script:GaloreApprovedCacheLocations
    )



    Invoke-GaloreAgedFileCleanup `
    -Roots $quickRoots `
    -AgeDays 14 `
    -ZeroByteAgeDays 7 `
    -MaxEntries 5000 `
    -MaxDeletes 250 `
    -MaxSeconds 25 `
    -EmptyFolderAgeDays 7



    Remove-GaloreOldCrashData



    Invoke-GaloreLauncherLogMaintenance `
    -StateFile $StateFile

}



function Initialize-GaloreRecycleBinSupport {

    if(
        "GaloreMaintenance.RecycleBin" -as [type]
    )
    {

        return $true

    }



    try
    {

        Add-Type @"
using System;
using System.Runtime.InteropServices;

namespace GaloreMaintenance
{
    public static class RecycleBin
    {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        private static extern int SHEmptyRecycleBin(
            IntPtr hwnd,
            string rootPath,
            uint flags
        );

        public static void EmptySilently()
        {
            const uint NoConfirmation = 0x00000001;
            const uint NoProgressUI = 0x00000002;
            const uint NoSound = 0x00000004;

            SHEmptyRecycleBin(
                IntPtr.Zero,
                null,
                NoConfirmation | NoProgressUI | NoSound
            );
        }
    }
}
"@ `
        -ErrorAction Stop



        return $true

    }
    catch
    {

        return $false

    }

}



function Invoke-GaloreWeeklyMaintenance {

    try
    {

        if(
            Initialize-GaloreRecycleBinSupport
        )
        {

            [GaloreMaintenance.RecycleBin]::EmptySilently()

        }

    }
    catch
    {



    }

}



function Test-GaloreBrowserProcessRunning {

    param(
        [string[]]$ProcessNames
    )



    foreach(
        $processName in $ProcessNames
    )
    {

        if(
            Get-Process `
            -Name $processName `
            -ErrorAction SilentlyContinue
        )
        {

            return $true

        }

    }



    return $false

}



# ============================================================
# DISCORD AND STEAM CLOSED-APPLICATION CACHES
# ============================================================

function Invoke-GaloreDiscordCacheCleanup {

    if(
        Test-GaloreBrowserProcessRunning `
        -ProcessNames @(
            "Discord"
            "DiscordCanary"
            "DiscordPTB"
        )
    )
    {

        return

    }



    $discordCacheRoots =
    @(
        foreach(
            $discordFolder in @(
                "discord"
                "discordcanary"
                "discordptb"
            )
        )
        {

            foreach(
                $cacheFolder in @(
                    "Cache"
                    "Code Cache"
                    "GPUCache"
                )
            )
            {

                Join-Path `
                (Join-Path $env:APPDATA $discordFolder) `
                $cacheFolder

            }

        }
    )



    Invoke-GaloreAgedFileCleanup `
    -Roots $discordCacheRoots `
    -AgeDays 30 `
    -MaxEntries 8000 `
    -MaxDeletes 600 `
    -MaxSeconds 40 `
    -EmptyFolderAgeDays 30

}



function Get-GaloreSteamHtmlCacheRoots {

    $steamFolders =
    New-Object 'System.Collections.Generic.List[string]'



    if(
        -not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)
    )
    {

        $steamFolders.Add(
            (Join-Path $env:LOCALAPPDATA "Steam")
        )

    }



    if(
        -not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})
    )
    {

        $steamFolders.Add(
            (Join-Path ${env:ProgramFiles(x86)} "Steam")
        )

    }



    if(
        -not [string]::IsNullOrWhiteSpace($env:ProgramFiles)
    )
    {

        $steamFolders.Add(
            (Join-Path $env:ProgramFiles "Steam")
        )

    }



    try
    {

        $registeredSteamPath =
        Get-ItemProperty `
        -LiteralPath "HKCU:\Software\Valve\Steam" `
        -Name "SteamPath" `
        -ErrorAction Stop |
        Select-Object `
        -ExpandProperty "SteamPath"



        if(
            -not [string]::IsNullOrWhiteSpace($registeredSteamPath)
        )
        {

            $steamFolders.Add(
                $registeredSteamPath
            )

        }

    }
    catch
    {



    }



    $cachePaths =
    @(
        foreach(
            $steamFolder in $steamFolders
        )
        {

            Join-Path `
            $steamFolder `
            "config\htmlcache"



            Join-Path `
            $steamFolder `
            "htmlcache"

        }
    )



    return @(
        Get-UniqueGaloreMaintenanceRoots `
        -Paths $cachePaths
    )

}



function Invoke-GaloreSteamCacheCleanup {

    if(
        Test-GaloreBrowserProcessRunning `
        -ProcessNames @(
            "steam"
            "steamwebhelper"
        )
    )
    {

        return

    }



    Invoke-GaloreAgedFileCleanup `
    -Roots (Get-GaloreSteamHtmlCacheRoots) `
    -AgeDays 30 `
    -MaxEntries 8000 `
    -MaxDeletes 600 `
    -MaxSeconds 40 `
    -EmptyFolderAgeDays 30

}



function Invoke-GaloreClosedApplicationCacheMaintenance {

    # Give Discord and Steam helper processes time to finish naturally.

    Start-Sleep `
    -Seconds 10



    Invoke-GaloreDiscordCacheCleanup

    Invoke-GaloreSteamCacheCleanup

}



function Get-GaloreChromiumCacheRoots {

    param(
        [string]$UserDataRoot
    )



    if(
        -not (Test-Path -LiteralPath $UserDataRoot -PathType Container)
    )
    {

        return

    }



    try
    {

        foreach(
            $profile in Get-ChildItem `
            -LiteralPath $UserDataRoot `
            -Directory `
            -Force `
            -ErrorAction SilentlyContinue
        )
        {

            if(
                $profile.Name -ne "Default" -and
                $profile.Name -ne "Guest Profile" -and
                $profile.Name -notlike "Profile *"
            )
            {

                continue

            }



            foreach(
                $relativePath in @(
                    "Cache"
                    "Code Cache"
                    "GPUCache"
                )
            )
            {

                $cachePath =
                Join-Path `
                $profile.FullName `
                $relativePath



                if(
                    Test-Path -LiteralPath $cachePath -PathType Container
                )
                {

                    $cachePath

                }

            }

        }

    }
    catch
    {



    }

}



function Get-GaloreOperaCacheRoots {

    param(
        [string]$ProfileRoot
    )



    if(
        -not (Test-Path -LiteralPath $ProfileRoot -PathType Container)
    )
    {

        return

    }



    foreach(
        $relativePath in @(
            "Cache"
            "Code Cache"
            "GPUCache"
        )
    )
    {

        $cachePath =
        Join-Path `
        $ProfileRoot `
        $relativePath



        if(
            Test-Path -LiteralPath $cachePath -PathType Container
        )
        {

            $cachePath

        }

    }

}



function Get-GaloreBrowserCacheRoots {

    $roots =
    New-Object 'System.Collections.Generic.List[string]'



    if(
        -not (
            Test-GaloreBrowserProcessRunning `
            -ProcessNames @("chrome")
        )
    )
    {

        foreach(
            $path in Get-GaloreChromiumCacheRoots `
            -UserDataRoot (Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data")
        )
        {

            $roots.Add($path)

        }

    }



    if(
        -not (
            Test-GaloreBrowserProcessRunning `
            -ProcessNames @("msedge")
        )
    )
    {

        foreach(
            $path in Get-GaloreChromiumCacheRoots `
            -UserDataRoot (Join-Path $env:LOCALAPPDATA "Microsoft\Edge\User Data")
        )
        {

            $roots.Add($path)

        }

    }



    if(
        -not (
            Test-GaloreBrowserProcessRunning `
            -ProcessNames @("brave")
        )
    )
    {

        foreach(
            $path in Get-GaloreChromiumCacheRoots `
            -UserDataRoot (Join-Path $env:LOCALAPPDATA "BraveSoftware\Brave-Browser\User Data")
        )
        {

            $roots.Add($path)

        }

    }



    if(
        -not (
            Test-GaloreBrowserProcessRunning `
            -ProcessNames @("opera", "opera_gx")
        )
    )
    {

        foreach(
            $operaProfile in @(
                (Join-Path $env:APPDATA "Opera Software\Opera Stable")
                (Join-Path $env:APPDATA "Opera Software\Opera GX Stable")
                (Join-Path $env:LOCALAPPDATA "Opera Software\Opera Stable")
                (Join-Path $env:LOCALAPPDATA "Opera Software\Opera GX Stable")
            )
        )
        {

            foreach(
                $path in Get-GaloreOperaCacheRoots `
                -ProfileRoot $operaProfile
            )
            {

                $roots.Add($path)

            }

        }

    }



    if(
        -not (
            Test-GaloreBrowserProcessRunning `
            -ProcessNames @("firefox")
        )
    )
    {

        $firefoxProfiles =
        Join-Path `
        $env:LOCALAPPDATA `
        "Mozilla\Firefox\Profiles"



        if(
            Test-Path -LiteralPath $firefoxProfiles -PathType Container
        )
        {

            foreach(
                $profile in Get-ChildItem `
                -LiteralPath $firefoxProfiles `
                -Directory `
                -Force `
                -ErrorAction SilentlyContinue
            )
            {

                $cachePath =
                Join-Path `
                $profile.FullName `
                "cache2"



                if(
                    Test-Path -LiteralPath $cachePath -PathType Container
                )
                {

                    $roots.Add($cachePath)

                }

            }

        }

    }



    return @(
        Get-UniqueGaloreMaintenanceRoots `
        -Paths $roots.ToArray()
    )

}



function Invoke-GaloreBrowserCacheCleanup {

    $browserCacheRoots =
    Get-GaloreBrowserCacheRoots



    if(
        $null -eq $browserCacheRoots -or
        $browserCacheRoots.Count -eq 0
    )
    {

        return

    }



    Invoke-GaloreAgedFileCleanup `
    -Roots $browserCacheRoots `
    -AgeDays 60 `
    -MaxEntries 10000 `
    -MaxDeletes 1000 `
    -MaxSeconds 60 `
    -EmptyFolderAgeDays 60

}



function Invoke-GaloreAbandonedInstallerCleanup {

    $installerPredicate =
    {

        param($file)



        $extension =
        $file.Extension.ToLowerInvariant()



        if(
            $extension -in @(
                ".msi"
                ".msp"
                ".msix"
                ".msixbundle"
                ".appx"
                ".appxbundle"
                ".cab"
            )
        )
        {

            return $true

        }



        return $extension -eq ".exe" -and
        $file.BaseName -match "(?i)(setup|installer|install|update)"

    }



    Invoke-GaloreAgedFileCleanup `
    -Roots (Get-GaloreTemporaryRoots) `
    -AgeDays 60 `
    -FilePredicate $installerPredicate `
    -MaxEntries 7500 `
    -MaxDeletes 300 `
    -MaxSeconds 35 `
    -EmptyFolderAgeDays 60

}



function Get-GaloreShortcutRoots {

    $paths =
    @(
        [Environment]::GetFolderPath(
            [Environment+SpecialFolder]::DesktopDirectory
        )
        [Environment]::GetFolderPath(
            [Environment+SpecialFolder]::Programs
        )
        (Join-Path $env:PUBLIC "Desktop")
        (Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs")
    )



    return @(
        Get-UniqueGaloreMaintenanceRoots `
        -Paths $paths
    )

}



function Test-GaloreShortcutTargetMissing {

    param(
        [string]$ShortcutPath,
        $Shell
    )



    try
    {

        $shortcut =
        $Shell.CreateShortcut($ShortcutPath)



        $targetPath =
        [Environment]::ExpandEnvironmentVariables(
            [string]$shortcut.TargetPath
        )



        if(
            [string]::IsNullOrWhiteSpace($targetPath) -or
            $targetPath.StartsWith("\\") -or
            -not [System.IO.Path]::IsPathRooted($targetPath)
        )
        {

            return $false

        }



        $pathRoot =
        [System.IO.Path]::GetPathRoot($targetPath)



        $driveInfo =
        New-Object System.IO.DriveInfo($pathRoot)



        if(
            $driveInfo.DriveType -ne [System.IO.DriveType]::Fixed -or
            -not $driveInfo.IsReady
        )
        {

            return $false

        }



        return -not [System.IO.File]::Exists($targetPath) -and
        -not [System.IO.Directory]::Exists($targetPath)

    }
    catch
    {

        return $false

    }

}



function Invoke-GaloreBrokenShortcutCleanup {

    param(
        [string]$StateFile
    )



    $state =
    Get-GaloreMaintenanceStateSnapshot `
    -StateFile $StateFile `
    -TimeoutMilliseconds 500



    if(
        $null -eq $state
    )
    {

        return $false

    }



    $candidates =
    @{}



    foreach(
        $candidate in $state.BrokenShortcutCandidates
    )
    {

        $candidates[[string]$candidate.Path] =
        Get-GaloreMaintenanceNumber `
        -Object $candidate `
        -PropertyName "FirstSeenRuntimeSeconds"

    }



    $shell =
    $null



    $examined =
    0



    try
    {

        $shell =
        New-Object `
        -ComObject WScript.Shell



        foreach(
            $shortcutRoot in Get-GaloreShortcutRoots
        )
        {

            foreach(
                $shortcut in Get-ChildItem `
                -LiteralPath $shortcutRoot `
                -Filter "*.lnk" `
                -File `
                -Recurse `
                -Force `
                -ErrorAction SilentlyContinue
            )
            {

                if(
                    $examined -ge 1500
                )
                {

                    break

                }



                $examined++



                $shortcutPath =
                $shortcut.FullName



                if(
                    Test-GaloreShortcutTargetMissing `
                    -ShortcutPath $shortcutPath `
                    -Shell $shell
                )
                {

                    if(
                        $candidates.ContainsKey($shortcutPath)
                    )
                    {

                        if(
                            ($state.TotalRuntimeSeconds - $candidates[$shortcutPath]) -ge
                            (7 * 24 * 60 * 60)
                        )
                        {

                            try
                            {

                                Remove-Item `
                                -LiteralPath $shortcutPath `
                                -Force `
                                -ErrorAction Stop



                                $null =
                                $candidates.Remove($shortcutPath)

                            }
                            catch
                            {



                            }

                        }

                    }
                    else
                    {

                        $candidates[$shortcutPath] =
                        $state.TotalRuntimeSeconds

                    }

                }
                else
                {

                    if(
                        $candidates.ContainsKey($shortcutPath)
                    )
                    {

                        $null =
                        $candidates.Remove($shortcutPath)

                    }

                }

            }



            if(
                $examined -ge 1500
            )
            {

                break

            }

        }

    }
    catch
    {



    }
    finally
    {

        if(
            $null -ne $shell
        )
        {

            try
            {

                [System.Runtime.InteropServices.Marshal]::FinalReleaseComObject(
                    $shell
                ) |
                Out-Null

            }
            catch
            {



            }

        }

    }



    $candidateList =
    @(
        foreach(
            $candidatePath in $candidates.Keys
        )
        {

            [pscustomobject]@{
                Path = $candidatePath
                FirstSeenRuntimeSeconds = $candidates[$candidatePath]
            }

        }
    )



    $updatedState =
    Update-GaloreMaintenanceState `
    -StateFile $StateFile `
    -Update {

        param($freshState)

        $freshState.BrokenShortcutCandidates =
        $candidateList

    }



    return $null -ne $updatedState

}



function Invoke-GaloreMonthlyMaintenance {

    param(
        [string]$StateFile
    )



    return Invoke-GaloreBrokenShortcutCleanup `
    -StateFile $StateFile

}



function Invoke-GaloreSixtyDayMaintenance {

    Invoke-GaloreBrowserCacheCleanup

    Invoke-GaloreAbandonedInstallerCleanup

}



function Get-GaloreDueMaintenanceGroups {

    param(
        $State,
        [string]$Mode
    )



    if(
        $Mode -eq "All"
    )
    {

        return @(
            "Quick"
            "Weekly"
            "Monthly"
            "SixtyDay"
        )

    }



    if(
        $Mode -ne "Due"
    )
    {

        return @($Mode)

    }



    $groups =
    New-Object 'System.Collections.Generic.List[string]'



    if(
        ($State.TotalRuntimeSeconds - $State.LastQuickRuntimeSeconds) -ge
        (2 * 60 * 60)
    )
    {

        $groups.Add("Quick")

    }



    if(
        ($State.TotalRuntimeSeconds - $State.LastWeeklyRuntimeSeconds) -ge
        (7 * 24 * 60 * 60)
    )
    {

        $groups.Add("Weekly")

    }



    if(
        ($State.TotalRuntimeSeconds - $State.LastMonthlyRuntimeSeconds) -ge
        (30 * 24 * 60 * 60)
    )
    {

        $groups.Add("Monthly")

    }



    if(
        ($State.TotalRuntimeSeconds - $State.LastSixtyDayRuntimeSeconds) -ge
        (60 * 24 * 60 * 60)
    )
    {

        $groups.Add("SixtyDay")

    }



    return $groups.ToArray()

}



function Set-GaloreMaintenanceGroupCompleted {

    param(
        [string]$StateFile,
        [string]$Group
    )



    $propertyName =
    switch($Group)
    {
        "Quick" { "LastQuickRuntimeSeconds" }
        "Weekly" { "LastWeeklyRuntimeSeconds" }
        "Monthly" { "LastMonthlyRuntimeSeconds" }
        "SixtyDay" { "LastSixtyDayRuntimeSeconds" }
        default { $null }
    }



    if(
        $null -eq $propertyName
    )
    {

        return

    }



    Update-GaloreMaintenanceState `
    -StateFile $StateFile `
    -Update {

        param($state)

        $state.$propertyName =
        $state.TotalRuntimeSeconds

    } |
    Out-Null

}



function Invoke-GaloreMaintenanceWorker {

    param(
        [string]$Mode,
        [string]$StateFile
    )



    if(
        [string]::IsNullOrWhiteSpace($StateFile)
    )
    {

        return

    }



    $workerMutex =
    $null



    $workerMutexOwned =
    $false



    try
    {

        $workerMutex =
        New-Object System.Threading.Mutex(
            $false,
            "Local\GaloreLauncherMaintenanceWorker"
        )



        try
        {

            $workerMutexOwned =
            $workerMutex.WaitOne(
                0,
                $false
            )

        }
        catch [System.Threading.AbandonedMutexException]
        {

            $workerMutexOwned =
            $true

        }



        if(
            -not $workerMutexOwned
        )
        {

            return

        }



        try
        {

            [System.Diagnostics.Process]::GetCurrentProcess().PriorityClass =
            [System.Diagnostics.ProcessPriorityClass]::BelowNormal

        }
        catch
        {



        }



        $state =
        Get-GaloreMaintenanceStateSnapshot `
        -StateFile $StateFile



        if(
            $null -eq $state
        )
        {

            return

        }



        foreach(
            $group in Get-GaloreDueMaintenanceGroups `
            -State $state `
            -Mode $Mode
        )
        {

            $groupCompleted =
            $false



            try
            {

                switch($group)
                {
                    "Quick"
                    {
                        Invoke-GaloreQuickMaintenance `
                        -StateFile $StateFile



                        $groupCompleted =
                        $true
                    }

                    "Weekly"
                    {
                        Invoke-GaloreWeeklyMaintenance



                        $groupCompleted =
                        $true
                    }

                    "Monthly"
                    {
                        $groupCompleted =
                        [bool](
                            Invoke-GaloreMonthlyMaintenance `
                            -StateFile $StateFile
                        )
                    }

                    "SixtyDay"
                    {
                        Invoke-GaloreSixtyDayMaintenance



                        $groupCompleted =
                        $true
                    }

                    "ClosedApplicationCaches"
                    {
                        Invoke-GaloreClosedApplicationCacheMaintenance



                        $groupCompleted =
                        $true
                    }
                }

            }
            catch
            {

                $groupCompleted =
                $false



            }



            if(
                $groupCompleted
            )
            {

                Set-GaloreMaintenanceGroupCompleted `
                -StateFile $StateFile `
                -Group $group

            }

        }

    }
    catch
    {



    }
    finally
    {

        if(
            $workerMutexOwned -and
            $null -ne $workerMutex
        )
        {

            try
            {

                $workerMutex.ReleaseMutex()

            }
            catch
            {



            }

        }



        if(
            $null -ne $workerMutex
        )
        {

            $workerMutex.Dispose()

        }

    }

}



# ============================================================
# WORKER ENTRY POINT
# ============================================================

if(
    -not [string]::IsNullOrWhiteSpace($GaloreMaintenanceWorkerMode)
)
{

    try
    {

        Invoke-GaloreMaintenanceWorker `
        -Mode $GaloreMaintenanceWorkerMode `
        -StateFile $GaloreMaintenanceStateFile

    }
    catch
    {



    }

}
