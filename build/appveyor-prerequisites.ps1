Add-AppveyorTest -Name "appveyor.prerequisites" -Framework NUnit -FileName "appveyor-prerequisites.ps1" -Outcome Running
$sw = [system.diagnostics.stopwatch]::startNew()

$modules = (Get-Module -ListAvailable) | Select-Object Name, Version


Install-Module PSFramework -Force -SkipPublisherCheck

choco install Pester -y
#Install-Module Pester

Import-Module Pester
Write-PSFMessage -Level Important -Message "Pester version: $((Get-Module -Name Pester).Version)"

Write-PSFMessage -Level Host -Message "Installing dbatools"
Install-Module dbatools -MinimumVersion "1.0.38" -Force -SkipPublisherCheck

Write-PSFMessage -Level Host -Message "Installing PSScriptAnalyzer"
Install-Module -Name PSScriptAnalyzer -Force -SkipPublisherCheck

. "$PSScriptRoot\appveyor-constants.ps1"

Write-PSFMessage -Level Host -Message "Create Unit Test Folder"
if (-not (Test-Path -Path $unittestfolder)) {
    $null = New-Item -Path $unittestfolder -ItemType Directory
}

Write-PSFMessage -Level Host -Message "Setup Database"
$server = Connect-DbaInstance -SqlInstance $instance

if ($server.Databases.Name -notcontains $database) {
    # Create the database
    $query = "CREATE DATABASE $($database)"
    $server.Query($query)

    # Refresh the server object
    $server.Refresh()

    Invoke-DbaQuery -SqlInstance $instance -Database $database -File "$PSScriptRoot\..\tests\functions\database.sql"

    $server.Databases.Refresh()

    if ($server.Databases[$database].Tables.Name -notcontains 'Person') {
        Stop-PSFFunction -Message "Database creation unsuccessful!"
        return
    }
}

$sw.Stop()
Update-AppveyorTest -Name "appveyor-prerequisites" -Framework NUnit -FileName "appveyor-prerequisites.ps1" -Outcome Passed -Duration $sw.ElapsedMilliseconds