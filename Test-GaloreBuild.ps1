param(
    [string]$AppRoot = $PSScriptRoot,

    [switch]$Compile,

    [switch]$SkipUnitTests
)



$ErrorActionPreference =
"Stop"



$script:BuildResults =
New-Object System.Collections.ArrayList



function Add-GaloreBuildResult {

    param(
        [ValidateSet(
            "PASS",
            "WARNING",
            "FAIL"
        )]
        [string]$Status,

        [string]$Name,

        [string]$Message
    )



    $result =
    [PSCustomObject]@{
        Status = $Status
        Name = $Name
        Message = $Message
    }



    $null =
    $script:BuildResults.Add($result)



    $foregroundColor =
    switch($Status)
    {
        "PASS" { "Green" }
        "WARNING" { "Yellow" }
        default { "Red" }
    }



    Write-Host `
    ("[{0}] {1}: {2}" -f $Status, $Name, $Message) `
    -ForegroundColor $foregroundColor



}



function Get-GaloreLoaderModuleFiles {

    param(
        $MainAst
    )



    $assignment =
    $MainAst.FindAll(
        {
            param($node)

            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $node.Left.VariablePath.UserPath -eq "GaloreModuleFiles"
        },
        $true
    ) |
    Select-Object -First 1



    if($null -eq $assignment)
    {

        throw "The Galore module loader list could not be found."

    }



    $moduleFiles =
    @(
        $assignment.Right.FindAll(
            {
                param($node)

                $node -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                $node.Value -like "*.ps1"
            },
            $true
        ) |
        ForEach-Object {
            $_.Value
        }
    )



    if($moduleFiles.Count -eq 0)
    {

        throw "The Galore module loader list is empty."

    }



    return $moduleFiles



}



function Get-GaloreDependencyValidator {

    param(
        $MainAst
    )



    $validatorAst =
    $MainAst.FindAll(
        {
            param($node)

            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq "Test-GaloreModuleDependencies"
        },
        $true
    ) |
    Select-Object -First 1



    if($null -eq $validatorAst)
    {

        throw "Test-GaloreModuleDependencies was not found in GaloreLauncher.ps1."

    }



    return [scriptblock]::Create(
        $validatorAst.Extent.Text
    )



}



function Test-GaloreJsonFile {

    param(
        [string]$Path,

        [string]$Name
    )



    if(
        -not (
            Test-Path `
            -LiteralPath $Path `
            -PathType Leaf
        )
    )
    {

        Add-GaloreBuildResult `
        -Status "WARNING" `
        -Name $Name `
        -Message "File does not exist yet."



        return

    }



    try
    {

        Get-Content `
        -LiteralPath $Path `
        -Raw `
        -ErrorAction Stop |
        ConvertFrom-Json `
        -ErrorAction Stop |
        Out-Null



        Add-GaloreBuildResult `
        -Status "PASS" `
        -Name $Name `
        -Message "Valid JSON."

    }
    catch
    {

        Add-GaloreBuildResult `
        -Status "FAIL" `
        -Name $Name `
        -Message $_.Exception.Message

    }



}



$AppRoot =
(Resolve-Path `
-LiteralPath $AppRoot `
-ErrorAction Stop).Path



$ModuleRoot =
Join-Path `
$AppRoot `
"Modules"



$ResourceRoot =
Join-Path `
$AppRoot `
"resources"



$LogRoot =
Join-Path `
$AppRoot `
"Logs"



$MainScript =
Join-Path `
$ModuleRoot `
"GaloreLauncher.ps1"



$ExecutablePath =
Join-Path `
$AppRoot `
"GaloreLauncher.exe"



$loadedModules =
$null



try
{

    foreach(
        $requiredFolder in @(
            $ModuleRoot,
            $ResourceRoot,
            $LogRoot
        )
    )
    {

        if(
            -not (
                Test-Path `
                -LiteralPath $requiredFolder `
                -PathType Container
            )
        )
        {

            Add-GaloreBuildResult `
            -Status "FAIL" `
            -Name "Required folder" `
            -Message "Missing: $requiredFolder"

        }

    }



    if(
        Test-Path `
        -LiteralPath $MainScript `
        -PathType Leaf
    )
    {

        Add-GaloreBuildResult `
        -Status "PASS" `
        -Name "Main script" `
        -Message "Found GaloreLauncher.ps1."

    }
    else
    {

        throw "GaloreLauncher.ps1 is missing: $MainScript"

    }



    $parseFailures =
    New-Object System.Collections.ArrayList



    $scriptFiles =
    Get-ChildItem `
    -LiteralPath $ModuleRoot `
    -Filter "*.ps1" `
    -File `
    -ErrorAction Stop



    foreach($scriptFile in $scriptFiles)
    {

        $tokens =
        $null



        $parseErrors =
        $null



        [System.Management.Automation.Language.Parser]::ParseFile(
            $scriptFile.FullName,
            [ref]$tokens,
            [ref]$parseErrors
        ) | Out-Null



        foreach($parseError in $parseErrors)
        {

            $null =
            $parseFailures.Add(
                "$($scriptFile.Name): $($parseError.Message)"
            )

        }

    }



    if($parseFailures.Count -eq 0)
    {

        Add-GaloreBuildResult `
        -Status "PASS" `
        -Name "PowerShell syntax" `
        -Message "$($scriptFiles.Count) PowerShell source scripts parsed successfully."

    }
    else
    {

        foreach($parseFailure in $parseFailures)
        {

            Add-GaloreBuildResult `
            -Status "FAIL" `
            -Name "PowerShell syntax" `
            -Message $parseFailure

        }

    }



    $selfTokens =
    $null



    $selfParseErrors =
    $null



    [System.Management.Automation.Language.Parser]::ParseFile(
        $PSCommandPath,
        [ref]$selfTokens,
        [ref]$selfParseErrors
    ) | Out-Null



    if($selfParseErrors.Count -eq 0)
    {

        Add-GaloreBuildResult `
        -Status "PASS" `
        -Name "Build validator syntax" `
        -Message "Test-GaloreBuild.ps1 parsed successfully."

    }
    else
    {

        foreach($selfParseError in $selfParseErrors)
        {

            Add-GaloreBuildResult `
            -Status "FAIL" `
            -Name "Build validator syntax" `
            -Message $selfParseError.Message

        }

    }
    $mainTokens =
    $null



    $mainParseErrors =
    $null



    $mainAst =
    [System.Management.Automation.Language.Parser]::ParseFile(
        $MainScript,
        [ref]$mainTokens,
        [ref]$mainParseErrors
    )



    if($mainParseErrors.Count -gt 0)
    {

        throw "GaloreLauncher.ps1 could not be parsed."

    }



    $moduleFiles =
    Get-GaloreLoaderModuleFiles `
    -MainAst $mainAst



    $duplicateModuleFiles =
    @(
        $moduleFiles |
        Group-Object |
        Where-Object Count -gt 1 |
        Select-Object -ExpandProperty Name
    )



    if($duplicateModuleFiles.Count -gt 0)
    {

        Add-GaloreBuildResult `
        -Status "FAIL" `
        -Name "Module loader" `
        -Message "Duplicate module entries: $($duplicateModuleFiles -join ', ')."

    }



    $actualModuleFiles =
    @(
        Get-ChildItem `
        -LiteralPath $ModuleRoot `
        -Filter "*.ps1" `
        -File |
        Where-Object Name -ne "GaloreLauncher.ps1" |
        Select-Object -ExpandProperty Name
    )



    $orphanModuleFiles =
    @($actualModuleFiles | Where-Object { $_ -notin $moduleFiles })



    $missingModuleFiles =
    @($moduleFiles | Where-Object { $_ -notin $actualModuleFiles })



    if($orphanModuleFiles.Count -gt 0 -or $missingModuleFiles.Count -gt 0)
    {

        Add-GaloreBuildResult `
        -Status "FAIL" `
        -Name "Module loader" `
        -Message (
            "Orphan modules: $($orphanModuleFiles -join ', '); " +
            "missing loader entries: $($missingModuleFiles -join ', ')."
        )

    }



    if(
        $duplicateModuleFiles.Count -eq 0 -and
        $orphanModuleFiles.Count -eq 0 -and
        $missingModuleFiles.Count -eq 0
    )
    {

        Add-GaloreBuildResult `
        -Status "PASS" `
        -Name "Module loader" `
        -Message "$($moduleFiles.Count) declared modules found with no orphan entries."

    }



    . (Get-GaloreDependencyValidator `
        -MainAst $mainAst)



    $script:AppRoot =
    $AppRoot



    $script:ModuleRoot =
    $ModuleRoot



    $script:LauncherRunningAsScript =
    $false



    $loadedModules =
    New-Object System.Collections.ArrayList



    for(
        $moduleIndex = 0;
        $moduleIndex -lt $moduleFiles.Count;
        $moduleIndex++
    )
    {

        $moduleFile =
        $moduleFiles[$moduleIndex]



        $modulePath =
        Join-Path `
        $ModuleRoot `
        $moduleFile



        if(
            -not (
                Test-Path `
                -LiteralPath $modulePath `
                -PathType Leaf
            )
        )
        {

            throw "Module listed by the loader is missing: $moduleFile"

        }



        Remove-Variable `
        -Name GaloreModuleManifest `
        -Scope Script `
        -ErrorAction SilentlyContinue



        . $modulePath



        if($null -eq $GaloreModuleManifest)
        {

            throw "$moduleFile did not declare GaloreModuleManifest."

        }



        $null =
        $loadedModules.Add(
            [PSCustomObject]@{
                FileName = $moduleFile
                ActualOrder = $moduleIndex + 1
                Manifest = $GaloreModuleManifest
                Source = Get-Content -LiteralPath $modulePath -Raw -ErrorAction Stop
            }
        )

    }



    $dependencyResult =
    Test-GaloreModuleDependencies `
    -LoadedModules $loadedModules `
    -ModuleRoot $ModuleRoot `
    -AppRoot $AppRoot



    if($dependencyResult.IsValid)
    {

        Add-GaloreBuildResult `
        -Status "PASS" `
        -Name "Dependency validation" `
        -Message (
            "$($dependencyResult.ModuleCount) modules, " +
            "$($dependencyResult.FunctionCount) functions, " +
            "$($dependencyResult.RequiredTypeCount) types, " +
            "$($dependencyResult.RequiredFileCount) required files."
        )

    }
    else
    {

        foreach($dependencyError in $dependencyResult.Errors)
        {

            Add-GaloreBuildResult `
            -Status "FAIL" `
            -Name "Dependency validation" `
            -Message $dependencyError

        }

    }



    $environmentPaths =
    New-LauncherEnvironmentPaths `
    -ResourceFolder $ResourceRoot `
    -ScrcpyFolder (Join-Path $AppRoot "Programs\scrcpy") `
    -ProgramRoot $AppRoot



    $programDefinitions =
    New-LauncherProgramConfiguration `
    -EnvPaths $environmentPaths



    $configuration =
    [PSCustomObject]@{
        ProgramRoot = $AppRoot
        EnvPaths = $environmentPaths
        Programs = $programDefinitions
    }



    $configurationSchema =
    Test-LauncherConfigurationSchema `
    -Configuration $configuration



    if(-not $configurationSchema.IsValid)
    {

        foreach($configurationError in $configurationSchema.Errors)
        {

            Add-GaloreBuildResult `
            -Status "FAIL" `
            -Name "Configuration schema" `
            -Message $configurationError

        }

    }
    else
    {

        $script:ProgramRoot =
        $configuration.ProgramRoot



        $script:EnvPaths =
        $configuration.EnvPaths



        $script:Programs =
        $configuration.Programs



        Add-GaloreBuildResult `
        -Status "PASS" `
        -Name "Configuration schema" `
        -Message "$($script:Programs.Count) program definitions initialized."

    }



    $runtimeDependencyResult =
    Test-GaloreModuleDependencies `
    -LoadedModules $loadedModules `
    -ModuleRoot $ModuleRoot `
    -AppRoot $AppRoot `
    -RuntimeVariablesOnly



    if($runtimeDependencyResult.IsValid)
    {

        Add-GaloreBuildResult `
        -Status "PASS" `
        -Name "Runtime dependencies" `
        -Message "Required runtime variables are available."

    }
    else
    {

        foreach($runtimeDependencyError in $runtimeDependencyResult.Errors)
        {

            Add-GaloreBuildResult `
            -Status "FAIL" `
            -Name "Runtime dependencies" `
            -Message $runtimeDependencyError

        }

    }



    $unitTestRunner =
    Join-Path `
    $AppRoot `
    "Test-GaloreUnitTests.ps1"



    if($SkipUnitTests)
    {

        Add-GaloreBuildResult `
        -Status "PASS" `
        -Name "Automated unit tests" `
        -Message "Skipped by the requested source and compile smoke check."

    }
    elseif(
        -not (
            Test-Path `
            -LiteralPath $unitTestRunner `
            -PathType Leaf
        )
    )
    {

        Add-GaloreBuildResult `
        -Status "FAIL" `
        -Name "Automated unit tests" `
        -Message "Test-GaloreUnitTests.ps1 is missing."

    }
    else
    {

        try
        {

            & $unitTestRunner `
            -GaloreRoot $AppRoot



            if($LASTEXITCODE -eq 0)
            {

                Add-GaloreBuildResult `
                -Status "PASS" `
                -Name "Automated unit tests" `
                -Message "Pester suite completed successfully."

            }
            else
            {

                Add-GaloreBuildResult `
                -Status "FAIL" `
                -Name "Automated unit tests" `
                -Message "Pester reported a test failure."

            }

        }
        catch
        {

            Add-GaloreBuildResult `
            -Status "FAIL" `
            -Name "Automated unit tests" `
            -Message $_.Exception.Message

        }

    }



    Test-GaloreJsonFile `
    -Path (Join-Path $AppRoot "Settings\settings.json") `
    -Name "settings.json"



    Test-GaloreJsonFile `
    -Path (Join-Path $AppRoot "Settings\maintenance-state.json") `
    -Name "maintenance-state.json"



    $settingsPath =
    Join-Path `
    $AppRoot `
    "Settings\settings.json"



    if(Test-Path -LiteralPath $settingsPath -PathType Leaf)
    {

        try
        {

            $settings =
            Get-Content `
            -LiteralPath $settingsPath `
            -Raw `
            -ErrorAction Stop |
            ConvertFrom-Json `
            -ErrorAction Stop



            ConvertTo-ValidatedLauncherSettings `
            -Settings $settings |
            Out-Null



            Add-GaloreBuildResult `
            -Status "PASS" `
            -Name "settings.json schema" `
            -Message "Galore window settings are valid."

        }
        catch
        {

            Add-GaloreBuildResult `
            -Status "FAIL" `
            -Name "settings.json schema" `
            -Message $_.Exception.Message

        }

    }



    $maintenanceStatePath =
    Join-Path `
    $AppRoot `
    "Settings\maintenance-state.json"



    if(Test-Path -LiteralPath $maintenanceStatePath -PathType Leaf)
    {

        try
        {

            $maintenanceState =
            Get-Content `
            -LiteralPath $maintenanceStatePath `
            -Raw `
            -ErrorAction Stop |
            ConvertFrom-Json `
            -ErrorAction Stop



            ConvertTo-ValidatedGaloreMaintenanceState `
            -State $maintenanceState |
            Out-Null



            Add-GaloreBuildResult `
            -Status "PASS" `
            -Name "maintenance-state.json schema" `
            -Message "Galore maintenance state is valid."

        }
        catch
        {

            Add-GaloreBuildResult `
            -Status "FAIL" `
            -Name "maintenance-state.json schema" `
            -Message $_.Exception.Message

        }

    }



    $logProbePath =
    Join-Path `
    $LogRoot `
    (".galore-build-{0}.tmp" -f [Guid]::NewGuid().ToString("N"))



    try
    {

        $logProbeStream =
        [System.IO.File]::Open(
            $logProbePath,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )



        $logProbeStream.Dispose()



        Add-GaloreBuildResult `
        -Status "PASS" `
        -Name "Log folder" `
        -Message "Logs folder is writable."

    }
    catch
    {

        Add-GaloreBuildResult `
        -Status "FAIL" `
        -Name "Log folder" `
        -Message $_.Exception.Message

    }
    finally
    {

        Remove-Item `
        -LiteralPath $logProbePath `
        -Force `
        -ErrorAction SilentlyContinue

    }



    foreach(
        $logName in @(
            "GaloreLauncher.log",
            "Diagnostics.log",
            "Crash.log"
        )
    )
    {

        $logPath =
        Join-Path `
        $LogRoot `
        $logName



        try
        {

            $logStream =
            [System.IO.File]::Open(
                $logPath,
                [System.IO.FileMode]::OpenOrCreate,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::ReadWrite
            )



            $logStream.Dispose()



            Add-GaloreBuildResult `
            -Status "PASS" `
            -Name $logName `
            -Message "Reachable and writable."

        }
        catch
        {

            Add-GaloreBuildResult `
            -Status "FAIL" `
            -Name $logName `
            -Message $_.Exception.Message

        }

    }



    if(
        Test-Path `
        -LiteralPath $ExecutablePath `
        -PathType Leaf
    )
    {

        $latestSource =
        Get-ChildItem `
        -LiteralPath $ModuleRoot `
        -Filter "*.ps1" `
        -File |
        Sort-Object LastWriteTimeUtc `
        -Descending |
        Select-Object -First 1



        $executableInfo =
        Get-Item `
        -LiteralPath $ExecutablePath



        if($executableInfo.Length -le 0)
        {

            Add-GaloreBuildResult `
            -Status "FAIL" `
            -Name "Executable metadata" `
            -Message "GaloreLauncher.exe is empty."

        }
        elseif(
            [string]::IsNullOrWhiteSpace(
                [string]$executableInfo.VersionInfo.FileVersion
            )
        )
        {

            Add-GaloreBuildResult `
            -Status "FAIL" `
            -Name "Executable metadata" `
            -Message "GaloreLauncher.exe has no file version."

        }
        else
        {

            Add-GaloreBuildResult `
            -Status "PASS" `
            -Name "Executable metadata" `
            -Message "Version $($executableInfo.VersionInfo.FileVersion)."



            if(
                $latestSource -and
                $executableInfo.LastWriteTimeUtc -lt $latestSource.LastWriteTimeUtc
            )
            {

                Add-GaloreBuildResult `
                -Status "WARNING" `
                -Name "Executable freshness" `
                -Message "GaloreLauncher.exe is older than $($latestSource.Name). Rebuild before release."

            }
            else
            {

                Add-GaloreBuildResult `
                -Status "PASS" `
                -Name "Executable freshness" `
                -Message "GaloreLauncher.exe is current."

            }

        }

    }
    else
    {

        Add-GaloreBuildResult `
        -Status "WARNING" `
        -Name "Executable freshness" `
        -Message "GaloreLauncher.exe does not exist yet."

    }



    if($Compile)
    {

        $temporaryExecutablePath =
        Join-Path `
        ([System.IO.Path]::GetTempPath()) `
        ("GaloreLauncher-build-{0}.exe" -f [Guid]::NewGuid().ToString("N"))



        try
        {

            if(
                -not (
                    Get-Command `
                    -Name ps2exe `
                    -ErrorAction SilentlyContinue
                )
            )
            {

                Import-Module `
                ps2exe `
                -ErrorAction Stop

            }



            ps2exe `
            -inputFile $MainScript `
            -outputFile $temporaryExecutablePath `
            -noConsole `
            -iconFile (Join-Path $ResourceRoot "Galore.ico") `
            -title "Galore Launcher" `
            -description "Interface Manager" `
            -version "1.0.1.0" `
            -copyright "Copyright © 2026 All Rights Reserved"



            if(
                -not (
                    Test-Path `
                    -LiteralPath $temporaryExecutablePath `
                    -PathType Leaf
                )
            )
            {

                throw "ps2exe did not create the temporary executable."

            }



            $temporaryExecutable =
            Get-Item `
            -LiteralPath $temporaryExecutablePath



            if($temporaryExecutable.Length -le 0)
            {

                throw "The temporary executable is empty."

            }



            Add-GaloreBuildResult `
            -Status "PASS" `
            -Name "Temporary executable compile" `
            -Message "ps2exe compiled and verified a disposable executable."

        }
        catch
        {

            Add-GaloreBuildResult `
            -Status "FAIL" `
            -Name "Temporary executable compile" `
            -Message $_.Exception.Message

        }
        finally
        {

            Remove-Item `
            -LiteralPath $temporaryExecutablePath `
            -Force `
            -ErrorAction SilentlyContinue

        }

    }

}
catch
{

    Add-GaloreBuildResult `
    -Status "FAIL" `
    -Name "Build validation" `
    -Message $_.Exception.Message

}
finally
{

    if(
        Get-Command `
        -Name Stop-LauncherRuntimeResources `
        -CommandType Function `
        -ErrorAction SilentlyContinue
    )
    {

        try
        {

            Stop-LauncherRuntimeResources

        }
        catch
        {

            # Validation cleanup must never hide the real result.

        }

    }

}



$passed =
@($script:BuildResults | Where-Object Status -eq "PASS").Count



$warnings =
@($script:BuildResults | Where-Object Status -eq "WARNING").Count



$failures =
@($script:BuildResults | Where-Object Status -eq "FAIL").Count




Write-Host ""



$summaryColor =
if($failures -gt 0)
{
    "Red"
}
elseif($warnings -gt 0)
{
    "Yellow"
}
else
{
    "Green"
}



Write-Host (
    "Galore build validation complete: " +
    "$passed passed, " +
    "$warnings warnings, " +
    "$failures failures."
) -ForegroundColor $summaryColor



if($failures -gt 0)
{

    exit 1

}



exit 0
