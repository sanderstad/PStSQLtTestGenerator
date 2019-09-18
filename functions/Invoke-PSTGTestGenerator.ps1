function Invoke-PSTGTestGenerator {
    <#
    .SYNOPSIS
        Create the basic tests for the database project

    .DESCRIPTION
        The script will connect to a database on a SQL Server instance, iterate through objects and create tests for the objects.

        The script will create the following tests
        - Test if the database settings (i.e. collation) are correct
        - Test if an object (Function, Procedure, Table, View etc) exists
        - Test if an object (Function or Procedure) has the correct parameters
        - Test if an object (Table or View) has the correct columns

        Each object and each test will be it's own file.

   .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

        This should be the primary replica.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database or databases to add.

    .PARAMETER OutputPath
        Folder where the files should be written to

    .PARAMETER TemplateFolder
        The template folder containing all the templates for the tests.
        By default it will use the internal templates directory

    .PARAMETER Function
        Filter out specific functions that should only be processed

    .PARAMETER Procedure
        Filter out specific procedures that should only be processed

    .PARAMETER Table
        Filter out specific tables that should only be processed

    .PARAMETER View
        Filter out specific views that should only be processed

    .PARAMETER SkipDatabaseTests
        Skip the database tests

    .PARAMETER SkipFunctionTests
        Skip the function tests

    .PARAMETER SkipProcedureTests
        Skip the procedure tests

    .PARAMETER SkipTableTests
        Skip the table tests

    .PARAMETER SkipViewTests
        Skip the view tests

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .EXAMPLE
        PS C:\> Invoke-PSTGTestGenerator -SqlInstance SQLDB1 -Database DB1 -OutputPath c:\projects\DB1\DB1-Tests\TestBasic

        Iterate through all the objects and output the files to "c:\projects\DB1\DB1-Tests\TestBasic"

    .EXAMPLE
        PS C:\> Invoke-PSTGTestGenerator -SqlInstance SQLDB1 -Database DB1 -OutputPath c:\projects\DB1\DB1-Tests\TestBasic -Procedure Proc1, Proc2

        Iterate through all the objects but only do "Proc1" and "Proc2" for the procedures.

        NOTE! All other tests like the table, function and view tests will still be generated

    .EXAMPLE
        PS C:\> Invoke-PSTGTestGenerator -SqlInstance SQLDB1 -Database DB1 -OutputPath c:\projects\DB1\DB1-Tests\TestBasic -SkipProcedureTests

        Iterate through all the objects but do not process the procedures
    #>

    [CmdletBinding()]

    param(
        [DbaInstanceParameter]$SqlInstance,
        [pscredential]$SqlCredential,
        [string]$Database,
        [string]$OutputPath,
        [string]$TemplateFolder,
        [string[]]$Function,
        [string[]]$Procedure,
        [string[]]$Table,
        [string[]]$View,
        [switch]$SkipDatabaseTests,
        [switch]$SkipFunctionTests,
        [switch]$SkipProcedureTests,
        [switch]$SkipTableTests,
        [switch]$SkipViewTests,
        [switch]$EnableException
    )

    begin {
        # Check the parameters
        if (-not $SqlInstance) {
            Stop-PSFFunction -Message "Please enter a SQL Server instance" -Target $SqlInstance
            return
        }

        if (-not $Database) {
            Stop-PSFFunction -Message "Please enter a database" -Target $Database
            return
        }

        if (-not $OutputPath) {
            Stop-PSFFunction -Message "Please enter path to output the files to" -Target $OutputPath
            return
        }

        if (-not (Test-Path -Path $OutputPath)) {
            Stop-PSFFunction -Message "Could not access output path" -Category ResourceUnavailable -Target $OutputPath
            return
        }

        if (-not $TemplateFolder) {
            $TemplateFolder = Join-Path -Path ($script:ModuleRoot) -ChildPath "internal\templates"
        }

        if (-not (Test-Path -Path $TemplateFolder)) {
            Stop-PSFFunction -Message "Could not find template folder" -Target $OutputPath
            return
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

        #########################################################################
        # Create the database tests
        #########################################################################

        if (-not $SkipDatabaseTests) {

            try {
                # Create the collation test
                New-PSTGDatabaseCollationTest -Database $Database -TemplateFolder $TemplateFolder -OutputPath $OutputPath -EnableException
            }
            catch {
                Stop-PSFFunction -Message "Something went wrong creating the database collation test" -Target $Database -ErrorRecord $_
            }

        }

        #########################################################################
        # Create the function tests
        #########################################################################
        if (-not $SkipFunctionTests) {
            # Get all the functions
            $functions = $server.Databases[$Database].UserDefinedFunctions | Where-Object { $_.IsSystemObject -eq $false }

            # Filter out functions
            if ($Function) {
                $functions = $functions | Where-Object Name -in $Function
            }

            # Create the function existence tests
            try {
                New-PSTGObjectExistenceTest -Object $functions -OutputPath $OutputPath -EnableException
            }
            catch {
                Stop-PSFFunction -Message "Something went wrong creating the function existence tests" -Target $Database -ErrorRecord $_
            }

            # Create the function parameter tests
            try {
                New-PSTGFunctionParameterTest -Function $functions -OutputPath $OutputPath -EnableException
            }
            catch {
                Stop-PSFFunction -Message "Something went wrong creating the function parameter tests" -Target $Database -ErrorRecord $_
            }
        }

        #########################################################################
        # Create the procedure tests
        #########################################################################
        if (-not $SkipProcedureTests) {
            # Get all the procedures
            $procedures = $server.Databases[$Database].StoredProcedures | Where-Object { $_.IsSystemObject -eq $false }

            if ($Procedure) {
                $procedures = $procedures | Where-Object Name -in $Procedure
            }

            # Create the procedure existence tests
            try {
                New-PSTGObjectExistenceTest -Object $procedures -OutputPath $OutputPath -EnableException
            }
            catch {
                Stop-PSFFunction -Message "Something went wrong creating the procedure existence tests" -Target $Database -ErrorRecord $_
            }

            # Create the procedure parameter tests
            try {
                New-PSTGProcedureParameterTest -Procedure $procedures -OutputPath $OutputPath -EnableException
            }
            catch {
                Stop-PSFFunction -Message "Something went wrong creating the procedure parameter tests" -Target $Database -ErrorRecord $_
            }
        }

        #########################################################################
        # Create the table tests
        #########################################################################
        if (-not $SkipTableTests) {
            # Get the tables
            $tables = $server.Databases[$Database].Tables

            if ($Table) {
                $tables = $tables | Where-Object Name -in $Table
            }

            # Create the table existence tests
            try {
                New-PSTGObjectExistenceTest -Object $tables -OutputPath $OutputPath -EnableException
            }
            catch {
                Stop-PSFFunction -Message "Something went wrong creating the table existence tests" -Target $Database -ErrorRecord $_
            }

            # Create the table column tests
            try {
                New-PSTGTableColumnTest -Table $tables -OutputPath $OutputPath -EnableException
            }
            catch {
                Stop-PSFFunction -Message "Something went wrong creating the table column tests" -Target $Database -ErrorRecord $_
            }
        }

        #########################################################################
        # Create the view tests
        #########################################################################
        if (-not $SkipViewTests) {
            # Get all the procedures
            $views = $server.Databases[$Database].Views | Where-Object { $_.IsSystemObject -eq $false }

            if ($View) {
                $views = $views | Where-Object Name -in $View
            }

            # Create the view existence tests
            try {
                New-PSTGObjectExistenceTest -Object $views -OutputPath $OutputPath -EnableException
            }
            catch {
                Stop-PSFFunction -Message "Something went wrong creating the view existence tests" -Target $Database -ErrorRecord $_
            }

            # Create the view column tests
            try {
                New-PSTGViewColumnTest -View $views -OutputPath $OutputPath -EnableException
            }
            catch {
                Stop-PSFFunction -Message "Something went wrong creating the table column tests" -Target $Database -ErrorRecord $_
            }
        }
    }
}