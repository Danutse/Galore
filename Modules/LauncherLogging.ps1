# ============================================================
# LAUNCHER LOGGING MODULE
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherLogging"
    LoadOrder = 20
    RequiresModules = @()
    RequiresFunctions = [ordered]@{}
    RequiresTypes = [ordered]@{}
    RequiresVariables = @("AppRoot")
    RequiresFolders = @()
    RequiresFiles = @()
    ProvidesTypes = @()
}

# ============================================================
# LOGGER SYSTEM
# ============================================================

$LogFolder = Join-Path $AppRoot "Logs"
if(-not (Test-Path $LogFolder)) {
    New-Item -ItemType Directory -Path $LogFolder | Out-Null
}
$script:LogFile = Join-Path $LogFolder "Crash.log"
$script:DiagnosticLogFile = Join-Path $LogFolder "Diagnostics.log"
$script:GaloreActivityLogFile = Join-Path $LogFolder "GaloreLauncher.log"
$LegacyGaloreActivityLogFile = Join-Path $LogFolder "Galore.log"
if(-not (Test-Path -LiteralPath $script:GaloreActivityLogFile -PathType Leaf) -and (Test-Path -LiteralPath $LegacyGaloreActivityLogFile -PathType Leaf)) {
    try {
        Move-Item -LiteralPath $LegacyGaloreActivityLogFile -Destination $script:GaloreActivityLogFile -ErrorAction Stop
    } catch {
    }
}
$script:LauncherFatalReported = $false

# ============================================================
# WRITE GALORE ACTIVITY LOG
# ============================================================

function Write-GaloreLog {
    param([ValidateSet("INFO", "WARNING", "ERROR")] [string]$Level = "INFO", [string]$Message = "", [object]$Exception = $null, [string]$Context = "", [string]$Component = "")
    try {
        $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $invocationInfo = $null
        if($Exception) {
            $invocationInfo = $Exception.InvocationInfo
            if([string]::IsNullOrWhiteSpace($Message)) {
                $Message = if($Exception.Exception) {
                    $Exception.Exception.Message
                } else {
                    [string]$Exception
                }
            }
        }
        if([string]::IsNullOrWhiteSpace($Message)) {
            return
        }
        if([string]::IsNullOrWhiteSpace($Component)) {
            $Component = if($invocationInfo -and $invocationInfo.ScriptName) {
                [System.IO.Path]::GetFileNameWithoutExtension($invocationInfo.ScriptName)
            } else {
                "Launcher"
            }
        }
        $singleLineMessage = ($Message -replace "\s+", " ").Trim()
        $entry = "[$timestamp] $Level [$Component] $singleLineMessage"
        try {
            Add-Content -LiteralPath $script:GaloreActivityLogFile -Value $entry -Encoding UTF8 -ErrorAction Stop
        } catch {
        }
        if($Exception) {
            $file = if($invocationInfo -and $invocationInfo.ScriptName) {
                $invocationInfo.ScriptName
            } else {
                "<unknown>"
            }
            $line = if($invocationInfo) {
                $invocationInfo.ScriptLineNumber
            } else {
                0
            }
            $stack = if($Exception.ScriptStackTrace) {
                $Exception.ScriptStackTrace
            } elseif($Exception.Exception -and $Exception.Exception.StackTrace) {
                $Exception.Exception.StackTrace
            } else {
                "<none>"
            }
            if([string]::IsNullOrWhiteSpace($Context)) {
                $Context = "No additional context."
            }
            $detailEntry =
@"

============================================================
[$timestamp] $Level
============================================================

Context:
$Context

Module:
$Component

File:
$file

Line:
$line

Error:
$Message

Stack:
$stack

============================================================

"@
            try {
                Add-Content -LiteralPath $script:DiagnosticLogFile -Value $detailEntry -Encoding UTF8 -ErrorAction Stop
            } catch {
            }
        }
        if($script:LauncherRunningAsScript) {
            $foregroundColor = switch($Level) {
                "WARNING" { "Yellow" }
                "ERROR" { "Red" }
                default { "DarkGray" }
            }
            Write-Host $entry -ForegroundColor $foregroundColor
        }
    } catch {
    }
}

# ============================================================
# SHOW LAUNCHER CRASH
# ============================================================

function Show-LauncherCrash {
    param([string]$Entry, [string]$Context, [string]$Message)
    if($script:LauncherRunningAsScript) {
        try {
            Write-Host ""
            Write-Host $Entry -ForegroundColor Red
            Write-Host "Crash log: $script:LogFile" -ForegroundColor Yellow
        } catch {
        }
    }
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $PopupMessage =
@"
Galore Launcher encountered a fatal error and must close.

Context:
$Context

Error:
$Message

Crash report:
$script:LogFile
"@
        [System.Windows.Forms.MessageBox]::Show($PopupMessage, "Galore Launcher - Fatal Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    } catch {
    }
}

# ============================================================
# WRITE LAUNCHER LOG
# ============================================================

function Write-LauncherLog {
    param($Exception, [string]$Context = "", [ValidateSet("ERROR", "WARNING")] [string]$Level = "ERROR")
    $Entry = [string]$Exception
    $Message = [string]$Exception
    if($Level -eq "ERROR") {
        if($script:LauncherFatalReported) {
            return
        }
        $script:LauncherFatalReported = $true
    }
    try {
        $Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $InvocationInfo = $Exception.InvocationInfo
        $File = if($InvocationInfo -and $InvocationInfo.ScriptName) {
            $InvocationInfo.ScriptName
        } else {
            "<unknown>"
        }
        $Line = if($InvocationInfo) {
            $InvocationInfo.ScriptLineNumber
        } else {
            0
        }
        $Message = if($Exception.Exception) {
            $Exception.Exception.Message
        } else {
            [string]$Exception
        }
        $Stack = if($Exception.ScriptStackTrace) {
            $Exception.ScriptStackTrace
        } elseif($Exception.Exception -and $Exception.Exception.StackTrace) {
            $Exception.Exception.StackTrace
        } else {
            "<none>"
        }
        if([string]::IsNullOrWhiteSpace($Context)) {
            $Context = "No additional context."
        }
        $TargetLog = if($Level -eq "WARNING") {
            $script:DiagnosticLogFile
        } else {
            $script:LogFile
        }
        $Entry =
@"

============================================================
[$Timestamp] $Level
============================================================

Context:
$Context

File:
$File

Line:
$Line

Error:
$Message

Stack:
$Stack

============================================================

"@
        Add-Content -Path $TargetLog -Value $Entry -ErrorAction Stop
        Write-GaloreLog -Level $Level -Component "Diagnostics" -Message "$Context $Message"
    } catch {
    } finally {
        if($Level -eq "ERROR") {
            Show-LauncherCrash -Entry $Entry -Context $Context -Message $Message
        }
    }
}

# ============================================================
# WRITE RECOVERABLE DIAGNOSTIC
# ============================================================

function Write-LauncherDiagnostic {
    param($Exception, [string]$Context)
    Write-GaloreLog -Level "ERROR" -Exception $Exception -Context $Context
}
