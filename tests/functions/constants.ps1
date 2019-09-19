# constants
if (Test-Path C:\temp\constants.ps1) {
    Write-Verbose "C:\temp\constants.ps1 found."
    . C:\temp\constants.ps1
}
else {
    $script:computer = "localhost"
    $script:instance = "localhost"
    $script:database = "UnitTesting_Tests"
    $script:tempfolder = "C:\projects\"
    $script:unittestfolder = (Join-Path -Path $script:tempfolder -ChildPath "unittests")
}

if ($env:appveyor) {
    $PSDefaultParameterValues['*:WarningAction'] = 'SilentlyContinue'
}