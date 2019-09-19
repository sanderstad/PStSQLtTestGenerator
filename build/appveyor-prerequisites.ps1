Add-AppveyorTest -Name "appveyor.prerequisites" -Framework NUnit -FileName "appveyor-prerequisites.ps1" -Outcome Running
$sw = [system.diagnostics.stopwatch]::startNew()

Install-Module PSFramework -Force -SkipPublisherCheck
Write-PSFMessage -Level Host -Message "Installing dbatools" -ForegroundColor Cyan
Install-Module dbatools -Force -SkipPublisherCheck
Write-PSFMessage -Level Host -Message "Installing Pester" -ForegroundColor Cyan
Install-Module Pester -Force -SkipPublisherCheck
Write-PSFMessage -Level Host -Message "Installing PSScriptAnalyzer" -ForegroundColor Cyan
Install-Module -Name PSScriptAnalyzer -Force -SkipPublisherCheck

. "$PSScriptRoot\appveyor-constants.ps1"

$sw.Stop()
Update-AppveyorTest -Name "appveyor-prerequisites" -Framework NUnit -FileName "appveyor-prerequisites.ps1" -Outcome Passed -Duration $sw.ElapsedMilliseconds