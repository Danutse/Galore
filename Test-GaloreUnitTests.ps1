[CmdletBinding()]

param(
    [string]$GaloreRoot =
    $PSScriptRoot
)



$testFile =
Join-Path `
$GaloreRoot `
"Tests\Galore.Unit.Tests.ps1"



if(
    -not (
        Test-Path `
        -LiteralPath $testFile `
        -PathType Leaf
    )
)
{

    throw "Galore unit test file was not found: '$testFile'."

}



$pester =
Get-Module `
-ListAvailable `
-Name Pester |
Sort-Object `
-Property Version `
-Descending |
Select-Object `
-First 1



if($null -eq $pester)
{

    throw "Pester is required to run Galore unit tests."

}



Import-Module `
$pester.Path `
-Force



$result =
Invoke-Pester `
-Script @{
    Path = $testFile
    Parameters = @{
        GaloreRoot = $GaloreRoot
    }
} `
-PassThru



if($result.FailedCount -gt 0)
{

    exit 1

}



Write-Host (
    "Galore unit tests complete: " +
    "$($result.PassedCount) passed, " +
    "$($result.FailedCount) failed."
) -ForegroundColor DarkGreen



exit 0
