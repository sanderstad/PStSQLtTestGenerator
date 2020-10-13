$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")

. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'Value', 'Type'

        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Path should not have illegal characters" {
        $originalValue = "c:<\t>em/p|\f?i*le1.ps1"

        $newValue = Remove-IllegalCharacters -Value $originalValue -Type Path

        It "Should have removed characters" {
            $newValue | Should -Not -Be $originalValue
        }

        It "Should have converted the path to a valid format" {
            $expectedValue = "c:\temp\file1.ps1"

            $newValue | Should -Be $expectedValue
        }
    }
}