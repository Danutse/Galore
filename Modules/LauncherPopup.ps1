# ============================================================
# LAUNCHER POPUP MODULE
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherPopup"
    LoadOrder = 290
    RequiresModules = @("LauncherDomain")
    RequiresFunctions = [ordered]@{}
    RequiresTypes = [ordered]@{
        "GalorePopupRuntimeState" = "LauncherDomain"
    }
    RequiresVariables = @()
    RequiresFolders = @()
    RequiresFiles = @()
    ProvidesTypes = @()
}

$script:GalorePopupRuntime = [GalorePopupRuntimeState]::new()

# ============================================================
# POPUP ANIMATION
# ============================================================

function Start-GalorePopupFade {
    param([System.Windows.Forms.Form]$Form, [double]$TargetOpacity, [switch]$CloseOnComplete)
    if($null -eq $Form -or $Form.IsDisposed -or $null -eq $Form.Tag) {
        return
    }
    $popupContext = $Form.Tag
    if($popupContext.FadeTimer) {
        $popupContext.FadeTimer.Stop()
        $popupContext.FadeTimer.Tag = $null
        $popupContext.FadeTimer.Dispose()
        $popupContext.FadeTimer = $null
    }
    $fadeTimer = New-Object System.Windows.Forms.Timer
    $fadeTimer.Interval = 15
    $fadeTimer.Tag = [pscustomobject]@{
        Form = $Form
        PopupContext = $popupContext
        StartOpacity = [double]$Form.Opacity
        TargetOpacity = [Math]::Max(0.0, [Math]::Min(1.0, $TargetOpacity))
        Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        CloseOnComplete = [bool]$CloseOnComplete
    }
    $fadeTimer.Add_Tick({
        $timer = $this
        $state = $timer.Tag
        if($null -eq $state -or $null -eq $state.Form -or $state.Form.IsDisposed) {
            $timer.Stop()
            $timer.Tag = $null
            $timer.Dispose()
            return
        }
        $progress = [Math]::Min(1.0, ($state.Stopwatch.Elapsed.TotalMilliseconds / 180))
        $easedProgress = $progress * $progress * (3 - (2 * $progress))
        $state.Form.Opacity = $state.StartOpacity + (($state.TargetOpacity - $state.StartOpacity) * $easedProgress)
        if($progress -lt 1) {
            return
        }
        $state.Form.Opacity = $state.TargetOpacity
        $timer.Stop()
        $timer.Tag = $null
        $timer.Dispose()
        $state.PopupContext.FadeTimer = $null
        if($state.CloseOnComplete -and -not $state.Form.IsDisposed) {
            $state.Form.Close()
        }
    })
    $popupContext.FadeTimer = $fadeTimer
    $fadeTimer.Start()
}

function Close-GalorePopupAnimated {
    param([System.Windows.Forms.Form]$Form)
    if($null -eq $Form -or $Form.IsDisposed -or $null -eq $Form.Tag) {
        return
    }
    $popupContext = $Form.Tag
    if($popupContext.IsClosing) {
        return
    }
    $popupContext.IsClosing = $true
    Start-GalorePopupFade -Form $Form -TargetOpacity 0 -CloseOnComplete
}

function Stop-GalorePopupFade {
    param([System.Windows.Forms.Form]$Form)
    if($null -eq $Form -or $Form.IsDisposed -or $null -eq $Form.Tag) {
        return
    }
    $popupContext = $Form.Tag
    if($popupContext.FadeTimer) {
        try {
            $popupContext.FadeTimer.Stop()
            $popupContext.FadeTimer.Tag = $null
            $popupContext.FadeTimer.Dispose()
        } catch {
        } finally {
            $popupContext.FadeTimer = $null
        }
    }
}

function Clear-GalorePopupOwner {
    param($Runtime, [string]$PropertyName, $Form)
    if($null -eq $Runtime -or [string]::IsNullOrWhiteSpace($PropertyName) -or $null -eq $Form) {
        return
    }
    if([object]::ReferenceEquals($Runtime.$PropertyName, $Form)) {
        $Runtime.$PropertyName = $null
    }
}
