function New-PSTGQueryElapsedTimeTest {
    <#
    .SYNOPSIS
        Function to create query execution time test

    .DESCRIPTION
        The function will retrieve the last elapsed time of the query and create test for it

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

    .PARAMETER Creator
        The person that created the tests. By default the command will get the environment username

    .PARAMETER TemplateFolder
        Path to template folder. By default the internal templates folder will be used

    .PARAMETER TestClass
        Test class name to use for the test

    .PARAMETER Query
        Query that needs to be found. This can be a wildcard

    .PARAMETER UseLastElapsedTime
        By default the command will calculate the average elapsed time
        Maybe the average is not good enough and you want the last elapsed time

    .PARAMETER UseExecute
        The command will collect the query statistics from the sys.dm_exec_query_stats DMV.
        But maybe you want to execute the query on the fly and calculate the elapsed time based on that.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .EXAMPLE
        New-PSTGQueryExecTimeTest -SqlInstance SQL1 -Database DB1 -OutputPath "C:\Projects\DB1\TestBasic\"

        Create tests for all the queries found

    .EXAMPLE
        New-PSTGQueryExecTimeTest -SqlInstance SQL1 -Database DB1 -Query "Select column1, column2 FROM table 1" -OutputPath "C:\Projects\DB1\TestBasic\"

        Create a test for a specific query
    #>

    [CmdletBinding(SupportsShouldProcess)]

    param(
        [DbaInstanceParameter]$SqlInstance,
        [pscredential]$SqlCredential,
        [string]$Database,
        [Parameter(Mandatory)][string]$OutputPath,
        [string]$Creator,
        [string]$TemplateFolder,
        [string]$TestClass,
        [string]$Query,
        [switch]$UseLastElapsedTime,
        [switch]$UseExecute,
        [parameter(ParameterSetName = "InputObject", ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.StoredProcedure[]]$InputObject,
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

        if (-not $Creator) {
            $Creator = $env:username
        }

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
            $db = $server.Databases[$Database]
        }
        catch {
            Stop-PSFFunction -Message "Could not connect to '$Sqlinstance'" -Target $Sqlinstance -ErrorRecord $_ -Category ConnectionError
            return
        }

        # Check if the database exists
        if ($Database -notin $server.Databases.Name) {
            Stop-PSFFunction -Message "Database cannot be found on '$SqlInstance'" -Target $Database
        }

        $stmnt = "SELECT qs.execution_count,
                    SUBSTRING(   qt.text,
                                    qs.statement_start_offset / 2 + 1,
                                    (CASE
                                        WHEN qs.statement_end_offset = -1 THEN
                                            LEN(CONVERT(NVARCHAR(MAX), qt.text)) * 2
                                        ELSE
                                            qs.statement_end_offset
                                    END - qs.statement_start_offset
                                    ) / 2
                                ) AS query_text,
                    qs.total_elapsed_time,
                    qs.last_elapsed_time,
                    qs.min_elapsed_time,
                    qs.max_elapsed_time,
                    qt.objectid,
                    qs.execution_count,
                    qs.sql_handle,
                    qs.plan_handle
                FROM sys.dm_exec_query_stats AS qs
                    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS qt
                WHERE qs.objectid IS NOT NULL
                    AND qt.text NOT LIKE 'CREATE%'
                    AND qt.text NOT LIKE 'DROP'
                    AND qt.text NOT LIKE 'ALTER'
                    AND qt.text NOT LIKE 'DELETE'
                    AND qt.text NOT LIKE 'INSERT' "

        # Create the output directory if it does not exist
        if (-not (Test-Path -Path $OutputPath)){
            try {
                $null = New-Item -ItemType Directory -Path $OutputPath
            }
            catch {
                Stop-PSFFunction -Message "Could not create output directory" -Target $OutputPath -ErrorRecord $_
            }
        }
    }

    process {
        if (Test-PSFFunctionInterrupt) { return }

        if (-not $InputObject -and -not $Procedure -and -not $SqlInstance) {
            Stop-PSFFunction -Message "You must pipe in an object or specify a Procedure"
            return
        }

        $objects = @()

        if ($Query) {
            $elapsedQuery = $stmnt + "AND qt.text LIKE '$Query'"
        }
        else {
            $elapsedQuery = $stmnt
        }

        # Get the query stats
        try {
            $objects += $db.Query($elapsedQuery)
        }
        catch {
            Stop-PSFFunction -Message "Could not retrieve query statistics" -ErrorRecord $_ -Target $server
        }

        if ($objects.Count -ge 1) {

            foreach ($item in $objects) {
                $testName = "test If query - "

                $queryText = $item.query_text

                # Check to see if there are multiple lines in the query
                $queryLines = $queryText | Measure-Object -Line | Select-Object -ExpandProperty Lines

                # Format the query to be a single line
                if ($queryLines -gt 1) {
                    $sb = [System.Text.StringBuilder]::new()

                    [array]$queryParts = $queryText.Split("`n")

                    for ($i = 0; $i -lt $queryParts.Count; $i++) {
                        [string]$lineText = ($queryParts[$i].Trim()).replace("`n", ",").replace("`r", ",").replace("`t", ",")
                        [void]$sb.Append("$lineText ")
                    }

                    $queryText = $sb.ToString().Trim()
                }

                # Generate the test name
                if ($queryText.length -gt 80) {
                    $testName += "$($queryText.Substring(0, 40)) ... "
                    $testName += $queryText.Substring($queryText.Length - 40, 40)
                }
                else {
                    $testName += $queryText
                }

                $testName += " - has correct elapsed time"
                $testName = $testName.Replace("'", "")

                $fileName = Join-Path -Path $OutputPath -ChildPath "$($testName).sql"

                $fileName = Remove-IllegalCharacters -Value $fileName -Type Path

                Write-Host $fileName
                # Import the template
                if ($UseLastElapsedTime) {
                    $templateName = "QueryElapsedTimeLastElapsed.template"
                    $elapsedTime = $item.last_elapsed_time
                }
                else {
                    $templateName = "QueryElapsedTimeAverage.template"
                    $elapsedTime = $item.total_elapsed_time / $item.execution_count
                }

                try {
                    $script = Get-Content -Path (Join-Path -Path $TemplateFolder -ChildPath $templateName)
                }
                catch {
                    Stop-PSFFunction -Message "Could not import test template '$templateName'" -Target $testName -ErrorRecord $_
                }

                # Convert the sql and plan handle from byte to a string
                $sqlHandle = "0x"; $item.sql_handle | ForEach-Object { $sqlHandle += ("{0:X}" -f $_).PadLeft(2, "0") }
                $planHandle = "0x"; $item.plan_handle | ForEach-Object { $planHandle += ("{0:X}" -f $_).PadLeft(2, "0") }

                # Replace the markers with the content
                $script = $script.Replace("___TESTCLASS___", $TestClass)
                $script = $script.Replace("___TESTNAME___", $testName)
                $script = $script.Replace("___DATABASE___", $Database)
                $script = $script.Replace("___QUERY___", $queryText)
                $script = $script.Replace("___CREATOR___", $creator)
                $script = $script.Replace("___DATE___", $date)
                $script = $script.Replace("___SQLHANDLE___", $sqlHandle)
                $script = $script.Replace("___PLANHANDLE___", $planHandle)
                $script = $script.Replace("___ELAPSEDTIME___", $elapsedTime)

                # Write the test
                if ($PSCmdlet.ShouldProcess("$Database", "Writing Query Elapsed Time Test")) {
                    try {
                        Write-PSFMessage -Message "Creating query elapsed time test for '$Database'"
                        $script | Out-File -FilePath "$fileName"

                        [PSCustomObject]@{
                            TestName = $testName
                            Category = "QueryPerformance"
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
        else {
            Write-PSFMessage -Level Verbose -Message "No queries found"
        }
    }
}