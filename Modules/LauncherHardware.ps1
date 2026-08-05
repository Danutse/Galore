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
    }
    RequiresVariables = @("AppRoot")
    RequiresFolders = @()
    RequiresFiles = @()
    ProvidesTypes = @("MemoryCleaner")
}

# ============================================================
# SYSTEM MONITOR CACHE
# ============================================================

$script:SystemUsageCache = [GaloreHardwareSnapshot]::new()

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
$script:RAMCleanerPowerShell = $null
$script:RAMCleanerAsyncResult = $null
$script:RAMCleanupTimer = $null

function Clear-RAM {
    if($script:RAMCleanerPowerShell) {
        $cleanerState = $script:RAMCleanerPowerShell.InvocationStateInfo.State
        if($cleanerState -eq [System.Management.Automation.PSInvocationState]::Running) {
            return
        }
        try {
            if($script:RAMCleanerAsyncResult) {
                $script:RAMCleanerPowerShell.EndInvoke($script:RAMCleanerAsyncResult) | Out-Null
            }
        } catch {
            Write-LauncherDiagnostic -Exception $_ -Context "The previous RAM-cleanup operation did not complete normally."
        }
        $script:RAMCleanerPowerShell.Dispose()
        $script:RAMCleanerPowerShell = $null
        $script:RAMCleanerAsyncResult = $null
    }
    $script:RAMCleanerPowerShell = [powershell]::Create()
    $script:RAMCleanerPowerShell.AddScript({

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
    $script:RAMCleanerAsyncResult = $script:RAMCleanerPowerShell.BeginInvoke()
}

# ============================================================
# BACKGROUND RAM CLEANUP SCHEDULE
# ============================================================

function Initialize-RAMCleanupSchedule {
    if($script:RAMCleanupTimer -and -not $script:RAMCleanupTimer.IsDisposed) {
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
    $script:RAMCleanupTimer = $timer
    Write-GaloreLog -Level "INFO" -Component "Hardware" -Message "Scheduled RAM cleanup enabled every 60 minutes."
}

# ============================================================
# BACKGROUND HARDWARE MONITOR
# ============================================================

$script:HardwareJob = $null

function Initialize-HardwareMonitorJob {
    if($script:HardwareJob) {
        if($script:HardwareJob.State -eq [System.Management.Automation.JobState]::Running) {
            return
        }
        $staleJobId = $script:HardwareJob.Id
        Stop-Job -Id $staleJobId -ErrorAction SilentlyContinue
        Receive-Job -Id $staleJobId -ErrorAction SilentlyContinue | Out-Null
        Remove-Job -Id $staleJobId -Force -ErrorAction SilentlyContinue
        $script:HardwareJob = $null
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
    $script:HardwareJob = Start-Job -ArgumentList $AppRoot,$hardwareDiagnosticLogPath,$hardwareActivityLogPath -ScriptBlock {
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
    Initialize-HardwareMonitorJob
    if($script:HardwareReadTimer -and -not $script:HardwareReadTimer.IsDisposed) {
        if(-not $script:HardwareReadTimer.Enabled) {
            $script:HardwareReadTimer.Start()
        }
        return
    }
    $script:HardwareReadTimer = New-Object System.Windows.Forms.Timer
    $script:HardwareReadTimer.Interval = 100
    $script:HardwareReadTimer.Add_Tick({
        $data = Receive-Job $script:HardwareJob
        if($data) {
            $latest = $data | Select-Object -Last 1
            $script:SystemUsageCache = ConvertTo-GaloreHardwareSnapshot $latest
        }
    })
    $script:HardwareReadTimer.Start()
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
    $systemTimer = New-Object System.Windows.Forms.Timer
    $systemTimer.Interval = 250
    $systemTimer.Add_Tick({
        if($Form.Visible) {
            $usage = $script:SystemUsageCache
            $newCPU = "CPU : " + $usage.CPU + "%"
            $newRAM = "RAM : " + $usage.RAM + "%"
            $newGPU = "GPU : " + $usage.GPU + "%"
            $newTemp = "GPU TEMP : " + $usage.GPUTemp + " C"
            Update-LabelText $CPULabel $newCPU
            Update-LabelText $RAMLabel $newRAM
            Update-LabelText $GPULabel $newGPU
            Update-LabelText $GPUTempLabel $newTemp
        }
    })
    $systemTimer.Start()
    $script:SystemTimer = $systemTimer
}

# ============================================================
# STOP HARDWARE MONITOR
# ============================================================

function Stop-HardwareMonitor {
    if($script:RAMCleanupTimer) {
        $script:RAMCleanupTimer.Stop()
        $script:RAMCleanupTimer.Dispose()
        $script:RAMCleanupTimer = $null
    }
    if($script:HardwareReadTimer) {
        $script:HardwareReadTimer.Stop()
        $script:HardwareReadTimer.Dispose()
        $script:HardwareReadTimer = $null
    }
    if($script:SystemTimer) {
        $script:SystemTimer.Stop()
        $script:SystemTimer.Dispose()
        $script:SystemTimer = $null
    }
    if($script:HardwareJob) {
        Stop-Job -Job $script:HardwareJob -ErrorAction SilentlyContinue
        Receive-Job -Job $script:HardwareJob -ErrorAction SilentlyContinue | Out-Null
        Remove-Job -Job $script:HardwareJob -Force -ErrorAction SilentlyContinue
        $script:HardwareJob = $null
    }
    if($script:RAMCleanerPowerShell) {
        try {
            $script:RAMCleanerPowerShell.Stop()
        } catch {
        }
        $script:RAMCleanerPowerShell.Dispose()
        $script:RAMCleanerPowerShell = $null
        $script:RAMCleanerAsyncResult = $null
    }
}
