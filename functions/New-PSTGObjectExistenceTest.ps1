function New-PSTGObjectExistenceTest {
    <#
    .SYNOPSIS
        Function to check if an object exists

    .DESCRIPTION
        The function will create a test to check for the existence of an object

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database or databases to add.

    .PARAMETER Object
        The object(s) to create the tests for

    .PARAMETER OutputPath
        Path to output the test to

    .PARAMETER TemplateFolder
        Path to template folder. By default the internal templates folder will be used

    .PARAMETER TestClass
        Test class name to use for the test

    .PARAMETER InputObject
        Takes the parameters required from a Login object that has been piped into the command

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .EXAMPLE
        New-PSTGObjectExistenceTest -Object $object -OutputPath $OutputPath

        Create a new object existence test

    .EXAMPLE
        $objects | New-PSTGObjectExistenceTest -OutputPath $OutputPath

        Create the tests using pipelines
    #>

    [CmdletBinding(SupportsShouldProcess)]

    param(
        [DbaInstanceParameter]$SqlInstance,
        [pscredential]$SqlCredential,
        [string]$Database,
        [string[]]$Object,
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

        $date = Get-Date -Format (Get-culture).DateTimeFormat.ShortDatePattern
        $creator = $env:username

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

        $task = "Collecting objects"
        Write-Progress -ParentId 1 -Activity " Object Existence" -Status 'Progress->' -CurrentOperation $task -Id 2
    }

    process {
        if (Test-PSFFunctionInterrupt) { return }

        if ($Object) {
            $InputObject += $server.Databases[$Database].Tables | Select-Object Schema, Name, @{Name = "ObjectType"; Expression = { "Table" } } | Where-Object Name -in $Object
            $InputObject += $server.Databases[$Database].StoredProcedures | Select-Object Schema, Name, @{Name = "ObjectType"; Expression = { "StoredProcedure" } }, IsSystemObject | Where-Object { $_.Name -in $Object -and $_.IsSystemObject -eq $false }
            $InputObject += $server.Databases[$Database].UserDefinedFunctions | Select-Object Schema, Name, @{Name = "ObjectType"; Expression = { "UserDefinedFunction" } }, IsSystemObject | Where-Object { $_.Name -in $Object -and $_.IsSystemObject -eq $false }
            $InputObject += $server.Databases[$Database].Views | Select-Object Schema, Name, @{Name = "ObjectType"; Expression = { "View" } }, IsSystemObject | Where-Object { $_.Name -in $Object -and $_.IsSystemObject -eq $false }
        }
        else {
            $InputObject += $server.Databases[$Database].Tables | Select-Object Schema, Name, @{Name = "ObjectType"; Expression = { "Table" } }
            $InputObject += $server.Databases[$Database].StoredProcedures | Select-Object Schema, Name, @{Name = "ObjectType"; Expression = { "StoredProcedure" } }, IsSystemObject | Where-Object IsSystemObject -eq $false
            $InputObject += $server.Databases[$Database].UserDefinedFunctions | Select-Object Schema, Name, @{Name = "ObjectType"; Expression = { "UserDefinedFunction" } }, IsSystemObject | Where-Object IsSystemObject -eq $false
            $InputObject += $server.Databases[$Database].Views | Select-Object Schema, Name, @{Name = "ObjectType"; Expression = { "View" } }, IsSystemObject | Where-Object IsSystemObject -eq $false
        }

        $objectCount = $InputObject.Count
        $objectStep = 1

        if ($objectCount -ge 1) {
            foreach ($input in $InputObject) {
                $task = "Creating object existence test $($objectStep) of $($objectCount)"
                Write-Progress -ParentId 1 -Activity "Creating..." -Status 'Progress->' -PercentComplete ($objectStep / $objectCount * 100) -CurrentOperation $task -Id 2

                switch ($input.ObjectType) {
                    "StoredProcedure" {
                        $objectType = "stored procedure"
                    }
                    "Table" {
                        $objectType = "table"
                    }
                    "UserDefinedFunction" {
                        $objectType = "user defined function"
                    }
                    "View" {
                        $objectType = "View"
                    }
                }

                $testName = "test If $($objectType.ToLower()) $($input.Schema)`.$($input.Name) exists"

                # Test if the name of the test does not become too long
                if ($testName.Length -gt 128) {
                    Stop-PSFFunction -Message "Name of the test is too long" -Target $testName
                }

                $fileName = Join-Path -Path $OutputPath -ChildPath "$($testName).sql"

                # Import the template
                try {
                    $script = Get-Content -Path (Join-Path -Path $TemplateFolder -ChildPath "ObjectExistence.template")
                }
                catch {
                    Stop-PSFFunction -Message "Could not import test template 'ObjectExistence.template'" -Target $testName -ErrorRecord $_
                }

                # Replace the markers with the content
                $script = $script.Replace("___TESTCLASS___", $TestClass)
                $script = $script.Replace("___TESTNAME___", $testName)
                $script = $script.Replace("___OBJECTTYPE___", $objectType.ToLower())
                $script = $script.Replace("___SCHEMA___", $input.Schema)
                $script = $script.Replace("___NAME___", $input.Name)
                $script = $script.Replace("___CREATOR___", $creator)
                $script = $script.Replace("___DATE___", $date)

                # Write the test
                if ($PSCmdlet.ShouldProcess("$($input.Schema).$($input.Name)", "Writing Object Existence Test")) {
                    try {
                        Write-PSFMessage -Message "Creating existence test for $($objectType.ToLower()) '$($input.Schema).$($input.Name)'"
                        $script | Out-File -FilePath $fileName

                        [PSCustomObject]@{
                            TestName = $testName
                            Category = "ObjectExistence"
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