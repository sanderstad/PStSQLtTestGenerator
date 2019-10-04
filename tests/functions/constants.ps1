# constants
if (Test-Path C:\temp\constants_pstsqlttestgenerator.ps1) {
    Write-Host "C:\temp\constants_pstsqlttestgenerator.ps1 found."
    . C:\temp\constants_pstsqlttestgenerator.ps1
}
else {
    $script:computer = "localhost"
    $script:sqlinstance = "localhost\SQL2017"
    $script:database = "UnitTesting_Tests"
    $script:tempfolder = "C:\projects\"
    $script:unittestfolder = (Join-Path -Path $script:tempfolder -ChildPath "unittests")
}

if ($env:appveyor) {
    $PSDefaultParameterValues['*:WarningAction'] = 'SilentlyContinue'
}