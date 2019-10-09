function New-PSTGIndexColumnTest {
    <#
    .SYNOPSIS
        Function to test the columns for an index

    .DESCRIPTION
        The function will retrieve the current columns for an index and create a test for it

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database or databases to add.

    .PARAMETER Table
        Table(s) to create tests for

    .PARAMETER Index
        Index(es) to create tests for

    .PARAMETER OutputPath
        Path to output the test to

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
        New-PSTGIndexColumnTest -Table $table -OutputPath $OutputPath

        Create a new index column test

    .EXAMPLE
        $tables | New-PSTGIndexColumnTest -OutputPath $OutputPath

        Create the tests using pipelines
    #>

    [CmdletBinding(SupportsShouldProcess)]

    param(
        [DbaInstanceParameter]$SqlInstance,
        [pscredential]$SqlCredential,
        [string]$Database,
        [string[]]$Table,
        [string[]]$Index,
        [string]$OutputPath,
        [string]$TemplateFolder,
        [string]$TestClass,
        [parameter(ParameterSetName = "InputObject", ValueFromPipeline)]
        [object[]]$InputObject,
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
        $creator = $env:username

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
        Write-Progress -ParentId 1 -Activity " Index Columns" -Status 'Progress->' -CurrentOperation $task -Id 2

        $tables = @()

        if ($Table) {
            $tables += $server.Databases[$Database].Tables | Where-Object { $_.IsSystemObject -eq $false -and $_.Name -in $Table } | Select-Object Schema, Name, Indexes
        }
        else {
            $tables += $server.Databases[$Database].Tables | Where-Object { $_.IsSystemObject -eq $false } | Select-Object Schema, Name, Indexes
        }
    }

    process {
        if (Test-PSFFunctionInterrupt) { return }

        if (-not $InputObject -and -not $Table -and -not $SqlInstance) {
            Stop-PSFFunction -Message "You must pipe in an object or specify a Table"
            return
        }

        $objects = @()

        if ($InputObject) {
            $objects += $tables.Indexes | Where-Object Name -in $InputObject | Select-Object Name, IndexedColumns
        }
        else {
            $objects += $tables.Indexes | Select-Object Name, IndexedColumns
        }


        if ($Index) {
            $objects = $objects | Where-Object Name -in $Index
        }

        $objectCount = $objects.Count
        $objectStep = 1

        if ($objectCount -ge 1) {
            foreach ($input in $objects) {
                $task = "Creating index $($objectStep) of $($objectCount)"
                Write-Progress -ParentId 1 -Activity "Creating..." -Status 'Progress->' -PercentComplete ($objectStep / $objectCount * 100) -CurrentOperation $task -Id 2

                $testName = "test If index $($input.Name) has the correct columns"

                # Test if the name of the test does not become too long
                if ($testName.Length -gt 128) {
                    Stop-PSFFunction -Message "Name of the test is too long" -Target $testName
                }

                $fileName = Join-Path -Path $OutputPath -ChildPath "$($testName).sql"
                $date = Get-Date -Format (Get-culture).DateTimeFormat.ShortDatePattern
                $creator = $env:username

                # Import the template
                try {
                    $script = Get-Content -Path (Join-Path -Path $TemplateFolder -ChildPath "IndexColumnTest.template")
                }
                catch {
                    Stop-PSFFunction -Message "Could not import test template 'IndexColumnTest.template'" -Target $testName -ErrorRecord $_
                }

                # Get the columns
                $columns = $input.IndexedColumns

                $columnTextCollection = @()

                # Loop through the columns
                foreach ($column in $columns) {
                    $columnText = "`t('$($column.Name)')"
                    $columnTextCollection += $columnText
                }

                # Replace the markers with the content
                $script = $script.Replace("___TESTCLASS___", $TestClass)
                $script = $script.Replace("___TESTNAME___", $testName)
                $script = $script.Replace("___NAME___", $input.Name)
                $script = $script.Replace("___CREATOR___", $creator)
                $script = $script.Replace("___DATE___", $date)
                $script = $script.Replace("___COLUMNS___", ($columnTextCollection -join ",`n") + ";")

                # Write the test
                if ($PSCmdlet.ShouldProcess("$($input.Schema).$($input.Name)", "Writing Index Column Test")) {
                    try {
                        Write-PSFMessage -Message "Creating index column test for index '$($input.Name)'"
                        $script | Out-File -FilePath $fileName

                        [PSCustomObject]@{
                            TestName = $testName
                            Category = "IndexColumn"
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
    }
}