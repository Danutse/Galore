# ============================================================
# LAUNCHER SEARCH MODULE
# ============================================================

$GaloreModuleManifest = [ordered]@{
    Name = "LauncherSearch"
    LoadOrder = 60
    RequiresModules = @("LauncherLogging")
    RequiresFunctions = [ordered]@{
        "Write-LauncherDiagnostic" = "LauncherLogging"
    }
    RequiresTypes = [ordered]@{}
    RequiresVariables = @()
    RequiresFolders = @()
    RequiresFiles = @()
    ProvidesTypes = @()
}

# ==========================
# SEARCH RESULT HELPER
# ==========================

function New-SearchResult {
    param([string]$Name, [string]$Path, [string]$Type)
    $result = @{
        Name = $Name
        Path = $Path
        Type = $Type
    }
    return $result
}

# ==========================
# WINDOWS SEARCH ENGINE
# ==========================

function Invoke-WindowsSearch {
    param([string]$Query)
    $results = New-Object System.Collections.ArrayList
    $connection = $null
    $command = $null
    $reader = $null
    if([string]::IsNullOrWhiteSpace($Query)) {
        return $results
    }
    try {
        $connection = New-Object System.Data.OleDb.OleDbConnection
        $connection.ConnectionString = "Provider=Search.CollatorDSO;Extended Properties='Application=Windows'"
        $connection.Open()
        $command = $connection.CreateCommand()
        $safeQuery = $Query.Replace("'", "''")
        $command.CommandText =
        "
        SELECT TOP 25

        System.ItemPathDisplay

        FROM SYSTEMINDEX

        WHERE

System.ItemName LIKE '%$safeQuery%'

        "
        $reader = $command.ExecuteReader()
        while($reader.Read()) {
            $path = $reader.GetValue(0)
            if([string]::IsNullOrWhiteSpace($path)) {
                continue
            }
            $path = $path.Replace("\Utilisateurs\", "\Users\")
            if(Test-Path $path) {
                try {
                    $item = Get-Item -LiteralPath $path -ErrorAction Stop
                } catch {
                    continue
                }

                # ==========================
                # FILTER ALLOWED TYPES
                # ==========================

                $extension = $item.Extension
                if($extension -ne ".exe" -and $extension -ne ".lnk" -and $extension -notin @(".png", ".jpg", ".jpeg", ".gif", ".bmp", ".tif", ".tiff", ".webp", ".ico", ".heic", ".avif") -and -not $item.PSIsContainer) {
                    continue
                }
                if($item.PSIsContainer) {
                    $type = "Folder"
                } elseif($item.Extension -eq ".exe") {
                    $type = "EXE"
                } elseif($item.Extension -eq ".lnk") {
                    $type = "Shortcut"
                } elseif($item.Extension -in @(".png", ".jpg", ".jpeg", ".gif", ".bmp", ".tif", ".tiff", ".webp", ".ico", ".heic", ".avif")) {
                    $type = "Image"
                }
                $result = New-SearchResult -Name $item.Name -Path $item.FullName -Type $type
                $results.Add($result) | Out-Null
            }
        }
        $script:SearchDiagnosticLogged = $false
    } catch {
        if(-not $script:SearchDiagnosticLogged) {
            Write-LauncherDiagnostic -Exception $_ -Context "Windows Search failed for query '$Query'."
            $script:SearchDiagnosticLogged = $true
        }
    } finally {
        if($reader) {
            try {
                $reader.Close()
                $reader.Dispose()
            } catch {
            }
        }
        if($command) {
            try {
                $command.Dispose()
            } catch {
            }
        }
        if($connection) {
            try {
                $connection.Close()
                $connection.Dispose()
            } catch {
            }
        }
    }
    return $results
}

# ==========================
# GET SEARCH RESULTS
# ==========================

function Get-SearchResults {
    param([string]$query)
    $SearchResults = New-Object System.Collections.ArrayList

    # ==========================
    # WINDOWS FILE SEARCH
    # ==========================

    $WindowsResults = Invoke-WindowsSearch $query
    foreach($item in $WindowsResults) {
        $SearchResults.Add($item) | Out-Null
    }

    # ==========================
    # SEARCH INSTALLED APPS
    # ==========================

    $AppResults = Get-StartApps | Where-Object {
        $_.Name -like "*$query*"
    }
    foreach($app in $AppResults) {
        $result = New-SearchResult -Name $app.Name -Path "shell:AppsFolder\$($app.AppID)" -Type "Application"
        $SearchResults.Add($result) | Out-Null
    }
    $SearchResults = $SearchResults | Select-Object -First 25
    return $SearchResults
}
