Add-AppveyorTest -Name "appveyor.prerequisites" -Framework NUnit -FileName "appveyor-prerequisites.ps1" -Outcome Running
$sw = [system.diagnostics.stopwatch]::startNew()

$modules = (Get-Module -ListAvailable) | Select-Object Name, Version

if ($modules.Name -notcontains "Pester") {
    #    Write-PMessage -Level Host -Message "Installing Pester"
    Install-Module Pester -MinimumVersion "4.8.1" -Force -SkipPublisherCheck

    Import-Module Pester
    Get-Module -Name Pester
}

if ($modules.Name -notcontains "PSFramework") {
    Install-Module PSFramework -Force -SkipPublisherCheck
}

if ($modules.Name -notcontains "Pester") {
    #    Write-PMessage -Level Host -Message "Installing Pester"
    Install-Module Pester -MinimumVersion "4.8.1" -Force -SkipPublisherCheck

    Import-Module Pester
    Get-Module -Name Pester
}

if ($modules.Name -notcontains "dbatools") {
    Write-PSFMessage -Level Host -Message "Installing dbatools"
    Install-Module dbatools -MinimumVersion "1.0.38" -Force -SkipPublisherCheck
}

if ($modules -notcontains "PSScriptAnalyzer") {
    Write-PSFMessage -Level Host -Message "Installing PSScriptAnalyzer"
    Install-Module -Name PSScriptAnalyzer -Force -SkipPublisherCheck
}

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