$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")

. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'OutputPath', 'TemplateFolder', 'Function', 'Procedure', 'Table', 'View', 'SkipDatabaseTests', 'SkipFunctionTests', 'SkipProcedureTests', 'SkipTableTests', 'SkipViewTests', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {

    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance

        if ($server.Databases.Name -notcontains $script:database) {
            $query = "CREATE DATABASE $($script:database)"
            $server.Query($query)
        }

        if (-not (Test-Path -Path $script:unittestfolder)) {
            $null = New-Item -Path $script:unittestfolder -ItemType Directory
        }

        Invoke-DbaQuery -SqlInstance $script:instance -Database $script:database -File "database.sql"
    }

    Context "Create Tests" {
        $result = Invoke-PSTGTestGenerator -SqlInstance $script:instance -Database $script:database -OutputPath $script:unittestfolder

        $files = Get-ChildItem -Path $script:unittestfolder

        $file = Get-Item -Path $result[0].FileName

        It "Should return a result" {
            $result | Should -Not -Be $null
        }

        It "Should have created a file" {
            $file | Should -Not -Be $null
        }

        it "Should have all the tests" {
            $files.Count | Should -Be 10
        }

        It "Result should have correct values" {
            $file.FullName | Should -Be $result[0].FileName
        }
    }

    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $script:instance -Database $script:database -Confirm:$false

        #$null = Remove-Item -Path $script:unittestfolder -Recurse -Force -Confirm:$false
    }

}