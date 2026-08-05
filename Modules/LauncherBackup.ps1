# ============================================================
# BACKUP MODULE
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherBackup"
    LoadOrder = 270
    RequiresModules = @("LauncherLogging", "LauncherSettings")
    RequiresFunctions = [ordered]@{
        "Get-LauncherSettingsFolder" = "LauncherSettings"
        "Write-LauncherDiagnostic" = "LauncherLogging"
    }
    RequiresTypes = [ordered]@{}
    RequiresVariables = @()
    RequiresFolders = @()
    RequiresFiles = @()
    ProvidesTypes = @()
}

# ============================================================
# SETTINGS BACKUP
# ============================================================

function Get-GaloreSettingsBackupFiles {
    $settingsFolder = Get-LauncherSettingsFolder
    @("settings.json", "categories.json", "quick-access.json", "postits.json", "hotkeys.json", "tray-automation.json") | ForEach-Object { Join-Path $settingsFolder $_ } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
}

function Export-GaloreSettingsBackup {
    param([System.Windows.Forms.IWin32Window]$Owner)
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $backupFolder = Join-Path $script:AppRoot "Backups"
    New-Item -ItemType Directory -Path $backupFolder -Force | Out-Null
    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.InitialDirectory = $backupFolder
    $dialog.Filter = "Galore backup (*.zip)|*.zip"
    $dialog.FileName = "Galore-settings-$((Get-Date).ToString('yyyy-MM-dd-HHmmss')).zip"
    try {
        if($dialog.ShowDialog($Owner) -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
        if(Test-Path -LiteralPath $dialog.FileName) { Remove-Item -LiteralPath $dialog.FileName -Force }
        $archive = [System.IO.Compression.ZipFile]::Open($dialog.FileName, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach($file in Get-GaloreSettingsBackupFiles) {
                [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file, [IO.Path]::GetFileName($file), [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
            }
        }
        finally { if($archive) { $archive.Dispose() } }
        [System.Windows.Forms.MessageBox]::Show("Galore settings backup created successfully.", "Galore Launcher", "OK", "Information") | Out-Null
        return $dialog.FileName
    }
    catch {
        Write-LauncherDiagnostic -Exception $_ -Context "Failed to create a Galore settings backup."
        [System.Windows.Forms.MessageBox]::Show("Galore could not create the settings backup.", "Galore Launcher", "OK", "Error") | Out-Null
        return $null
    }
    finally { $dialog.Dispose() }
}
