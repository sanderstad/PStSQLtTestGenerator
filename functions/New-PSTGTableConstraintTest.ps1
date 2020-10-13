function New-PSTGTableConstraintTest {
    <#
    .SYNOPSIS
        Function to test the constraints in a table

    .DESCRIPTION
        The function will retrieve the constraints for a table and create a test for it

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database or databases to add.

    .PARAMETER Schema
        Filter the tables based on schema

    .PARAMETER Table
        Table(s) to create tests for

    .PARAMETER OutputPath
        Path to output the test to

    .PARAMETER Creator
        The person that created the tests. By default the command will get the environment username

    .PARAMETER TemplateFolder
        Path to template folder. By default the internal templates folder will be used

    .PARAMETER TestClass
        Test class name to use for the test

    .PARAMETER InputObject
        Takes the parameters required from a Table object that has been piped into the command

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .EXAMPLE
        New-PSTGTableConstraintTest -SqlInstance SQL1 -Database DB1 -Table $table -OutputPath $OutputPath

        Create a new constraint test

    .EXAMPLE
        $tables | New-PSTGTableConstraintTest -OutputPath $OutputPath

        Create the tests using pipelines
    #>

    [CmdletBinding(SupportsShouldProcess)]

    param(
        [DbaInstanceParameter]$SqlInstance,
        [pscredential]$SqlCredential,
        [string]$Database,
        [string[]]$Schema,
        [string[]]$Table,
        [string]$OutputPath,
        [string]$Creator,
        [string]$TemplateFolder,
        [string]$TestClass,
        [parameter(ParameterSetName = "InputObject", ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Table[]]$InputObject,
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

        # Check the output path
        if (-not $OutputPath) {
            Stop-PSFFunction -Message "Please enter an output path"
            return
        }

        if (-not (Test-Path -Path $OutputPath)) {
            try {
                $null = New-Item -Path $OutputPath -ItemType Directory
            }
            catch {
                Stop-PSFFunction -Message "Something went wrong creating the output directory" -Target $OutputPath -ErrorRecord $_
            }
        }

        # Check the template folder
        if (-not $TemplateFolder) {
            $TemplateFolder = Join-Path -Path ($script:ModuleRoot) -ChildPath "internal\templates"
        }

        if (-not (Test-Path -Path $TemplateFolder)) {
            Stop-PSFFunction -Message "Could not find template folder" -Target $OutputPath
        }

        if (-not $TestClass) {
            $TestClass = "TestBasic"
        }

        $date = Get-Date -Format (Get-culture).DateTimeFormat.ShortDatePattern

        if (-not $Creator) {
            $Creator = $env:username
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
            Stop-PSFFunction -Message "Database '$Database' cannot be found on '$SqlInstance'" -Target $Database
        }

        $task = "Collecting objects"
        Write-Progress -ParentId 1 -Activity " Table Columns" -Status 'Progress->' -CurrentOperation $task -Id 2
    }

    process {
        if (Test-PSFFunctionInterrupt) { return }

        if (-not $InputObject -and -not $Table -and -not $SqlInstance) {
            Stop-PSFFunction -Message "You must pipe in an object or specify a Table"
            return
        }

        $objects = @()

        if ($InputObject) {
            $objects += $server.Databases[$Database].Tables | Where-Object { $_.IsSystemObject -eq $false -and $_.Name -in $InputObject } | Select-Object Schema, Name, Columns
        }
        else {
            $objects += $server.Databases[$Database].Tables | Where-Object { $_.IsSystemObject -eq $false } | Select-Object Schema, Name, Columns
        }

        if ($Schema) {
            [array]$objects = $objects | Where-Object Schema -in $Schema
        }

        if ($Table) {
            [array]$objects = $objects | Where-Object Name -in $Table
        }

        $objectCount = $objects.Count
        $objectStep = 1

        if ($objectCount -ge 1) {
            foreach ($object in $objects) {
                $task = "Creating table constraint test $($objectStep) of $($objectCount)"
                Write-Progress -ParentId 1 -Activity "Creating..." -Status 'Progress->' -PercentComplete ($objectStep / $objectCount * 100) -CurrentOperation $task -Id 2

                $testName = "test If table $($object.Schema).$($object.Name) has the correct constraints"

                # Test if the name of the test does not become too long
                if ($testName.Length -gt 128) {
                    Stop-PSFFunction -Message "Name of the test is too long" -Target $testName
                }

                $fileName = Join-Path -Path $OutputPath -ChildPath "$($testName).sql"
                $date = Get-Date -Format (Get-culture).DateTimeFormat.ShortDatePattern
                $creator = $env:username

                # Import the template
                try {
                    $script = Get-Content -Path (Join-Path -Path $TemplateFolder -ChildPath "TableConstraintTest.template")
                }
                catch {
                    Stop-PSFFunction -Message "Could not import test template 'TableConstraintTest.template'" -Target $testName -ErrorRecord $_
                }

                # Get the columns
                $query = "SELECT s.name AS [SchemaName],
                        t.name AS [TableName],
                        OBJECT_NAME(o.OBJECT_ID) AS [ConstraintName],
                        o.type_desc AS ConstraintType
                    FROM sys.objects as o
                        inner join sys.schemas as s
                        on s.schema_id = o.schema_id
                        INNER JOIN sys.tables as t
                        on t.object_id = o.parent_object_id
                    WHERE o.type_desc LIKE '%CONSTRAINT'
                        AND s.name = '$($object.Schema)'
                        AND t.name = '$($object.Name)'
                    ORDER BY ConstraintName"

                try {
                    $constraints = Invoke-DbaQuery -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -Query $query
                }
                catch {
                    Stop-PSFFunction -Message "Could not retrieve columns for [$($object.Schema)].[$($object.Name)]" -Target $object -Continue
                }

                $constraintTextCollection = @()

                # Loop through the columns
                foreach ($constr in $constraints) {
                    $constraintText = "`t('$($constr.SchemaName)', '$($constr.TableName)', '$($constr.ConstraintName)', '$($constr.ConstraintType)')"
                    $constraintTextCollection += $constraintText
                }

                # Replace the markers with the content
                $script = $script.Replace("___TESTCLASS___", $TestClass)
                $script = $script.Replace("___TESTNAME___", $testName)
                $script = $script.Replace("___SCHEMA___", $object.Schema)
                $script = $script.Replace("___NAME___", $object.Name)
                $script = $script.Replace("___CREATOR___", $creator)
                $script = $script.Replace("___DATE___", $date)
                $script = $script.Replace("___COLUMNS___", ($constraintTextCollection -join ",`n") + ";")

                # Write the test
                if ($PSCmdlet.ShouldProcess("$($object.Schema).$($object.Name)", "Writing Table Column Test")) {
                    try {
                        Write-PSFMessage -Message "Creating table constraint test for table '$($object.Schema).$($object.Name)'"
                        $script | Out-File -FilePath $fileName

                        [PSCustomObject]@{
                            TestName = $testName
                            Category = "TableColumn"
                            Creator  = $creator
                            FileName = $fileName
                        }
                    }
                    catch {
                        Stop-PSFFunction -Message "Something went wrong writing the test" -Target $testName -ErrorRecord $_
                    }
                }

                $objectStep++
            }
        }
    }
}