$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")

. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'Database', 'OutputPath', 'TemplateFolder', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {

    BeforeAll {
        $query = "CREATE DATABASE $($script:database)"
        Invoke-DbaQuery -SqlInstance $script:instance -Database master -Query $query
    }

    Context "Create Database Collation Test" {
        $result = New-PSTGDatabaseCollationTest -Database $script:database -OutputPath $script:unittestfolder

        $file = Get-Item -Path (Join-Path $script:unittestingfolder -ChildPath "test If database has correct collation Expect Success.sql")
        $file
        It "Should have created a file" {
            $file | Should -Not -Be $null
        }

    }

    AfterAll {
        Remove-DbaDatabase -SqlInstance $script:instance1 -Name $script:database
    }

}