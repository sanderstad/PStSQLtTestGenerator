# constants
if (Test-Path C:\temp\constants_pstsqlttestgenerator.ps1) {
    Write-Verbose "C:\temp\constants.ps1 found."
    . C:\temp\constants_pstsqlttestgenerator.ps1
}
else {
    $script:computer = "localhost"
    $script:instance = "localhost\SQL2017"
    $script:database = "UnitTesting_Tests"
    $script:tempfolder = "C:\projects\"
    $script:unittestfolder = (Join-Path -Path $script:tempfolder -ChildPath "unittests")
}

if ($env:appveyor) {
    $PSDefaultParameterValues['*:WarningAction'] = 'SilentlyContinue'
}