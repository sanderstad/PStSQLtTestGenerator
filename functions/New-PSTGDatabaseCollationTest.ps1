function New-PSTGDatabaseCollationTest {
    <#
    .SYNOPSIS
        Function to create a collation test

    .DESCRIPTION
        The function will lookup the current collation of the database and create a test with that value

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database or databases to add.

    .PARAMETER OutputPath
        Path to output the test to

    .PARAMETER TemplateFolder
        Path to template folder. By default the internal templates folder will be used

    .PARAMETER TestClass
        Test class name to use for the test

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
        [DbaInstanceParameter]$SqlInstance,
        [pscredential]$SqlCredential,
        [string]$Database,
        [Parameter(Mandatory)][string]$OutputPath,
        [string]$TemplateFolder,
        [string]$TestClass,
        [switch]$EnableException
    )

    begin {
        # Check parameters
        if (-not $SqlInstance) {
            Stop-PSFFunction -Message "Please enter a SQL Server instance" -Target $SqlInstance
            return
        }

        if (-not $Database) {
            Stop-PSFFunction -Message "Please enter a database" -Target $Database
            return
        }

        # Test if the name of the test does not become too long
        if ($testName.Length -gt 128) {
            Stop-PSFFunction -Message "Name of the test is too long" -Target $testName
        }

        if (-not $TestClass) {
            $TestClass = "TestBasic"
        }

        $date = Get-Date -Format (Get-culture).DateTimeFormat.ShortDatePattern
        $creator = $env:username

        if (-not $TemplateFolder) {
            $TemplateFolder = Join-Path -Path ($script:ModuleRoot) -ChildPath "internal\templates"
        }

        if (-not (Test-Path -Path $TemplateFolder)) {
            try {
                $null = New-Item -Path $OutputPath -ItemType Directory
            }
            catch {
                Stop-PSFFunction -Message "Something went wrong creating the output directory" -Target $OutputPath -ErrorRecord $_
            }
        }

        # Connect to the server
        try {
            $server = Connect-DbaInstance -SqlInstance $Sqlinstance -SqlCredential $SqlCredential
        }
        catch {
            Stop-PSFFunction -Message "Could not connect to '$Sqlinstance'" -Target $Sqlinstance -ErrorRecord $_ -Category ConnectionError
            return
        }

        # Check if the database exists
        if ($Database -notin $server.Databases.Name) {
            Stop-PSFFunction -Message "Database cannot be found on '$SqlInstance'" -Target $Database
        }
    }

    process {
        if (Test-PSFFunctionInterrupt) { return }

        $testName = "test If database has correct collation"
        $fileName = Join-Path -Path $OutputPath -ChildPath "$($testName).sql"

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

                [PSCustomObject]@{
                    TestName = $testName
                    Category = "DatabaseCollation"
                    Creator  = $creator
                    FileName = $fileName
                }
            }
            catch {
                Stop-PSFFunction -Message "Something went wrong writing the test" -Target $testName -ErrorRecord $_
            }
        }
    }
}