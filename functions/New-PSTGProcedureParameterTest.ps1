function New-PSTGProcedureParameterTest {
    <#
    .SYNOPSIS
        Function to create procedure tests

    .DESCRIPTION
        The function will collect the parameter(s) of the procedure(s) and create the test

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database or databases to add.

    .PARAMETER Schema
        Filter the stored procedures based on schema

    .PARAMETER Procedure
        Procedure(s) to create tests for

    .PARAMETER OutputPath
        Path to output the test to

    .PARAMETER Creator
        The person that created the tests. By default the command will get the environment username

    .PARAMETER TemplateFolder
        Path to template folder. By default the internal templates folder will be used

    .PARAMETER TestClass
        Test class name to use for the test

    .PARAMETER InputObject
        Takes the parameters required from a Procedure object that has been piped into the command

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .EXAMPLE
        New-PSTGProcedureParameterTest -Procedure $procedure -OutputPath $OutputPath

        Create a new procedure parameter test

    .EXAMPLE
        $procedures | New-PSTGProcedureParameterTest -OutputPath $OutputPath

        Create the tests using pipelines
    #>

    [CmdletBinding(SupportsShouldProcess)]

    param(
        [DbaInstanceParameter]$SqlInstance,
        [pscredential]$SqlCredential,
        [string]$Database,
        [string[]]$Schema,
        [string[]]$Procedure,
        [string]$OutputPath,
        [string]$Creator,
        [string]$TemplateFolder,
        [string]$TestClass,
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

        # Check the output path
        if (-not $OutputPath) {
            Stop-PSFFunction -Message "Please enter an output path"
            return
        }

        if (-not (Test-Path -Path $OutputPath)) {
            Stop-PSFFunction -Message "Could not access output path" -Category ResourceUnavailable -Target $OutputPath
        }

        # Check the template folder
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
            Stop-PSFFunction -Message "Database cannot be found on '$SqlInstance'" -Target $Database
        }

        $task = "Collecting objects"
        Write-Progress -ParentId 1 -Activity " Stored Procedure Parameters" -Status 'Progress->' -CurrentOperation $task -Id 2
    }

    process {
        if (Test-PSFFunctionInterrupt) { return }

        if (-not $InputObject -and -not $Procedure -and -not $SqlInstance) {
            Stop-PSFFunction -Message "You must pipe in an object or specify a Procedure"
            return
        }

        $objects = @()

        if ($InputObject) {
            $objects += Get-DbaModule -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -Type StoredProcedure -ExcludeSystemObjects | Where-Object Name -in $InputObject | Select-Object SchemaName, Name
        }
        else {
            $objects += Get-DbaModule -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -Type StoredProcedure -ExcludeSystemObjects | Select-Object SchemaName, Name
        }

        if ($Schema) {
            $objects = $objects | Where-Object SchemaName -in $Schema
        }

        if ($Procedure) {
            $objects = $objects | Where-Object Name -in $Procedure
        }

        $objectCount = $objects.Count
        $objectStep = 1

        if ($objectCount -ge 1) {
            foreach ($procedureObject in $objects) {

                $procedureObject = $server.Databases[$Database].StoredProcedures | Where-Object { $_.Schema -eq $procedureObject.SchemaName -and $_.Name -eq $procedureObject.Name }

                $task = "Creating procedure test $($objectStep) of $($objectCount)"
                Write-Progress -ParentId 1 -Activity "Creating..." -Status 'Progress->' -PercentComplete ($objectStep / $objectCount * 100) -CurrentOperation $task -Id 2

                $testName = "test If stored procedure $($procedureObject.Schema).$($procedureObject.Name) has the correct parameters"

                # Test if the name of the test does not become too long
                if ($testName.Length -gt 128) {
                    Stop-PSFFunction -Message "Name of the test is too long" -Target $testName
                }

                $fileName = Join-Path -Path $OutputPath -ChildPath "$($testName).sql"
                $date = Get-Date -Format (Get-culture).DateTimeFormat.ShortDatePattern
                $creator = $env:username

                # Get the parameters
                $query = "SELECT pm.name AS ParameterName,
                        t.name AS DataType,
                        pm.max_length AS MaxLength,
                        pm.precision AS [Precision],
                        pm.scale AS Scale
                FROM sys.parameters AS pm
                    INNER JOIN sys.procedures AS ps
                        ON pm.object_id = ps.object_id
                    INNER JOIN sys.schemas AS s
                        ON s.schema_id = ps.schema_id
                    INNER JOIN sys.types AS t
                        ON pm.system_type_id = t.system_type_id
                            AND pm.user_type_id = t.user_type_id
                WHERE s.name = '$($procedureObject.Schema)'
                    AND ps.name = '$($procedureObject.Name)';"

                try {
                    $parameters = @()
                    $parameters += Invoke-DbaQuery -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -Query $query
                }
                catch {
                    Stop-PSFFunction -Message "Could not retrieve parameters for [$($procedureObject.Schema)].[$($procedureObject.Name)]" -Target $procedureObject -Continue
                }

                if ($parameters.Count -ge 1) {
                    # Import the template
                    try {
                        $script = Get-Content -Path (Join-Path -Path $TemplateFolder -ChildPath "ProcedureParameterTest.template")
                    }
                    catch {
                        Stop-PSFFunction -Message "Could not import test template 'ProcedureParameterTest.template'" -Target $testName -ErrorRecord $_
                    }

                    $paramTextCollection = @()

                    # Loop through the parameters
                    foreach ($parameter in $parameters) {
                        $paramText = "`t('$($parameter.ParameterName)', '$($parameter.DataType)', $($parameter.MaxLength), $($parameter.Precision), $($parameter.Scale))"
                        $paramTextCollection += $paramText
                    }

                    # Replace the markers with the content
                    $script = $script.Replace("___TESTCLASS___", $TestClass)
                    $script = $script.Replace("___TESTNAME___", $testName)
                    $script = $script.Replace("___SCHEMA___", $procedureObject.Schema)
                    $script = $script.Replace("___NAME___", $procedureObject.Name)
                    $script = $script.Replace("___CREATOR___", $creator)
                    $script = $script.Replace("___DATE___", $date)
                    $script = $script.Replace("___PARAMETERS___", ($paramTextCollection -join ",`n") + ";")

                    # Write the test
                    if ($PSCmdlet.ShouldProcess("$($procedureObject.Schema).$($procedureObject.Name)", "Writing Procedure Parameter Test")) {
                        try {
                            Write-PSFMessage -Message "Creating procedure parameter test for procedure '$($procedureObject.Schema).$($procedureObject.Name)'"
                            $script | Out-File -FilePath $fileName

                            [PSCustomObject]@{
                                TestName = $testName
                                Category = "ProcedureParameter"
                                Creator  = $creator
                                FileName = $fileName
                            }
                        }
                        catch {
                            Stop-PSFFunction -Message "Something went wrong writing the test" -Target $testName -ErrorRecord $_
                        }
                    }
                }
                else {
                    Write-PSFMessage -Message "Procedure $($procedureObject.Schema).$($procedureObject.Name) does not have any parameters. Skipping..."
                }

                $objectStep++
            }
        }
    }
}