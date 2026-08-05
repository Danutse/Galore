# ============================================================
# LAUNCHER DOMAIN MODULE
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherDomain"
    LoadOrder = 10
    RequiresModules = @()
    RequiresFunctions = [ordered]@{}
    RequiresTypes = [ordered]@{}
    RequiresVariables = @()
    RequiresFolders = @()
    RequiresFiles = @()
    ProvidesTypes = @(
        "GaloreProgramDefinition"
        "GaloreCategorySlot"
        "GaloreCategory"
        "GaloreCategoryState"
        "GaloreWindowPlacement"
        "GaloreLauncherSettings"
        "GaloreHardwareSnapshot"
    )
}

# ============================================================
# PROGRAM DEFINITION
# ============================================================

class GaloreProgramDefinition {
    [string]$Path
    [string]$Args
    [string]$StatusProcess
    [string]$WindowProcess
    [string]$DisplayName
    [string]$BrowserId
    [string]$BrowserDisplayName

    GaloreProgramDefinition() {
        $this.Path = ""
        $this.Args = ""
        $this.StatusProcess = ""
        $this.WindowProcess = ""
        $this.DisplayName = ""
        $this.BrowserId = ""
        $this.BrowserDisplayName = ""
    }

    [bool] IsConfigured() {
        return -not [string]::IsNullOrWhiteSpace($this.Path)
    }

    [void] ApplyExecutable([string]$Path, [string]$DisplayName) {
        $this.Path = $Path
        $this.DisplayName = $DisplayName
        if([string]::IsNullOrWhiteSpace($Path)) {
            $this.StatusProcess = ""
            $this.WindowProcess = ""
            return
        }
        $processName = [System.IO.Path]::GetFileNameWithoutExtension($Path)
        $this.StatusProcess = $processName
        $this.WindowProcess = $processName
    }

    [void] Clear() {
        $this.Path = ""
        $this.Args = ""
        $this.StatusProcess = ""
        $this.WindowProcess = ""
        $this.DisplayName = ""
        $this.BrowserId = ""
        $this.BrowserDisplayName = ""
    }
}

# ============================================================
# CATEGORY STATE
# ============================================================

class GaloreCategorySlot {
    [string]$Id
    [string]$Path
    [string]$DisplayName
    [bool]$Selected

    GaloreCategorySlot() {
        $this.Id = ""
        $this.Path = ""
        $this.DisplayName = "Empty"
        $this.Selected = $false
    }

    GaloreCategorySlot([string]$Id) {
        $this.Id = $Id
        $this.Path = ""
        $this.DisplayName = "Empty"
        $this.Selected = $false
    }

    [bool] IsConfigured() {
        return -not [string]::IsNullOrWhiteSpace($this.Path)
    }

    [void] Clear() {
        $this.Path = ""
        $this.DisplayName = "Empty"
        $this.Selected = $false
    }
}

class GaloreCategory {
    [string]$Id
    [string]$Name
    [GaloreCategorySlot[]]$Slots

    GaloreCategory() {
        $this.Id = ""
        $this.Name = ""
        $this.Slots = @()
    }

    GaloreCategory([string]$Id, [string]$Name, [GaloreCategorySlot[]]$Slots) {
        $this.Id = $Id
        $this.Name = $Name
        $this.Slots = $Slots
    }
}

class GaloreCategoryState {
    [int]$Version
    [GaloreCategory[]]$Categories

    GaloreCategoryState() {
        $this.Version = 1
        $this.Categories = @()
    }
}

# ============================================================
# LAUNCHER SETTINGS
# ============================================================

class GaloreWindowPlacement {
    [int]$Width
    [int]$Height
    [int]$X
    [int]$Y

    GaloreWindowPlacement() {
        $this.Width = 1100
        $this.Height = 550
        $this.X = 0
        $this.Y = 0
    }

    GaloreWindowPlacement([int]$Width, [int]$Height, [int]$X, [int]$Y) {
        $this.Width = $Width
        $this.Height = $Height
        $this.X = $X
        $this.Y = $Y
    }

    [bool] HasValidSize() {
        return $this.Width -gt 0 -and $this.Height -gt 0
    }
}

class GaloreLauncherSettings {
    [string[]]$Selected
    [int]$Width
    [int]$Height
    [int]$X
    [int]$Y
    [object]$BrowserId
    [System.Collections.IDictionary]$ProgramOverrides

    GaloreLauncherSettings() {
        $this.Selected = @()
        $this.Width = 1100
        $this.Height = 550
        $this.X = 0
        $this.Y = 0
        $this.BrowserId = $null
        $this.ProgramOverrides = [ordered]@{}
    }

    [GaloreWindowPlacement] GetWindowPlacement() {
        return [GaloreWindowPlacement]::new($this.Width, $this.Height, $this.X, $this.Y)
    }
}

# ============================================================
# HARDWARE SNAPSHOT
# ============================================================

class GaloreHardwareSnapshot {
    [double]$CPU
    [double]$RAM
    [double]$GPU
    [double]$GPUTemp

    GaloreHardwareSnapshot() {
        $this.CPU = 0
        $this.RAM = 0
        $this.GPU = 0
        $this.GPUTemp = 0
    }

    GaloreHardwareSnapshot([double]$CPU, [double]$RAM, [double]$GPU, [double]$GPUTemp) {
        $this.CPU = $CPU
        $this.RAM = $RAM
        $this.GPU = $GPU
        $this.GPUTemp = $GPUTemp
    }
}
