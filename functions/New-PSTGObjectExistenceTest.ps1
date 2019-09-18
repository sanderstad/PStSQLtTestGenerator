function New-PSTGObjectExistenceTest {
    <#
    .SYNOPSIS
        Function to check if an object exists

    .DESCRIPTION
        The function will create a test to check for the existence of an object

    .PARAMETER Object
        The object(s) to create the tests for

    .PARAMETER OutputPath
        Path to output the test to

    .PARAMETER TemplateFolder
        Path to template folder. By default the internal templates folder will be used

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
        [parameter(ParameterSetName = "Object", Mandatory)]
        [object[]]$Object,
        [string]$OutputPath,
        [string]$TemplateFolder,
        [parameter(ParameterSetName = "InputObject", ValueFromPipeline)]
        [object]$InputObject,
        [switch]$EnableException
    )

    begin {
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
            Stop-PSFFunction -Message "Could not find template folder" -Target $OutputPath
        }
    }

    process {
        if (Test-PSFFunctionInterrupt) { return }

        if (-not $InputObject -and -not $Object) {
            Stop-Function -Message "You must pipe in an object or specify an Object"
            return
        }

        if ($Object) {
            $InputObject = $Object
        }

        foreach ($input in $InputObject) {

            switch ($input.GetType().Name) {
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

            $testName = "test If $($objectType.ToLower()) $($input.Schema)`.$($input.Name) exists Expect Success"

            # Test if the name of the test does not become too long
            if ($testName.Length -gt 128) {
                Stop-PSFFunction -Message "Name of the test is too long" -Target $testName
            }

            $fileName = Join-Path -Path $OutputPath -ChildPath "$($testName).sql"
            $date = Get-Date -Format (Get-culture).DateTimeFormat.ShortDatePattern
            $creator = $env:username

            # Import the template
            try {
                $script = Get-Content -Path (Join-Path -Path $TemplateFolder -ChildPath "ObjectExistence.template")
            }
            catch {
                Stop-PSFFunction -Message "Could not import test template 'ObjectExistence.template'" -Target $testName -ErrorRecord $_
            }

            # Replace the markers with the content
            $script = $script.Replace("___TESTNAME___", $testName)
            $script = $script.Replace("___OBJECTTYPE___", $ObjectType.ToLower())
            $script = $script.Replace("___SCHEMA___", $input.$Schema)
            $script = $script.Replace("___NAME___", $input.Name)
            $script = $script.Replace("___CREATOR___", $creator)
            $script = $script.Replace("___DATE___", $date)

            # Write the test
            if ($PSCmdlet.ShouldProcess("$($input.Schema).$($input.Name)", "Writing Object Existence Test")) {
                try {
                    Write-PSFMessage -Message "Creating existence test for $($ObjectType.ToLower()) '$($input.Schema).$($input.Name)'"
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