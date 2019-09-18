function New-PSTGDatabaseCollationTest {
    <#
    .SYNOPSIS
        Function to create a collation test

    .DESCRIPTION
        The function will lookup the current collation of the database and create a test with that value

    .PARAMETER Database
        Name of the database to create the test for

    .PARAMETER OutputPath
        Path to output the test to

    .PARAMETER TemplateFolder
        Path to template folder. By default the internal templates folder will be used

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .EXAMPLE
        New-PSTGDatabaseCollationTest -Database DB1 -OutputPath "C:\Projects\DB1\TestBasic\"

        Create a new database collation test
    #>

    [CmdletBinding(SupportsShouldProcess)]

    param(
        [Parameter(Mandatory)][string]$Database,
        [Parameter(Mandatory)][string]$OutputPath,
        [string]$TemplateFolder,
        [switch]$EnableException
    )

    begin {
        $testName = "test If database has correct collation Expect Success"

        # Test if the name of the test does not become too long
        if ($testName.Length -gt 128) {
            Stop-PSFFunction -Message "Name of the test is too long" -Target $testName
        }

        $fileName = Join-Path -Path $OutputPath -ChildPath "$($testName).sql"
        $date = Get-Date -Format (Get-culture).DateTimeFormat.ShortDatePattern
        $creator = $env:username

        if (-not $TemplateFolder) {
            $TemplateFolder = Join-Path -Path ($script:ModuleRoot) -ChildPath "internal\templates"
        }

        if (-not (Test-Path -Path $TemplateFolder)) {
            Stop-PSFFunction -Message "Could not find template folder" -Target $OutputPath
        }
    }

    process {
        if (Test-PSFFunctionInterrupt) { return }

        # Import the template
        try {
            $script = Get-Content -Path (Join-Path -Path $TemplateFolder -ChildPath "DatabaseCollationTest.template")
        }
        catch {
            Stop-PSFFunction -Message "Could not import test template 'DatabaseCollationTest.template'" -Target $testName -ErrorRecord $_
        }

        # Replace the markers with the content
        $script = $script.Replace("___TESTNAME___", $testName)
        $script = $script.Replace("___DATABASE___", $Database)
        $script = $script.Replace("___COLLATION___", $server.Databases[$Database].Collation)
        $script = $script.Replace("___CREATOR___", $creator)
        $script = $script.Replace("___DATE___", $date)

        # Write the test
        if ($PSCmdlet.ShouldProcess("$Database", "Writing Database Collation Test")) {
            try {
                Write-PSFMessage -Message "Creating collation test for '$Database'"
                $script | Out-File -FilePath $fileName
            }
            catch {
                Stop-PSFFunction -Message "Something went wrong writing the test" -Target $testName -ErrorRecord $_
            }
        }
    }
}