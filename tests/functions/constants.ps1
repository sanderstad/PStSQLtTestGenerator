# constants
if (Test-Path C:\temp\constants.ps1) {
    Write-Verbose "C:\temp\constants.ps1 found."
    . C:\temp\constants.ps1
}
elseif (Test-Path "$PSScriptRoot\constants.local.ps1") {
    Write-Verbose "tests\constants.local.ps1 found."
    . "$PSScriptRoot\constants.local.ps1"
}
else {
    $script:computer = "localhost"
    $script:instance = "localhost"
    $script:database = "UnitTesting_Tests"
    $script:tempfolder = "C:\temp\"
    $script:unittestfolder = (Join-Path -Path $script:tempfolder -ChildPath "unittests")
}

if ($env:appveyor) {
    $PSDefaultParameterValues['*:WarningAction'] = 'SilentlyContinue'
}