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

    .PARAMETER Creator
        The person that created the tests. By default the command will get the environment username

    .PARAMETER TemplateFolder
        The template folder containing all the templates for the tests.
        By default it will use the internal templates directory

    .PARAMETER Schema
        Filter the functions based on schema

    .PARAMETER Function
        Filter out specific functions that should only be processed

    .PARAMETER Procedure
        Filter out specific procedures that should only be processed

    .PARAMETER Table
        Filter out specific tables that should only be processed

    .PARAMETER Index
        Filter out specific indexes that should be processed

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

    .PARAMETER SkipIndexTests
        Skip the view tests

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
        [string]$Creator,
        [string]$TemplateFolder,
        [string[]]$Schema,
        [string[]]$Function,
        [string[]]$Procedure,
        [string[]]$Table,
        [string[]]$Index,
        [string[]]$View,
        [switch]$SkipDatabaseTests,
        [switch]$SkipFunctionTests,
        [switch]$SkipProcedureTests,
        [switch]$SkipTableTests,
        [switch]$SkipIndexTests,
        [switch]$SkipViewTests,
        [string]$TestClass,
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

        if (-not $Creator) {
            $Creator = $env:username
        }

        if (-not $TemplateFolder) {
            $TemplateFolder = Join-Path -Path ($script:ModuleRoot) -ChildPath "internal\templates"
        }

        if (-not (Test-Path -Path $TemplateFolder)) {
            Stop-PSFFunction -Message "Could not find template folder" -Target $OutputPath
            return
        }

        if (-not $TestClass) {
            $TestClass = "TestBasic"
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

        $db = $server.Databases[$Database]

        #########################################################################
        # Create the database tests
        #########################################################################

        $totalSteps = 7
        $currentStep = 1
        $task = "Creating Unit Tests"

        $progressParams = @{
            Id               = 1
            Activity         = "Creating tSQLt Unit Tests"
            Status           = 'Progress->'
            PercentComplete  = $null
            CurrentOperation = $task
        }

        if (-not $SkipDatabaseTests) {
            $progressParams.PercentComplete = $($currentStep / $totalSteps * 100)
            Write-Progress @progressParams

            try {
                # Create the collation test
                New-PSTGDatabaseCollationTest -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -Creator $Creator -TemplateFolder $TemplateFolder -OutputPath $OutputPath -TestClass $TestClass -EnableException
            }
            catch {
                Stop-PSFFunction -Message "Something went wrong creating the database collation test" -Target $Database -ErrorRecord $_
            }

        }

        #########################################################################
        # Create the function tests
        #########################################################################

        $currentStep = 2

        if (-not $SkipFunctionTests) {
            $progressParams.PercentComplete = $($currentStep / $totalSteps * 100)
            Write-Progress @progressParams

            $dbObjects = @()

            if ($Schema) {
                $dbObjects += $db.UserDefinedFunctions | Where-Object IsSystemObject -eq $false | Where-Object Schema -in $Schema
            }
            else {
                $dbObjects += $db.UserDefinedFunctions | Where-Object IsSystemObject -eq $false
            }

            if ($Function) {
                $dbObjects = $dbObjects | Where-Object Name -in $Function
            }

            # Create the function existence tests
            try {
                $params = @{
                    SqlInstance     = $SqlInstance
                    SqlCredential   = $SqlCredential
                    Database        = $Database
                    Schema          = @($dbObjects | Select-Object Schema -ExpandProperty Schema -Unique)
                    Object          = @($dbObjects | Select-Object Name -ExpandProperty Name -Unique)
                    Creator         = $Creator
                    OutputPath      = $OutputPath
                    TestClass       = $TestClass
                    EnableException = $EnableException
                }

                New-PSTGObjectExistenceTest @params
            }
            catch {
                Stop-PSFFunction -Message "Something went wrong creating the function existence tests" -Target $Database -ErrorRecord $_
            }

            # Create the function parameter tests
            try {
                $params = @{
                    SqlInstance     = $SqlInstance
                    SqlCredential   = $SqlCredential
                    Database        = $Database
                    Schema          = @($dbObjects | Select-Object Schema -ExpandProperty Schema -Unique)
                    Function        = @($dbObjects | Select-Object Name -ExpandProperty Name -Unique)
                    Creator         = $Creator
                    OutputPath      = $OutputPath
                    TestClass       = $TestClass
                    EnableException = $EnableException
                }

                New-PSTGFunctionParameterTest @params
            }
            catch {
                Stop-PSFFunction -Message "Something went wrong creating the function parameter tests" -Target $Database -ErrorRecord $_
            }
        }

        #########################################################################
        # Create the procedure tests
        #########################################################################

        $currentStep = 3

        if (-not $SkipProcedureTests) {
            $progressParams.PercentComplete = $($currentStep / $totalSteps * 100)
            Write-Progress @progressParams

            $dbObjects = @()

            $dbObjects += Get-DbaModule -SqlInstance $SqlInstance -Database $Database -Type StoredProcedure -ExcludeSystemObjects | Select-Object SchemaName, Name

            if ($Schema) {
                $dbObjects = $dbObjects | Where-Object SchemaName -in $Schema
            }

            if ($Procedure) {
                $dbObjects = $dbObjects | Where-Object Name -in $Procedure
            }

            # Create the procedure existence tests
            try {
                $params = @{
                    SqlInstance     = $SqlInstance
                    SqlCredential   = $SqlCredential
                    Database        = $Database
                    Schema          = @($dbObjects | Select-Object SchemaName -ExpandProperty SchemaName -Unique)
                    Object          = @($dbObjects | Select-Object Name -ExpandProperty Name -Unique)
                    Creator         = $Creator
                    OutputPath      = $OutputPath
                    TestClass       = $TestClass
                    EnableException = $EnableException
                }

                New-PSTGObjectExistenceTest @params
            }
            catch {
                Stop-PSFFunction -Message "Something went wrong creating the procedure existence tests" -Target $Database -ErrorRecord $_
            }

            # Create the procedure parameter tests
            try {
                $params = @{
                    SqlInstance     = $SqlInstance
                    SqlCredential   = $SqlCredential
                    Database        = $Database
                    Schema          = @($dbObjects | Select-Object SchemaName -ExpandProperty SchemaName -Unique)
                    Procedure       = @($dbObjects | Select-Object Name -ExpandProperty Name -Unique)
                    Creator         = $Creator
                    OutputPath      = $OutputPath
                    TestClass       = $TestClass
                    EnableException = $EnableException
                }

                New-PSTGProcedureParameterTest @params
            }
            catch {
                Stop-PSFFunction -Message "Something went wrong creating the procedure parameter tests" -Target $Database -ErrorRecord $_
            }
        }

        #########################################################################
        # Create the table tests
        #########################################################################

        $currentStep = 4

        if (-not $SkipTableTests) {
            $progressParams.PercentComplete = $($currentStep / $totalSteps * 100)
            Write-Progress @progressParams

            $dbObjects = @()

            if ($Schema) {
                $dbObjects += $db.Tables | Where-Object IsSystemObject -eq $false | Where-Object Schema -in $Schema
            }
            else {
                $dbObjects += $db.Tables | Where-Object IsSystemObject -eq $false
            }

            if ($Table) {
                $dbObjects = $dbObjects | Where-Object Name -in $Table
            }

            # Create the table existence tests
            try {
                $params = @{
                    SqlInstance     = $SqlInstance
                    SqlCredential   = $SqlCredential
                    Database        = $Database
                    Schema          = @($dbObjects | Select-Object Schema -ExpandProperty Schema -Unique)
                    Object          = @($dbObjects | Select-Object Name -ExpandProperty Name -Unique)
                    Creator         = $Creator
                    OutputPath      = $OutputPath
                    TestClass       = $TestClass
                    EnableException = $EnableException
                }

                New-PSTGObjectExistenceTest @params
            }
            catch {
                Stop-PSFFunction -Message "Something went wrong creating the table existence tests" -Target $Database -ErrorRecord $_
            }

            # Create the table column tests
            try {
                $params = @{
                    SqlInstance     = $SqlInstance
                    SqlCredential   = $SqlCredential
                    Database        = $Database
                    Schema          = @($dbObjects | Select-Object Schema -ExpandProperty Schema -Unique)
                    Table           = @($dbObjects | Select-Object Name -ExpandProperty Name -Unique)
                    Creator         = $Creator
                    OutputPath      = $OutputPath
                    TestClass       = $TestClass
                    EnableException = $EnableException
                }

                New-PSTGTableColumnTest @params
            }
            catch {
                Stop-PSFFunction -Message "Something went wrong creating the table column tests" -Target $Database -ErrorRecord $_
            }
        }

        #########################################################################
        # Create the table index tests
        #########################################################################

        $currentStep = 5

        if (-not $SkipIndexTests) {
            $progressParams.PercentComplete = $($currentStep / $totalSteps * 100)
            Write-Progress @progressParams

            $dbObjects = @()

            if ($Schema) {
                $dbObjects += $db.Tables | Where-Object IsSystemObject -eq $false | Where-Object Schema -in $Schema
            }
            else {
                $dbObjects += $db.Tables | Where-Object IsSystemObject -eq $false
            }

            if ($Table) {
                $dbObjects = $dbObjects | Where-Object Name -in $Table
            }

            # Create the table index tests
            try {
                $params = @{
                    SqlInstance     = $SqlInstance
                    SqlCredential   = $SqlCredential
                    Database        = $Database
                    Schema          = @($dbObjects | Select-Object Schema -ExpandProperty Schema -Unique)
                    Table           = @($dbObjects | Select-Object Name -ExpandProperty Name -Unique)
                    Creator         = $Creator
                    OutputPath      = $OutputPath
                    TestClass       = $TestClass
                    EnableException = $EnableException
                }

                New-PSTGTableIndexTest @params
            }
            catch {
                Stop-PSFFunction -Message "Something went wrong creating the table index tests" -Target $Database -ErrorRecord $_
            }
        }

        #########################################################################
        # Create the index tests
        #########################################################################

        $currentStep = 6

        if (-not $SkipIndexTests) {
            $progressParams.PercentComplete = $($currentStep / $totalSteps * 100)
            Write-Progress @progressParams

            $dbObjects = @()

            if ($Schema) {
                $dbObjects += $db.Tables | Where-Object IsSystemObject -eq $false | Where-Object Schema -in $Schema
            }
            else {
                $dbObjects += $db.Tables | Where-Object IsSystemObject -eq $false
            }

            if ($Table) {
                $dbObjects = $dbObjects | Where-Object Name -in $Table
            }

            $indObjects = @()

            if ($Index) {
                $indObjects += $dbObjects.Indexes | Where-Object Name -in $Index | Select-Object Name
            }
            else {
                $indObjects += $dbObjects.Indexes | Select-Object Name
            }

            # Create the index existence tests
            try {
                $params = @{
                    SqlInstance     = $SqlInstance
                    SqlCredential   = $SqlCredential
                    Database        = $Database
                    Schema          = @($dbObjects | Select-Object Schema -ExpandProperty Schema -Unique)
                    Table           = @($dbObjects | Select-Object Name -ExpandProperty Name -Unique)
                    Index           = @($indObjects | Select-Object Name -ExpandProperty Name -Unique)
                    Creator         = $Creator
                    OutputPath      = $OutputPath
                    TestClass       = $TestClass
                    EnableException = $EnableException
                }

                New-PSTGIndexColumnTest @params
            }
            catch {
                Stop-PSFFunction -Message "Something went wrong creating the index column tests" -Target $Database -ErrorRecord $_
            }
        }

        #########################################################################
        # Create the view tests
        #########################################################################

        $currentStep = 7

        if (-not $SkipViewTests) {
            $progressParams.PercentComplete = $($currentStep / $totalSteps * 100)
            Write-Progress @progressParams

            $dbObjects = @()

            if ($Schema) {
                $dbObjects += $db.Views | Where-Object IsSystemObject -eq $false | Where-Object Schema -in $Schema
            }
            else {
                $dbObjects += $db.Views | Where-Object IsSystemObject -eq $false
            }

            if ($View) {
                $dbObjects = $dbObjects | Where-Object Name -in $View
            }

            # Create the view existence tests
            try {
                $params = @{
                    SqlInstance     = $SqlInstance
                    SqlCredential   = $SqlCredential
                    Database        = $Database
                    Schema          = @($dbObjects | Select-Object Schema -ExpandProperty Schema -Unique)
                    Object          = @($dbObjects | Select-Object Name -ExpandProperty Name -Unique)
                    Creator         = $Creator
                    OutputPath      = $OutputPath
                    TestClass       = $TestClass
                    EnableException = $EnableException
                }

                New-PSTGObjectExistenceTest @params
            }
            catch {
                Stop-PSFFunction -Message "Something went wrong creating the view existence tests" -Target $Database -ErrorRecord $_
            }

            # Create the view column tests
            try {
                $params = @{
                    SqlInstance     = $SqlInstance
                    SqlCredential   = $SqlCredential
                    Database        = $Database
                    Schema          = @($dbObjects | Select-Object Schema -ExpandProperty Schema -Unique)
                    View            = @($dbObjects | Select-Object Name -ExpandProperty Name -Unique)
                    Creator         = $Creator
                    OutputPath      = $OutputPath
                    TestClass       = $TestClass
                    EnableException = $EnableException
                }

                New-PSTGViewColumnTest @params
            }
            catch {
                Stop-PSFFunction -Message "Something went wrong creating the view column tests" -Target $Database -ErrorRecord $_
            }
        }
    }
}