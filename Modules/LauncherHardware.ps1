# ============================================================
# LAUNCHER HARDWARE MODULE
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherHardware"
    LoadOrder = 60
    RequiresModules = @("LauncherDomain", "LauncherLogging")
    RequiresFunctions = [ordered]@{
        "Write-GaloreLog" = "LauncherLogging"
        "Write-LauncherDiagnostic" = "LauncherLogging"
    }
    RequiresTypes = [ordered]@{
        "GaloreHardwareSnapshot" = "LauncherDomain"
        "GaloreHardwareRuntimeState" = "LauncherDomain"
    }
    RequiresVariables = @("AppRoot")
    RequiresFolders = @()
    RequiresFiles = @()
    ProvidesTypes = @("MemoryCleaner")
}

# ============================================================
# SYSTEM MONITOR CACHE
# ============================================================

$script:GaloreHardwareRuntime = [GaloreHardwareRuntimeState]::new()

# ============================================================
# RAM CLEANER
# ============================================================

if(-not ("MemoryCleaner" -as [type])) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;

public class MemoryCleaner
{

    [DllImport("psapi.dll")]
    public static extern bool EmptyWorkingSet(
        IntPtr hwProc
    );

}
"@
}
function Clear-RAM {
    $runtime = $script:GaloreHardwareRuntime
    if($runtime.Stopping) {
        return
    }
    if($runtime.RAMCleanerPowerShell) {
        $cleanerState = $runtime.RAMCleanerPowerShell.InvocationStateInfo.State
        if($cleanerState -in @(
                [System.Management.Automation.PSInvocationState]::Running,
                [System.Management.Automation.PSInvocationState]::Stopping
            )) {
            return
        }
        try {
            if($runtime.RAMCleanerAsyncResult) {
                $runtime.RAMCleanerPowerShell.EndInvoke($runtime.RAMCleanerAsyncResult) | Out-Null
            }
        } catch {
            Write-LauncherDiagnostic -Exception $_ -Context "The previous RAM-cleanup operation did not complete normally."
        }
        try {
            $runtime.RAMCleanerPowerShell.Dispose()
        } catch {
            Write-LauncherDiagnostic -Exception $_ -Context "The previous RAM-cleanup resources could not be released cleanly."
        }
        $runtime.RAMCleanerPowerShell = $null
        $runtime.RAMCleanerAsyncResult = $null
    }
    $cleaner = [powershell]::Create()
    try {
        $cleaner.AddScript({

        # ==========================
        # TRIM ALL PROCESSES
        # ==========================

        foreach($process in Get-Process) {
            try {
                [MemoryCleaner]::EmptyWorkingSet($process.Handle) | Out-Null
            } catch {
            }
        }

        # ==========================
        # FORCE .NET CLEANUP
        # ==========================

        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()

        # ==========================
        # WINDOWS IDLE CLEANUP
        # ==========================

        Start-Process "rundll32.exe" "advapi32.dll,ProcessIdleTasks" -WindowStyle Hidden
        }) | Out-Null
        $asyncResult = $cleaner.BeginInvoke()
        $runtime.RAMCleanerPowerShell = $cleaner
        $runtime.RAMCleanerAsyncResult = $asyncResult
    } catch {
        try {
            $cleaner.Dispose()
        } catch {
        }
        throw
    }
}

# ============================================================
# BACKGROUND RAM CLEANUP SCHEDULE
# ============================================================

function Initialize-RAMCleanupSchedule {
    $runtime = $script:GaloreHardwareRuntime
    if($runtime.Stopping -or $runtime.RAMCleanupTimer) {
        return
    }
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 3600000
    $timer.Add_Tick({
        try {
            Clear-RAM
            Write-GaloreLog -Level "INFO" -Component "Hardware" -Message "Scheduled hourly RAM cleanup started."
        } catch {
            Write-LauncherDiagnostic -Exception $_ -Context "Scheduled RAM cleanup could not be started."
        }
    }.GetNewClosure())
    $timer.Start()
    $runtime.RAMCleanupTimer = $timer
    Write-GaloreLog -Level "INFO" -Component "Hardware" -Message "Scheduled RAM cleanup enabled every 60 minutes."
}

# ============================================================
# BACKGROUND HARDWARE MONITOR
# ============================================================

function Initialize-HardwareMonitorJob {
    $runtime = $script:GaloreHardwareRuntime
    if($runtime.Stopping) {
        return
    }
    if($runtime.HardwareJob) {
        if($runtime.HardwareJob.State -in @(
                [System.Management.Automation.JobState]::Running,
                [System.Management.Automation.JobState]::NotStarted
            )) {
            return
        }
        $staleJobId = $runtime.HardwareJob.Id
        Stop-Job -Id $staleJobId -ErrorAction SilentlyContinue
        Receive-Job -Id $staleJobId -ErrorAction SilentlyContinue | Out-Null
        Remove-Job -Id $staleJobId -Force -ErrorAction SilentlyContinue
        $runtime.HardwareJob = $null
    }
    $NvidiaSensorReaderPath = Join-Path $AppRoot "Programs\NvidiaSensor\NvidiaSensorReader.exe"
    if(Test-Path -LiteralPath $NvidiaSensorReaderPath -PathType Leaf) {
        Write-GaloreLog -Level "INFO" -Component "Hardware" -Message "NVIDIA sensor reader available."
    } else {
        Write-GaloreLog -Level "WARNING" -Component "Hardware" -Message "NVIDIA sensor reader unavailable; GPU fallback values will be used."
    }
    Write-GaloreLog -Level "INFO" -Component "Hardware" -Message "Background hardware monitor started."
    $hardwareDiagnosticLogPath = Join-Path $AppRoot "Logs\Diagnostics.log"
    $hardwareActivityLogPath = Join-Path $AppRoot "Logs\GaloreLauncher.log"
    $runtime.HardwareJob = Start-Job -ArgumentList $AppRoot,$hardwareDiagnosticLogPath,$hardwareActivityLogPath -ScriptBlock {
    param($monitorRoot, $diagnosticLogPath, $activityLogPath)
    $ErrorActionPreference = "Stop"
    $loggedHardwareErrors = @{}
    while($true) {
        try {
            $cpu = Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average | Select-Object -ExpandProperty Average
            $memory = Get-CimInstance Win32_OperatingSystem
            $ramUsed = $memory.TotalVisibleMemorySize -
            $memory.FreePhysicalMemory
            $ram = ($ramUsed / $memory.TotalVisibleMemorySize) * 100
            $gpu = 0
            $temp = 0
            $reader = Join-Path $monitorRoot "Programs\NvidiaSensor\NvidiaSensorReader.exe"
            if(Test-Path $reader) {
                $gpuData = & $reader
                foreach($line in $gpuData) {
                    if($line -like "GPU=*") {
                        $gpu = $line.Replace("GPU=", "").Trim()
                    }
                    if($line -like "TEMP=*") {
                        $temp = $line.Replace("TEMP=", "").Trim()
                    }
                }
            }
            [PSCustomObject]@{
                CPU = [math]::Round($cpu)
                RAM = [math]::Round($ram)
                GPU = $gpu
                GPUTemp = $temp
            }
        } catch {
            $errorMessage = [string]$_.Exception.Message
            if([string]::IsNullOrWhiteSpace($errorMessage)) {
                $errorMessage = [string]$_
            }
            if(-not $loggedHardwareErrors.ContainsKey($errorMessage)) {
                $loggedHardwareErrors[$errorMessage] = $true
                $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                $lineNumber = $_.InvocationInfo.ScriptLineNumber
                $stackTrace = $_.ScriptStackTrace
                $diagnosticEntry =
@"

============================================================
[$timestamp] ERROR
============================================================

Context:
Background hardware collection failed.

File:
LauncherHardware.ps1 background job

Line:
$lineNumber

Error:
$errorMessage

Stack:
$stackTrace

============================================================

"@
                try {
                    Add-Content -Path $diagnosticLogPath -Value $diagnosticEntry -ErrorAction Stop
                } catch {
                }
                try {
                    $activityEntry = "[$timestamp] ERROR [LauncherHardware] Background hardware collection failed. $errorMessage"
                    Add-Content -LiteralPath $activityLogPath -Value $activityEntry -Encoding UTF8 -ErrorAction Stop
                } catch {
                }
            }
        }
        Start-Sleep -Seconds 1
    }
    }
    $runtime.HardwareFailureLogged = $false
}

# ============================================================
# HARDWARE CACHE READER
# ============================================================

function ConvertTo-GaloreHardwareNumber {
    param($Value)
    $number = 0.0
    $parsed = $null -ne $Value -and (
        [double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$number) -or
        [double]::TryParse([string]$Value, [ref]$number)
    )
    if($parsed -and -not [double]::IsNaN($number) -and -not [double]::IsInfinity($number)) {
        return $number
    }
    return 0.0
}

function ConvertTo-GaloreHardwareSnapshot {
    param($Data)
    if($null -eq $Data) {
        return [GaloreHardwareSnapshot]::new()
    }
    return [GaloreHardwareSnapshot]::new(
        (ConvertTo-GaloreHardwareNumber $Data.CPU),
        (ConvertTo-GaloreHardwareNumber $Data.RAM),
        (ConvertTo-GaloreHardwareNumber $Data.GPU),
        (ConvertTo-GaloreHardwareNumber $Data.GPUTemp)
    )
}

function Initialize-HardwareCacheReader {
    $runtime = $script:GaloreHardwareRuntime
    if($runtime.Stopping) {
        return
    }
    Initialize-HardwareMonitorJob
    if($runtime.HardwareReadTimer) {
        if(-not $runtime.HardwareReadTimer.Enabled) {
            $runtime.HardwareReadTimer.Start()
        }
        return
    }
    $runtime.HardwareReadTimer = New-Object System.Windows.Forms.Timer
    $runtime.HardwareReadTimer.Interval = 100
    $runtime.HardwareReadTimer.Add_Tick({
        $runtime = $this.Tag
        if(-not $runtime -or $runtime.Stopping -or -not $runtime.HardwareJob) {
            return
        }
        try {
            if($runtime.HardwareJob.State -notin @(
                    [System.Management.Automation.JobState]::Running,
                    [System.Management.Automation.JobState]::NotStarted
                )) {
                Initialize-HardwareMonitorJob
                if(-not $runtime.HardwareJob -or $runtime.HardwareJob.State -notin @(
                        [System.Management.Automation.JobState]::Running,
                        [System.Management.Automation.JobState]::NotStarted
                    )) {
                    return
                }
            }
            $data = Receive-Job $runtime.HardwareJob -ErrorAction Stop
            if($data) {
                $latest = $data | Select-Object -Last 1
                $runtime.SystemUsageCache = ConvertTo-GaloreHardwareSnapshot $latest
            }
        } catch {
            if(-not $runtime.HardwareFailureLogged) {
                $runtime.HardwareFailureLogged = $true
                Write-LauncherDiagnostic -Exception $_ -Context "Hardware monitor data could not be read."
            }
        }
    })
    $runtime.HardwareReadTimer.Tag = $runtime
    $runtime.HardwareReadTimer.Start()
}

# ============================================================
# LABEL TEXT UPDATE
# ============================================================

function Update-LabelText {
    param($Label, $Text)
    if($Label.Text -ne $Text) {
        $Label.Text = $Text
    }
}

# ============================================================
# SYSTEM MONITOR DISPLAY TIMER
# ============================================================

function Initialize-SystemMonitorDisplay {
    param($CPULabel, $RAMLabel, $GPULabel, $GPUTempLabel, $Form)
    $runtime = $script:GaloreHardwareRuntime
    $systemTimer = $runtime.SystemTimer
    if(-not $systemTimer) {
        $systemTimer = New-Object System.Windows.Forms.Timer
        $systemTimer.Interval = 250
        $systemTimer.Add_Tick({
            $state = $this.Tag
            if(-not $state -or -not $state.Form -or $state.Form.IsDisposed -or -not $state.Form.Visible) {
                return
            }
            if($state.Form.Visible) {
                $usage = $state.Runtime.SystemUsageCache
                $newCPU = "CPU : " + $usage.CPU + "%"
                $newRAM = "RAM : " + $usage.RAM + "%"
                $newGPU = "GPU : " + $usage.GPU + "%"
                $newTemp = "GPU TEMP : " + $usage.GPUTemp + " C"
                Update-LabelText $state.CPULabel $newCPU
                Update-LabelText $state.RAMLabel $newRAM
                Update-LabelText $state.GPULabel $newGPU
                Update-LabelText $state.GPUTempLabel $newTemp
            }
        })
        $runtime.SystemTimer = $systemTimer
    }
    $systemTimer.Tag = [pscustomobject]@{
        Runtime = $runtime
        CPULabel = $CPULabel
        RAMLabel = $RAMLabel
        GPULabel = $GPULabel
        GPUTempLabel = $GPUTempLabel
        Form = $Form
    }
    $systemTimer.Start()
}

# ============================================================
# STOP HARDWARE MONITOR
# ============================================================

function Stop-HardwareMonitor {
    $runtime = $script:GaloreHardwareRuntime
    $runtime.Stopping = $true
    if($runtime.RAMCleanupTimer) {
        try {
            $runtime.RAMCleanupTimer.Stop()
        } catch {
        } finally {
            try {
                $runtime.RAMCleanupTimer.Dispose()
            } catch {
            }
            $runtime.RAMCleanupTimer = $null
        }
    }
    if($runtime.HardwareReadTimer) {
        try {
            $runtime.HardwareReadTimer.Stop()
            $runtime.HardwareReadTimer.Tag = $null
        } catch {
        } finally {
            try {
                $runtime.HardwareReadTimer.Dispose()
            } catch {
            }
            $runtime.HardwareReadTimer = $null
        }
    }
    if($runtime.SystemTimer) {
        try {
            $runtime.SystemTimer.Stop()
            $runtime.SystemTimer.Tag = $null
        } catch {
        } finally {
            try {
                $runtime.SystemTimer.Dispose()
            } catch {
            }
            $runtime.SystemTimer = $null
        }
    }
    if($runtime.HardwareJob) {
        Stop-Job -Job $runtime.HardwareJob -ErrorAction SilentlyContinue
        Receive-Job -Job $runtime.HardwareJob -ErrorAction SilentlyContinue | Out-Null
        Remove-Job -Job $runtime.HardwareJob -Force -ErrorAction SilentlyContinue
        $runtime.HardwareJob = $null
    }
    if($runtime.RAMCleanerPowerShell) {
        try {
            $runtime.RAMCleanerPowerShell.Stop()
        } catch {
        }
        try {
            if($runtime.RAMCleanerAsyncResult) {
                $runtime.RAMCleanerPowerShell.EndInvoke($runtime.RAMCleanerAsyncResult) | Out-Null
            }
        } catch {
        } finally {
            try {
                $runtime.RAMCleanerPowerShell.Dispose()
            } catch {
            }
            $runtime.RAMCleanerPowerShell = $null
            $runtime.RAMCleanerAsyncResult = $null
        }
    }
}
